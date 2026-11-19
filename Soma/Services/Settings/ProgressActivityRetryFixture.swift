#if DEBUG
    import Foundation

    @MainActor
    enum ProgressActivityRetryFixture {
        private static let root = FileManager.default.temporaryDirectory.appending(path: "activity-retry-\(UUID())")
        private static let reader = Reader()

        private static var failureSignal: String? {
            guard AppTestRuntime.isRunning else { return nil }
            return ProcessInfo.processInfo.environment["SOMA_UI_ACTIVITY_READ_RETRY"]
        }

        static var isRequested: Bool {
            failureSignal != nil
        }

        private static func makeStore() -> HealthConnectionStore {
            HealthConnectionStore(cacheDirectory: root.appending(path: "cache"), connectionDirectory: root.appending(path: "connection"))
        }

        static func makeCoordinator() -> DailyActivitySyncCoordinator? {
            guard failureSignal != nil else { return nil }
            return DailyActivitySyncCoordinator(reader: reader, cache: makeStore())
        }

        static func listenForFailure() async {
            guard let failureSignal else { return }
            await ProgressHistoryTestFixture.listenForActivitySignal(named: failureSignal) {
                await reader.failRead()
            }
        }

        private actor Reader: DailyActivityReading {
            nonisolated let isAvailable = true
            private var didFail = false
            private var currentStream: AsyncStream<DailyActivityUpdate>.Continuation?

            func requestAuthorization() async throws {}

            func updates(in window: DailyActivityWindow) -> AsyncStream<DailyActivityUpdate> {
                AsyncStream { continuation in
                    if let key = window.days.last {
                        continuation.yield(.values(.steps, [.init(key: key, value: didFail ? 6420 : 6200)], .now))
                    }
                    currentStream = continuation
                }
            }

            func failRead() {
                didFail = true
                currentStream?.yield(.failure(.steps))
            }
        }
    }
#endif
