import Foundation

/// Schlanke Persistenz auf JSON-Dateien in
/// ~/Library/Application Support/Dashboard/.
/// Bewusst simpel gehalten – lässt sich später gegen SwiftData tauschen,
/// ohne dass die Views davon etwas mitbekommen.
enum JSONStore {

    static let directory: URL = {
        // Testläufe können den Ablageort umlenken. Ohne das schreiben sie in
        // die echten Daten – „Application Support“ löst FileManager über den
        // Benutzerdatensatz auf, eine Umleitung von HOME greift dort nicht.
        let base: URL
        if let override = ProcessInfo.processInfo.environment["DASHBOARD_DATA_DIR"], !override.isEmpty {
            base = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        }
        let dir = base.appendingPathComponent("Dashboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        let url = directory.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to file: String) {
        let url = directory.appendingPathComponent(file)
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Dashboard: Konnte \(file) nicht speichern – \(error.localizedDescription)")
        }
    }
}
