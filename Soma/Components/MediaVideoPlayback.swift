import AVKit
import Observation
import SwiftUI

@MainActor
@Observable
final class MediaVideoPlayback {
    private(set) var player: AVPlayer?
    private(set) var errorMessage: String?
    private var generation = UUID()
    private var statusObservation: NSKeyValueObservation?
    private var resumesOnForeground = false

    func open(url: URL?) async {
        close()
        let token = generation
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "视频文件不可用，请重新添加视频。"
            return
        }
        do {
            let asset = AVURLAsset(url: url)
            guard try await asset.load(.isPlayable) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try Task.checkCancellation()
            guard generation == token else { return }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            self.player = player
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor [weak self] in
                    guard let self, generation == token else { return }
                    errorMessage = "视频无法播放，请重试或重新添加视频。"
                }
            }
            // AVPlayer 在 readyToPlay 前接收播放意图，准备完成后自行开始。
            player.play()
        } catch is CancellationError {
            return
        } catch {
            guard generation == token else { return }
            errorMessage = "视频无法播放，请重试或重新添加视频。"
        }
    }

    func sceneChanged(_ phase: ScenePhase) {
        if phase == .active {
            if resumesOnForeground {
                try? AVAudioSession.sharedInstance().setActive(true)
                player?.play()
                resumesOnForeground = false
            }
        } else {
            resumesOnForeground = resumesOnForeground || (player?.rate ?? 0) > 0
            player?.pause()
        }
    }

    func close() {
        generation = UUID()
        statusObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        errorMessage = nil
        resumesOnForeground = false
    }
}

struct MediaViewerVideo: View {
    @Environment(\.scenePhase) private var scenePhase
    let path: String
    let isSelected: Bool
    @State private var playback = MediaVideoPlayback()
    @State private var retryID = UUID()

    var body: some View {
        Group {
            if let error = playback.errorMessage {
                ContentUnavailableView {
                    Label("视频无法播放", systemImage: "video.slash")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { retryID = UUID() }
                }
                .foregroundStyle(.white)
            } else if let player = playback.player {
                VideoPlayer(player: player)
                    .accessibilityLabel("视频播放器")
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: "\(path)-\(isSelected)-\(retryID)") {
            guard isSelected else {
                playback.close()
                return
            }
            await playback.open(url: MediaStore.url(at: path))
            playback.sceneChanged(scenePhase)
        }
        .onChange(of: scenePhase) { _, phase in playback.sceneChanged(phase) }
        .onDisappear { playback.close() }
    }
}
