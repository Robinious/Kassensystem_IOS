import SwiftUI

struct AppRootView: View {
    @StateObject private var store = AppStore()

    @State private var topNoticeMessage: String?
    @State private var topNoticeIsError = false
    @State private var topNoticeVisible = false

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [POSColor.slate950, POSColor.slate900, POSColor.slate850.opacity(0.84)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            content
                .padding(.horizontal, store.route == .tables ? POSSpacing.sm : POSSpacing.xxl)
                .padding(.vertical, store.route == .tables ? POSSpacing.xs : POSSpacing.xl)
                .animation(POSMotion.panel, value: store.route)

            if topNoticeVisible, let message = topNoticeMessage, !message.isEmpty {
                NoticeBanner(message: message, isError: topNoticeIsError)
                    .padding(.top, store.route == .tables ? POSSpacing.xxs : POSSpacing.md)
                    .padding(.horizontal, POSSpacing.lg)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
            }

            if store.route == .tables {
                ConnectionStatusDot(isOnline: store.isOnline)
                    .padding(.top, 1)
                    .padding(.leading, 8)
                    .offset(x: 6, y: -11)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .preferredColorScheme(store.isDarkMode ? .dark : .light)
        .onAppear {
            store.start()
        }
        .onDisappear {
            store.stop()
        }
        .onChange(of: store.noticeMessage) { _, next in
            showNotice(next)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.route {
        case .pairing:
            PairingView(store: store)
                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .leading)), removal: .opacity))
        case .login:
            LoginView(store: store)
                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity))
        case .tables:
            TablesScreenView(store: store)
                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity))
        }
    }

    private func showNotice(_ message: String?) {
        let normalized = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        let lowered = normalized.lowercased()
        topNoticeIsError = lowered.contains("fehl") ||
            lowered.contains("ungültig") ||
            lowered.contains("error") ||
            lowered.contains("gesperrt") ||
            lowered.contains("ausverkauft")

        withAnimation(POSMotion.overlay) {
            topNoticeMessage = normalized
            topNoticeVisible = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(POSMotion.feedback) {
                    topNoticeVisible = false
                }
            }

            try? await Task.sleep(nanoseconds: 180_000_000)
            await MainActor.run {
                if store.noticeMessage?.trimmingCharacters(in: .whitespacesAndNewlines) == normalized {
                    store.clearNotice()
                }
                if topNoticeMessage == normalized {
                    topNoticeMessage = nil
                }
            }
        }
    }
}

private struct ConnectionStatusDot: View {
    let isOnline: Bool
    @State private var pulse = false

    private var dotColor: Color {
        isOnline ? POSColor.indigo500 : POSColor.red500
    }

    private var pulseAnimation: Animation {
        if isOnline {
            return .easeInOut(duration: 1.45).repeatForever(autoreverses: true)
        }
        return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(dotColor)
                .frame(width: 16, height: 16)
                .scaleEffect(pulse ? (isOnline ? 1.56 : 1.9) : 1.18)
                .opacity(pulse ? (isOnline ? 0.06 : 0.09) : (isOnline ? 0.18 : 0.3))

            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .scaleEffect(pulse ? (isOnline ? 1.08 : 1.18) : 1.0)
                .shadow(color: dotColor.opacity(isOnline ? 0.5 : 0.62), radius: isOnline ? 6 : 8, y: 1)
        }
        .onAppear(perform: restartPulse)
        .onChange(of: isOnline) { _, _ in
            restartPulse()
        }
    }

    private func restartPulse() {
        pulse = false
        DispatchQueue.main.async {
            withAnimation(pulseAnimation) {
                pulse = true
            }
        }
    }
}

private struct NoticeBanner: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: POSSpacing.md) {
            Circle()
                .fill(isError ? POSColor.red500 : POSColor.indigo500)
                .frame(width: 8, height: 8)
                .shadow(
                    color: (isError ? POSColor.red500 : POSColor.indigo500).opacity(0.45),
                    radius: 3,
                    y: 1
                )

            Text(message)
                .font(POSTypography.labelLarge)
                .foregroundStyle(POSColor.slate050)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, POSSpacing.xl)
        .padding(.vertical, POSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: POSRadius.notice)
                .fill(Color.adaptive(darkHex: 0x202C3F, lightHex: 0xF8FAFF, darkAlpha: 0.94, lightAlpha: 0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: POSRadius.notice)
                        .stroke(
                            Color.adaptive(
                                darkHex: isError ? 0xEF4444 : 0x6B4DFF,
                                lightHex: isError ? 0xE05656 : 0x8FA3C5,
                                darkAlpha: isError ? 0.55 : 0.38,
                                lightAlpha: isError ? 0.48 : 0.58
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
    }
}
