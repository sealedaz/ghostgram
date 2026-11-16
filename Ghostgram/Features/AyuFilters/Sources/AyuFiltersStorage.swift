import Foundation

public final class AyuFiltersStorage {
    public static let shared = AyuFiltersStorage()

    private let fileManager = FileManager.default
    private let fileName = "filters_v2.json"
    private let lock = NSLock()

    private var directoryURL: URL {
        let appSupport = self.fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("AyuGram", isDirectory: true)
    }

    private var fileURL: URL {
        return self.directoryURL.appendingPathComponent(self.fileName)
    }

    private init() {
        self.ensureDirectoryExists()
    }

    private func ensureDirectoryExists() {
        let dir = self.directoryURL
        if !self.fileManager.fileExists(atPath: dir.path) {
            try? self.fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDir = dir
            try? mutableDir.setResourceValues(values)
        }
    }

    public func load() -> AyuFiltersConfig {
        self.lock.lock()
        defer { self.lock.unlock() }

        let url = self.fileURL
        guard self.fileManager.fileExists(atPath: url.path) else {
            return AyuFiltersConfig()
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let config = try decoder.decode(AyuFiltersConfig.self, from: data)
            return config
        } catch {
            return AyuFiltersConfig()
        }
    }

    public func save(_ config: AyuFiltersConfig) {
        self.lock.lock()
        defer { self.lock.unlock() }

        self.ensureDirectoryExists()
        let url = self.fileURL

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: url, options: .atomic)

            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableUrl = url
            try? mutableUrl.setResourceValues(values)
        } catch {
            // Write failure handled gracefully
        }
    }

    public func exportJsonString() -> String? {
        let config = self.load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
