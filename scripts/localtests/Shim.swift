// Faux XCTest, juste assez pour executer les suites de logique pure sur ce
// Mac. Xcode n'est pas installe ici (seulement les Command Line Tools), donc
// XCTest n'existe pas, mais `swiftc` si.
//
// Le but n'est PAS de remplacer la CI: les vues SwiftUI et SwiftData ne
// compilent pas ici. Le but est d'EXECUTER pour de vrai les regles qui
// calculent des chiffres, au lieu de les relire.
import Foundation

var failures: [String] = []
var checks = 0

func record(_ ok: Bool, _ what: @autoclosure () -> String, _ msg: String,
            _ f: String, _ l: Int) {
    checks += 1
    if !ok { failures.append("\(URL(fileURLWithPath: f).lastPathComponent):\(l) \(what())\(msg.isEmpty ? "" : " — " + msg)") }
}

class XCTestCase {}

func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () -> T?, _ b: @autoclosure () -> T?,
                                  _ m: String = "", file: String = #file, line: Int = #line) {
    let (x, y) = (a(), b())
    record(x == y, "\(String(describing: x)) != \(String(describing: y))", m, file, line)
}
func XCTAssertEqual(_ a: @autoclosure () -> Double, _ b: @autoclosure () -> Double,
                    accuracy: Double, _ m: String = "", file: String = #file, line: Int = #line) {
    let (x, y) = (a(), b())
    record(abs(x - y) <= accuracy, "\(x) != \(y) (±\(accuracy))", m, file, line)
}
func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () -> T?, _ b: @autoclosure () -> T?,
                                     _ m: String = "", file: String = #file, line: Int = #line) {
    record(a() != b(), "les deux valeurs sont égales", m, file, line)
}
func XCTAssertTrue(_ a: @autoclosure () -> Bool, _ m: String = "",
                   file: String = #file, line: Int = #line) {
    record(a(), "attendu vrai", m, file, line)
}
func XCTAssertFalse(_ a: @autoclosure () -> Bool, _ m: String = "",
                    file: String = #file, line: Int = #line) {
    record(!a(), "attendu faux", m, file, line)
}
func XCTAssertNil<T>(_ a: @autoclosure () -> T?, _ m: String = "",
                     file: String = #file, line: Int = #line) {
    let v = a()
    record(v == nil, "attendu nil, obtenu \(String(describing: v))", m, file, line)
}
func XCTAssertNotNil<T>(_ a: @autoclosure () -> T?, _ m: String = "",
                        file: String = #file, line: Int = #line) {
    record(a() != nil, "attendu non nil", m, file, line)
}
func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T,
                                         _ m: String = "", file: String = #file, line: Int = #line) {
    let (x, y) = (a(), b())
    record(x > y, "\(x) n'est pas > \(y)", m, file, line)
}
func XCTAssertLessThan<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T,
                                      _ m: String = "", file: String = #file, line: Int = #line) {
    let (x, y) = (a(), b())
    record(x < y, "\(x) n'est pas < \(y)", m, file, line)
}
func XCTAssertLessThanOrEqual<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T,
                                             _ m: String = "", file: String = #file, line: Int = #line) {
    let (x, y) = (a(), b())
    record(x <= y, "\(x) n'est pas <= \(y)", m, file, line)
}
func XCTAssertNoThrow<T>(_ a: @autoclosure () throws -> T, _ m: String = "",
                         file: String = #file, line: Int = #line) {
    do { _ = try a() } catch { record(false, "a levé \(error)", m, file, line) }
}

/// Un test qui a besoin des fichiers du depot ne peut pas tourner ici: le
/// harnais compile une COPIE temporaire, donc `#filePath` ne designe plus le
/// depot. Ces tests se sautent en local et tournent en CI.
struct XCTSkip: Error {
    let reason: String
    init(_ reason: String = "") { self.reason = reason }
}

/// Journal factice: les services purs journalisent leurs echecs.
struct ShimLogger { func info(_ s: String) {} ; func error(_ s: String) {} }
enum AppLog { static let general = ShimLogger(); static let data = ShimLogger() }
