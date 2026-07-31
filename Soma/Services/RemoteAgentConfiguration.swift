import Foundation
import Observation

enum RemoteAgentPreference {
    static let enabledKey = "agent.remote.enabled"
    static let baseURLKey = "agent.remote.baseURL"
    static let pendingRevocationKey = "agent.remote.pendingRevocation"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey) && baseURL(defaults: defaults) != nil
    }

    static func baseURL(defaults: UserDefaults = .standard) -> URL? {
        let configured = defaults.string(forKey: baseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundled = Bundle.main.object(
            forInfoDictionaryKey: "SOMARemoteAgentBaseURL"
        ) as? String
        guard let rawValue = [configured, bundled]
            .compactMap({ $0 })
            .first(where: { !$0.isEmpty }),
            let url = URL(string: rawValue),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || Self.isDevelopmentLoopback(url)
        else {
            return nil
        }
        return url
    }

    static func setBaseURL(
        _ rawValue: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(
            rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: baseURLKey
        )
    }

    private static func isDevelopmentLoopback(_ url: URL) -> Bool {
        #if DEBUG
            url.scheme?.lowercased() == "http"
                && ["127.0.0.1", "localhost"].contains(url.host?.lowercased() ?? "")
        #else
            false
        #endif
    }
}

@MainActor
@Observable
final class RemoteAgentStatus {
    private(set) var isWorking = false
    private(set) var message: String?

    func revokeAndDisable() async {
        guard let baseURL = RemoteAgentPreference.baseURL() else {
            UserDefaults.standard.set(false, forKey: RemoteAgentPreference.enabledKey)
            RemoteDeviceIdentity.shared.clearCredentials()
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await RemoteAgentClient(baseURL: baseURL).deleteDeviceData()
            message = "服务器临时数据与设备凭据已撤销。"
            UserDefaults.standard.set(
                false,
                forKey: RemoteAgentPreference.pendingRevocationKey
            )
            RemoteDeviceIdentity.shared.clearCredentials()
        } catch {
            message = "服务器暂时无法连接；本机已关闭后台持续处理，可稍后再次清除远端数据。"
            UserDefaults.standard.set(
                true,
                forKey: RemoteAgentPreference.pendingRevocationKey
            )
        }
        UserDefaults.standard.set(false, forKey: RemoteAgentPreference.enabledKey)
    }
}

enum RemoteAgentRevocationService {
    static func retryIfNeeded() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(
            forKey: RemoteAgentPreference.pendingRevocationKey
        ),
            let baseURL = RemoteAgentPreference.baseURL()
        else {
            return
        }
        do {
            try await RemoteAgentClient(baseURL: baseURL).deleteDeviceData()
            defaults.set(
                false,
                forKey: RemoteAgentPreference.pendingRevocationKey
            )
            RemoteDeviceIdentity.shared.clearCredentials()
        } catch {
            // Fail closed: remote execution remains disabled and a later
            // foreground entry retries with the still-valid device identity.
        }
    }
}
