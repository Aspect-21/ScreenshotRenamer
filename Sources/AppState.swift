import Foundation
import SwiftUI

@Observable
final class AppState {
    // MARK: - Persisted Settings
    var watchedFolderPath: String {
        didSet { UserDefaults.standard.set(watchedFolderPath, forKey: "watchedFolderPath") }
    }
    var isActive: Bool {
        didSet { UserDefaults.standard.set(isActive, forKey: "isActive") }
    }
    var geminiAPIKey: String {
        didSet { UserDefaults.standard.set(geminiAPIKey, forKey: "geminiAPIKey") }
    }

    // MARK: - Runtime State
    var renameHistory: [RenameRecord] = []
    var statusMessage: String = "Idle"
    var isProcessing: Bool = false

    // MARK: - Components
    var folderMonitor: FolderMonitor?

    init() {
        self.watchedFolderPath = UserDefaults.standard.string(forKey: "watchedFolderPath") ?? ""
        self.isActive = UserDefaults.standard.bool(forKey: "isActive")
        self.geminiAPIKey = UserDefaults.standard.string(forKey: "geminiAPIKey") ?? ""
        Logger.log("AppState: initialized — folder=\"\(self.watchedFolderPath)\", isActive=\(self.isActive), hasAPIKey=\(!self.geminiAPIKey.isEmpty)")
    }

    // MARK: - Auto-resume on Launch

    /// Call this once after the app finishes launching to resume monitoring if it was active before.
    func resumeIfNeeded() {
        Logger.log("AppState: resumeIfNeeded called — isActive=\(isActive), folder=\"\(watchedFolderPath)\"")
        if isActive && !watchedFolderPath.isEmpty && !geminiAPIKey.isEmpty {
            Logger.log("AppState: auto-resuming monitoring")
            // Reset isActive temporarily so startMonitoring sets it back
            isActive = false
            startMonitoring()
        }
    }

    // MARK: - Control

    func startMonitoring() {
        guard !watchedFolderPath.isEmpty else {
            statusMessage = "No folder selected"
            Logger.log("AppState: startMonitoring FAILED — no folder selected")
            return
        }
        guard !geminiAPIKey.isEmpty else {
            statusMessage = "No API key set"
            Logger.log("AppState: startMonitoring FAILED — no API key")
            return
        }

        // Verify the folder exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: watchedFolderPath, isDirectory: &isDir), isDir.boolValue else {
            statusMessage = "Folder not found"
            Logger.log("AppState: startMonitoring FAILED — folder does not exist: \(watchedFolderPath)")
            return
        }

        stopMonitoring()

        let url = URL(fileURLWithPath: watchedFolderPath)
        folderMonitor = FolderMonitor(url: url) { [weak self] fileURL in
            guard let self else {
                Logger.log("AppState: onChange callback — self is nil, skipping")
                return
            }
            Task { @MainActor in
                await self.processNewScreenshot(at: fileURL)
            }
        }

        folderMonitor?.start()
        isActive = true
        statusMessage = "Watching: \(watchedFolderPath)"
        Logger.log("AppState: STARTED monitoring \(watchedFolderPath)")
    }

    func stopMonitoring() {
        folderMonitor?.stop()
        folderMonitor = nil
        isActive = false
        statusMessage = "Paused"
        Logger.log("AppState: STOPPED monitoring")
    }

    func toggleMonitoring() {
        if isActive {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    // MARK: - Processing

    @MainActor
    private func processNewScreenshot(at fileURL: URL) async {
        let fileName = fileURL.lastPathComponent
        Logger.log("AppState: processing screenshot: \(fileName)")

        isProcessing = true
        statusMessage = "🔍 Analyzing: \(fileName)"

        do {
            // Wait for file write to fully complete
            try await Task.sleep(for: .milliseconds(1500))

            // Verify file still exists (it may have been moved/deleted)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                Logger.log("AppState: file no longer exists, skipping: \(fileName)")
                statusMessage = "⏭ File moved: \(fileName)"
                isProcessing = false
                return
            }

            // Try Gemini first, fall back to on-device Vision if it fails
            var suggestedName: String
            var modelUsed: String = "Vision AI"
            let creationDate = FileRenamer.creationDate(for: fileURL)
            let datePrefix = formatDate(creationDate)
            let ext = fileURL.pathExtension.lowercased()

            do {
                Logger.log("AppState: sending to Gemini API for analysis (model fallback chain)...")
                let gemini = GeminiAnalyzer(apiKey: geminiAPIKey)
                let result = try await gemini.analyzeName(for: fileURL)
                suggestedName = result.name
                modelUsed = result.modelUsed
                Logger.log("AppState: Gemini returned name: \"\(suggestedName)\" via \(modelUsed)")
            } catch {
                Logger.log("AppState: all Gemini models failed (\(error.localizedDescription)), falling back to on-device Vision...")
                statusMessage = "🔄 All Gemini models unavailable, using Vision AI..."

                let analyzer = ImageAnalyzer()
                let analysis = try await analyzer.analyze(imageAt: fileURL)
                let generator = NameGenerator()
                let fallbackFullName = generator.generateName(from: analysis, originalURL: fileURL, date: creationDate)
                // NameGenerator already includes date prefix + extension, extract just the descriptive part
                suggestedName = fallbackFullName
                    .replacingOccurrences(of: "\(datePrefix)_", with: "")
                    .replacingOccurrences(of: ".\(ext)", with: "")
                modelUsed = "on-device Vision"
                Logger.log("AppState: Vision fallback name: \"\(suggestedName)\"")
            }

            let newName = "\(datePrefix)_\(suggestedName).\(ext)"
            Logger.log("AppState: renaming \"\(fileName)\" → \"\(newName)\" (model: \(modelUsed))")

            // Rename the file
            let newURL = try FileRenamer.rename(fileAt: fileURL, to: newName)

            let record = RenameRecord(
                originalName: fileName,
                newName: newURL.lastPathComponent,
                date: Date(),
                previewText: suggestedName,
                modelUsed: modelUsed
            )
            renameHistory.insert(record, at: 0)

            // Keep history manageable
            if renameHistory.count > 50 {
                renameHistory = Array(renameHistory.prefix(50))
            }

            statusMessage = "✅ \(newURL.lastPathComponent)"
            Logger.log("AppState: SUCCESS — renamed to \(newURL.lastPathComponent) via \(modelUsed)")

        } catch {
            statusMessage = "❌ Error: \(error.localizedDescription)"
            Logger.log("AppState: ERROR processing \(fileName): \(error)")
        }

        isProcessing = false
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Models

struct RenameRecord: Identifiable {
    let id = UUID()
    let originalName: String
    let newName: String
    let date: Date
    let previewText: String
    let modelUsed: String
}
