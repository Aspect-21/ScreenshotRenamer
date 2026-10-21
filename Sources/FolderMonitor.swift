import Foundation

final class FolderMonitor {
    private let watchedURL: URL
    private let onChange: (URL) -> Void

    // DispatchSource-based monitoring (instant notifications)
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let sourceQueue = DispatchQueue(label: "com.screenshotrenamer.foldermonitor.source", qos: .utility)

    // Polling timer as a safety net (catches events if DispatchSource stops firing)
    private var pollTimer: DispatchSourceTimer?
    private let pollInterval: TimeInterval = 2.0

    // Separate queue for processing new files (avoids blocking the source queue)
    private let processingQueue = DispatchQueue(label: "com.screenshotrenamer.foldermonitor.processing", qos: .utility)

    private var knownFiles: Set<String> = []
    private let knownFilesLock = NSLock()
    private var isRunning = false
    private var isProcessing = false // prevents overlapping scans

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "bmp", "heic", "webp"]

    init(url: URL, onChange: @escaping (URL) -> Void) {
        self.watchedURL = url
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard !isRunning else { return }

        // Snapshot current files so we don't rename existing ones
        knownFiles = currentImageFiles()
        Logger.log("FolderMonitor: initial snapshot has \(knownFiles.count) existing image files")

        startDispatchSource()
        startPollTimer()

        isRunning = true
        Logger.log("FolderMonitor: STARTED watching \(watchedURL.path)")
    }

    func stop() {
        guard isRunning else { return }

        stopDispatchSource()
        stopPollTimer()

        isRunning = false
        Logger.log("FolderMonitor: STOPPED")
    }

    // MARK: - DispatchSource Management

    private func startDispatchSource() {
        stopDispatchSource()

        fileDescriptor = open(watchedURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            Logger.log("FolderMonitor: FAILED to open directory: \(watchedURL.path)")
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .extend],
            queue: sourceQueue
        )

        newSource.setEventHandler { [weak self] in
            guard let self else { return }
            Logger.log("FolderMonitor: DispatchSource event fired")
            // Don't block the source queue — schedule on the processing queue
            self.processingQueue.async {
                self.scanForNewFiles()
            }
        }

        newSource.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        newSource.resume()
        source = newSource
    }

    private func stopDispatchSource() {
        source?.cancel()
        source = nil
    }

    /// Re-create the DispatchSource to ensure it keeps delivering events.
    /// This is called after processing to work around macOS kqueue limitations.
    private func refreshDispatchSource() {
        guard isRunning else { return }
        sourceQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            Logger.log("FolderMonitor: refreshing DispatchSource")
            self.startDispatchSource()
        }
    }

    // MARK: - Poll Timer (Safety Net)

    private func startPollTimer() {
        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            self?.scanForNewFiles()
        }
        timer.resume()
        pollTimer = timer
    }

    private func stopPollTimer() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    // MARK: - Core Scanning Logic

    /// Scans the directory for new files and processes them.
    /// Thread-safe: uses a lock to prevent overlapping scans.
    private func scanForNewFiles() {
        // Prevent overlapping scans
        knownFilesLock.lock()
        guard !isProcessing else {
            knownFilesLock.unlock()
            return
        }
        isProcessing = true
        knownFilesLock.unlock()

        defer {
            knownFilesLock.lock()
            isProcessing = false
            knownFilesLock.unlock()
        }

        // Small delay to let the file system settle (screenshot might still be writing)
        Thread.sleep(forTimeInterval: 0.5)

        let currentFiles = currentImageFiles()

        knownFilesLock.lock()
        let newFiles = currentFiles.subtracting(knownFiles)
        knownFilesLock.unlock()

        if newFiles.isEmpty {
            // Even if no new files, update the set (files may have been renamed/deleted)
            knownFilesLock.lock()
            knownFiles = currentFiles
            knownFilesLock.unlock()
            return
        }

        Logger.log("FolderMonitor: detected \(newFiles.count) new file(s): \(newFiles.joined(separator: ", "))")

        for fileName in newFiles {
            let fileURL = watchedURL.appendingPathComponent(fileName)

            // Only process screenshot-like files (macOS screenshots start with "Screenshot" or "Screen Shot")
            let name = fileName.lowercased()
            let isScreenshot = name.hasPrefix("screenshot") ||
                               name.hasPrefix("screen shot") ||
                               name.hasPrefix("screen recording") ||
                               name.hasPrefix("cleanshot") ||
                               name.contains("screenshot")

            if isScreenshot {
                // Wait until file size stabilizes (file fully written)
                if waitForStableFileSize(at: fileURL) {
                    Logger.log("FolderMonitor: screenshot ready, triggering rename: \(fileName)")
                    onChange(fileURL)
                } else {
                    Logger.log("FolderMonitor: file never stabilized, skipping: \(fileName)")
                }
            } else {
                Logger.log("FolderMonitor: ignoring non-screenshot file: \(fileName)")
            }
        }

        // Update known files AFTER processing (so renamed files are captured on next scan)
        // Small delay to let the rename happen before re-scanning
        Thread.sleep(forTimeInterval: 0.5)
        let updatedFiles = currentImageFiles()
        knownFilesLock.lock()
        knownFiles = updatedFiles
        knownFilesLock.unlock()

        // Refresh the DispatchSource to ensure it keeps working
        refreshDispatchSource()
    }

    /// Polls the file size until it stops changing, up to a maximum number of attempts.
    private func waitForStableFileSize(at url: URL, maxAttempts: Int = 15) -> Bool {
        var previousSize: Int64 = -1
        var stableCount = 0
        for attempt in 1...maxAttempts {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int64 else {
                Logger.log("FolderMonitor: could not read file size (attempt \(attempt))")
                Thread.sleep(forTimeInterval: 0.3)
                continue
            }
            if size > 0 && size == previousSize {
                stableCount += 1
                if stableCount >= 2 {
                    return true // file size stable for 2 consecutive checks
                }
            } else {
                stableCount = 0
            }
            previousSize = size
            Thread.sleep(forTimeInterval: 0.3)
        }
        // Accept the file if we have a non-zero size even if we ran out of attempts
        return previousSize > 0
    }

    private func currentImageFiles() -> Set<String> {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: watchedURL,
                includingPropertiesForKeys: [.contentTypeKey],
                options: [.skipsHiddenFiles]
            )
            return Set(contents
                .filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
                .map { $0.lastPathComponent }
            )
        } catch {
            Logger.log("FolderMonitor: error listing directory: \(error)")
            return []
        }
    }
}
