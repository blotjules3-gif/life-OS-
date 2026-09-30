// Coeur du comparateur de vols LifeOS: modele commun, regroupement, classement.
//
// Aucun fournisseur n'apparait ici. Chaque adaptateur (providers/*.js) traduit
// SA reponse vers ce modele; tout le reste (regroupement, classement, filtres,
// explications) appartient a LifeOS.
//
// Regles:
//   - une valeur inconnue reste `null` (bagages, conditions, frais), jamais 0;
//   - deux offres ne se fusionnent JAMAIS: le regroupement met cote a cote des
//     offres du MEME itineraire (memes vols), chacune garde vendeur, tarif,
//     bagages et conditions;
//   - une offre dont les frais ou bagages sont inconnus n'est pas classee
//     "moins chere" devant une offre complete sans le dire.

/** @typedef {{ iata: string, name?: string|null, timeZone?: string|null }} Place */

/**
 * Offre normalisee.
 * @typedef {{
 *   id: string,                     // identifiant LifeOS: `${provider}:${ref}`
 *   provider: string,               // source (duffel, travelport, demo...)
 *   providerRef: string,            // reference PROPRE a la source, jamais reutilisee ailleurs
 *   seller: { code: string|null, name: string, kind: "airline"|"agency"|"distributor" },
 *   demo: boolean,
 *   slices: Array<{
 *     origin: Place, destination: Place, durationMinutes: number|null,
 *     segments: Array<{
 *       origin: Place, destination: Place,
 *       departingAt: string, arrivingAt: string,   // heure LOCALE ISO sans decalage, + fuseau dans Place
 *       marketingCarrier: { code: string, name: string|null },
 *       operatingCarrier: { code: string, name: string|null },
 *       flightNumber: string|null, cabin: string|null, fareBrand: string|null,
 *     }>,
 *   }>,
 *   passengers: { adults: number, children: number, infants: number, childAges: number[] },
 *   price: { total: number, currency: string, taxesKnown: boolean, feesNote: string|null,
 *            original?: { total: number, currency: string },            // prix facture, si converti
 *            conversion?: { rate: number, source: string, date: string } },
 *   baggage: { checked: number|null, carryOn: number|null,        // GARANTI a chaque voyageur; null = inconnu
 *              varies?: boolean,                                  // franchise differente selon le voyageur
 *              perPassenger?: Array<{ label: string, checked: number|null, carryOn: number|null }> },
 *   conditions: { refundable: boolean|null, changeable: boolean|null },
 *   selfTransfer: boolean|null,
 *   fetchedAt: string, expiresAt: string|null,
 * }} Offer
 */

export const CABINS = ["economy", "premium_economy", "business", "first"];

// ---------- Requete ----------

/** Valide et normalise une recherche. Rend { query } ou { error }. */
export function parseQuery(body, now = new Date()) {
  const errors = [];
  const slices = Array.isArray(body?.slices) ? body.slices : [];
  if (slices.length < 1 || slices.length > 6) errors.push("De 1 à 6 trajets.");
  const today = now.toISOString().slice(0, 10);
  const clean = slices.map((s, i) => {
    const origin = String(s?.origin || "").toUpperCase().trim();
    const destination = String(s?.destination || "").toUpperCase().trim();
    const date = String(s?.date || s?.departure_date || "");
    if (!/^[A-Z]{3}$/.test(origin)) errors.push(`Trajet ${i + 1} : aéroport ou ville de départ invalide.`);
    if (!/^[A-Z]{3}$/.test(destination)) errors.push(`Trajet ${i + 1} : destination invalide.`);
    if (origin && origin === destination) errors.push(`Trajet ${i + 1} : départ et arrivée identiques.`);
    if (!isCalendarDate(date)) errors.push(`Trajet ${i + 1} : date invalide.`);
    else if (date < today) errors.push(`Trajet ${i + 1} : date passée.`);
    return { origin, destination, date };
  });
  for (let i = 1; i < clean.length; i++) {
    if (clean[i].date < clean[i - 1].date) errors.push(`Trajet ${i + 1} : date avant le trajet précédent.`);
  }
  const p = body?.passengers || {};
  const adults = int(p.adults, 1), children = int(p.children, 0), infants = int(p.infants, 0);
  if (adults < 1 || adults > 9) errors.push("De 1 à 9 adultes.");
  if (children < 0 || children > 8 || adults + children > 9) errors.push("9 voyageurs au plus.");
  if (infants < 0 || infants > adults) errors.push("Un bébé par adulte au plus.");
  // L'age de chaque enfant change le tarif chez les compagnies: il est exige,
  // jamais invente. Bebe = moins de 2 ans, sur les genoux d'un adulte.
  const childAges = Array.isArray(p.childAges) ? p.childAges.map((a) => Number.parseInt(a, 10)) : [];
  if (children > 0 && childAges.length !== children) errors.push("Indique l'âge de chaque enfant.");
  if (childAges.some((a) => !Number.isInteger(a) || a < 2 || a > 17)) errors.push("Âge d'enfant entre 2 et 17 ans.");
  const cabin = CABINS.includes(body?.cabin) ? body.cabin : "economy";
  const currency = /^[A-Z]{3}$/.test(body?.currency || "") ? body.currency : "EUR";
  const maxConnections = Math.min(2, Math.max(0, int(body?.maxConnections, 1)));
  if (errors.length) return { error: errors };
  return { query: { slices: clean, passengers: { adults, children, infants, childAges: children ? childAges : [] }, cabin, currency, maxConnections } };
}

function int(v, d) { const n = Number.parseInt(v, 10); return Number.isFinite(n) ? n : d; }

/** "2027-02-31" a le bon format et n'existe pas: on refuse. */
export function isCalendarDate(s) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const [y, m, d] = s.split("-").map(Number);
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
}

// ---------- Temps ----------

/** Minutes entre deux heures locales de fuseaux differents. */
export function minutesBetween(localA, tzA, localB, tzB) {
  const a = toUTC(localA, tzA), b = toUTC(localB, tzB);
  if (a == null || b == null) return null;
  return Math.round((b - a) / 60000);
}

/** Heure locale "YYYY-MM-DDTHH:mm:ss" + fuseau IANA -> ms UTC. */
export function toUTC(local, tz) {
  if (!local) return null;
  if (/[zZ]|[+-]\d{2}:?\d{2}$/.test(local)) return Date.parse(local);
  if (!tz) return null;
  const guess = Date.parse(local + "Z");
  if (Number.isNaN(guess)) return null;
  // Decalage du fuseau a cet instant (gere les changements d'heure).
  const offset = tzOffsetMinutes(guess, tz);
  const first = guess - offset * 60000;
  const offset2 = tzOffsetMinutes(first, tz);
  return guess - offset2 * 60000;
}

function tzOffsetMinutes(utcMs, tz) {
  const f = new Intl.DateTimeFormat("en-US", { timeZone: tz, hour12: false, year: "numeric", month: "2-digit",
    day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" });
  const parts = Object.fromEntries(f.formatToParts(new Date(utcMs)).map((x) => [x.type, x.value]));
  const asUTC = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour % 24, +parts.minute, +parts.second);
  return Math.round((asUTC - utcMs) / 60000);
}

// ---------- Analyse d'une offre ----------

/** Correspondances, changements d'aeroport, nuits sur place, duree totale. */
export function analyse(offer) {
  const slices = offer.slices.map((s) => {
    const segs = s.segments;
    const layovers = [];
    for (let i = 1; i < segs.length; i++) {
      const prev = segs[i - 1], next = segs[i];
      const minutes = minutesBetween(prev.arrivingAt, prev.destination.timeZone, next.departingAt, next.origin.timeZone);
      layovers.push({
        at: prev.destination.iata,
        minutes,
        airportChange: prev.destination.iata !== next.origin.iata,
        overnight: prev.arrivingAt.slice(0, 10) !== next.departingAt.slice(0, 10),
      });
    }
    const first = segs[0], last = segs[segs.length - 1];
    const duration = s.durationMinutes ??
      minutesBetween(first.departingAt, first.origin.timeZone, last.arrivingAt, last.destination.timeZone);
    return { stops: segs.length - 1, layovers, durationMinutes: duration };
  });
  const totalMinutes = slices.every((s) => s.durationMinutes != null)
    ? slices.reduce((a, s) => a + s.durationMinutes, 0) : null;
  const warnings = [];
  if (offer.selfTransfer) warnings.push("Transfert autonome : bagages et correspondance à ta charge.");
  if (slices.some((s) => s.layovers.some((l) => l.airportChange))) warnings.push("Changement d'aéroport pendant la correspondance.");
  if (slices.some((s) => s.layovers.some((l) => l.overnight))) warnings.push("Nuit sur place pendant une correspondance.");
  if (slices.some((s) => s.layovers.some((l) => l.minutes != null && l.minutes < 60))) warnings.push("Correspondance de moins d'une heure.");
  if (offer.baggage.checked == null) warnings.push("Bagage en soute : inconnu pour cette offre.");
  if (!offer.price.taxesKnown) warnings.push("Taxes ou frais pas tous connus : le prix peut augmenter.");
  return { slices, totalMinutes, warnings };
}

// ---------- Regroupement ----------

/** Cle d'itineraire: les memes vols (compagnie + numero + depart), rien d'autre. */
export function itineraryKey(offer) {
  return offer.slices.map((s) => s.segments.map((g) =>
    `${g.marketingCarrier.code}${g.flightNumber || "?"}@${g.origin.iata}${g.departingAt.slice(0, 16)}`).join(">")).join("|");
}

/**
 * Regroupe par itineraire. Chaque groupe garde TOUTES ses offres (vendeurs,
 * tarifs, bagages differents), triees par prix. Rien n'est fusionne.
 */
export function group(offers) {
  const map = new Map();
  for (const o of offers) {
    const k = itineraryKey(o);
    if (!map.has(k)) map.set(k, []);
    map.get(k).push(o);
  }
  return [...map.entries()].map(([key, list]) => {
    list.sort((a, b) => a.price.total - b.price.total);
    return { key, offers: list, analysis: analyse(list[0]), sources: [...new Set(list.map((o) => o.provider))] };
  });
}

// ---------- Filtres ----------

/**
 * Filtres. Un critere d'OFFRE (prix, bagage, transfert autonome, demo) s'applique
 * a chaque offre: un groupe ne reste que si UNE offre satisfait TOUS les
 * criteres a la fois. Les offres qui echouent sont retirees, puis l'analyse et
 * les sources sont recalculees. Les criteres d'ITINERAIRE (escales, aeroport,
 * compagnies, duree) valent pour tout le groupe, les vols etant les memes.
 */
export function applyFilters(groups, f = {}) {
  const offerOk = (o) =>
    (f.maxPrice == null || o.price.total <= f.maxPrice) &&
    (!f.checkedBagRequired || (o.baggage.checked ?? 0) >= 1) &&
    (!f.noSelfTransfer || o.selfTransfer !== true) &&
    (!f.excludeDemo || !o.demo);
  const out = [];
  for (const g of groups) {
    const a = g.analysis;
    if (f.maxStops != null && a.slices.some((s) => s.stops > f.maxStops)) continue;
    if (f.noAirportChange && a.slices.some((s) => s.layovers.some((l) => l.airportChange))) continue;
    if (f.carriers?.length && !g.offers[0].slices.every((s) => s.segments.every((x) => f.carriers.includes(x.marketingCarrier.code)))) continue;
    if (f.maxDurationMinutes != null && (a.totalMinutes == null || a.totalMinutes > f.maxDurationMinutes)) continue;
    const offers = g.offers.filter(offerOk);
    if (!offers.length) continue;
    out.push(offers.length === g.offers.length ? g : withOffers(g, offers));
  }
  return out;
}

function withOffers(g, offers) {
  return { key: g.key, offers, analysis: analyse(offers[0]), sources: [...new Set(offers.map((o) => o.provider))] };
}

// ---------- Devises ----------

/**
 * Une seule devise par classement. Une offre dans la devise demandee passe telle
 * quelle. Une autre devise n'est comparee que convertie avec un taux DATE, et le
 * prix facture reste visible (`original`). Sans taux, l'offre est mise a part,
 * jamais classee: comparer 100 EUR et 500 JPY comme des nombres est faux.
 */
export function normalizeCurrency(offers, target, rates) {
  const comparable = [], setAside = [];
  for (const o of offers) {
    const from = o.price.currency;
    if (from === target) { comparable.push(o); continue; }
    const rate = rates && crossRate(rates, from, target);
    if (!rate) { setAside.push(o); continue; }
    comparable.push({ ...o, price: { ...o.price,
      total: Math.round(o.price.total * rate * 100) / 100, currency: target,
      original: { total: o.price.total, currency: from },
      conversion: { rate, source: rates.source, date: rates.date } } });
  }
  return { comparable, setAside };
}

/** Taux croise depuis une table en base EUR (BCE): EUR->X = rates[X]. */
export function crossRate(table, from, to) {
  const r = (c) => (c === table.base ? 1 : table.rates?.[c]);
  const a = r(from), b = r(to);
  return a > 0 && b > 0 ? b / a : null;
}

/** La devise dans laquelle le vendeur facture reellement. */
export function billedPrice(o) { return o.price.original || { total: o.price.total, currency: o.price.currency }; }

// ---------- Classement ----------

/**
 * Trois classements, jamais sponsorises:
 *   - moins cher: prix total; a prix egal, l'offre aux frais CONNUS passe devant;
 *     une offre aux frais inconnus est marquee et ne gagne pas en silence;
 *   - plus rapide: duree totale (inconnue = en fin de liste);
 *   - meilleur compromis: prix et duree normalises sur les resultats, penalites
 *     explicites (escales, transfert autonome, changement d'aeroport, nuit,
 *     bagages inconnus). L'explication est rendue avec chaque resultat.
 */
export function rank(groups) {
  const currencies = new Set(groups.flatMap((g) => g.offers.map((o) => o.price.currency)));
  if (currencies.size > 1) throw new Error(`Classement refusé : devises mélangées (${[...currencies].join(", ")}).`);
  const withPrice = groups.filter((g) => Number.isFinite(g.offers[0]?.price.total));
  const prices = withPrice.map((g) => g.offers[0].price.total);
  const durations = withPrice.map((g) => g.analysis.totalMinutes).filter((x) => x != null);
  const [pMin, pMax] = [Math.min(...prices), Math.max(...prices)];
  const [dMin, dMax] = durations.length ? [Math.min(...durations), Math.max(...durations)] : [0, 0];
  const norm = (v, lo, hi) => (hi > lo ? (v - lo) / (hi - lo) : 0);

  const scored = withPrice.map((g) => {
    const o = g.offers[0], a = g.analysis;
    const reasons = [];
    let score = 0.55 * norm(o.price.total, pMin, pMax);
    score += a.totalMinutes == null ? 0.45 : 0.45 * norm(a.totalMinutes, dMin, dMax);
    const stops = a.slices.reduce((x, s) => x + s.stops, 0);
    if (stops) { score += 0.04 * stops; reasons.push(`${stops} escale(s)`); }
    if (o.selfTransfer) { score += 0.15; reasons.push("transfert autonome"); }
    if (a.slices.some((s) => s.layovers.some((l) => l.airportChange))) { score += 0.12; reasons.push("changement d'aéroport"); }
    if (a.slices.some((s) => s.layovers.some((l) => l.overnight))) { score += 0.08; reasons.push("nuit en correspondance"); }
    if (o.baggage.checked == null) { score += 0.03; reasons.push("bagages inconnus"); }
    if (!o.price.taxesKnown) { score += 0.05; reasons.push("frais pas tous connus"); }
    return { g, score, reasons };
  });

  const cheapest = [...withPrice].sort((a, b) =>
    a.offers[0].price.total - b.offers[0].price.total ||
    Number(b.offers[0].price.taxesKnown) - Number(a.offers[0].price.taxesKnown));
  const fastest = [...withPrice].sort((a, b) =>
    (a.analysis.totalMinutes ?? Infinity) - (b.analysis.totalMinutes ?? Infinity) ||
    a.offers[0].price.total - b.offers[0].price.total);
  const best = scored.sort((a, b) => a.score - b.score).map((x) => ({ ...x.g, explanation: explain(x, pMin, dMin) }));
  return { cheapest, fastest, best };
}

/** Explication en mots simples: ecart au moins cher, ecart au plus rapide, penalites. */
function explain({ g, reasons }, pMin, dMin) {
  const o = g.offers[0], min = g.analysis.totalMinutes;
  const extra = Math.round((o.price.total - pMin) * 100) / 100;
  const parts = [extra <= 0 ? "Le moins cher" : `${extra.toLocaleString("fr-FR")} ${o.price.currency} de plus que le moins cher`];
  if (min == null) parts.push("durée inconnue");
  else parts.push(min - dMin <= 0 ? "le plus rapide" : `${hm(min - dMin)} de plus que le plus rapide`);
  return parts.join(", ") + (reasons.length ? `. Pénalisé : ${reasons.join(", ")}.` : ".");
}

function hm(m) { return m >= 60 ? `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, "0")}` : `${m} min`; }

/** Deux offres comparees a hypotheses equivalentes? Sinon, on explique pourquoi. */
export function comparability(a, b) {
  const notes = [];
  if (a.price.currency !== b.price.currency) notes.push("devises différentes");
  if (a.baggage.checked !== b.baggage.checked) notes.push("bagages en soute différents ou inconnus");
  if (a.conditions.refundable !== b.conditions.refundable) notes.push("conditions de remboursement différentes");
  if (a.price.taxesKnown !== b.price.taxesKnown) notes.push("frais connus d'un côté seulement");
  const cabins = (o) => o.slices.flatMap((s) => s.segments.map((g) => g.cabin)).join(",");
  if (cabins(a) !== cabins(b)) notes.push("classes différentes");
  return { equivalent: notes.length === 0, notes };
}
