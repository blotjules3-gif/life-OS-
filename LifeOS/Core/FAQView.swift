import SwiftUI

/// Foire aux questions in-app — sert de premier niveau de support.
///
/// 18 questions organisées en 5 sections. Chaque question est un
/// `DisclosureGroup` — accordéon natif iOS. Le lien "Nous contacter"
/// ouvre le mail par défaut avec un template pré-rempli.
///
/// Accessible depuis `ProfileView` via une nouvelle entrée "Aide et support".
struct FAQView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.items, id: \.q) { item in
                        DisclosureGroup {
                            Text(item.a)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.vertical, 6)
                                .fixedSize(horizontal: false, vertical: true)
                        } label: {
                            Text(item.q)
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }

            Section("Contact") {
                Button {
                    openMail()
                } label: {
                    Label("Écrire au support", systemImage: "envelope.fill")
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Envoyer un email au support LifeOS")
            }
        }
        .navigationTitle("Aide")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openMail() {
        let subject = "LifeOS — Support"
        let body = """


        —
        Merci de laisser ces infos pour un diagnostic plus rapide :
        • Modèle iPhone :
        • Version iOS :
        • Version LifeOS : 1.0.0
        • Décris le problème :
        """
        let s = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let b = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:support@lifeos.app?subject=\(s)&body=\(b)") {
            openURL(url)
        }
    }
}

// MARK: - Contenu

private struct FAQItem {
    let q: String
    let a: String
}

private struct FAQSection {
    let title: String
    let items: [FAQItem]
}

private let sections: [FAQSection] = [

    FAQSection(title: "Ton coach", items: [
        FAQItem(
            q: "Comment le coach connaît mes données ?",
            a: "Le coach lit ton contexte local (sommeil, séances, humeur, habitudes, objectifs actifs) au moment où tu lui parles. Ces données ne quittent pas ton iPhone pour te profiler — elles servent juste à te donner une réponse pertinente."
        ),
        FAQItem(
            q: "Pourquoi il répond parfois hors ligne ?",
            a: "Si le serveur du coach est indisponible, LifeOS bascule sur un mode local qui répond aux commandes simples (créer une habitude, logger un verre d'eau, résumé de ta semaine). Un bandeau te prévient."
        ),
        FAQItem(
            q: "Est-ce que mes messages sont enregistrés ?",
            a: "L'historique du chat est stocké uniquement sur ton iPhone. Aucun serveur ne garde tes messages après la réponse. Tu peux tout effacer via le menu du chat."
        ),
        FAQItem(
            q: "Le coach peut-il me diagnostiquer médicalement ?",
            a: "Non. LifeOS est un outil d'aide au quotidien, pas un dispositif médical. Pour tout symptôme, consulte un professionnel de santé."
        )
    ]),

    FAQSection(title: "Confidentialité", items: [
        FAQItem(
            q: "Où sont stockées mes données ?",
            a: "Toutes tes données (sommeil, humeur, finances, photos, chat…) sont dans la base SwiftData locale de ton iPhone. Aucun serveur applicatif ne conserve tes données personnelles. Si tu actives le sync iCloud, elles sont chiffrées et transitent uniquement entre tes propres appareils via ton compte Apple."
        ),
        FAQItem(
            q: "LifeOS vend mes données ?",
            a: "Non. LifeOS ne collecte pas de données pour la publicité, ne les revend pas, et n'utilise aucun tracker tiers. Le manifest privacy déclare : NSPrivacyTracking = false."
        ),
        FAQItem(
            q: "Comment supprimer toutes mes données ?",
            a: "Profil → Mes données → Tout effacer. Suppression totale et irréversible. Un export JSON peut être partagé avant si tu veux garder une sauvegarde."
        ),
        FAQItem(
            q: "Que fait LifeOS de mes données Santé ?",
            a: "Sommeil, HRV et pas sont lus pour calculer ton score de récup. Rien n'est transmis. Tu peux révoquer l'accès à tout moment dans Réglages iOS → Santé → LifeOS."
        )
    ]),

    FAQSection(title: "Notifications", items: [
        FAQItem(
            q: "Comment désactiver les notifications ?",
            a: "Profil → Notifications. Tu peux couper chaque catégorie (sommeil, habitudes, sport, nutrition, matin) indépendamment. Le mode silence global coupe tout d'un coup."
        ),
        FAQItem(
            q: "Pourquoi mon rappel n'est pas parti ?",
            a: "Vérifie : (1) Réglages iOS → Notifications → LifeOS → autorisé, (2) que ton iPhone n'est pas en Focus/Ne pas déranger, (3) que l'heure programmée n'est pas passée. Si ça persiste, écris au support."
        ),
        FAQItem(
            q: "Puis-je changer l'heure du briefing matinal ?",
            a: "Oui — Profil → Réveil et briefing. Tu ajustes l'heure de réveil et le briefing part au bon moment."
        )
    ]),

    FAQSection(title: "Modules et données", items: [
        FAQItem(
            q: "Puis-je désactiver un module que je n'utilise pas ?",
            a: "Oui — Profil → Modules affichés. Décoche ceux que tu veux masquer. Ils ne s'affichent plus dans la grille des catégories mais les données restent stockées."
        ),
        FAQItem(
            q: "Est-ce que LifeOS marche sur iPad ?",
            a: "Oui. LifeOS est universel iPhone + iPad. Sur iPad, l'expérience est optimisée en mode portrait."
        ),
        FAQItem(
            q: "Puis-je synchroniser entre mes appareils ?",
            a: "Le sync iCloud est disponible en opt-in (Profil → Synchronisation). Il utilise ton compte Apple, sans compte LifeOS. Actuellement en beta — teste sur données non-critiques."
        ),
        FAQItem(
            q: "Comment sauvegarder mes données ?",
            a: "Profil → Mes données → Exporter. Un fichier JSON récapitulatif est généré avec ShareLink pour l'envoyer sur ton Mac ou dans Fichiers."
        )
    ]),

    FAQSection(title: "Achat et abonnement", items: [
        FAQItem(
            q: "LifeOS est-il gratuit ?",
            a: "La version 1.0 est entièrement gratuite. Une version premium avec des fonctions avancées de coaching pourrait arriver dans une prochaine version — les fonctions actuelles resteront gratuites."
        ),
        FAQItem(
            q: "Comment restaurer un achat ?",
            a: "Pas d'achat in-app dans la v1. Si tu vois cette question mise à jour dans une prochaine version, l'App Store gère automatiquement la restauration via ton compte Apple."
        ),
        FAQItem(
            q: "Comment demander un remboursement ?",
            a: "Toute demande de remboursement se fait via reportaproblem.apple.com avec ton compte Apple, dans les 90 jours suivant l'achat."
        )
    ])
]
