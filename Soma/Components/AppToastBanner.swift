import SwiftUI

struct AppToastBanner: View {
    let message: String
    var systemImage: String = "exclamationmark.triangle.fill"
    var tint: Color = .orange

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .accessibilityAddTraits(.isStaticText)
    }
}

struct AppToastModifier: ViewModifier {
    @Binding var message: String?
    var duration: TimeInterval = 4
    var systemImage: String = "exclamationmark.triangle.fill"
    var tint: Color = .orange

    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                AppToastBanner(
                    message: message,
                    systemImage: systemImage,
                    tint: tint
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture {
                    clear()
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: message)
        .onChange(of: message) { _, newValue in
            dismissTask?.cancel()
            guard newValue != nil else { return }
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    clear()
                }
            }
        }
    }

    private func clear() {
        dismissTask?.cancel()
        dismissTask = nil
        message = nil
    }
}

extension View {
    func appToast(
        _ message: Binding<String?>,
        duration: TimeInterval = 4,
        systemImage: String = "exclamationmark.triangle.fill",
        tint: Color = .orange
    ) -> some View {
        modifier(AppToastModifier(
            message: message,
            duration: duration,
            systemImage: systemImage,
            tint: tint
        ))
    }
}
