import Foundation

/// LRU disk cache for audio files with a configurable size cap.
///
/// Caches downloaded audio files on disk so previously played recordings
/// can be replayed without re-downloading. Uses an LRU (Least Recently Used)
/// eviction policy when the cache exceeds the configured size limit.
///
/// ## Behavior
/// - Files are stored in the app's Caches directory under `audio_cache/`.
/// - The default size cap is 100 MB.
/// - When the cap is exceeded, the least recently accessed files are evicted first.
/// - The system may also purge this directory under storage pressure.
final class CacheManager: @unchecked Sendable {
    /// The default maximum cache size in bytes (100 MB).
    static let defaultMaxSize: UInt64 = 100 * 1024 * 1024

    private let cacheDirectory: URL
    private let maxSize: UInt64
    private nonisolated(unsafe) let fileManager: FileManager

    /// Creates a cache manager with the given size limit.
    ///
    /// - Parameters:
    ///   - maxSize: The maximum total size of cached files in bytes.
    ///     Defaults to ``defaultMaxSize`` (100 MB).
    ///   - directory: The base directory for the cache. Defaults to the
    ///     system Caches directory.
    init(maxSize: UInt64 = CacheManager.defaultMaxSize, directory: URL? = nil) {
        self.maxSize = maxSize
        self.fileManager = .default

        let baseDir = directory ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = baseDir.appendingPathComponent("audio_cache", isDirectory: true)

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Returns the local cache URL for a recording, or `nil` if not cached.
    ///
    /// If the file exists, its last-accessed date is updated for LRU tracking.
    ///
    /// - Parameter recordingId: The recording's unique identifier.
    /// - Returns: The local file URL if cached, otherwise `nil`.
    func cachedFileURL(for recordingId: UUID) -> URL? {
        let fileURL = fileURL(for: recordingId)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        // Touch the file to update access time for LRU
        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )

        return fileURL
    }

    /// Caches audio data for a recording.
    ///
    /// Writes the data to disk and triggers eviction if the cache exceeds its size cap.
    ///
    /// - Parameters:
    ///   - data: The audio file data to cache.
    ///   - recordingId: The recording's unique identifier.
    /// - Throws: If the data cannot be written to disk.
    func cache(data: Data, for recordingId: UUID) throws {
        let fileURL = fileURL(for: recordingId)
        try data.write(to: fileURL)
        evictIfNeeded()
    }

    /// Caches an audio file by moving it from a temporary location.
    ///
    /// - Parameters:
    ///   - sourceURL: The temporary file URL to move into the cache.
    ///   - recordingId: The recording's unique identifier.
    /// - Throws: If the file cannot be moved.
    func cacheFile(from sourceURL: URL, for recordingId: UUID) throws {
        let destinationURL = fileURL(for: recordingId)

        // Remove existing cached file if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        evictIfNeeded()
    }

    /// Removes a specific recording from the cache.
    ///
    /// - Parameter recordingId: The recording's unique identifier.
    func remove(recordingId: UUID) {
        let fileURL = fileURL(for: recordingId)
        try? fileManager.removeItem(at: fileURL)
    }

    /// Removes all files from the cache.
    func clearAll() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Returns the total size of all cached files in bytes.
    func currentSize() -> UInt64 {
        cachedFiles().reduce(0) { total, entry in
            total + entry.size
        }
    }

    // MARK: - Private

    private func fileURL(for recordingId: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(recordingId.uuidString).m4a")
    }

    private struct CachedFile {
        let url: URL
        let size: UInt64
        let modificationDate: Date
    }

    private func cachedFiles() -> [CachedFile] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else {
            return []
        }

        return contents.compactMap { url in
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? UInt64,
                  let modified = attributes[.modificationDate] as? Date else {
                return nil
            }
            return CachedFile(url: url, size: size, modificationDate: modified)
        }
    }

    private func evictIfNeeded() {
        var files = cachedFiles()
        var totalSize = files.reduce(0 as UInt64) { $0 + $1.size }

        guard totalSize > maxSize else { return }

        // Sort by modification date (oldest first) for LRU eviction
        files.sort { $0.modificationDate < $1.modificationDate }

        for file in files {
            guard totalSize > maxSize else { break }
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size
        }
    }
}
