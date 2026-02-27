import Foundation
import Observation

/// Represents the state of a single upload task.
enum UploadTaskState: Sendable {
    /// The upload is waiting to be sent.
    case pending

    /// The upload is actively transferring data.
    case uploading(progress: Double)

    /// The upload completed successfully.
    case completed

    /// The upload failed and may be retried.
    case failed(Error)
}

/// A tracked upload operation with progress and state.
struct UploadTask: Identifiable, Sendable {
    /// Unique identifier for this upload task.
    let id: UUID

    /// The recording ID this upload is associated with.
    let recordingId: UUID

    /// The local file URL of the audio file to upload.
    let fileURL: URL

    /// The pre-signed URL to PUT the file to.
    let presignedURL: URL

    /// The current upload state.
    var state: UploadTaskState
}

/// A pending upload that is persisted to disk for resume on app relaunch.
private struct PersistentUpload: Codable {
    let id: UUID
    let recordingId: UUID
    let filePath: String
    let presignedURLString: String
    let createdAt: Date
}

/// Manages background uploads of audio files to pre-signed S3 URLs.
///
/// Uses a background `URLSession` so uploads continue even when the app
/// is backgrounded. Persists pending uploads to disk so they survive
/// app termination and can be retried on next launch.
///
/// ## Upload Flow
/// 1. Call `upload(fileURL:to:recordingId:)` with the local file and pre-signed URL.
/// 2. The manager creates a background upload task and tracks progress.
/// 3. If the app is backgrounded, iOS continues the upload.
/// 4. On failure, the upload is queued for retry when connectivity returns.
@Observable
final class UploadManager: NSObject, @unchecked Sendable {
    /// The background session identifier used for upload tasks.
    static let sessionIdentifier = "app.hearhere.upload"

    /// Active and pending upload tasks.
    private(set) var tasks: [UploadTask] = []

    @ObservationIgnored
    private var _backgroundSession: URLSession?

    private var backgroundSession: URLSession {
        if let session = _backgroundSession { return session }
        let config = URLSessionConfiguration.background(
            withIdentifier: Self.sessionIdentifier
        )
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        _backgroundSession = session
        return session
    }

    @ObservationIgnored
    private var urlTaskToUploadId: [Int: UUID] = [:]

    private let persistenceURL: URL

    /// Creates an upload manager that persists pending uploads to the given directory.
    /// - Parameter directory: The directory for storing pending upload metadata.
    ///   Defaults to the app's Application Support directory.
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.persistenceURL = dir.appendingPathComponent("pending_uploads.json")
        super.init()
    }

    /// Starts an upload of an audio file to a pre-signed URL.
    ///
    /// The upload runs on a background session and continues even when the app
    /// is suspended. Progress updates are delivered via the ``tasks`` array.
    ///
    /// - Parameters:
    ///   - fileURL: The local URL of the `.m4a` file to upload.
    ///   - presignedURL: The pre-signed S3 PUT URL from the API.
    ///   - recordingId: The recording ID associated with this upload.
    /// - Returns: The created ``UploadTask`` for tracking.
    @discardableResult
    func upload(fileURL: URL, to presignedURL: URL, recordingId: UUID) -> UploadTask {
        let uploadTask = UploadTask(
            id: UUID(),
            recordingId: recordingId,
            fileURL: fileURL,
            presignedURL: presignedURL,
            state: .pending
        )
        tasks.append(uploadTask)
        persistPendingUploads()

        var request = URLRequest(url: presignedURL)
        request.httpMethod = "PUT"
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")

        let urlTask = backgroundSession.uploadTask(with: request, fromFile: fileURL)
        urlTaskToUploadId[urlTask.taskIdentifier] = uploadTask.id
        urlTask.resume()

        updateTaskState(id: uploadTask.id, state: .uploading(progress: 0))
        return uploadTask
    }

    /// Retries all failed uploads.
    func retryFailedUploads() {
        for task in tasks where task.isFailed {
            var request = URLRequest(url: task.presignedURL)
            request.httpMethod = "PUT"
            request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")

            let urlTask = backgroundSession.uploadTask(with: request, fromFile: task.fileURL)
            urlTaskToUploadId[urlTask.taskIdentifier] = task.id
            urlTask.resume()

            updateTaskState(id: task.id, state: .uploading(progress: 0))
        }
    }

    /// Loads pending uploads from disk and retries them.
    ///
    /// Call this on app launch to resume uploads that were interrupted.
    func restorePendingUploads() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let persistedUploads = try? JSONDecoder().decode([PersistentUpload].self, from: data) else {
            return
        }

        for persisted in persistedUploads {
            let fileURL = URL(fileURLWithPath: persisted.filePath)
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let presignedURL = URL(string: persisted.presignedURLString) else {
                continue
            }

            // Only restore if not already tracked
            if !tasks.contains(where: { $0.id == persisted.id }) {
                upload(fileURL: fileURL, to: presignedURL, recordingId: persisted.recordingId)
            }
        }
    }

    /// Removes a completed or failed upload from the tracked list.
    /// - Parameter id: The upload task ID to remove.
    func removeTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        persistPendingUploads()
    }

    // MARK: - Private

    private func updateTaskState(id: UUID, state: UploadTaskState) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].state = state

        if case .completed = state {
            persistPendingUploads()
        }
    }

    private func persistPendingUploads() {
        let pending = tasks.filter { !$0.isCompleted }.map { task in
            PersistentUpload(
                id: task.id,
                recordingId: task.recordingId,
                filePath: task.fileURL.path,
                presignedURLString: task.presignedURL.absoluteString,
                createdAt: Date()
            )
        }

        let directory = persistenceURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(pending).write(to: persistenceURL)
    }
}

// MARK: - URLSessionTaskDelegate

extension UploadManager: URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let uploadId = urlTaskToUploadId[task.taskIdentifier],
              totalBytesExpectedToSend > 0 else { return }

        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        Task { @MainActor in
            self.updateTaskState(id: uploadId, state: .uploading(progress: progress))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let uploadId = urlTaskToUploadId.removeValue(forKey: task.taskIdentifier) else { return }

        Task { @MainActor in
            if let error {
                self.updateTaskState(id: uploadId, state: .failed(error))
            } else if let httpResponse = task.response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) {
                self.updateTaskState(id: uploadId, state: .completed)
            } else {
                self.updateTaskState(
                    id: uploadId,
                    state: .failed(APIError.uploadFailed(underlying: URLError(.badServerResponse)))
                )
            }
        }
    }
}

// MARK: - URLSessionDelegate

extension UploadManager: URLSessionDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // The app delegate should store and call the completion handler here.
        // This hook allows the system to know when background events are handled.
    }
}

// MARK: - UploadTask Helpers

extension UploadTask {
    /// Whether this upload has completed successfully.
    var isCompleted: Bool {
        if case .completed = state { return true }
        return false
    }

    /// Whether this upload has failed.
    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    /// The upload progress as a value from 0.0 to 1.0, or `nil` if not uploading.
    var progress: Double? {
        if case .uploading(let progress) = state { return progress }
        return nil
    }
}
