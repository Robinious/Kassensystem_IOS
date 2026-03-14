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

            if topNoticeVisible, let message = topNoticeMessage, !message.isEmpty {
                NoticeBanner(message: message, isError: topNoticeIsError)
                    .padding(.top, store.route == .tables ? POSSpacing.xxs : POSSpacing.md)
                    .padding(.horizontal, POSSpacing.lg)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if store.route == .tables {
                Circle()
                    .fill(store.isOnline ? POSColor.indigo500 : POSColor.red500)
                    .frame(width: 10, height: 10)
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
        case .login:
            LoginView(store: store)
        case .tables:
            TablesScreenView(store: store)
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

        withAnimation(POSMotion.quick) {
            topNoticeMessage = normalized
            topNoticeVisible = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(POSMotion.quick) {
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

private struct NoticeBanner: View {
    let message: String
    let isError: Bool

    var body: some View {
        Text(message)
            .font(POSTypography.labelLarge)
            .foregroundStyle(isError ? Color(hex: 0xFFE2DE) : POSColor.indigo500)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, POSSpacing.xl)
            .padding(.vertical, POSSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: POSRadius.notice)
                    .fill(isError ? POSColor.red500.opacity(0.22) : POSColor.indigo500.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: POSRadius.notice)
                            .stroke(isError ? POSColor.red500.opacity(0.55) : POSColor.indigo500.opacity(0.38), lineWidth: 1)
                    )
            )
    }
}
