// Worker "lifeos-flights": le moteur de comparaison de vols de LifeOS.
//
// Les cles des fournisseurs ne quittent JAMAIS ce serveur (secrets Cloudflare).
// L'app parle a ce Worker avec une cle d'application; le Worker parle aux
// fournisseurs.
//
// Budget: un Durable Object (`BudgetGate`) reserve le cout AVANT chaque appel
// payant, une requete a la fois, donc deux recherches simultanees ne peuvent pas
// depenser le meme reste. Sans ce stockage, aucune source payante n'est appelee.
// Il limite aussi le nombre de recherches payantes par adresse IP et par jour.
// La cle d'application n'est PAS une identite: tant qu'il n'y a pas de comptes,
// l'adresse IP vue par Cloudflare est la seule limite par personne.
//
// Routes:
//   GET    /v1/providers                sources, capacites, etat du budget et des alertes
//   POST   /v1/search                   recherche (JSON) ; ?stream=1 : resultats partiels au fil de l'eau (NDJSON)
//   POST   /v1/confirm                  relit une offre chez sa source avant passage au vendeur
//   POST   /v1/alerts                   cree une alerte de prix (rend id + jeton de desinscription)
//   GET    /v1/alerts/:id?token=        etat d'une alerte
//   DELETE /v1/alerts/:id?token=        desinscription
//   scheduled                           verifie les alertes (cron), si ALERTS_CRON = "on"

import { parseQuery, applyFilters, rank } from "./core.js";
import { makeEngine, evaluateAlert, CACHE_TTL_MS } from "./engine.js";
import { makeDuffel } from "./providers/duffel.js";
import { makeTravelport } from "./providers/travelport.js";
import { makeDemo } from "./providers/demo.js";

export function providersFor(env, fetchImpl = fetch) {
  const list = [makeDuffel({ token: env.DUFFEL_TOKEN || "", fetchImpl }), makeTravelport(env)];
  // Deux sources fictives, pour eprouver le regroupement a l'ecran. Jamais comptees
  // comme sources reelles (multiSource les exclut), toujours etiquetees "fictif".
  if (env.DEMO_PROVIDERS === "yes") list.push(makeDemo({ id: "demo-a", seed: 1 }), makeDemo({ id: "demo-b", seed: 4 }));
  return list;
}

// Par instance du Worker: un cache date et borne, et les recherches en cours.
const SEARCH_CACHE = new Map();
const INFLIGHT = new Map();

const json = (data, status = 200) => new Response(JSON.stringify(data), {
  status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
});

function authorized(req, env) {
  return Boolean(env.APP_KEY) && req.headers.get("X-LifeOS-Key") === env.APP_KEY;
}

const day = () => new Date().toISOString().slice(0, 10);
const alertsOn = (env) => env.ALERTS_CRON === "on" && Boolean(env.STATE);

// ---------- Budget ----------

/** Client du Durable Object. Sans lui: refus explicite, jamais d'appel payant. */
export function budgetFor(env, client) {
  if (!env.BUDGET) {
    return {
      configured: false,
      reserve: async () => ({ ok: false, reason: "Budget non configuré sur le serveur : aucune source payante n'est interrogée." }),
      settle: async () => {},
    };
  }
  const stub = env.BUDGET.get(env.BUDGET.idFromName("global"));
  const call = async (path, body) => {
    const r = await stub.fetch(`https://budget${path}`, { method: "POST", body: JSON.stringify(body) });
    return r.json();
  };
  return {
    configured: true,
    reserve: (provider, usd) => call("/reserve", {
      day: day(), usd, provider, client,
      cap: Number(env.DAILY_BUDGET_USD || 5), clientCap: Number(env.CLIENT_DAILY_SEARCHES || 40),
    }).catch(() => ({ ok: false, reason: "Budget injoignable : aucune source payante n'est interrogée." })),
    settle: (id, actual) => call("/settle", { day: day(), id, actual }).catch(() => {}),
  };
}

/**
 * Compteur de depenses atomique. Un Durable Object traite ses evenements un par
 * un, et la verification + la reservation se font SANS attente entre les deux:
 * deux recherches ne peuvent pas lire le meme reste.
 */
export class BudgetGate {
  constructor(state) {
    this.state = state;
    this.data = { days: {} };
    state.blockConcurrencyWhile(async () => { this.data = (await state.storage.get("data")) || { days: {} }; });
  }

  async fetch(req) {
    const url = new URL(req.url);
    const body = await req.json().catch(() => ({}));
    let out;
    if (url.pathname === "/reserve") out = this.reserve(body);
    else if (url.pathname === "/settle") out = this.settle(body);
    else if (url.pathname === "/state") out = this.data.days[body.day] || null;
    else return new Response("not found", { status: 404 });
    await this.state.storage.put("data", this.data);
    return json(out);
  }

  bucket(d) {
    for (const k of Object.keys(this.data.days)) if (k < d) delete this.data.days[k];   // une seule journee gardee
    return (this.data.days[d] ||= { spent: 0, holds: {}, clients: {} });
  }

  reserve({ day: d, usd, cap, client, clientCap, now = Date.now() }) {
    const b = this.bucket(d);
    // Une reservation jamais reglee (Worker mort) compte comme depensee.
    for (const [id, h] of Object.entries(b.holds)) if (now - h.at > 5 * 60000) { b.spent += h.usd; delete b.holds[id]; }
    const held = Object.values(b.holds).reduce((a, h) => a + h.usd, 0);
    if (b.spent + held + usd > cap + 1e-9) return { ok: false, reason: "Budget de recherche du jour atteint." };
    const used = b.clients[client] || 0;
    if (used >= clientCap) return { ok: false, reason: "Limite de recherches du jour atteinte pour cet appareil." };
    const id = `${now}-${Math.random().toString(36).slice(2, 10)}`;
    b.holds[id] = { usd, at: now };
    b.clients[client] = used + 1;
    return { ok: true, id };
  }

  settle({ day: d, id, actual }) {
    const b = this.bucket(d);
    const h = b.holds[id];
    if (!h) return { ok: false };
    delete b.holds[id];
    b.spent = Math.round((b.spent + (Number.isFinite(actual) ? actual : h.usd)) * 1e6) / 1e6;
    return { ok: true, spent: b.spent };
  }
}

// ---------- Taux de change ----------

let RATES = null;

/** Taux de reference BCE (base EUR), dates, gardes 6 h. null si indisponibles. */
export async function ecbRates(env, fetchImpl = fetch) {
  if (RATES && Date.now() - RATES.fetchedAt < 6 * 3600e3) return RATES.table;
  try {
    const r = await fetchImpl("https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml");
    if (!r.ok) throw new Error(`BCE ${r.status}`);
    const table = parseEcb(await r.text());
    if (!table) throw new Error("BCE illisible");
    RATES = { table, fetchedAt: Date.now() };
    await env.STATE?.put("rates:ecb", JSON.stringify(table), { expirationTtl: 7 * 86400 });
    return table;
  } catch {
    const saved = env.STATE && (await env.STATE.get("rates:ecb"));
    return saved ? JSON.parse(saved) : null;
  }
}

export function parseEcb(xml) {
  const date = xml.match(/time=['"](\d{4}-\d{2}-\d{2})['"]/)?.[1];
  const rates = {};
  for (const m of xml.matchAll(/currency=['"]([A-Z]{3})['"]\s+rate=['"]([\d.]+)['"]/g)) rates[m[1]] = Number(m[2]);
  return date && Object.keys(rates).length ? { base: "EUR", date, source: "BCE", rates } : null;
}

export function resetRatesCache() { RATES = null; }

// ---------- Routes ----------

function engineFor(env, fetchImpl, client) {
  return makeEngine({
    providers: providersFor(env, fetchImpl), cache: SEARCH_CACHE, inflight: INFLIGHT,
    budget: budgetFor(env, client), rates: () => ecbRates(env, fetchImpl),
  });
}

export default {
  async fetch(req, env, ctx, deps = {}) {
    const url = new URL(req.url);
    const fetchImpl = deps.fetchImpl || fetch;
    const client = req.headers.get("CF-Connecting-IP") || "inconnu";

    if (url.pathname === "/v1/health") return json({ ok: true });
    if (!authorized(req, env)) return json({ error: "Non autorisé." }, 401);

    const providers = providersFor(env, fetchImpl);

    if (req.method === "GET" && url.pathname === "/v1/providers") {
      return json({
        providers: providers.map((p) => ({
          id: p.id, name: p.name, active: p.active, kind: p.kind, demo: Boolean(p.demo), skeleton: Boolean(p.skeleton),
          sellerComparison: p.sellerComparison, handoff: p.handoff, baggageInfo: p.baggageInfo,
          conditions: p.conditions, refreshOffer: p.refreshOffer, priceCalendar: p.priceCalendar, notes: p.notes,
        })),
        multiSource: providers.filter((p) => p.active && !p.demo).length >= 2,
        budget: { configured: Boolean(env.BUDGET), dailyUSD: Number(env.DAILY_BUDGET_USD || 5) },
        alerts: { serverChecks: alertsOn(env), delivery: "app" },
        cacheTtlMinutes: CACHE_TTL_MS / 60000,
      });
    }

    if (req.method === "POST" && url.pathname === "/v1/search") {
      let body;
      try { body = await req.json(); } catch { return json({ error: ["Requête illisible."] }, 400); }
      const parsed = parseQuery(body);
      if (parsed.error) return json({ error: parsed.error }, 400);
      const engine = engineFor(env, fetchImpl, client);

      if (url.searchParams.get("stream") === "1") {
        const { readable, writable } = new TransformStream();
        const writer = writable.getWriter();
        const enc = new TextEncoder();
        const send = (obj) => writer.write(enc.encode(JSON.stringify(obj) + "\n"));
        const task = (async () => {
          try {
            const result = await engine.search(parsed.query, {
              onBatch: (b) => send({ type: "partial", provider: b.provider, ...shape({ ...b.partial, partial: true, statuses: {}, cached: false, at: new Date().toISOString() }, body.filters) }),
            });
            await send({ type: "done", ...shape(result, body.filters) });
          } catch (e) {
            await send({ type: "error", message: e.message });
          } finally {
            await writer.close();
          }
        })();
        ctx?.waitUntil?.(task);
        return new Response(readable, { headers: { "Content-Type": "application/x-ndjson", "Cache-Control": "no-store" } });
      }
      try { return json(shape(await engine.search(parsed.query), body.filters)); }
      catch (e) { return json({ error: [e.message] }, 500); }
    }

    if (req.method === "POST" && url.pathname === "/v1/confirm") {
      let body;
      try { body = await req.json(); } catch { return json({ error: "Requête illisible." }, 400); }
      const parsed = parseQuery(body.query || {});
      if (parsed.error || !body.offer?.provider || !body.offer?.providerRef) return json({ error: "Offre ou recherche manquante." }, 400);
      const engine = engineFor(env, fetchImpl, client);
      return json(await engine.confirm(body.offer, parsed.query));
    }

    const alertMatch = url.pathname.match(/^\/v1\/alerts(?:\/([A-Za-z0-9-]+))?$/);
    if (alertMatch) {
      if (!env.STATE) return json({ error: "Alertes non configurées (stockage absent)." }, 503);
      const id = alertMatch[1];
      if (req.method === "POST" && !id) {
        if (!alertsOn(env)) return json({ error: ["La surveillance des prix n'est pas encore activée sur le serveur."] }, 503);
        let body;
        try { body = await req.json(); } catch { return json({ error: "Requête illisible." }, 400); }
        const parsed = parseQuery(body.query || {});
        const maxPrice = Number(body.maxPrice);
        if (parsed.error) return json({ error: parsed.error }, 400);
        if (!(maxPrice > 0)) return json({ error: ["Seuil de prix invalide."] }, 400);
        const alert = { id: crypto.randomUUID(), token: crypto.randomUUID(), query: parsed.query, maxPrice,
          currency: parsed.query.currency, createdAt: new Date().toISOString(),
          triggered: false, triggeredAt: null, lastPrice: null, lastCheck: null, lastError: null };
        await env.STATE.put(`alert:${alert.id}`, JSON.stringify(alert));
        return json({ id: alert.id, token: alert.token }, 201);
      }
      if (!id) return json({ error: "Alerte inconnue." }, 404);
      const raw = await env.STATE.get(`alert:${id}`);
      const alert = raw && JSON.parse(raw);
      if (!alert || url.searchParams.get("token") !== alert.token) return json({ error: "Alerte inconnue." }, 404);
      if (req.method === "GET") { const { token, ...pub } = alert; return json(pub); }
      if (req.method === "DELETE") { await env.STATE.delete(`alert:${id}`); return json({ deleted: true }); }
    }

    return json({ error: "Route inconnue." }, 404);
  },

  /**
   * Verifie chaque alerte au plus une fois par passage, page par page. Une alerte
   * qui echoue n'arrete pas les autres; une alerte supprimee entre-temps n'est pas
   * recreee. Le budget est le meme que pour les recherches de l'app.
   */
  async scheduled(_event, env, _ctx, deps = {}) {
    if (!alertsOn(env)) return { checked: 0, skipped: "alertes désactivées" };
    const engine = engineFor(env, deps.fetchImpl || fetch, "cron");
    let cursor, checked = 0, failed = 0;
    do {
      const page = await env.STATE.list({ prefix: "alert:", cursor });
      for (const k of page.keys) {
        try {
          const raw = await env.STATE.get(k.name);
          if (!raw) continue;
          const alert = JSON.parse(raw);
          const result = await engine.search(alert.query, { allowCache: false });
          const r = evaluateAlert(alert, result);
          if (!(await env.STATE.get(k.name))) continue;      // desinscrite pendant la verification
          alert.lastCheck = new Date().toISOString();
          alert.lastError = r.price == null ? (result.partial ? "Résultat partiel." : r.reason) : null;
          if (r.price != null) alert.lastPrice = { total: r.price, currency: r.currency };
          if (r.trigger) { alert.triggered = true; alert.triggeredAt = alert.lastCheck; }
          else if (r.price != null && !r.below) { alert.triggered = false; alert.triggeredAt = null; }   // re-armee
          await env.STATE.put(k.name, JSON.stringify(alert));
          checked += 1;
        } catch {
          failed += 1;
        }
      }
      cursor = page.list_complete ? undefined : page.cursor;
    } while (cursor);
    return { checked, failed };
  },
};

function shape(result, filters) {
  const groups = applyFilters(result.groups, filters || {});
  const ranking = rank(groups);
  return {
    at: result.at, cached: result.cached, cachedAgeMs: result.cachedAgeMs ?? 0,
    partial: result.partial, statuses: result.statuses,
    count: groups.length,
    setAside: result.setAside || { count: 0, currencies: [] },
    ratesDate: result.ratesDate ?? null,
    cheapest: ranking.cheapest.map(summary),
    fastest: ranking.fastest.map(summary),
    best: ranking.best.map((g) => ({ ...summary(g), explanation: g.explanation })),
  };
}

function summary(g) {
  return { key: g.key, sources: g.sources, analysis: g.analysis, offers: g.offers };
}
