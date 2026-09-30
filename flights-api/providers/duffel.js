// Adaptateur Duffel (API Flights v2, en-tete `Duffel-Version: v2`).
// Documentation: https://duffel.com/docs/api/v2/offer-requests/create-offer-request
//
// Ce que Duffel EST: un distributeur technique qui vend des billets via ses
// propres accreditations (NDC, GDS, low-cost selon les compagnies). Ce qu'il
// n'est PAS: une comparaison d'agences. Toutes ses offres ont le meme vendeur
// technique (Duffel), meme si la compagnie proprietaire change.
//
// Couts publies (pricing, lu le 28 sept. 2026): 3 $ par commande + 1 % de la
// valeur, 1 500 recherches gratuites par commande, puis 0,005 $ par recherche
// excedentaire. Sans aucune commande, chaque recherche est excedentaire.

import { minutesBetween } from "../core.js";

export const DUFFEL_SEARCH_COST_USD = 0.005;

export const capabilities = {
  id: "duffel",
  name: "Duffel",
  kind: "distributor",
  active: false,                 // devient vrai quand DUFFEL_TOKEN est pose
  sellerComparison: false,       // un seul vendeur technique
  oneWay: true, roundTrip: true, multiCity: true,
  cabins: true, children: true, infants: true,
  baggageInfo: "per_segment",    // bagages inclus par segment et passager
  conditions: true,              // remboursement / modification avant depart
  refreshOffer: true,            // GET /air/offers/{id}
  handoff: "booking_api",        // pas de lien vers la compagnie: reservation via Duffel seulement
  priceCalendar: false,
  notes: "Recherche et réservation via Duffel. Aucun lien de redirection vers la compagnie. Réserver ferait de LifeOS le vendeur (paiement, émission, service client) : non activé.",
};

const BASE = "https://api.duffel.com";

export function makeDuffel({ token, fetchImpl = fetch, supplierTimeoutMs = 15000 }) {
  const headers = {
    "Duffel-Version": "v2",
    Authorization: `Bearer ${token}`,
    Accept: "application/json",
    "Accept-Encoding": "gzip",
    "Content-Type": "application/json",
  };

  async function call(path, init = {}) {
    const res = await fetchImpl(BASE + path, { ...init, headers });
    const text = await res.text();
    let json = null;
    try { json = text ? JSON.parse(text) : null; } catch { /* laisse json null */ }
    if (!res.ok) {
      const code = json?.errors?.[0]?.code || `http_${res.status}`;
      const message = json?.errors?.[0]?.message || `Erreur ${res.status}`;
      const err = new Error(message);
      err.code = code; err.status = res.status;
      throw err;
    }
    return json;
  }

  return {
    ...capabilities,
    active: Boolean(token),

    async search(query, { signal } = {}) {
      const passengers = [
        ...Array(query.passengers.adults).fill({ type: "adult" }),
        // L'age reel de chaque enfant, saisi par l'utilisateur. Jamais un age par defaut.
        ...(query.passengers.childAges || []).map((age) => ({ age })),
        ...Array(query.passengers.infants).fill({ type: "infant_without_seat" }),
      ];
      const body = { data: {
        slices: query.slices.map((s) => ({ origin: s.origin, destination: s.destination, departure_date: s.date })),
        passengers, cabin_class: query.cabin, max_connections: query.maxConnections,
      } };
      const json = await call(`/air/offer_requests?return_offers=true&supplier_timeout=${supplierTimeoutMs}`,
        { method: "POST", body: JSON.stringify(body), signal });
      const now = new Date().toISOString();
      return (json?.data?.offers || []).map((o) => normalize(o, query, now)).filter(Boolean);
    },

    /** Relit une offre juste avant de la proposer: prix, disponibilite, expiration. */
    async refresh(providerRef, query, { signal } = {}) {
      try {
        const json = await call(`/air/offers/${encodeURIComponent(providerRef)}?return_available_services=false`, { signal });
        return { status: "ok", offer: normalize(json.data, query, new Date().toISOString()) };
      } catch (e) {
        if (e.status === 404 || /expired|no_longer_available|not_found/.test(e.code || "")) return { status: "unavailable", reason: e.message };
        throw e;
      }
    },
  };
}

/** Offre Duffel -> modele LifeOS. Une valeur absente reste null. */
export function normalize(o, query, fetchedAt) {
  if (!o?.id || o.total_amount == null) return null;
  const total = Number.parseFloat(o.total_amount);
  if (!Number.isFinite(total)) return null;
  const place = (p) => ({ iata: p?.iata_code || "???", name: p?.name ?? null, timeZone: p?.time_zone ?? null });
  const slices = (o.slices || []).map((s) => {
    const segments = (s.segments || []).map((g) => {
      const list = Array.isArray(g.passengers) ? g.passengers : [];
      const pax = list[0] || {};
      const cabins = new Set(list.map((x) => x.cabin_class).filter(Boolean));
      return {
        origin: place(g.origin), destination: place(g.destination),
        departingAt: g.departing_at, arrivingAt: g.arriving_at,
        marketingCarrier: { code: g.marketing_carrier?.iata_code || "??", name: g.marketing_carrier?.name ?? null },
        operatingCarrier: { code: g.operating_carrier?.iata_code || g.marketing_carrier?.iata_code || "??", name: g.operating_carrier?.name ?? null },
        flightNumber: g.marketing_carrier_flight_number ?? null,
        // Une cabine commune a tous les voyageurs, sinon on ne pretend pas en avoir une.
        cabin: cabins.size > 1 ? "mixed" : (pax.cabin_class ?? null),
        fareBrand: cabins.size > 1 ? null : (pax.fare_brand_name ?? pax.cabin_class_marketing_name ?? null),
        paxBaggage: list.map((x) => ({ id: x.passenger_id ?? null, baggages: Array.isArray(x.baggages) ? x.baggages : null })),
      };
    });
    const first = segments[0], last = segments[segments.length - 1];
    return {
      origin: place(s.origin), destination: place(s.destination),
      durationMinutes: isoDuration(s.duration) ??
        (first && last ? minutesBetween(first.departingAt, first.origin.timeZone, last.arrivingAt, last.destination.timeZone) : null),
      segments,
    };
  });
  // Bagages PAR VOYAGEUR: pour chacun, le minimum sur tous ses segments. Le chiffre
  // affiche est celui garanti a TOUS (le plus petit); s'il differe d'un voyageur a
  // l'autre, on le dit. Un voyageur sans information rend l'ensemble inconnu.
  const allSegs = slices.flatMap((s) => s.segments);
  const paxList = Array.isArray(o.passengers) && o.passengers.length
    ? o.passengers : [{ id: null, type: "adult" }];
  const count = (bags, type) => bags.filter((b) => b.type === type).reduce((a, b) => a + (b.quantity || 0), 0);
  const perPassenger = paxList.map((p, i) => {
    const entries = allSegs.map((g) => (p.id ? g.paxBaggage.find((x) => x.id === p.id) : g.paxBaggage[i]) || null);
    const known = entries.length > 0 && entries.every((e) => e && e.baggages);
    return {
      label: paxLabel(p, i),
      checked: known ? Math.min(...entries.map((e) => count(e.baggages, "checked"))) : null,
      carryOn: known ? Math.min(...entries.map((e) => count(e.baggages, "carry_on"))) : null,
    };
  });
  const guaranteed = (k) => (perPassenger.some((p) => p[k] == null) ? null : Math.min(...perPassenger.map((p) => p[k])));
  const checked = guaranteed("checked"), carryOn = guaranteed("carryOn");
  const varies = new Set(perPassenger.map((p) => `${p.checked}/${p.carryOn}`)).size > 1;
  for (const g of allSegs) delete g.paxBaggage;
  const allowed = (c) => (c == null ? null : Boolean(c.allowed));
  return {
    id: `duffel:${o.id}`,
    provider: "duffel",
    providerRef: o.id,
    seller: { code: o.owner?.iata_code ?? null, name: `${o.owner?.name || "Compagnie"} via Duffel`, kind: "distributor" },
    demo: false,
    slices,
    passengers: { ...query.passengers },
    price: {
      total, currency: o.total_currency,
      taxesKnown: o.tax_amount != null,
      feesNote: "Prix total Duffel, taxes comprises. Frais de paiement éventuels du vendeur non inclus.",
    },
    baggage: { checked, carryOn, varies, perPassenger },
    conditions: { refundable: allowed(o.conditions?.refund_before_departure), changeable: allowed(o.conditions?.change_before_departure) },
    selfTransfer: false,
    fetchedAt,
    expiresAt: o.expires_at ?? null,
  };
}

/** "PT2H35M" -> 155. */
export function isoDuration(d) {
  if (!d) return null;
  const m = /^P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?/.exec(d);
  if (!m) return null;
  return (+(m[1] || 0)) * 1440 + (+(m[2] || 0)) * 60 + (+(m[3] || 0));
}

function paxLabel(p, i) {
  if (p.type === "adult") return `Adulte ${i + 1}`;
  if (p.type === "infant_without_seat") return `Bébé ${i + 1}`;
  if (p.age != null) return `Enfant ${i + 1} (${p.age} ans)`;
  return `Voyageur ${i + 1}`;
}
