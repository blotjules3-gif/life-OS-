// Travelport: SQUELETTE, pas un adaptateur.
//
// Ce fichier ne contient AUCUN echange OAuth, aucune requete de recherche et
// aucune traduction de reponse. Poser des identifiants ne l'active pas: il faudra
// ECRIRE le connecteur (jeton OAuth 2, recherche, normalisation vers core.js,
// relecture d'offre), puis le faire certifier par Travelport.
//
// Travelport (JSON Flights APIs, OAuth 2) exige une societe provisionnee par
// contrat: identifiants client, groupe d'acces, PCC. Sans eux, ce connecteur
// repond "non configure" et n'est jamais presente comme une source active.
// Docs: https://developer.travelport.com/docs/flights/guides/flights-search-guide
//
// Ce qu'il manque, precisement: un accord commercial avec Travelport (ou une
// agence partenaire), puis TRAVELPORT_CLIENT_ID, TRAVELPORT_CLIENT_SECRET,
// TRAVELPORT_ACCESS_GROUP et TRAVELPORT_PCC poses en secrets du Worker, et la
// certification (journaux requete/reponse revus par Travelport).

export const capabilities = {
  id: "travelport",
  name: "Travelport",
  kind: "distributor",
  active: false,
  sellerComparison: false,
  oneWay: true, roundTrip: true, multiCity: true,
  cabins: true, children: true, infants: true,
  baggageInfo: "per_fare",
  conditions: true,
  refreshOffer: true,
  handoff: "booking_api",
  priceCalendar: false,
  skeleton: true,
  notes: "Squelette : connecteur à écrire (OAuth, recherche, normalisation) puis à certifier. Contrat Travelport requis.",
};

export function makeTravelport(env = {}) {
  const configured = Boolean(env.TRAVELPORT_CLIENT_ID && env.TRAVELPORT_CLIENT_SECRET && env.TRAVELPORT_ACCESS_GROUP && env.TRAVELPORT_PCC);
  return {
    ...capabilities,
    active: false,          // reste faux tant que la traduction n'est pas certifiee
    configured,
    async search() {
      const err = new Error(configured
        ? "Travelport : identifiants présents, mais le connecteur n'est pas encore écrit."
        : "Travelport : non configuré (contrat et identifiants requis).");
      err.code = "not_configured";
      throw err;
    },
    async refresh() { return { status: "unavailable", reason: "Travelport non configuré." }; },
  };
}
