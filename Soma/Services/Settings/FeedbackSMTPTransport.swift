import Darwin
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
    fileprivate static let hostname = "smtp.qq.com"
    private static let port = NWEndpoint.Port(rawValue: 465)!

    func send(
        message: Data,
        sender: String,
        recipient: String,
        authorizationCode: String
    ) async throws {
        var lastError = FeedbackSubmissionError.networkUnavailable
        for host in Self.hosts() {
            do {
                try await deliver(
                    message: message,
                    sender: sender,
                    recipient: recipient,
                    authorizationCode: authorizationCode,
                    host: host
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as FeedbackSubmissionError {
                if error == .authenticationFailed {
                    throw error
                }
                lastError = error
            }
        }
        throw lastError
    }

    private func deliver(
        message: Data,
        sender: String,
        recipient: String,
        authorizationCode: String,
        host: NWEndpoint.Host
    ) async throws {
        let session = SMTPConnection(host: host, port: Self.port)
        do {
            try await session.start()
            try await session.expect([220])
            try await session.command("EHLO soma.local", expecting: [250])
            try await authenticate(
                session,
                sender: sender,
                authorizationCode: authorizationCode
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
        } catch let error as FeedbackSubmissionError {
            session.close()
            throw error
        } catch {
            session.close()
            throw FeedbackSubmissionError.networkUnavailable
        }
    }

    private func authenticate(
        _ session: SMTPConnection,
        sender: String,
        authorizationCode: String
    ) async throws {
        do {
            try await session.command("AUTH LOGIN", expecting: [334])
            try await session.command(
                Data(sender.utf8).base64EncodedString(),
                expecting: [334]
            )
            try await session.command(
                Data(authorizationCode.utf8).base64EncodedString(),
                expecting: [235]
            )
        } catch let error as FeedbackSubmissionError
            where error == .authenticationFailed
        {
            let payload = Data("\0\(sender)\0\(authorizationCode)".utf8)
                .base64EncodedString()
            try await session.command(
                "AUTH PLAIN \(payload)",
                expecting: [235]
            )
        }
    }

    private static func hosts() -> [NWEndpoint.Host] {
        ipv4Hosts() + [NWEndpoint.Host("smtp.qq.com")]
    }

    private static func ipv4Hosts() -> [NWEndpoint.Host] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, "465", &hints, &info) == 0, let first = info else {
            return []
        }
        defer { freeaddrinfo(first) }
        var hosts: [NWEndpoint.Host] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let current = cursor {
            if let address = current.pointee.ai_addr {
                var numeric = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    address,
                    socklen_t(current.pointee.ai_addrlen),
                    &numeric,
                    socklen_t(numeric.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    hosts.append(NWEndpoint.Host(String(cString: numeric)))
                }
            }
            cursor = current.pointee.ai_next
        }
        return hosts
    }
}

private final class SMTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "top.hedon.soma.feedback-smtp")

    init(host: NWEndpoint.Host, port: NWEndpoint.Port) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(
            tls.securityProtocolOptions,
            QQSMTPTransport.hostname
        )
        connection = NWConnection(
            host: host,
            port: port,
            using: NWParameters(tls: tls)
        )
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
            throw FeedbackSMTPReply.error(for: response.code)
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

    private func receiveResponse() async throws -> FeedbackSMTPReply {
        var collected = Data()
        while collected.count <= 64 * 1024 {
            try await collected.append(receiveChunk())
            if let response = FeedbackSMTPReply(data: collected) {
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

struct FeedbackSMTPReply: Equatable {
    let code: Int

    init?(data: Data) {
        guard let text = String(bytes: data, encoding: .utf8) else {
            return nil
        }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            guard line.count >= 4, let code = Int(line.prefix(3)) else {
                continue
            }
            let separator = line[line.index(line.startIndex, offsetBy: 3)]
            if separator == " " {
                self.code = code
                return
            }
        }
        return nil
    }

    static func error(for code: Int) -> FeedbackSubmissionError {
        if code == 535 || code == 534 || code == 530 {
            return .authenticationFailed
        }
        if (400 ... 499).contains(code) {
            return .networkUnavailable
        }
        return .deliveryUnavailable
    }
}
