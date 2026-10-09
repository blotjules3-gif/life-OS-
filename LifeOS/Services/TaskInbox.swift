import Foundation

/// Une tache creee hors de Todoo (Siri, coach, raccourci de l'accueil) passe par la meme
/// saisie rapide que l'app : « appeler maman demain 18h #maison !2 » donne une echeance,
/// un projet et une priorite. Sans projet ecrit, elle va dans la Boite de reception
/// (avant : le projet par defaut du modele, « Perso », la cachait de la reception).
enum TaskInbox {
    static func makeTodo(_ text: String, priority fallback: Int = 0, now: Date = .now) -> TodoItem {
        let p = TaskCapture.parse(text, now: now)
        return makeTodo(parsed: p, title: p.title.isEmpty ? text : p.title, due: p.due, priority: fallback)
    }

    /// Meme fabrication, a partir d'une lecture deja faite puis corrigee a l'ecran
    /// (capture universelle) : titre et echeance viennent de l'apercu, le reste
    /// (projet, etiquettes, priorite, recurrence) de la lecture.
    static func makeTodo(parsed p: ParsedTask, title: String, due: Date?, priority fallback: Int = 0) -> TodoItem {
        let t = TodoItem(title: title, due: due, priority: p.priority ?? fallback, project: p.project ?? "")
        t.tagsRaw = TagList.serialize(p.tags)
        p.recurrence.apply(to: t)
        t.uid = UUID().uuidString
        return t
    }
}
