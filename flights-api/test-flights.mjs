// node test-flights.mjs — aucun appel reseau: Duffel est simule a partir de sa
// documentation, et deux sources factices (A, B) servent a eprouver le
// multi-sources. Elles n'existent que dans ce fichier.
import assert from "node:assert/strict";
import { parseQuery, group, rank, applyFilters, analyse, comparability, minutesBetween, itineraryKey, normalizeCurrency, isCalendarDate } from "./core.js";
import { makeEngine, evaluateAlert, summarize, CACHE_MAX } from "./engine.js";
import { makeDuffel, normalize, isoDuration } from "./providers/duffel.js";
import { makeTravelport } from "./providers/travelport.js";
import worker, { BudgetGate, parseEcb, resetRatesCache } from "./worker.js";

let passed = 0;
const tests = [];
const test = (name, fn) => tests.push([name, fn]);

const NOW = new Date("2026-09-28T10:00:00Z");
const Q = parseQuery({ slices: [{ origin: "LIS", destination: "CDG", date: "2026-10-20" }], passengers: { adults: 1 } }, NOW).query;

// --- offre factice au format LifeOS ---
function offer(provider, ref, { price, flight = "TP438", dep = "2026-10-20T08:00:00", arr = "2026-10-20T11:40:00",
  bag = 1, taxesKnown = true, refundable = false, selfTransfer = false, segments, currency = "EUR" } = {}) {
  const seg = (o, d, fn, dp, ar) => ({ origin: { iata: o, timeZone: o === "LIS" ? "Europe/Lisbon" : "Europe/Paris" },
    destination: { iata: d, timeZone: d === "LIS" ? "Europe/Lisbon" : "Europe/Paris" }, departingAt: dp, arrivingAt: ar,
    marketingCarrier: { code: fn.slice(0, 2), name: null }, operatingCarrier: { code: fn.slice(0, 2), name: null },
    flightNumber: fn.slice(2), cabin: "economy", fareBrand: null });
  return { id: `${provider}:${ref}`, provider, providerRef: ref, demo: false,
    seller: { code: "TP", name: `${provider} seller`, kind: "agency" },
    slices: [{ origin: { iata: "LIS" }, destination: { iata: "CDG" }, durationMinutes: null,
      segments: segments || [seg("LIS", "CDG", flight, dep, arr)] }],
    passengers: { adults: 1, children: 0, infants: 0 },
    price: { total: price, currency, taxesKnown, feesNote: null },
    baggage: { checked: bag, carryOn: 1 }, conditions: { refundable, changeable: null }, selfTransfer,
    fetchedAt: NOW.toISOString(), expiresAt: null };
}
const fake = (id, offersOrFn, { delay = 0, fail = null, refreshed } = {}) => ({
  id, name: id, active: true, async search() {
    if (delay) await new Promise((r) => setTimeout(r, delay));
    if (fail) throw Object.assign(new Error(fail), { code: "down" });
    return typeof offersOrFn === "function" ? offersOrFn() : offersOrFn;
  },
  async refresh(ref) { return refreshed ? refreshed(ref) : { status: "unavailable", reason: "?" }; },
});

// ================= Requete =================
test("requête: erreurs lisibles, jamais de valeur inventée", () => {
  const r = parseQuery({ slices: [{ origin: "LIS", destination: "LIS", date: "2026-01-01" }], passengers: { adults: 0, infants: 2 } }, NOW);
  assert.ok(r.error.some((e) => e.includes("identiques")));
  assert.ok(r.error.some((e) => e.includes("passée")));
  assert.ok(r.error.some((e) => e.includes("adultes")));
  const multi = parseQuery({ slices: [{ origin: "LIS", destination: "CDG", date: "2026-10-20" }, { origin: "CDG", destination: "FCO", date: "2026-10-18" }] }, NOW);
  assert.ok(multi.error.some((e) => e.includes("avant le trajet précédent")));
  assert.deepEqual(Q.passengers, { adults: 1, children: 0, infants: 0, childAges: [] });
});

// ================= Fuseaux =================
test("durée entre fuseaux et au changement d'heure", () => {
  assert.equal(minutesBetween("2026-10-20T08:00:00", "Europe/Lisbon", "2026-10-20T11:40:00", "Europe/Paris"), 160);
  // Nuit du 25 octobre 2026: Paris passe de +2 a +1.
  assert.equal(minutesBetween("2026-10-25T01:00:00", "Europe/Paris", "2026-10-25T04:00:00", "Europe/Paris"), 240);
  assert.equal(isoDuration("PT2H35M"), 155);
  assert.equal(isoDuration("P1DT2H"), 1560);
});

// ================= Duffel =================
const duffelOffer = {
  id: "off_0000A", total_amount: "142.30", total_currency: "EUR", tax_amount: "38.20", expires_at: "2026-10-01T10:00:00Z",
  owner: { iata_code: "TP", name: "TAP Air Portugal" },
  conditions: { refund_before_departure: { allowed: false }, change_before_departure: { allowed: true, penalty_amount: "50.00" } },
  slices: [{ origin: { iata_code: "LIS", name: "Lisbon", time_zone: "Europe/Lisbon" }, destination: { iata_code: "CDG", time_zone: "Europe/Paris" },
    duration: "PT2H40M", segments: [{ origin: { iata_code: "LIS", time_zone: "Europe/Lisbon" }, destination: { iata_code: "CDG", time_zone: "Europe/Paris" },
      departing_at: "2026-10-20T08:00:00", arriving_at: "2026-10-20T11:40:00",
      marketing_carrier: { iata_code: "TP", name: "TAP" }, operating_carrier: { iata_code: "TP", name: "TAP" }, marketing_carrier_flight_number: "438",
      passengers: [{ cabin_class: "economy", fare_brand_name: "Classic", baggages: [{ type: "checked", quantity: 1 }, { type: "carry_on", quantity: 1 }] }] }] }],
};

test("Duffel: normalisation fidèle, inconnu reste null", () => {
  const o = normalize(duffelOffer, Q, NOW.toISOString());
  assert.equal(o.id, "duffel:off_0000A");
  assert.equal(o.price.total, 142.3);
  assert.equal(o.price.taxesKnown, true);
  assert.equal(o.baggage.checked, 1);
  assert.equal(o.conditions.refundable, false);
  assert.equal(o.conditions.changeable, true);
  assert.equal(o.slices[0].durationMinutes, 160);
  assert.equal(o.seller.kind, "distributor");
  const noBag = structuredClone(duffelOffer); delete noBag.slices[0].segments[0].passengers[0].baggages; delete noBag.tax_amount;
  const u = normalize(noBag, Q, NOW.toISOString());
  assert.equal(u.baggage.checked, null, "bagages inconnus: pas 0");
  assert.equal(u.price.taxesKnown, false);
  assert.equal(normalize({ id: "x" }, Q, ""), null, "sans prix: pas d'offre");
});

test("Duffel: requête conforme à l'API v2, en-têtes et corps", async () => {
  let seen;
  const d = makeDuffel({ token: "duffel_test_x", fetchImpl: async (url, init) => {
    seen = { url, init }; return new Response(JSON.stringify({ data: { offers: [duffelOffer] } }), { status: 201 });
  } });
  const offers = await d.search(Q);
  assert.equal(offers.length, 1);
  assert.match(seen.url, /^https:\/\/api\.duffel\.com\/air\/offer_requests\?return_offers=true&supplier_timeout=\d+$/);
  assert.equal(seen.init.headers["Duffel-Version"], "v2");
  assert.equal(seen.init.headers.Authorization, "Bearer duffel_test_x");
  const body = JSON.parse(seen.init.body);
  assert.deepEqual(body.data.slices, [{ origin: "LIS", destination: "CDG", departure_date: "2026-10-20" }]);
  assert.equal(body.data.cabin_class, "economy");
});

test("Duffel: offre expirée à la relecture = indisponible", async () => {
  const d = makeDuffel({ token: "t", fetchImpl: async () => new Response(JSON.stringify({ errors: [{ code: "offer_no_longer_available", message: "Offer expired" }] }), { status: 422 }) });
  const r = await d.refresh("off_0000A", Q);
  assert.equal(r.status, "unavailable");
});

test("Duffel sans clé: inactif, jamais interrogé", async () => {
  let called = false;
  const d = makeDuffel({ token: "", fetchImpl: async () => { called = true; } });
  const e = makeEngine({ providers: [d] });
  const r = await e.search(Q);
  assert.equal(d.active, false);
  assert.equal(called, false);
  assert.equal(r.statuses.none.status, "no_source");
});

test("Travelport: préparé, jamais annoncé actif", async () => {
  const t = makeTravelport({});
  assert.equal(t.active, false);
  await assert.rejects(t.search(Q), /non configuré/);
});

// ================= Multi-sources =================
test("même itinéraire chez deux sources: regroupé, offres gardées séparées", async () => {
  const A = fake("srcA", [offer("srcA", "1", { price: 150 })]);
  const B = fake("srcB", [offer("srcB", "9", { price: 139 }), offer("srcB", "10", { price: 155, bag: 0 })]);
  const r = await makeEngine({ providers: [A, B] }).search(Q);
  assert.equal(r.groups.length, 1, "un seul itinéraire TP438");
  const g = r.groups[0];
  assert.equal(g.offers.length, 3, "rien n'est fusionné");
  assert.deepEqual(g.sources.sort(), ["srcA", "srcB"]);
  assert.equal(g.offers[0].price.total, 139);
  assert.equal(comparability(g.offers[1], g.offers[2]).equivalent, false, "bagages différents: pas équivalents");
});

test("une source en panne n'empêche pas les autres, résultat marqué partiel", async () => {
  const A = fake("srcA", [offer("srcA", "1", { price: 150 })]);
  const B = fake("srcB", [], { fail: "503 service indisponible" });
  const r = await makeEngine({ providers: [A, B] }).search(Q);
  assert.equal(r.partial, true);
  assert.equal(r.statuses.srcA.status, "ok");
  assert.equal(r.statuses.srcB.status, "error");
  assert.equal(r.groups.length, 1);
});

test("une source trop lente est coupée au délai", async () => {
  const A = fake("srcA", [offer("srcA", "1", { price: 150 })]);
  const slow = fake("slow", [offer("slow", "2", { price: 90 })], { delay: 300 });
  const r = await makeEngine({ providers: [A, slow] }).search(Q, { timeoutMs: 50 });
  assert.equal(r.statuses.slow.status, "timeout");
  assert.equal(r.groups[0].offers.length, 1);
});

test("lots progressifs dans l'ordre d'arrivée", async () => {
  const order = [];
  const A = fake("fast", [offer("fast", "1", { price: 150 })]);
  const B = fake("late", [offer("late", "2", { price: 120, flight: "AF1025" })], { delay: 30 });
  await makeEngine({ providers: [A, B] }).search(Q, { onBatch: (b) => order.push(b.provider) });
  assert.deepEqual(order, ["fast", "late"]);
});

test("une source ne peut pas injecter les offres d'une autre", async () => {
  const bad = fake("srcA", [offer("srcB", "evil", { price: 1 })]);
  const r = await makeEngine({ providers: [bad] }).search(Q);
  assert.equal(r.groups.length, 0);
});

test("cache daté, pas de cache pour un résultat partiel", async () => {
  let calls = 0, t = 0;
  const A = fake("srcA", () => { calls++; return [offer("srcA", "1", { price: 150 })]; });
  const e = makeEngine({ providers: [A], now: () => t });
  await e.search(Q); t = 60000;
  const r = await e.search(Q);
  assert.equal(calls, 1); assert.equal(r.cached, true); assert.equal(r.cachedAgeMs, 60000);
  t = 11 * 60000; await e.search(Q);
  assert.equal(calls, 2, "expiré après 10 min");
  const B = fake("srcB", [], { fail: "x" });
  const e2 = makeEngine({ providers: [A, B] });
  await e2.search(Q); await e2.search(Q);
  assert.equal(calls, 4, "partiel: toujours relancé");
});

test("budget: une source payante n'est appelée qu'après une réservation acceptée", async () => {
  let called = 0;
  const duffelLike = fake("duffel", () => { called++; return [offer("duffel", "1", { price: 100 })]; });
  const refuse = { reserve: async () => ({ ok: false, reason: "Budget de recherche du jour atteint." }), settle: async () => {} };
  const r = await makeEngine({ providers: [duffelLike], budget: refuse }).search(Q);
  assert.equal(r.statuses.duffel.status, "skipped_budget");
  assert.equal(called, 0, "refus = aucun appel");
  const r2 = await makeEngine({ providers: [duffelLike] }).search(Q);
  assert.equal(r2.statuses.duffel.status, "skipped_budget", "sans budget configuré: refus explicite");
  const settled = [];
  const ok = { reserve: async () => ({ ok: true, id: "h1" }), settle: async (id, usd) => { settled.push([id, usd]); } };
  await makeEngine({ providers: [duffelLike], budget: ok }).search(Q);
  assert.deepEqual(settled, [["h1", 0.005]], "coût réel réglé après l'appel");
});

// ================= Relecture avant vendeur =================
test("relecture: même prix, nouveau prix, indisponible", async () => {
  const base = offer("srcA", "1", { price: 150 });
  const mk = (refreshed) => makeEngine({ providers: [fake("srcA", [base], { refreshed })] });
  assert.equal((await mk(() => ({ status: "ok", offer: base })).confirm(base, Q)).status, "same_price");
  const up = await mk(() => ({ status: "ok", offer: { ...base, price: { ...base.price, total: 171.5 } } })).confirm(base, Q);
  assert.equal(up.status, "price_changed"); assert.equal(up.delta, 21.5);
  assert.equal((await mk(() => ({ status: "unavailable", reason: "expirée" })).confirm(base, Q)).status, "unavailable");
});

// ================= Classement, analyse, filtres =================
test("moins cher: à prix égal, l'offre aux frais connus passe devant", () => {
  const g = group([offer("a", "1", { price: 100, taxesKnown: false, flight: "AA1" }), offer("b", "2", { price: 100, flight: "BB2" })]);
  assert.equal(rank(g).cheapest[0].offers[0].provider, "b");
});

test("meilleur compromis expliqué et pénalités visibles", () => {
  const direct = offer("a", "1", { price: 180, flight: "TP438" });
  const selfT = offer("b", "2", { price: 120, selfTransfer: true, segments: [
    { origin: { iata: "LIS", timeZone: "Europe/Lisbon" }, destination: { iata: "MAD", timeZone: "Europe/Madrid" }, departingAt: "2026-10-20T06:00:00", arrivingAt: "2026-10-20T08:15:00",
      marketingCarrier: { code: "FR", name: null }, operatingCarrier: { code: "FR", name: null }, flightNumber: "1", cabin: "economy", fareBrand: null },
    { origin: { iata: "MAD", timeZone: "Europe/Madrid" }, destination: { iata: "ORY", timeZone: "Europe/Paris" }, departingAt: "2026-10-20T13:00:00", arrivingAt: "2026-10-20T15:05:00",
      marketingCarrier: { code: "VY", name: null }, operatingCarrier: { code: "VY", name: null }, flightNumber: "2", cabin: "economy", fareBrand: null }] });
  const r = rank(group([direct, selfT]));
  assert.equal(r.cheapest[0].offers[0].provider, "b");
  assert.equal(r.best[0].offers[0].provider, "a", "le direct gagne malgré 60 € de plus");
  assert.match(r.best[1].explanation, /transfert autonome/);
  assert.match(r.best[0].explanation, /^60 EUR de plus que le moins cher, le plus rapide\.$/);
  assert.match(r.best[1].explanation, /^Le moins cher, .* de plus que le plus rapide\. Pénalisé : 1 escale\(s\), transfert autonome/);
  const a = analyse(selfT);
  assert.ok(a.warnings.some((w) => w.includes("Transfert autonome")));
  assert.equal(a.slices[0].layovers[0].minutes, 285);
});

test("changement d'aéroport et nuit sur place détectés", () => {
  const o = offer("a", "1", { price: 90, segments: [
    { origin: { iata: "LIS", timeZone: "Europe/Lisbon" }, destination: { iata: "LGW", timeZone: "Europe/London" }, departingAt: "2026-10-20T20:00:00", arrivingAt: "2026-10-20T23:30:00",
      marketingCarrier: { code: "U2", name: null }, operatingCarrier: { code: "U2", name: null }, flightNumber: "1", cabin: "economy", fareBrand: null },
    { origin: { iata: "LHR", timeZone: "Europe/London" }, destination: { iata: "CDG", timeZone: "Europe/Paris" }, departingAt: "2026-10-21T07:00:00", arrivingAt: "2026-10-21T09:20:00",
      marketingCarrier: { code: "BA", name: null }, operatingCarrier: { code: "BA", name: null }, flightNumber: "2", cabin: "economy", fareBrand: null }] });
  const a = analyse(o);
  assert.equal(a.slices[0].layovers[0].airportChange, true);
  assert.equal(a.slices[0].layovers[0].overnight, true);
});

test("filtres: escales, bagage exigé, prix, démo", () => {
  const g = group([offer("a", "1", { price: 150 }), offer("b", "2", { price: 90, bag: 0, flight: "U21" })]);
  assert.equal(applyFilters(g, { checkedBagRequired: true }).length, 1);
  assert.equal(applyFilters(g, { maxPrice: 100 }).length, 1);
  const demoG = group([{ ...offer("demo", "x", { price: 10, flight: "ZZ1" }), demo: true }]);
  assert.equal(applyFilters(demoG, { excludeDemo: true }).length, 0);
});

test("clé d'itinéraire: mêmes vols seulement", () => {
  assert.notEqual(itineraryKey(offer("a", "1", { price: 1 })), itineraryKey(offer("a", "2", { price: 1, dep: "2026-10-20T09:00:00" })));
});

// ================= Alertes =================
test("alerte: une fois, réarmée, jamais sur une démo, un prix incomplet ou un prix converti", async () => {
  const at = (...offers) => ({ groups: group(offers) });
  const alert = { maxPrice: 120, triggered: false, currency: "EUR" };
  assert.equal(evaluateAlert(alert, at(offer("a", "1", { price: 110 }))).trigger, true);
  assert.equal(evaluateAlert({ ...alert, triggered: true }, at(offer("a", "1", { price: 105 }))).trigger, false);
  assert.equal(evaluateAlert(alert, at(offer("a", "1", { price: 110, taxesKnown: false }))).trigger, false);
  assert.equal(evaluateAlert(alert, at({ ...offer("demo", "d", { price: 10 }), demo: true })).trigger, false);
  const converted = normalizeCurrency([offer("a", "1", { price: 100, currency: "USD" })], "EUR", { base: "EUR", date: "2026-09-28", source: "BCE", rates: { USD: 1.25 } }).comparable;
  assert.equal(converted[0].price.total, 80);
  assert.equal(evaluateAlert(alert, at(...converted)).trigger, false, "80 EUR converti ne déclenche pas une alerte en EUR");
});

// ================= Défauts de l'audit du 28 septembre =================
test("audit: date inexistante refusée, âge de chaque enfant exigé", () => {
  assert.equal(isCalendarDate("2027-02-31"), false);
  assert.equal(isCalendarDate("2028-02-29"), true);
  assert.ok(parseQuery({ slices: [{ origin: "LIS", destination: "CDG", date: "2027-02-31" }] }, NOW).error.some((e) => e.includes("date invalide")));
  const noAge = parseQuery({ slices: [{ origin: "LIS", destination: "CDG", date: "2026-11-02" }], passengers: { adults: 1, children: 2, childAges: [5] } }, NOW);
  assert.ok(noAge.error.some((e) => e.includes("âge de chaque enfant")));
  const ok = parseQuery({ slices: [{ origin: "LIS", destination: "CDG", date: "2026-11-02" }], passengers: { adults: 1, children: 2, childAges: [5, 11] } }, NOW);
  assert.deepEqual(ok.query.passengers.childAges, [5, 11]);
});

test("audit: Duffel reçoit l'âge réel des enfants, jamais 8 ans par défaut", async () => {
  let body;
  const d = makeDuffel({ token: "t", fetchImpl: async (u, init) => { body = JSON.parse(init.body); return new Response(JSON.stringify({ data: { offers: [] } }), { status: 201 }); } });
  const q = parseQuery({ slices: [{ origin: "LIS", destination: "CDG", date: "2026-11-02" }], passengers: { adults: 2, children: 2, childAges: [3, 14], infants: 1 } }, NOW).query;
  await d.search(q);
  assert.deepEqual(body.data.passengers, [{ type: "adult" }, { type: "adult" }, { age: 3 }, { age: 14 }, { type: "infant_without_seat" }]);
});

test("audit: bagages par voyageur, le chiffre affiché est celui garanti à tous", () => {
  const o = structuredClone(duffelOffer);
  o.passengers = [{ id: "pa", type: "adult" }, { id: "pc", age: 5 }];
  o.slices[0].segments[0].passengers = [
    { passenger_id: "pa", cabin_class: "economy", baggages: [{ type: "checked", quantity: 1 }, { type: "carry_on", quantity: 1 }] },
    { passenger_id: "pc", cabin_class: "economy", baggages: [{ type: "carry_on", quantity: 1 }] },
  ];
  const n = normalize(o, Q, NOW.toISOString());
  assert.equal(n.baggage.checked, 0, "l'enfant n'a pas de soute: 0 garanti, pas 1");
  assert.equal(n.baggage.varies, true);
  assert.deepEqual(n.baggage.perPassenger.map((p) => p.checked), [1, 0]);
  delete o.slices[0].segments[0].passengers[1].baggages;
  assert.equal(normalize(o, Q, NOW.toISOString()).baggage.checked, null, "un voyageur inconnu: inconnu");
});

test("audit: filtres combinés sur la MÊME offre, analyse recalculée", () => {
  const cheapNoBag = offer("a", "1", { price: 100, bag: 0 });
  const bagPricey = offer("b", "2", { price: 160, bag: 1 });
  const g = group([cheapNoBag, bagPricey]);
  assert.equal(applyFilters(g, { checkedBagRequired: true, maxPrice: 120 }).length, 0, "aucune offre ne satisfait les deux");
  const kept = applyFilters(g, { checkedBagRequired: true });
  assert.equal(kept[0].offers.length, 1);
  assert.equal(kept[0].offers[0].price.total, 160, "le prix représentatif suit l'offre restante");
  assert.deepEqual(kept[0].sources, ["b"]);
  assert.equal(rank(kept).best[0].explanation, "Le moins cher, le plus rapide.");
});

test("audit: jamais de classement entre devises sans conversion", () => {
  const eur = offer("a", "1", { price: 100 }), jpy = offer("b", "2", { price: 500, currency: "JPY", flight: "NH1" });
  assert.throws(() => rank(group([eur, jpy])), /devises mélangées/);
  const none = summarize([eur, jpy], Q, null);
  assert.equal(none.groups.length, 1, "le yen est mis à part sans taux");
  assert.deepEqual(none.setAside, { count: 1, currencies: ["JPY"] });
  const withRates = summarize([eur, jpy], Q, { base: "EUR", date: "2026-09-28", source: "BCE", rates: { JPY: 160 } });
  const conv = withRates.groups.flatMap((x) => x.offers).find((o) => o.provider === "b");
  assert.equal(conv.price.total, 3.13);
  assert.deepEqual(conv.price.original, { total: 500, currency: "JPY" });
  assert.equal(conv.price.conversion.date, "2026-09-28");
  assert.equal(withRates.ranking.cheapest[0].offers[0].provider, "b", "500 JPY ≈ 3,13 EUR: vraiment moins cher");
});

test("audit: taux BCE lus depuis le XML officiel", () => {
  const t = parseEcb(ECB_XML);
  assert.equal(t.date, "2026-09-28"); assert.equal(t.rates.USD, 1.1712); assert.equal(t.base, "EUR");
});

test("audit: relecture bornée dans le temps et vérifiée", async () => {
  const base = offer("srcA", "1", { price: 150 });
  const slow = makeEngine({ providers: [fake("srcA", [base], { refreshed: () => new Promise(() => {}) })] });
  assert.equal((await slow.confirm(base, Q, { timeoutMs: 30 })).status, "error");
  const other = makeEngine({ providers: [fake("srcA", [base], { refreshed: () => ({ status: "ok", offer: offer("srcA", "1", { price: 150, flight: "AF99" }) }) })] });
  assert.equal((await other.confirm(base, Q)).status, "unavailable", "autre itinéraire: pas une confirmation");
  const cur = makeEngine({ providers: [fake("srcA", [base], { refreshed: () => ({ status: "ok", offer: offer("srcA", "1", { price: 170, currency: "USD" }) }) })] });
  const c = await cur.confirm(base, Q);
  assert.equal(c.status, "price_changed"); assert.equal(c.delta, null, "pas de différence entre deux devises");
});

test("audit: cache borné, recherches identiques simultanées mutualisées", async () => {
  let calls = 0;
  const A = fake("srcA", async () => { calls++; await new Promise((r) => setTimeout(r, 20)); return [offer("srcA", "1", { price: 150 })]; });
  const cache = new Map();
  const e = makeEngine({ providers: [A], cache });
  await Promise.all([e.search(Q), e.search(Q), e.search(Q)]);
  assert.equal(calls, 1, "trois recherches identiques en même temps: un seul appel");
  for (let i = 0; i < CACHE_MAX + 20; i++) cache.set(`k${i}`, { at: Date.now(), result: {} });
  const q2 = parseQuery({ slices: [{ origin: "LIS", destination: "OPO", date: "2026-10-21" }] }, NOW).query;
  await e.search(q2);
  assert.ok(cache.size <= CACHE_MAX, `taille ${cache.size}`);
});

// ================= Worker =================
const kv = (pageSize = 1000) => { const m = new Map(); return {
  get: async (k) => m.get(k) ?? null, put: async (k, v) => { m.set(k, v); }, delete: async (k) => { m.delete(k); },
  list: async ({ prefix, cursor }) => {
    // Comme KV: le curseur marque la derniere cle rendue (ordre lexical), pas une position.
    const all = [...m.keys()].filter((k) => k.startsWith(prefix) && (!cursor || k > cursor)).sort();
    const keys = all.slice(0, pageSize).map((name) => ({ name }));
    const done = all.length <= pageSize;
    return { keys, list_complete: done, cursor: done ? undefined : keys[keys.length - 1].name };
  }, _m: m }; };

/** Le vrai BudgetGate, sur un stockage en memoire, derriere un faux binding Durable Object. */
function budgetBinding() {
  const store = new Map();
  const gate = new BudgetGate({ storage: { get: async (k) => store.get(k), put: async (k, v) => { store.set(k, structuredClone(v)); } },
    blockConcurrencyWhile: (fn) => fn() });
  return { idFromName: () => "global", get: () => ({ fetch: (url, init) => gate.fetch(new Request(url, init)) }), gate };
}

const ECB_XML = `<?xml version="1.0"?><gesmes:Envelope><Cube><Cube time='2026-09-28'><Cube currency='USD' rate='1.1712'/><Cube currency='JPY' rate='160.5'/></Cube></Cube></gesmes:Envelope>`;

/** Faux reseau: Duffel ou la BCE selon l'adresse; compte les appels a Duffel. */
function net({ offers = [duffelOffer], delay = 0 } = {}) {
  const n = { duffel: 0 };
  n.fetchImpl = async (url) => {
    if (String(url).includes("ecb.europa.eu")) return new Response(ECB_XML, { status: 200 });
    n.duffel++;
    if (delay) await new Promise((r) => setTimeout(r, delay));
    return new Response(JSON.stringify({ data: { offers } }), { status: 201 });
  };
  return n;
}
const H = (ip = "1.1.1.1") => ({ "X-LifeOS-Key": "k", "CF-Connecting-IP": ip });
const searchReq = (date, ip) => new Request("https://x/v1/search", { method: "POST", headers: H(ip),
  body: JSON.stringify({ slices: [{ origin: "LIS", destination: "CDG", date }], passengers: { adults: 1 } }) });

test("worker: clé d'application obligatoire", async () => {
  const r = await worker.fetch(new Request("https://x/v1/providers"), { APP_KEY: "k" });
  assert.equal(r.status, 401);
});

test("worker: une seule source réelle = pas multi-sources, Travelport déclaré squelette", async () => {
  const r = await worker.fetch(new Request("https://x/v1/providers", { headers: H() }), { APP_KEY: "k", DUFFEL_TOKEN: "t" });
  const body = await r.json();
  assert.equal(body.multiSource, false);
  assert.equal(body.providers.find((p) => p.id === "duffel").active, true);
  const tp = body.providers.find((p) => p.id === "travelport");
  assert.equal(tp.active, false); assert.equal(tp.skeleton, true);
  assert.equal(body.budget.configured, false);
  assert.equal(body.alerts.serverChecks, false, "alertes annoncées inactives tant que le cron n'est pas posé");
});

test("worker: sans stockage de budget, Duffel n'est jamais appelé", async () => {
  resetRatesCache();
  const n = net();
  const body = await (await worker.fetch(searchReq("2099-10-19"), { APP_KEY: "k", DUFFEL_TOKEN: "t" }, null, n)).json();
  assert.equal(n.duffel, 0);
  assert.equal(body.statuses.duffel.status, "skipped_budget");
  assert.match(body.statuses.duffel.message, /Budget non configuré/);
});

test("worker: budget pour UN appel, trois recherches simultanées = un seul appel payant", async () => {
  resetRatesCache();
  const n = net({ delay: 20 });
  const env = { APP_KEY: "k", DUFFEL_TOKEN: "t", BUDGET: budgetBinding(), DAILY_BUDGET_USD: "0.005" };
  const dates = ["2099-11-01", "2099-11-02", "2099-11-03"];
  const out = await Promise.all(dates.map((d) => worker.fetch(searchReq(d), env, null, n).then((r) => r.json())));
  assert.equal(n.duffel, 1, `${n.duffel} appels`);
  assert.equal(out.filter((b) => b.statuses.duffel.status === "ok").length, 1);
  assert.equal(out.filter((b) => b.statuses.duffel.status === "skipped_budget").length, 2);
});

test("worker: limite de recherches payantes par adresse et par jour", async () => {
  resetRatesCache();
  const n = net();
  const env = { APP_KEY: "k", DUFFEL_TOKEN: "t", BUDGET: budgetBinding(), CLIENT_DAILY_SEARCHES: "2" };
  for (const d of ["2099-12-01", "2099-12-02", "2099-12-03"]) await worker.fetch(searchReq(d, "9.9.9.9"), env, null, n);
  assert.equal(n.duffel, 2, "le troisième est refusé");
  const other = await (await worker.fetch(searchReq("2099-12-04", "8.8.8.8"), env, null, n)).json();
  assert.equal(other.statuses.duffel.status, "ok", "une autre adresse garde son quota");
});

test("worker: recherche Duffel de bout en bout, cache sans coût", async () => {
  resetRatesCache();
  const n = net();
  const env = { APP_KEY: "k", DUFFEL_TOKEN: "t", BUDGET: budgetBinding() };
  const body = await (await worker.fetch(searchReq("2099-10-20"), env, null, n)).json();
  assert.equal(body.count, 1);
  assert.equal(body.partial, false, "Travelport inactif n'est pas interrogé");
  assert.equal(body.cheapest[0].offers[0].price.total, 142.3);
  const spent = env.BUDGET.gate.data.days[new Date().toISOString().slice(0, 10)].spent;
  assert.equal(spent, 0.005);
  const again = await (await worker.fetch(searchReq("2099-10-20"), env, null, n)).json();
  assert.equal(again.cached, true);
  assert.equal(n.duffel, 1, "le cache ne rappelle pas Duffel");
});

test("worker: offre en dollars convertie au taux BCE daté, prix facturé gardé", async () => {
  resetRatesCache();
  const usd = { ...structuredClone(duffelOffer), id: "off_usd", total_currency: "USD", total_amount: "117.12" };
  const n = net({ offers: [usd] });
  const env = { APP_KEY: "k", DUFFEL_TOKEN: "t", BUDGET: budgetBinding() };
  const body = await (await worker.fetch(searchReq("2099-10-22"), env, null, n)).json();
  const o = body.cheapest[0].offers[0];
  assert.equal(o.price.currency, "EUR"); assert.equal(o.price.total, 100);
  assert.deepEqual(o.price.original, { total: 117.12, currency: "USD" });
  assert.equal(body.ratesDate, "2026-09-28");
});

test("worker: alertes refusées tant que la surveillance serveur n'est pas activée", async () => {
  const env = { APP_KEY: "k", STATE: kv() };
  const post = await worker.fetch(new Request("https://x/v1/alerts", { method: "POST", headers: H(),
    body: JSON.stringify({ query: { slices: [{ origin: "LIS", destination: "CDG", date: "2099-10-20" }] }, maxPrice: 120 }) }), env);
  assert.equal(post.status, 503);
});

test("worker: alertes créées, lues avec jeton, désinscription", async () => {
  const env = { APP_KEY: "k", STATE: kv(), ALERTS_CRON: "on" };
  const post = await worker.fetch(new Request("https://x/v1/alerts", { method: "POST", headers: H(),
    body: JSON.stringify({ query: { slices: [{ origin: "LIS", destination: "CDG", date: "2099-10-20" }] }, maxPrice: 120 }) }), env);
  assert.equal(post.status, 201);
  const { id, token } = await post.json();
  assert.equal((await worker.fetch(new Request(`https://x/v1/alerts/${id}?token=bad`, { headers: H() }), env)).status, 404);
  const got = await (await worker.fetch(new Request(`https://x/v1/alerts/${id}?token=${token}`, { headers: H() }), env)).json();
  assert.equal(got.maxPrice, 120); assert.equal(got.currency, "EUR"); assert.equal(got.token, undefined, "le jeton n'est jamais renvoyé");
  const del = await worker.fetch(new Request(`https://x/v1/alerts/${id}?token=${token}`, { method: "DELETE", headers: H() }), env);
  assert.equal(del.status, 200);
  assert.equal(env.STATE._m.size, 0);
});

test("worker: tâche planifiée, pagination, alerte cassée isolée, désinscrite non recréée", async () => {
  resetRatesCache();
  const env = { APP_KEY: "k", DUFFEL_TOKEN: "t", STATE: kv(2), BUDGET: budgetBinding(), ALERTS_CRON: "on" };
  const q = parseQuery({ slices: [{ origin: "LIS", destination: "CDG", date: "2099-10-20" }] }).query;
  for (const i of [1, 2, 3, 4, 5]) await env.STATE.put(`alert:${i}`, JSON.stringify({ id: String(i), token: "z", maxPrice: 150, currency: "EUR", triggered: false, query: q }));
  await env.STATE.put("alert:6", "{cassé");
  const n = net();
  const realGet = env.STATE.get;
  let seen = 0;
  env.STATE.get = async (k) => { if (k === "alert:3" && ++seen === 2) env.STATE._m.delete("alert:3"); return realGet(k); };
  const r = await worker.scheduled({}, env, null, n);
  assert.equal(r.failed, 1, "l'alerte illisible échoue seule");
  assert.equal(r.checked, 4, "les autres pages sont bien lues");
  assert.equal(await realGet("alert:3"), null, "désinscrite pendant le passage: pas recréée");
  const a = JSON.parse(await realGet("alert:5"));
  assert.equal(a.triggered, true); assert.ok(a.triggeredAt);
  assert.equal(a.lastPrice.total, 142.3);
});

test("worker: flux progressif, résultats partiels consultables puis le résultat", async () => {
  resetRatesCache();
  const n = net();
  const env = { APP_KEY: "k", DUFFEL_TOKEN: "t", BUDGET: budgetBinding() };
  const req = new Request("https://x/v1/search?stream=1", { method: "POST", headers: H(),
    body: JSON.stringify({ slices: [{ origin: "LIS", destination: "CDG", date: "2099-10-21" }] }) });
  const r = await worker.fetch(req, env, undefined, n);
  const lines = (await r.text()).trim().split("\n").map((l) => JSON.parse(l));
  assert.deepEqual(lines.map((l) => l.type), ["partial", "done"]);
  assert.equal(lines[0].provider, "duffel");
  assert.equal(lines[0].cheapest[0].offers[0].price.total, 142.3, "le lot partiel porte les offres, pas seulement un compteur");
  assert.equal(lines[1].cheapest[0].offers[0].price.total, 142.3);
});

for (const [name, fn] of tests) {
  try { await fn(); passed++; console.log("ok  ", name); }
  catch (e) { console.log("FAIL", name, "\n     ", e.message); process.exitCode = 1; }
}
console.log(`\n${passed}/${tests.length} contrôles passent`);
