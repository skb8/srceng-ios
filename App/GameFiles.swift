import Foundation

enum GameFiles {
    enum ImportError: LocalizedError {
        case missingGameInfo

        var errorDescription: String? {
            "В выбранной папке должен быть файл hl2/gameinfo.txt. Выберите корневую папку Half-Life 2."
        }
    }

    private static let marker = "current"

    private static func storage() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("SourceContent", isDirectory: true)
    }

    static func installedBase() -> URL? {
        try? currentBase(in: storage())
    }

    private static func currentBase(in storage: URL) -> URL? {
        let markerURL = storage.appendingPathComponent(marker)
        guard let name = try? String(contentsOf: markerURL, encoding: .utf8),
              let folderID = UUID(uuidString: name) else { return nil }
        let base = storage.appendingPathComponent(folderID.uuidString, isDirectory: true)
        return containsGameInfo(base) ? base : nil
    }

    private static func containsGameInfo(_ base: URL) -> Bool {
        let gameInfo = base.appendingPathComponent("hl2/gameinfo.txt")
        let basePath = base.resolvingSymlinksInPath().path
        return gameInfo.resolvingSymlinksInPath().path.hasPrefix(basePath + "/")
            && (try? gameInfo.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    // Run off the main thread. The marker is committed only after the copy is complete.
    static func install(from selectedFolder: URL) throws {
        let scoped = selectedFolder.startAccessingSecurityScopedResource()
        defer { if scoped { selectedFolder.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        var storage = try storage()
        try fileManager.createDirectory(at: storage, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? storage.setResourceValues(resourceValues)

        let previous = currentBase(in: storage)
        let folderID = UUID().uuidString
        let destination = storage.appendingPathComponent(folderID, isDirectory: true)
        var installed = false
        defer { if !installed { try? fileManager.removeItem(at: destination) } }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copyResult: Result<Void, Error>?
        coordinator.coordinate(readingItemAt: selectedFolder, options: [],
                               error: &coordinationError) { source in
            copyResult = Result {
                guard containsGameInfo(source) else { throw ImportError.missingGameInfo }
                try fileManager.copyItem(at: source, to: destination)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let copyResult else { throw CocoaError(.fileReadUnknown) }
        try copyResult.get()
        guard containsGameInfo(destination) else { throw ImportError.missingGameInfo }
        try folderID.write(to: storage.appendingPathComponent(marker), atomically: true, encoding: .utf8)
        installed = true
        if let previous { try? fileManager.removeItem(at: previous) }
    }
}
