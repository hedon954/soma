import Foundation
import Network

protocol FeedbackSMTPTransport: Sendable {
    func send(
        message: Data,
        sender: String,
        recipient: String,
        authorizationCode: String
    ) async throws
}

struct QQSMTPTransport: FeedbackSMTPTransport {
    private static let host = NWEndpoint.Host("smtp.qq.com")
    private static let port = NWEndpoint.Port(rawValue: 465)!

    func send(
        message: Data,
        sender: String,
        recipient: String,
        authorizationCode: String
    ) async throws {
        let session = SMTPConnection(
            host: Self.host,
            port: Self.port
        )
        do {
            try await session.start()
            try await session.expect([220])
            try await session.command("EHLO soma.local", expecting: [250])
            try await session.command("AUTH LOGIN", expecting: [334])
            try await session.command(
                Data(sender.utf8).base64EncodedString(),
                expecting: [334]
            )
            try await session.command(
                Data(authorizationCode.utf8).base64EncodedString(),
                expecting: [235]
            )
            try await session.command(
                "MAIL FROM:<\(sender)>",
                expecting: [250]
            )
            try await session.command(
                "RCPT TO:<\(recipient)>",
                expecting: [250, 251]
            )
            try await session.command("DATA", expecting: [354])
            try await session.sendMessage(message)
            try await session.expect([250])
            try await session.command("QUIT", expecting: [221])
            session.close()
        } catch is CancellationError {
            session.close()
            throw CancellationError()
        } catch {
            session.close()
            throw FeedbackSubmissionError.deliveryUnavailable
        }
    }
}

private final class SMTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "top.hedon.soma.feedback-smtp")

    init(host: NWEndpoint.Host, port: NWEndpoint.Port) {
        connection = NWConnection(host: host, port: port, using: .tls)
    }

    func start() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let continuationGate = ContinuationGate()
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard continuationGate.claim() else { return }
                        continuation.resume()
                    case let .failed(error):
                        guard continuationGate.claim() else { return }
                        continuation.resume(throwing: error)
                    case .cancelled:
                        guard continuationGate.claim() else { return }
                        continuation.resume(throwing: CancellationError())
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    func command(_ value: String, expecting codes: Set<Int>) async throws {
        try await send(Data("\(value)\r\n".utf8))
        try await expect(codes)
    }

    func expect(_ codes: Set<Int>) async throws {
        let response = try await receiveResponse()
        guard codes.contains(response.code) else {
            throw FeedbackSubmissionError.deliveryUnavailable
        }
    }

    func sendMessage(_ message: Data) async throws {
        guard var text = String(bytes: message, encoding: .utf8) else {
            throw FeedbackSubmissionError.deliveryUnavailable
        }
        text = text.replacingOccurrences(of: "\r\n.", with: "\r\n..")
        if !text.hasSuffix("\r\n") {
            text += "\r\n"
        }
        try await send(Data("\(text).\r\n".utf8))
    }

    func close() {
        connection.cancel()
    }

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    private func receiveResponse() async throws -> SMTPResponse {
        var collected = Data()
        while collected.count <= 64 * 1024 {
            try await collected.append(receiveChunk())
            if let response = SMTPResponse(data: collected) {
                return response
            }
        }
        throw FeedbackSubmissionError.deliveryUnavailable
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: 16 * 1024
            ) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(
                        throwing: FeedbackSubmissionError.deliveryUnavailable
                    )
                }
            }
        }
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

private struct SMTPResponse {
    let code: Int

    init?(data: Data) {
        guard let text = String(bytes: data, encoding: .utf8) else {
            return nil
        }
        for line in text.components(separatedBy: "\r\n") where line.count >= 4 {
            let codeEnd = line.index(line.startIndex, offsetBy: 3)
            guard let code = Int(line[..<codeEnd]) else { continue }
            guard line[codeEnd] == " " else { continue }
            self.code = code
            return
        }
        return nil
    }
}
