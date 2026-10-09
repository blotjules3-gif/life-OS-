import Foundation
import QuartzCore
import Darwin

#if DEBUG
/// Mesure de fluidite, reservee aux builds Debug.
///
/// Un lien d'affichage (CADisplayLink) note l'ecart entre deux images. A 60 i/s une
/// image dure 16,7 ms; un ecart de plus de 50 ms se voit comme un accroc, plus de
/// 250 ms comme un gel. On ne juge pas a l'oeil sur le simulateur: on compte.
///
/// Lancement: `-perf` ecrit `Documents/perf.txt` (temps de lancement jusqu'a la
/// premiere image, puis accrocs des 8 premieres secondes). Avec `-routeSmoke`, chaque
/// outil recoit aussi son temps d'ouverture et ses accrocs.
@MainActor
final class PerfProbe: NSObject {
    static let shared = PerfProbe()
    static var enabled: Bool { DebugLaunchFlags.has("-perf") }

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private(set) var worstGap: Double = 0      // ms
    private(set) var hitches = 0               // ecarts > 50 ms
    private(set) var stalledMs: Double = 0     // temps perdu au dela d'une image
    private var lines: [String] = []

    /// Debut du processus, lu dans le noyau: le lancement compte depuis la, pas
    /// depuis notre premier code Swift.
    static var processStart: Date {
        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &kinfo, &size, nil, 0) == 0 else { return .now }
        let tv = kinfo.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
    }

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) {
        defer { last = l.timestamp }
        guard last > 0 else { return }
        let gap = (l.timestamp - last) * 1000
        let frame = max(l.targetTimestamp - l.timestamp, 1.0 / 120) * 1000
        if gap > worstGap { worstGap = gap }
        if gap > 50 { hitches += 1 }
        if gap > frame * 1.5 { stalledMs += gap - frame }
    }

    /// Remet les compteurs a zero au debut d'une fenetre de mesure.
    func resetWindow() { worstGap = 0; hitches = 0; stalledMs = 0; last = 0 }

    func window() -> String {
        String(format: "pire %.0f ms, accrocs %d, perdu %.0f ms", worstGap, hitches, stalledMs)
    }

    func log(_ line: String) {
        lines.append(line)
        try? lines.joined(separator: "\n").write(
            to: AppPaths.documents.appendingPathComponent("perf.txt"), atomically: true, encoding: .utf8)
    }

    /// Etape du lancement, en ms depuis le debut du processus.
    static func mark(_ name: String) {
        guard enabled else { return }
        let ms = Date().timeIntervalSince(processStart) * 1000
        shared.log(String(format: "ETAPE %@ %.0f ms", name, ms))
    }

    /// Lancement: appele a la premiere apparition de l'ecran principal.
    private var firstFrameLogged = false
    func firstFrame() {
        guard Self.enabled, !firstFrameLogged else { return }
        firstFrameLogged = true
        let ms = Date().timeIntervalSince(Self.processStart) * 1000
        log(String(format: "LANCEMENT premiere image %.0f ms", ms))
        start(); resetWindow()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self.log("APRES LANCEMENT 8 s: " + self.window())
        }
    }
}
#endif
