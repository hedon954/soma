import CryptoKit
import Foundation
import UIKit
import UniformTypeIdentifiers

private struct RegistrationChallengeEnvelope: Decodable {
    var protocolVersion: Int
    var challengeID: String
    var challenge: String
}

private struct DeviceTokenEnvelope: Decodable {
    var protocolVersion: Int
    var accessToken: String
    var rotationToken: String?
    var expiresAt: Date
}

private struct UploadGrantEnvelope: Decodable {
    var protocolVersion: Int
    var uploadID: String
    var uploadURL: URL
    var requiredHeaders: [String: String]
}

private struct ErrorEnvelope: Decodable {
    struct Payload: Decodable {
        var code: String
        var message: String
    }

    var error: Payload
}

private struct DeletedEnvelope: Decodable {
    var deleted: Bool
}

struct RemoteAgentClient: AgentExecutionBackend {
    let kind = AgentExecutionBackendKind.remote

    private let baseURL: URL
    private let identity: RemoteDeviceIdentity
    private let session: URLSession

    init(
        baseURL: URL,
        identity: RemoteDeviceIdentity = .shared,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.identity = identity
        self.session = session
    }

    func submit(
        job: AgentJobSubmission
    ) async throws -> RemoteAgentJobSnapshot {
        var uploadIDs: [String] = []
        do {
            for attachment in job.attachments {
                if attachment.kind == .video {
                    guard let sourceURL = MediaStore.url(at: attachment.path)
                    else {
                        throw RemoteAgentError.server(
                            code: "media_missing",
                            message: "一项待发送视频已不在本机。"
                        )
                    }
                    let frames = await VideoFrameExtractor.frames(
                        from: sourceURL
                    )
                    guard !frames.isEmpty else {
                        throw RemoteAgentError.server(
                            code: "video_frames_unavailable",
                            message: "无法读取视频关键帧；可改为本次仅本机后重试。"
                        )
                    }
                    for frame in frames {
                        try await uploadIDs.append(uploadJPEGFrame(frame))
                    }
                } else if attachment.kind == .image {
                    try await uploadIDs.append(upload(attachment))
                }
            }
            let body = try encodeBody([
                "clientJobID": job.clientJobID.uuidString.lowercased(),
                "turnID": job.turnID.uuidString.lowercased(),
                "sessionID": job.sessionID.uuidString.lowercased(),
                "protocolVersion": 1,
                "text": job.text,
                "contextSnapshot": job.contextSnapshot,
                "uploadIDs": uploadIDs,
                "allowedRemoteTools": [],
                "allowedDeviceTools": AgentToolName.allCases.map(\.rawValue),
                "liveActivityEnabled": job.liveActivityEnabled
            ])
            let data = try await authenticatedRequest(
                method: "POST",
                path: "/v1/agent-jobs",
                body: body,
                headers: [
                    "idempotency-key":
                        job.clientJobID.uuidString.lowercased()
                ]
            )
            return try decode(RemoteAgentJobSnapshot.self, from: data)
        } catch {
            for uploadID in uploadIDs {
                try? await deleteUpload(uploadID)
            }
            throw error
        }
    }

    func events(
        remoteJobID: String,
        after sequence: Int
    ) async throws -> RemoteAgentEventPage {
        let data = try await authenticatedRequest(
            method: "GET",
            path: "/v1/agent-jobs/\(remoteJobID)/events?after=\(sequence)&limit=200",
            body: Data()
        )
        return try decode(RemoteAgentEventPage.self, from: data)
    }

    func eventStream(
        remoteJobID: String,
        after sequence: Int
    ) -> AsyncThrowingStream<RemoteAgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var permitsAuthenticationRetry = true
                    streamLoop: while true {
                        let path = "/v1/agent-jobs/\(remoteJobID)/events/stream?after=\(sequence)"
                        let request = try await authenticatedURLRequest(
                            method: "GET",
                            path: path,
                            body: Data(),
                            timeoutInterval: 60 * 60
                        )
                        let (bytes, response) = try await session.bytes(
                            for: request
                        )
                        guard let http = response as? HTTPURLResponse else {
                            throw RemoteAgentError.invalidResponse
                        }
                        if http.statusCode == 401,
                           permitsAuthenticationRetry
                        {
                            identity.clearTokens()
                            permitsAuthenticationRetry = false
                            continue streamLoop
                        }
                        guard (200 ... 299).contains(http.statusCode) else {
                            throw URLError(.badServerResponse)
                        }
                        var block: [String] = []
                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            if line.isEmpty {
                                if let event = try RemoteAgentSSEDecoder.decode(
                                    block: block.joined(separator: "\n")
                                ) {
                                    continuation.yield(event)
                                }
                                block.removeAll(keepingCapacity: true)
                            } else if !line.hasPrefix(":") {
                                block.append(line)
                            }
                        }
                        if !block.isEmpty,
                           let event = try RemoteAgentSSEDecoder.decode(
                               block: block.joined(separator: "\n")
                           )
                        {
                            continuation.yield(event)
                        }
                        break streamLoop
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func cancel(remoteJobID: String) async throws {
        _ = try await authenticatedRequest(
            method: "POST",
            path: "/v1/agent-jobs/\(remoteJobID)/cancel",
            body: encodeBody([:])
        )
    }

    func acknowledge(
        remoteJobID: String,
        through sequence: Int
    ) async throws {
        _ = try await authenticatedRequest(
            method: "POST",
            path: "/v1/agent-jobs/\(remoteJobID)/ack",
            body: encodeBody(["throughSequence": sequence])
        )
    }

    func submitToolResult(
        remoteJobID: String,
        toolCallID: String,
        result: AgentToolResult
    ) async throws {
        let resultData = try JSONEncoder().encode(result)
        let resultObject = try JSONSerialization.jsonObject(
            with: resultData
        )
        _ = try await authenticatedRequest(
            method: "POST",
            path: "/v1/agent-jobs/\(remoteJobID)/tool-results",
            body: encodeBody([
                "toolCallID": toolCallID,
                "result": resultObject
            ])
        )
    }

    func registerActivityToken(
        _ token: String,
        remoteJobID: String
    ) async throws {
        #if DEBUG
            let environment = "development"
        #else
            let environment = "production"
        #endif
        _ = try await authenticatedRequest(
            method: "PUT",
            path: "/v1/agent-jobs/\(remoteJobID)/live-activity-token",
            body: encodeBody([
                "token": token,
                "environment": environment
            ])
        )
    }

    func deleteActivityToken(remoteJobID: String) async throws {
        _ = try await authenticatedRequest(
            method: "DELETE",
            path: "/v1/agent-jobs/\(remoteJobID)/live-activity-token",
            body: Data()
        )
    }

    func deleteDeviceData() async throws {
        let data = try await authenticatedRequest(
            method: "DELETE",
            path: "/v1/device-data",
            body: Data()
        )
        _ = try decode(DeletedEnvelope.self, from: data)
    }

    func completeUpload(
        uploadID: String,
        bytes: Int,
        digest: String
    ) async throws {
        _ = try await authenticatedRequest(
            method: "POST",
            path: "/v1/uploads/\(uploadID)/complete",
            body: encodeBody([
                "bytes": bytes,
                "sha256": digest
            ])
        )
    }

    private func upload(
        _ attachment: MediaAttachmentReference
    ) async throws -> String {
        guard let sourceURL = MediaStore.url(at: attachment.path) else {
            throw RemoteAgentError.server(
                code: "media_missing",
                message: "一项待发送媒体已不在本机。"
            )
        }
        return try await uploadFile(
            sourceURL,
            contentType: mediaType(for: sourceURL, kind: attachment.kind)
        )
    }

    private func uploadJPEGFrame(_ data: Data) async throws -> String {
        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "soma-remote-frame-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        try data.write(to: sourceURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        return try await uploadFile(sourceURL, contentType: "image/jpeg")
    }

    private func uploadFile(
        _ sourceURL: URL,
        contentType: String
    ) async throws -> String {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: sourceURL.path
        )
        let bytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let digest = try fileDigest(sourceURL)
        let grantData = try await authenticatedRequest(
            method: "POST",
            path: "/v1/uploads",
            body: encodeBody([
                "contentType": contentType,
                "contentLength": bytes,
                "sha256": digest
            ])
        )
        let grant = try decode(UploadGrantEnvelope.self, from: grantData)
        var request = URLRequest(url: grant.uploadURL)
        request.httpMethod = "PUT"
        for (name, value) in grant.requiredHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        try await BackgroundRemoteUploadCoordinator.shared.upload(
            request: request,
            fromFile: sourceURL,
            uploadID: grant.uploadID,
            bytes: bytes,
            digest: digest,
            baseURL: baseURL
        )
        try await completeUpload(
            uploadID: grant.uploadID,
            bytes: bytes,
            digest: digest
        )
        return grant.uploadID
    }

    private func deleteUpload(_ uploadID: String) async throws {
        _ = try await authenticatedRequest(
            method: "DELETE",
            path: "/v1/uploads/\(uploadID)",
            body: Data()
        )
    }

    private func authenticatedRequest(
        method: String,
        path: String,
        body: Data,
        headers: [String: String] = [:],
        permitsRetry: Bool = true
    ) async throws -> Data {
        do {
            let signed = try await authenticatedURLRequest(
                method: method,
                path: path,
                body: body,
                headers: headers
            )
            return try await request(signed)
        } catch let RemoteAgentError.server(code, _)
            where permitsRetry
            && code == "unauthorized_device"
        {
            identity.clearTokens()
            return try await authenticatedRequest(
                method: method,
                path: path,
                body: body,
                headers: headers,
                permitsRetry: false
            )
        }
    }

    private func authenticatedURLRequest(
        method: String,
        path: String,
        body: Data,
        headers: [String: String] = [:],
        timeoutInterval: TimeInterval = 30
    ) async throws -> URLRequest {
        let accessToken = try await validAccessToken()
        let timestamp = String(Int(Date.now.timeIntervalSince1970))
        let nonce = UUID().uuidString.lowercased()
        let digest = sha256(body)
        let canonical = [
            method.uppercased(),
            path,
            timestamp,
            nonce,
            digest
        ].joined(separator: "\n")
        var signedHeaders = headers
        signedHeaders["authorization"] = "Bearer \(accessToken)"
        signedHeaders["x-soma-device-id"] =
            identity.deviceID.uuidString.lowercased()
        signedHeaders["x-soma-timestamp"] = timestamp
        signedHeaders["x-soma-nonce"] = nonce
        signedHeaders["x-soma-body-sha256"] = digest
        signedHeaders["x-soma-signature"] = try identity.sign(
            Data(canonical.utf8)
        )
        return try makeRequest(
            method: method,
            path: path,
            body: body,
            headers: signedHeaders,
            timeoutInterval: timeoutInterval
        )
    }

    private func validAccessToken() async throws -> String {
        if let token = identity.accessToken,
           let expiry = identity.accessTokenExpiry,
           expiry.timeIntervalSinceNow > 30
        {
            return token
        }
        if let rotationToken = identity.rotationToken {
            do {
                let data = try await request(
                    method: "POST",
                    path: "/v1/device-tokens/refresh",
                    body: encodeBody(["rotationToken": rotationToken])
                )
                let tokens = try decode(DeviceTokenEnvelope.self, from: data)
                try requireCurrentProtocol(tokens.protocolVersion)
                identity.storeTokens(
                    accessToken: tokens.accessToken,
                    expiresAt: tokens.expiresAt
                )
                return tokens.accessToken
            } catch {
                identity.clearTokens()
            }
        }
        return try await registerDevice()
    }

    private func registerDevice() async throws -> String {
        let challengeData = try await request(
            method: "POST",
            path: "/v1/device-registration-challenges",
            body: encodeBody([:])
        )
        let challenge = try decode(
            RegistrationChallengeEnvelope.self,
            from: challengeData
        )
        try requireCurrentProtocol(challenge.protocolVersion)
        let timestamp = Int(Date.now.timeIntervalSince1970)
        let deviceID = identity.deviceID.uuidString.lowercased()
        let bundleID = Bundle.main.bundleIdentifier ?? "top.hedon.soma"
        let canonical = [
            challenge.challenge,
            deviceID,
            bundleID,
            "1",
            String(timestamp)
        ].joined(separator: "\n")
        let attestation = try await identity.appAttestation(
            challenge: challenge.challenge
        )
        var body: [String: Any] = try [
            "challengeID": challenge.challengeID,
            "deviceID": deviceID,
            "publicKeyPem": identity.publicKeyPEM(),
            "signature": identity.sign(Data(canonical.utf8)),
            "timestamp": timestamp,
            "protocolVersion": 1
        ]
        if let attestation {
            body["attestationObject"] = attestation.object
            body["attestationKeyID"] = attestation.keyID
        }
        let tokenData = try await request(
            method: "POST",
            path: "/v1/devices",
            body: encodeBody(body)
        )
        let tokens = try decode(DeviceTokenEnvelope.self, from: tokenData)
        try requireCurrentProtocol(tokens.protocolVersion)
        identity.storeTokens(
            accessToken: tokens.accessToken,
            rotationToken: tokens.rotationToken,
            expiresAt: tokens.expiresAt
        )
        return tokens.accessToken
    }

    private func request(
        method: String,
        path: String,
        body: Data,
        headers: [String: String] = [:]
    ) async throws -> Data {
        try await request(makeRequest(
            method: method,
            path: path,
            body: body,
            headers: headers
        ))
    }

    private func makeRequest(
        method: String,
        path: String,
        body: Data,
        headers: [String: String] = [:],
        timeoutInterval: TimeInterval = 30
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw RemoteAgentError.endpointMissing
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body.isEmpty ? nil : body
        request.timeoutInterval = timeoutInterval
        if !body.isEmpty {
            request.setValue(
                "application/json",
                forHTTPHeaderField: "content-type"
            )
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private func request(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteAgentError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            if let envelope = try? decode(ErrorEnvelope.self, from: data) {
                throw RemoteAgentError.server(
                    code: envelope.error.code,
                    message: envelope.error.message
                )
            }
            throw RemoteAgentError.server(
                code: "http_\(http.statusCode)",
                message: "Soma 后台暂时无法处理请求（\(http.statusCode)）。"
            )
        }
        return data
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        do {
            return try remoteAgentJSONDecoder().decode(type, from: data)
        } catch {
            throw RemoteAgentError.invalidResponse
        }
    }

    private func encodeBody(_ value: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(value) else {
            throw RemoteAgentError.invalidResponse
        }
        return try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func requireCurrentProtocol(_ value: Int) throws {
        guard value == 1 else { throw RemoteAgentError.protocolMismatch }
    }

    private func sha256(_ value: Data) -> String {
        SHA256.hash(data: value).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private func fileDigest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while autoreleasepool(invoking: {
            let data = try? handle.read(upToCount: 1_048_576)
            guard let data, !data.isEmpty else { return false }
            hash.update(data: data)
            return true
        }) {}
        return hash.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }

    private func mediaType(
        for url: URL,
        kind: MediaKind
    ) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType,
           [
               "image/jpeg",
               "image/heic",
               "image/png",
               "video/quicktime",
               "video/mp4"
           ].contains(mime)
        {
            return mime
        }
        return kind == .video ? "video/quicktime" : "image/jpeg"
    }
}
