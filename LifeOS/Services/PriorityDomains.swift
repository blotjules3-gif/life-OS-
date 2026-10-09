import SwiftUI

/// Les 3 domaines prioritaires de l'utilisateur (ex: Nutrition, Sport, Productivité).
///
/// Ils servent a choisir les bons blocs par defaut de l'accueil et a expliquer chaque
/// recommandation (« Parce que tu as choisi Nutrition »). Ils sont stockes une seule
/// fois, ici, sous la cle "priorityDomains" ("nutrition,fitness,productivity").
///
/// Utilisateur existant (pas encore de cle) : on reprend les 3 premiers modules
/// recommandes a l'onboarding, sinon une liste de secours. Le choix se modifie ensuite
/// dans le Profil.
enum PriorityDomains {
    static let storageKey = "priorityDomains"
    static let maxCount = 3
    /// Liste de secours quand l'onboarding n'a rien recommande.
    static let fallback: [AppCategory] = [.productivity, .fitness, .nutrition]

    /// Lit un texte stocke : doublons et valeurs inconnues retires, 3 au plus.
    static func parse(_ raw: String) -> [AppCategory] {
        var seen = Set<AppCategory>()
        return raw.split(separator: ",")
            .compactMap { AppCategory(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
            .filter { seen.insert($0).inserted }
            .prefix(maxCount)
            .map { $0 }
    }

    static func serialize(_ list: [AppCategory]) -> String {
        parse(list.map(\.rawValue).joined(separator: ",")).map(\.rawValue).joined(separator: ",")
    }

    /// Valeur de depart pour un utilisateur qui n'a jamais choisi.
    static func seed(recommendedRaw: String) -> [AppCategory] {
        let fromOnboarding = parse(recommendedRaw)
        return fromOnboarding.isEmpty ? fallback : fromOnboarding
    }

    /// Les domaines actuels. Pose la valeur de depart une seule fois si la cle manque.
    @discardableResult
    static func current(_ defaults: UserDefaults = .standard) -> [AppCategory] {
        if defaults.object(forKey: storageKey) == nil {
            let seeded = seed(recommendedRaw: defaults.string(forKey: AppStorageKeys.recommendedModules) ?? "")
            defaults.set(serialize(seeded), forKey: storageKey)
            return seeded
        }
        return parse(defaults.string(forKey: storageKey) ?? "")
    }

    static func save(_ list: [AppCategory], _ defaults: UserDefaults = .standard) {
        defaults.set(serialize(list), forKey: storageKey)
    }

    /// Ajoute ou retire un domaine. Au dela de 3, l'ajout est refuse (jamais un
    /// remplacement silencieux d'un choix precedent).
    static func toggle(_ cat: AppCategory, in list: [AppCategory]) -> (list: [AppCategory], refused: Bool) {
        if let i = list.firstIndex(of: cat) {
            var l = list; l.remove(at: i)
            return (l, false)
        }
        guard list.count < maxCount else { return (list, true) }
        return (list + [cat], false)
    }

    /// « Parce que tu as choisi Nutrition »
    static func reason(_ cat: AppCategory) -> String {
        "Parce que tu as choisi \(shortTitle(cat))"
    }

    static func shortTitle(_ cat: AppCategory) -> String {
        switch cat {
        case .sleep: return "Sommeil"
        case .fitness: return "Sport"
        case .mind: return "Mental"
        case .finance: return "Finances"
        case .invest: return "Investissement"
        case .home: return "Maison"
        case .social: return "Social"
        case .admin: return "Admin"
        case .medical: return "Santé"
        case .cycle: return "Cycle"
        default: return cat.title
        }
    }
}

// MARK: - Editeur (Profil)

/// Choisir ses 3 domaines prioritaires. Le Profil l'ouvre ; l'accueil s'en sert pour
/// ses recommandations, sans rien reorganiser tout seul.
struct PriorityDomainsEditor: View {
    @AppStorage(PriorityDomains.storageKey) private var raw = ""
    @State private var refusedFlash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var chosen: [AppCategory] { PriorityDomains.parse(raw) }

    var body: some View {
        List {
            Section {
                ForEach(AppCategory.allCases) { cat in
                    let on = chosen.contains(cat)
                    Button {
                        let r = PriorityDomains.toggle(cat, in: chosen)
                        if r.refused {
                            Haptics.warning()
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { refusedFlash = true }
                        } else {
                            raw = PriorityDomains.serialize(r.list)
                            refusedFlash = false
                            Haptics.tap()
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: cat.icon)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(cat.tint)
                                .frame(width: 32, height: 32)
                            Text(cat.title).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: on ? "star.fill" : "star")
                                .foregroundStyle(on ? cat.tint : Theme.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(cat.title)
                    .accessibilityValue(on ? "Prioritaire" : "")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            } header: {
                Text("\(chosen.count) sur \(PriorityDomains.maxCount) choisis")
            } footer: {
                if refusedFlash {
                    Text("Tu as déjà 3 domaines. Retire-en un pour en choisir un autre.")
                        .foregroundStyle(Theme.warning)
                } else {
                    Text("L'accueil te propose des indicateurs et des raccourcis selon ces domaines. Il ne range rien sans toi.")
                }
            }
        }
        .navigationTitle("Domaines prioritaires")
        .navigationBarTitleDisplayMode(.inline)
        // Pose la valeur de depart seulement si la cle n'existe pas encore : une liste
        // videe volontairement reste vide.
        .onAppear { PriorityDomains.current() }
    }
}
