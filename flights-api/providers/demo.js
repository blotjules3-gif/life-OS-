// Source de DEMONSTRATION. Fictive, identifiee comme telle, desactivee par defaut.
// Sert aux essais et aux captures, jamais melangee a des offres reelles sans
// l'etiquette `demo: true` et un vendeur nomme "Démo LifeOS (fictif)".

export function makeDemo({ id = "demo", seed = 1 } = {}) {
  return {
    id, name: `Démo LifeOS (${id}, fictif)`, kind: "agency", active: true, demo: true,
    sellerComparison: false, oneWay: true, roundTrip: true, multiCity: true,
    baggageInfo: "per_offer", conditions: true, refreshOffer: true, handoff: "none", priceCalendar: false,
    notes: "Données fictives pour démonstration.",
    async search(query) {
      const first = query.slices[0];
      const base = 80 + (first.origin.charCodeAt(0) + first.destination.charCodeAt(0) + seed * 7) % 90;
      const place = (iata) => ({ iata, timeZone: "Europe/Paris" });
      // Chaque trajet de la recherche (aller, retour, multi-villes) a son vol.
      const slicesAt = (dep, arr, bag) => query.slices.map((s, i) => {
        const at = (h) => `${s.date}T${String(h).padStart(2, "0")}:00:00`;
        return { origin: place(s.origin), destination: place(s.destination), durationMinutes: (arr - dep) * 60,
          segments: [{ origin: place(s.origin), destination: place(s.destination), departingAt: at(dep), arrivingAt: at(arr),
            marketingCarrier: { code: "ZZ", name: "Démo Air" }, operatingCarrier: { code: "ZZ", name: "Démo Air" },
            flightNumber: String(100 + dep + i * 50), cabin: query.cabin, fareBrand: bag ? "Plus" : "Light" }] };
      });
      const mk = (ref, price, dep, arr, bag) => ({
        id: `${id}:${ref}`, provider: id, providerRef: ref, demo: true,
        seller: { code: null, name: "Démo LifeOS (fictif)", kind: "agency" },
        slices: slicesAt(dep, arr, bag),
        passengers: { ...query.passengers },
        price: { total: price * query.slices.length, currency: query.currency, taxesKnown: true, feesNote: "Fictif." },
        baggage: { checked: bag ? 1 : 0, carryOn: 1 }, conditions: { refundable: false, changeable: bag },
        selfTransfer: false, fetchedAt: new Date().toISOString(), expiresAt: null,
      });
      return [mk("a", base, 7, 9, false), mk("b", base + 35, 7, 9, true), mk("c", base - 10, 18, 21, false)];
    },
    async refresh(ref, query) {
      const offers = await this.search(query);
      const o = offers.find((x) => x.providerRef === ref);
      return o ? { status: "ok", offer: o } : { status: "unavailable", reason: "Offre démo inconnue." };
    },
  };
}
