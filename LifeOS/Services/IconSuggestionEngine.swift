import Foundation

// MARK: - Moteur de suggestion d'icônes

public enum IconSuggestionEngine {

    /// Catalogue complet d'icônes organisées par catégories (~160 symboles SF).
    public static let catalog: [(category: String, icons: [String])] = [
        ("Sport & Santé", [
            "dumbbell.fill", "figure.strengthtraining.traditional", "figure.run",
            "figure.walk", "figure.outdoor.cycle", "figure.pool.swim", "figure.boxing",
            "figure.yoga", "figure.cross.training", "flame.fill", "heart.fill",
            "bolt.heart.fill", "trophy.fill", "medal.fill", "timer", "stopwatch.fill",
            "shoe.2.fill", "figure.climbing", "sportscourt.fill", "lungs.fill"
        ]),
        ("Esprit & Bien-être", [
            "leaf.fill", "wind", "sun.max.fill", "moon.fill", "moon.stars.fill",
            "bed.double.fill", "zzz", "powersleep", "sparkles", "sun.horizon.fill",
            "sunrise.fill", "sunset.fill", "drop.fill", "waterbottle.fill",
            "brain.head.profile", "eye.fill", "smile.fill", "heart.circle.fill"
        ]),
        ("Productivité & Travail", [
            "book.fill", "books.vertical.fill", "bookmark.fill", "character.book.closed.fill",
            "graduationcap.fill", "pencil", "pencil.and.outline", "doc.text.fill",
            "folder.fill", "tray.full.fill", "laptopcomputer", "desktopcomputer",
            "terminal.fill", "keyboard.fill", "briefcase.fill", "hammer.fill",
            "wrench.and.screwdriver.fill", "checklist", "list.bullet.clipboard.fill",
            "chart.bar.fill", "chart.pie.fill", "target"
        ]),
        ("Maison, Famille & Animaux", [
            "house.fill", "building.2.fill", "door.left.hand.closed", "key.fill",
            "lock.fill", "paintbrush.fill", "bubbles.and.sparkles.fill", "trash.fill",
            "pawprint.fill", "dog.fill", "cat.fill", "bird.fill", "fish.fill",
            "car.fill", "bicycle", "fuelpump.fill", "lightbulb.fill", "shower.fill"
        ]),
        ("Nourriture & Boisson", [
            "cup.and.saucer.fill", "mug.fill", "takeoutbag.and.cup.and.straw.fill",
            "fork.knife", "wineglass.fill", "birthday.cake.fill", "carrot.fill",
            "fish.circle.fill", "apple.logo", "frying.pan.fill"
        ]),
        ("Finances & Shopping", [
            "eurosign.circle.fill", "dollarsign.circle.fill", "creditcard.fill",
            "banknote.fill", "cart.fill", "bag.fill", "chart.line.uptrend.xyaxis",
            "bitcoinsign.circle.fill", "gift.fill", "tag.fill"
        ]),
        ("Social, Loisirs & Voyage", [
            "person.fill", "person.2.fill", "message.fill", "phone.fill",
            "envelope.fill", "camera.fill", "video.fill", "music.note",
            "headphones", "guitars.fill", "gamecontroller.fill", "tv.fill",
            "airplane", "globe.europe.africa.fill", "map.fill", "compass.drawing",
            "theatermasks.fill", "ticket.fill"
        ])
    ]

    /// Liste de repli générale : 20 icônes favorites variées.
    public static let default20: [String] = [
        "drop.fill",
        "book.fill",
        "dumbbell.fill",
        "figure.run",
        "leaf.fill",
        "sun.max.fill",
        "moon.fill",
        "bed.double.fill",
        "pencil",
        "heart.fill",
        "cup.and.saucer.fill",
        "laptopcomputer",
        "flame.fill",
        "house.fill",
        "fork.knife",
        "eurosign.circle.fill",
        "checklist",
        "sparkles",
        "target",
        "pawprint.fill"
    ]

    /// Table de correspondance de mots-clés bilingues (FR / EN).
    private static let keywordMap: [(keywords: [String], icons: [String])] = [
        (
            ["workout", "sport", "gym", "muscu", "musculation", "fitness", "biceps", "train", "push", "pull", "legs", "fonte", "halter", "alter", "body"],
            ["dumbbell.fill", "figure.strengthtraining.traditional", "flame.fill", "trophy.fill", "bolt.heart.fill", "figure.cross.training", "timer"]
        ),
        (
            ["run", "course", "courir", "footing", "jogging", "marathon", "sprint"],
            ["figure.run", "shoe.2.fill", "flame.fill", "heart.fill", "timer", "stopwatch.fill"]
        ),
        (
            ["walk", "marche", "marcher", "pas", "steps", "balade", "randonnee", "rando", "hike"],
            ["figure.walk", "shoe.2.fill", "leaf.fill", "figure.climbing", "map.fill"]
        ),
        (
            ["velo", "bike", "cycling", "cyclisme", "bicyclette"],
            ["figure.outdoor.cycle", "bicycle", "heart.fill", "timer"]
        ),
        (
            ["boxe", "boxing", "combat", "fight", "mma"],
            ["figure.boxing", "flame.fill", "trophy.fill"]
        ),
        (
            ["swim", "nage", "natation", "piscine", "pool"],
            ["figure.pool.swim", "drop.fill", "waterbottle.fill"]
        ),
        (
            ["eau", "water", "boire", "drink", "hydrat", "hydratation", "bouteille"],
            ["drop.fill", "waterbottle.fill", "cup.and.saucer.fill", "mug.fill"]
        ),
        (
            ["read", "lire", "livre", "book", "lecture", "roman", "manga", "page"],
            ["book.fill", "books.vertical.fill", "bookmark.fill", "character.book.closed.fill", "doc.text.fill"]
        ),
        (
            ["etude", "study", "cours", "ecole", "reviser", "revision", "learn", "apprendre", "examen"],
            ["graduationcap.fill", "book.fill", "pencil", "pencil.and.outline", "brain.head.profile"]
        ),
        (
            ["ecrire", "write", "journal", "note", "noter", "pencil", "pen"],
            ["pencil", "pencil.and.outline", "doc.text.fill", "bookmark.fill"]
        ),
        (
            ["sleep", "dormir", "sommeil", "bed", "lit", "sieste", "nap", "repos", "nuit", "night"],
            ["bed.double.fill", "moon.fill", "moon.stars.fill", "zzz", "powersleep"]
        ),
        (
            ["medit", "zen", "respir", "breathe", "calm", "relax", "paix", "yoga", "souffle"],
            ["figure.yoga", "leaf.fill", "wind", "sparkles", "sun.max.fill", "heart.circle.fill"]
        ),
        (
            ["clean", "menage", "ranger", "tidy", "maison", "house", "nettoy", "aspirat", "vaisselle", "lessive"],
            ["house.fill", "bubbles.and.sparkles.fill", "trash.fill", "paintbrush.fill", "sparkles"]
        ),
        (
            ["code", "dev", "program", "work", "travail", "boulot", "ordi", "computer", "bureau", "job"],
            ["laptopcomputer", "terminal.fill", "desktopcomputer", "keyboard.fill", "briefcase.fill", "checklist"]
        ),
        (
            ["argent", "money", "budget", "econom", "salaire", "invest", "bourse", "finance", "crypto", "banque"],
            ["eurosign.circle.fill", "dollarsign.circle.fill", "banknote.fill", "creditcard.fill", "chart.line.uptrend.xyaxis", "bitcoinsign.circle.fill"]
        ),
        (
            ["manger", "eat", "food", "cook", "cuisine", "nutrition", "repas", "diet", "diner", "dejeuner", "dej", "petit-dej"],
            ["fork.knife", "carrot.fill", "takeoutbag.and.cup.and.straw.fill", "apple.logo", "cup.and.saucer.fill", "frying.pan.fill"]
        ),
        (
            ["cafe", "coffee", "the", "tea"],
            ["cup.and.saucer.fill", "mug.fill"]
        ),
        (
            ["chien", "chat", "dog", "cat", "pet", "animal", "animaux", "veterinaire"],
            ["pawprint.fill", "dog.fill", "cat.fill", "bird.fill", "fish.fill"]
        ),
        (
            ["soleil", "sun", "matin", "morning", "reveil", "lever"],
            ["sun.max.fill", "sun.horizon.fill", "sunrise.fill", "sparkles"]
        ),
        (
            ["voiture", "car", "conduire", "drive", "permis", "essence"],
            ["car.fill", "fuelpump.fill", "key.fill"]
        ),
        (
            ["musique", "music", "guitare", "piano", "chanter", "song"],
            ["music.note", "guitars.fill", "headphones"]
        ),
        (
            ["appeler", "call", "famille", "amis", "friends", "message", "sms"],
            ["phone.fill", "message.fill", "envelope.fill", "person.2.fill"]
        )
    ]

    /// Normalise une chaîne de recherche (minuscule, sans accents).
    public static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Génère exactement 20 propositions d'icônes adaptées à la recherche.
    public static func suggest(for query: String, limit: Int = 20) -> [String] {
        let clean = normalize(query)
        guard !clean.isEmpty else {
            return Array(default20.prefix(limit))
        }

        var results: [String] = []
        var seen = Set<String>()

        func appendIcon(_ icon: String) {
            guard !seen.contains(icon) else { return }
            seen.insert(icon)
            results.append(icon)
        }

        // 1. Détection des correspondances mots-clés
        let words = clean.split(separator: " ").map(String.init)
        for entry in keywordMap {
            let matches = entry.keywords.contains { kw in
                if clean.contains(kw) { return true }
                for w in words {
                    if w == kw { return true }
                    if w.count >= 3 && kw.count >= 3 && (w.hasPrefix(kw) || kw.hasPrefix(w)) {
                        return true
                    }
                }
                return false
            }
            if matches {
                for icon in entry.icons {
                    appendIcon(icon)
                    if results.count >= limit { break }
                }
            }
            if results.count >= limit { break }
        }

        // 2. Recherche directe sur le nom de l'icône dans le catalogue complet
        if results.count < limit {
            for (_, group) in catalog {
                for icon in group {
                    let cleanIcon = normalize(icon.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "fill", with: ""))
                    if cleanIcon.contains(clean) || words.contains(where: { cleanIcon.contains($0) }) {
                        appendIcon(icon)
                        if results.count >= limit { break }
                    }
                }
                if results.count >= limit { break }
            }
        }

        // 3. Compléter avec les 20 icônes par défaut pour toujours en avoir 20
        for fallback in default20 {
            if results.count >= limit { break }
            appendIcon(fallback)
        }

        return Array(results.prefix(limit))
    }
}
