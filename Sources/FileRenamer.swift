import Foundation

enum FileRenamer {

    /// Rename a file, handling duplicates by appending -2, -3, etc.
    /// Returns the URL of the renamed file.
    @discardableResult
    static func rename(fileAt url: URL, to newName: String) throws -> URL {
        let directory = url.deletingLastPathComponent()
        var targetURL = directory.appendingPathComponent(newName)

        // Handle duplicates
        if FileManager.default.fileExists(atPath: targetURL.path) {
            let nameWithoutExt = (newName as NSString).deletingPathExtension
            let ext = (newName as NSString).pathExtension

            var counter = 2
            while FileManager.default.fileExists(atPath: targetURL.path) {
                let numberedName = "\(nameWithoutExt)-\(counter).\(ext)"
                targetURL = directory.appendingPathComponent(numberedName)
                counter += 1
            }
        }

        try FileManager.default.moveItem(at: url, to: targetURL)
        return targetURL
    }

    /// Get the creation date of a file, falling back to current date.
    static func creationDate(for url: URL) -> Date {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.creationDate] as? Date) ?? Date()
        } catch {
            return Date()
        }
    }
}
