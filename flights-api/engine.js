// Moteur de recherche multi-sources de LifeOS.
//
// - Toutes les sources actives sont interrogees en parallele, chacune avec son
//   propre delai. Une source en panne ou lente ne bloque pas les autres: le
//   resultat est marque PARTIEL et dit quelle source manque et pourquoi.
// - Une source PAYANTE n'est appelee qu'apres une reservation de budget acceptee
//   (`reserve`). Sans reservation, pas d'appel: le plafond ne se lit pas apres coup.
// - Apres chaque source, un resultat partiel complet (regroupe, classe) est rendu
//   (`onBatch`), pour un affichage progressif.
// - Une seule devise par classement (voir normalizeCurrency).
// - Cache date et borne, recherches identiques simultanees mutualisees.

import { group, rank, itineraryKey, normalizeCurrency, billedPrice } from "./core.js";
import { DUFFEL_SEARCH_COST_USD } from "./providers/duffel.js";

export const DEFAULT_TIMEOUT_MS = 20000;
export const CONFIRM_TIMEOUT_MS = 15000;
export const CACHE_TTL_MS = 10 * 60 * 1000;
export const CACHE_MAX = 200;

export function queryKey(q) {
  return JSON.stringify([q.slices, q.passengers, q.cabin, q.currency, q.maxConnections]);
}

/** Cout d'une recherche par source (USD). 0 = source gratuite, aucune reservation. */
export function searchCost(providerId) {
  return providerId === "duffel" ? DUFFEL_SEARCH_COST_USD : 0;
}

/** Regroupe et classe des offres brutes, dans la devise de la recherche. */
export function summarize(offers, query, rates) {
  const { comparable, setAside } = normalizeCurrency(dedupe(offers), query.currency, rates);
  const groups = group(comparable);
  return {
    groups, ranking: rank(groups),
    setAside: { count: setAside.length, currencies: [...new Set(setAside.map((o) => o.price.currency))] },
    ratesDate: rates?.date ?? null,
  };
}

const noBudget = { reserve: async () => ({ ok: false, reason: "Budget non configuré." }), settle: async () => {} };

export function makeEngine({
  providers, cache = new Map(), inflight = new Map(), now = () => Date.now(),
  budget = noBudget, rates = async () => null, metrics = newMetrics(),
}) {
  const active = () => providers.filter((p) => p.active);

  async function search(query, opts = {}) {
    const key = queryKey(query);
    const { allowCache = true } = opts;
    if (allowCache) {
      const hit = cache.get(key);
      if (hit && now() - hit.at < CACHE_TTL_MS) {
        cache.delete(key); cache.set(key, hit);            // recent en dernier (LRU)
        return { ...hit.result, cached: true, cachedAgeMs: now() - hit.at };
      }
      // Meme recherche deja en cours: on attend la sienne au lieu de payer deux fois.
      if (inflight.has(key) && !opts.onBatch) return inflight.get(key);
    }
    const run = runSearch(query, opts);
    if (allowCache && !opts.onBatch) inflight.set(key, run);
    try {
      const result = await run;
      if (!result.partial) remember(key, result);
      return result;
    } finally {
      if (inflight.get(key) === run) inflight.delete(key);
    }
  }

  function remember(key, result) {
    const t = now();
    for (const [k, v] of cache) if (t - v.at >= CACHE_TTL_MS) cache.delete(k);
    cache.set(key, { at: t, result });
    while (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value);
  }

  async function runSearch(query, { onBatch, timeoutMs = DEFAULT_TIMEOUT_MS, signal } = {}) {
    const list = active();
    const statuses = {};
    const offers = [];
    const ratesPromise = Promise.resolve().then(rates).catch(() => null);
    if (!list.length) {
      return finish([], { none: { status: "no_source", message: "Aucune source de vols active." } }, false, null);
    }
    await Promise.all(list.map(async (p) => {
      const cost = searchCost(p.id);
      let hold = null;
      if (cost > 0) {
        hold = await budget.reserve(p.id, cost);
        if (!hold?.ok) {
          statuses[p.id] = { status: "skipped_budget", message: hold?.reason || "Budget de recherche atteint." };
          return;
        }
      }
      const started = now();
      const ctrl = new AbortController();
      const onAbort = () => ctrl.abort();
      signal?.addEventListener?.("abort", onAbort);
      let timer;
      try {
        const batch = await Promise.race([
          p.search(query, { signal: ctrl.signal }),
          new Promise((_, rej) => { timer = setTimeout(() => { ctrl.abort(); rej(Object.assign(new Error("Délai dépassé"), { code: "timeout" })); }, timeoutMs); }),
        ]);
        const clean = batch.filter((o) => o && o.provider === p.id);
        offers.push(...clean);
        statuses[p.id] = { status: "ok", count: clean.length, ms: now() - started };
        record(metrics, p.id, { ok: true, ms: now() - started, cost });
        if (onBatch) onBatch({ provider: p.id, count: clean.length, partial: summarize(offers, query, await ratesPromise) });
      } catch (e) {
        statuses[p.id] = { status: e.code === "timeout" ? "timeout" : "error", message: e.message, code: e.code || null, ms: now() - started };
        record(metrics, p.id, { ok: false, ms: now() - started, cost });
      } finally {
        clearTimeout(timer);
        signal?.removeEventListener?.("abort", onAbort);
        // Une requete partie est facturee, meme coupee: on regle le cout reel.
        if (hold?.ok) await budget.settle(hold.id, cost);
      }
    }));
    const partial = Object.values(statuses).some((s) => s.status !== "ok");
    return finish(offers, statuses, partial, await ratesPromise);

    function finish(list, st, part, table) {
      return { query, statuses: st, partial: part, ...summarize(list, query, table), cached: false, at: new Date(now()).toISOString() };
    }
  }

  /**
   * Relit l'offre chez SA source avant de la proposer. Rend le nouveau prix, une
   * indisponibilite ou une expiration. L'identifiant d'une source n'est jamais
   * envoye a une autre. La relecture doit porter sur le MEME itineraire.
   */
  async function confirm(offer, query, { timeoutMs = CONFIRM_TIMEOUT_MS } = {}) {
    const p = providers.find((x) => x.id === offer.provider);
    if (!p || !p.active) return { status: "unavailable", reason: "Source indisponible." };
    const started = now();
    let timer;
    let r;
    try {
      r = await Promise.race([
        p.refresh(offer.providerRef, query),
        new Promise((_, rej) => { timer = setTimeout(() => rej(Object.assign(new Error("La source ne répond pas."), { code: "timeout" })), timeoutMs); }),
      ]);
    } catch (e) {
      return { status: "error", reason: e.message };
    } finally { clearTimeout(timer); }
    metrics.confirmations += 1;
    if (r.status !== "ok") return r;
    const fresh = r.offer;
    if (!fresh || fresh.provider !== offer.provider || itineraryKey(fresh) !== itineraryKey(offer)) {
      return { status: "unavailable", reason: "La source a rendu un autre itinéraire : offre non confirmée." };
    }
    const before = billedPrice(offer), after = billedPrice(fresh);
    if (before.currency !== after.currency) {
      return { status: "price_changed", offer: fresh, previousTotal: before.total, previousCurrency: before.currency,
        delta: null, reason: `La source facture maintenant en ${after.currency} (avant : ${before.currency}).` };
    }
    const delta = Math.round((after.total - before.total) * 100) / 100;
    metrics.priceDeltas.push({ provider: p.id, delta, ms: now() - started });
    return { status: delta === 0 ? "same_price" : "price_changed", offer: fresh, previousTotal: before.total, previousCurrency: before.currency, delta };
  }

  return { search, confirm, metrics, providers };
}

/** Meme offre renvoyee deux fois par une source (meme reference): gardee une fois. */
export function dedupe(offers) {
  const seen = new Set();
  return offers.filter((o) => (seen.has(o.id) ? false : (seen.add(o.id), true)));
}

export function newMetrics() {
  return { searches: 0, costUSD: 0, byProvider: {}, confirmations: 0, priceDeltas: [] };
}

function record(m, id, { ok, ms, cost }) {
  m.searches += 1;
  m.costUSD = Math.round((m.costUSD + cost) * 1000) / 1000;
  const p = (m.byProvider[id] ||= { calls: 0, errors: 0, totalMs: 0 });
  p.calls += 1; p.totalMs += ms; if (!ok) p.errors += 1;
}

// ---------- Alertes de prix ----------

/**
 * Une alerte: un trajet, des voyageurs, un seuil DANS UNE DEVISE. Elle ne se
 * declenche que sur un prix reel, aux frais connus, facture dans cette devise
 * (jamais sur un prix converti, jamais sur une demo), une seule fois par baisse.
 */
export function evaluateAlert(alert, result) {
  const currency = alert.currency || alert.query?.currency;
  const candidates = result.groups.flatMap((g) => g.offers)
    .filter((o) => !o.demo && o.price.taxesKnown && !o.price.original && o.price.currency === currency);
  if (!candidates.length) return { trigger: false, reason: "Aucun prix complet dans la devise de l'alerte." };
  const best = candidates.reduce((a, b) => (b.price.total < a.price.total ? b : a));
  const price = best.price.total;
  const below = price <= alert.maxPrice;
  return { trigger: below && !alert.triggered, price, currency, below };
}
