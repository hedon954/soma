import Foundation

private struct BackgroundUploadMetadata: Codable {
    var uploadID: String
    var bytes: Int
    var digest: String
    var baseURL: String
}

final class BackgroundRemoteUploadCoordinator: NSObject,
    URLSessionDataDelegate,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    static let sessionIdentifier = "top.hedon.soma.remote-agent-uploads"
    static let shared = BackgroundRemoteUploadCoordinator()

    private struct Pending {
        var data: Data
        var response: HTTPURLResponse?
        var continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]
    private var backgroundCompletion: (() -> Void)?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.sessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }()

    func activate() {
        _ = session
    }

    func handleBackgroundEvents(completion: @escaping () -> Void) {
        lock.lock()
        backgroundCompletion = completion
        lock.unlock()
        activate()
    }

    func upload(
        request: URLRequest,
        fromFile fileURL: URL,
        uploadID: String,
        bytes: Int,
        digest: String,
        baseURL: URL
    ) async throws {
        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.taskDescription = try String(
            data: JSONEncoder().encode(BackgroundUploadMetadata(
                uploadID: uploadID,
                bytes: bytes,
                digest: digest,
                baseURL: baseURL.absoluteString
            )),
            encoding: .utf8
        )
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pending[task.taskIdentifier] = Pending(
                data: Data(),
                continuation: continuation
            )
            lock.unlock()
            task.resume()
        }
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        pending[dataTask.taskIdentifier]?.data.append(data)
        lock.unlock()
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let value = pending.removeValue(forKey: task.taskIdentifier)
        lock.unlock()

        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        let uploadError: Error? = if let error {
            error
        } else if !(200 ... 299).contains(status) {
            RemoteAgentError.server(
                code: "upload_incomplete",
                message: "附件未能上传完整，请检查网络并重新发送。"
            )
        } else {
            nil
        }
        if let value {
            if let uploadError {
                value.continuation.resume(throwing: uploadError)
            } else {
                value.continuation.resume()
            }
        } else if uploadError == nil,
                  let description = task.taskDescription,
                  let data = description.data(using: .utf8),
                  let metadata = try? JSONDecoder().decode(
                      BackgroundUploadMetadata.self,
                      from: data
                  ),
                  let baseURL = URL(string: metadata.baseURL)
        {
            // iOS may relaunch the App after the originating process was
            // terminated. Finalize the already uploaded object before asking
            // the local persistent Job runner to resume.
            Task {
                try? await RemoteAgentClient(baseURL: baseURL).completeUpload(
                    uploadID: metadata.uploadID,
                    bytes: metadata.bytes,
                    digest: metadata.digest
                )
                NotificationCenter.default.post(
                    name: .remoteBackgroundUploadCompleted,
                    object: nil
                )
            }
        }
    }

    func urlSessionDidFinishEvents(
        forBackgroundURLSession _: URLSession
    ) {
        lock.lock()
        let completion = backgroundCompletion
        backgroundCompletion = nil
        lock.unlock()
        DispatchQueue.main.async {
            completion?()
        }
    }
}

extension Notification.Name {
    static let remoteBackgroundUploadCompleted = Notification.Name(
        "remoteBackgroundUploadCompleted"
    )
}
