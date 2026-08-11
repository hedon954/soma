import CryptoKit
import Foundation
import Security
@testable import Soma
import Testing

struct RemoteAgentExecutionTests {
    @Test
    func remoteStatesCanBeReclaimedWithoutLosingIdentity() throws {
        let job = AgentJob(
            turnID: UUID(),
            sessionID: UUID(),
            userMessageID: UUID(),
            dataSpace: .personal,
            backend: .remote,
            userText: "虚构任务",
            mediaAttachments: [],
            contextSnapshot: .init(structuredContext: "", includeLocation: false)
        )

        try job.transition(to: .running)
        try job.transition(to: .remoteRunning)

        #expect(job.state.isRunnable)
        #expect(job.backend == .remote)
        #expect(job.remoteEventCursor == 0)
        try job.transition(to: .running)
        #expect(job.state == .running)
    }

    @Test
    func suspendedToolEventDecodesFixedRequest() throws {
        let arguments: [String: RemoteJSONValue] = [
            "exercise_id": .string(UUID().uuidString),
            "set_entries": .array([
                .object([
                    "reps": .number(5),
                    "external_weight_kg": .number(30)
                ])
            ])
        ]
        let event = RemoteAgentEvent(
            id: UUID().uuidString,
            jobID: UUID().uuidString,
            sequence: 3,
            kind: "tool",
            phase: "suspended",
            payloadVersion: 1,
            payload: [
                "toolCallID": .string(UUID().uuidString),
                "toolName": .string("record_workout"),
                "schemaVersion": .number(1),
                "arguments": .object(arguments),
                "mutation": .bool(true)
            ],
            createdAt: .now
        )

        let request = try #require(RemoteDeviceToolRequest(event: event))
        #expect(request.name == AgentToolName.recordWorkout.rawValue)
        #expect(request.schemaVersion == 1)
        #expect(request.mutation)

        let data = try JSONEncoder().encode(request.arguments)
        let decoded = try JSONDecoder().decode(
            AgentToolArguments.self,
            from: data
        )
        #expect(decoded.setEntries?.first?.reps == 5)
        #expect(decoded.setEntries?.first?.externalWeightKG == 30)
    }

    @Test
    func remoteSSEDecoderPreservesOrderedTextAndTerminalEvents() throws {
        let firstJSON = "{\"id\":\"event-2\",\"jobID\":\"job-1\"," +
            "\"sequence\":2,\"kind\":\"text\",\"phase\":\"updated\"," +
            "\"payloadVersion\":1,\"payload\":{\"delta\":\"第一段\"," +
            "\"itemID\":\"00000000-0000-0000-0000-000000000001\"}," +
            "\"createdAt\":\"2026-08-03T00:00:00Z\"}"
        let finalJSON = "{\"id\":\"event-3\",\"jobID\":\"job-1\"," +
            "\"sequence\":3,\"kind\":\"output\",\"phase\":\"completed\"," +
            "\"payloadVersion\":1,\"payload\":{\"answer\":\"第一段完成\"}," +
            "\"createdAt\":\"2026-08-03T00:00:01Z\"}"
        let first = try #require(try RemoteAgentSSEDecoder.decode(
            block: "id: 2\nevent: agent_event\ndata: \(firstJSON)"
        ))
        let final = try #require(try RemoteAgentSSEDecoder.decode(
            block: "id: 3\nevent: agent_event\ndata: \(finalJSON)"
        ))

        #expect(first.sequence == 2)
        #expect(first.payload["delta"]?.stringValue == "第一段")
        #expect(final.sequence == 3)
        #expect(final.payload["answer"]?.stringValue == "第一段完成")
    }

    @Test
    func clientRegistersSignsAndSubmitsIdempotently() async throws {
        let identity = RemoteDeviceIdentity(usesEphemeralStorage: true)
        let server = MockRemoteAgentServer()
        MockRemoteURLProtocol.handler = { request in
            try server.response(to: request)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockRemoteURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let baseURL = try #require(URL(string: "https://soma.test"))
        let client = RemoteAgentClient(
            baseURL: baseURL,
            identity: identity,
            session: session
        )
        let clientJobID = UUID()
        let turnID = UUID()
        let submitted = try await client.submit(job: AgentJobSubmission(
            clientJobID: clientJobID,
            turnID: turnID,
            sessionID: UUID(),
            text: "虚构远程任务",
            contextSnapshot: "最小虚构上下文",
            attachments: [],
            liveActivityEnabled: true
        ))

        #expect(submitted.clientJobID == clientJobID.uuidString.lowercased())
        #expect(submitted.turnID == turnID.uuidString.lowercased())
        #expect(server.registrationSignatureWasValid)
        #expect(server.jobSignatureWasValid)
        #expect(server.idempotencyKey == clientJobID.uuidString.lowercased())
        #expect(server.submittedDeviceTools.contains("list_exercise_names"))
        #expect(server.submittedDeviceTools.contains("record_workout"))
        #expect(server.submittedRemoteTools.isEmpty)
    }
}

private final class MockRemoteAgentServer: @unchecked Sendable {
    private let now = Date()
    private var publicKey: SecKey?
    private(set) var registrationSignatureWasValid = false
    private(set) var jobSignatureWasValid = false
    private(set) var idempotencyKey: String?
    private(set) var submittedDeviceTools: [String] = []
    private(set) var submittedRemoteTools: [String] = []
    func response(to request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let path = request.url?.path ?? ""
        let responseBody: [String: Any]
        let status: Int
        switch (request.httpMethod, path) {
        case ("POST", "/v1/device-registration-challenges"):
            status = 201
            responseBody = [
                "protocolVersion": 1,
                "challengeID": "challenge-id",
                "challenge": "challenge-value",
                "expiresAt": iso(now.addingTimeInterval(300))
            ]
        case ("POST", "/v1/devices"):
            status = 201
            let body = try bodyObject(request)
            let pem = try requiredString(body["publicKeyPem"])
            publicKey = try makePublicKey(pem: pem)
            let canonical = try [
                "challenge-value",
                requiredString(body["deviceID"]),
                "top.hedon.soma",
                "1",
                String(requiredInt(body["timestamp"]))
            ].joined(separator: "\n")
            registrationSignatureWasValid = try verify(
                requiredString(body["signature"]),
                message: canonical
            )
            responseBody = [
                "protocolVersion": 1,
                "accessToken": "access-token",
                "rotationToken": "rotation-token",
                "expiresAt": iso(now.addingTimeInterval(900))
            ]
        case ("POST", "/v1/agent-jobs"):
            status = 201
            let body = try bodyObject(request)
            submittedDeviceTools = body["allowedDeviceTools"] as? [String] ?? []
            submittedRemoteTools = body["allowedRemoteTools"] as? [String] ?? []
            idempotencyKey = request.value(
                forHTTPHeaderField: "idempotency-key"
            )
            jobSignatureWasValid = verifyRequest(request)
            responseBody = try [
                "protocolVersion": 1,
                "id": UUID().uuidString.lowercased(),
                "clientJobID": requiredString(body["clientJobID"]),
                "turnID": requiredString(body["turnID"]),
                "sessionID": requiredString(body["sessionID"]),
                "state": "queued",
                "lastSequence": 1,
                "createdAt": iso(now),
                "updatedAt": iso(now)
            ]
        default:
            status = 404
            responseBody = [
                "protocolVersion": 1,
                "error": [
                    "code": "not_found",
                    "message": "not found"
                ]
            ]
        }
        let response = try #require(HTTPURLResponse(
            url: request.url ?? URL(string: "https://soma.test")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["content-type": "application/json"]
        ))
        return try (
            response,
            JSONSerialization.data(withJSONObject: responseBody)
        )
    }

    private func verifyRequest(_ request: URLRequest) -> Bool {
        guard let body = try? requestBody(request),
              let timestamp = request.value(
                  forHTTPHeaderField: "x-soma-timestamp"
              ),
              let nonce = request.value(forHTTPHeaderField: "x-soma-nonce"),
              let digest = request.value(
                  forHTTPHeaderField: "x-soma-body-sha256"
              ),
              let signature = request.value(
                  forHTTPHeaderField: "x-soma-signature"
              ),
              digest == SHA256.hash(data: body).map({
                  String(format: "%02x", $0)
              }).joined()
        else {
            return false
        }
        let path = [
            request.url?.path ?? "",
            request.url?.query.map { "?\($0)" } ?? ""
        ].joined()
        return verify(
            signature,
            message: [
                request.httpMethod ?? "",
                path,
                timestamp,
                nonce,
                digest
            ].joined(separator: "\n")
        )
    }

    private func verify(_ signature: String, message: String) -> Bool {
        guard let publicKey,
              let signatureData = Data(base64Encoded: signature)
        else {
            return false
        }
        return SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            Data(message.utf8) as CFData,
            signatureData as CFData,
            nil
        )
    }

    private func makePublicKey(pem: String) throws -> SecKey {
        let base64 = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let der = try #require(Data(base64Encoded: base64))
        let point = der.dropFirst(26)
        var error: Unmanaged<CFError>?
        let key = SecKeyCreateWithData(
            Data(point) as CFData,
            [
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
                kSecAttrKeySizeInBits as String: 256
            ] as CFDictionary,
            &error
        )
        return try #require(key)
    }

    private func bodyObject(_ request: URLRequest) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(
                with: requestBody(request)
            ) as? [String: Any]
        )
    }

    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw stream.streamError ?? RemoteAgentError.invalidResponse
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }

    private func requiredString(_ value: Any?) throws -> String {
        try #require(value as? String)
    }

    private func requiredInt(_ value: Any?) throws -> Int {
        try #require(value as? Int)
    }

    private func iso(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter.string(from: value)
    }
}

private class MockRemoteURLProtocol: URLProtocol,
    @unchecked Sendable
{
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler?(request)
                ?? {
                    throw RemoteAgentError.invalidResponse
                }()
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
