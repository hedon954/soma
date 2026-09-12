import Foundation

extension ConversationProcessingService {
    func appendRemoteCanonicalFrames(
        for event: RemoteAgentEvent,
        to job: AgentJob
    ) {
        guard var snapshot = job.contextSnapshot,
              var frames = snapshot.remoteCanonicalFrames
        else { return }

        if event.kind == "model", event.phase == "completed",
           let calls = remoteToolCalls(event)
        {
            frames.append(AgentModelMessage(
                role: .assistant,
                text: event.payload["assistantText"]?.stringValue ?? "",
                toolCalls: calls
            ))
        } else if event.kind == "tool",
                  ["completed", "failed"].contains(event.phase),
                  let callID = event.payload["toolCallID"]?.stringValue,
                  let result = event.payload["result"]
        {
            frames.append(AgentModelMessage(
                role: .tool,
                text: canonicalRemoteJSON(result),
                toolCallID: callID
            ))
        } else {
            return
        }
        snapshot.remoteCanonicalFrames = frames
        job.contextSnapshot = snapshot
    }

    func completeRemoteCanonicalTurn(
        job: AgentJob,
        userMessage: CoachMessage,
        answer: String
    ) {
        guard var snapshot = job.contextSnapshot,
              var frames = snapshot.remoteCanonicalFrames,
              AgentCanonicalTurn.hasCompleteToolBatches(frames)
        else { return }
        frames.append(AgentModelMessage(role: .assistant, text: answer))
        snapshot.canonicalTurn = AgentCanonicalTurn(
            sourceFingerprint: AgentCanonicalTurn.fingerprint(
                user: userMessage.text,
                assistant: answer,
                correction: nil
            ),
            messages: frames
        )
        snapshot.remoteCanonicalFrames = nil
        job.contextSnapshot = snapshot
    }

    private func remoteToolCalls(_ event: RemoteAgentEvent) -> [AgentModelToolCall]? {
        guard case let .array(values)? = event.payload["toolCalls"] else { return nil }
        let calls = values.compactMap { value -> AgentModelToolCall? in
            guard case let .object(raw) = value,
                  let id = raw["id"]?.stringValue,
                  case let .object(function)? = raw["function"],
                  let name = function["name"]?.stringValue,
                  let arguments = function["arguments"]?.stringValue
            else { return nil }
            return AgentModelToolCall(id: id, name: name, arguments: arguments)
        }
        return calls.count == values.count && !calls.isEmpty ? calls : nil
    }

    private func canonicalRemoteJSON(_ value: RemoteJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(data: (try? encoder.encode(value)) ?? Data(), encoding: .utf8) ?? "null"
    }
}
