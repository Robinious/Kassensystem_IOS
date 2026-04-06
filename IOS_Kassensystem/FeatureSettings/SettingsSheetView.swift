import SwiftUI

struct SettingsSheetView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var animateIn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: POSSpacing.lg) {
                        Text("Erscheinungsbild")
                            .font(POSTypography.titleMedium)
                            .foregroundStyle(POSColor.slate050)

                        HStack(spacing: POSSpacing.sm) {
                            Button("Dunkel") {
                                withAnimation(POSMotion.select) {
                                    store.setDarkMode(true)
                                }
                                POSHaptics.selection()
                            }
                            .buttonStyle(ThemeButtonStyle(selected: store.isDarkMode))

                            Button("Hell") {
                                withAnimation(POSMotion.select) {
                                    store.setDarkMode(false)
                                }
                                POSHaptics.selection()
                            }
                            .buttonStyle(ThemeButtonStyle(selected: !store.isDarkMode))
                        }

                        Text("Bestellübersicht")
                            .font(POSTypography.titleMedium)
                            .foregroundStyle(POSColor.slate050)

                        settingsToggle(
                            title: "Mehrwertsteuer auf Artikelkacheln",
                            subtitle: "Blendet MwSt unter dem Preis ein oder aus.",
                            isOn: store.showVatOnProductTiles,
                            onChange: store.setShowVatOnProductTiles
                        )

                        settingsToggle(
                            title: "Voller Artikeltext",
                            subtitle: "Zeigt lange Namen in bis zu 2 Zeilen.",
                            isOn: store.showFullProductText,
                            onChange: store.setShowFullProductText
                        )

                        settingsToggle(
                            title: "Artikelpreis anzeigen",
                            subtitle: "Blendet den Preis auf Kacheln ein oder aus. Aus = kompaktere Kacheln.",
                            isOn: store.showPriceOnProductTiles,
                            onChange: store.setShowPriceOnProductTiles
                        )

                        settingsToggle(
                            title: "Storno-Info-Druck",
                            subtitle: "Steuert, ob bei Storno ein Info-Druck gesendet wird.",
                            isOn: store.printStornoInfoEnabled,
                            onChange: store.setPrintStornoInfoEnabled
                        )
                    }
                    .padding(POSSpacing.xxl)
                    .opacity(animateIn ? 1 : 0.01)
                    .offset(y: animateIn ? 0 : 16)
                }
                footer
                    .padding(.horizontal, POSSpacing.xxl)
                    .padding(.vertical, POSSpacing.lg)
                    .background(POSColor.slate950.opacity(0.9))
            }
            .background(POSColor.slate950.ignoresSafeArea())
            .navigationTitle("Einstellungen")
        }
        .preferredColorScheme(store.isDarkMode ? .dark : .light)
        .onAppear {
            withAnimation(POSMotion.panel) {
                animateIn = true
            }
        }
    }

    private var footer: some View {
        HStack(spacing: POSSpacing.md) {
            currentUserBadge

            Spacer()

            Button("Schließen") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .tint(POSColor.slate700)
            .foregroundStyle(POSColor.slate050)
        }
    }

    private var currentUserBadge: some View {
        let normalized = {
            let displayName = store.activeUserDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let displayName, !displayName.isEmpty {
                return displayName
            }
            let userId = store.activeUserId?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let userId, !userId.isEmpty else { return "Unbekannt" }
            return userId
        }()
        return HStack(spacing: POSSpacing.xs) {
            Image(systemName: "person.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(normalized)
                .font(POSTypography.labelMedium)
                .lineLimit(1)
        }
        .foregroundStyle(POSColor.slate050)
        .padding(.horizontal, POSSpacing.md)
        .padding(.vertical, POSSpacing.xs)
        .background(POSColor.slate800.opacity(0.82))
        .overlay(
            Capsule()
                .stroke(POSColor.slate700.opacity(0.55), lineWidth: 1)
        )
        .clipShape(Capsule())
        .accessibilityLabel("Angemeldeter Benutzer \(normalized)")
    }

    private func settingsToggle(title: String, subtitle: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        SettingsToggleRow(
            title: title,
            subtitle: subtitle,
            isOn: isOn,
            onChange: onChange
        )
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Bool
    let onChange: (Bool) -> Void
    @State private var flash = false

    var body: some View {
        HStack(spacing: POSSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(POSTypography.bodyLarge)
                    .foregroundStyle(POSColor.slate050)
                Text(subtitle)
                    .font(POSTypography.labelMedium)
                    .foregroundStyle(POSColor.slate300)
            }
            Spacer()
            Toggle("", isOn: Binding(get: {
                isOn
            }, set: { next in
                withAnimation(POSMotion.feedback) {
                    onChange(next)
                }
                POSHaptics.selection()
                withAnimation(POSMotion.feedback) {
                    flash = true
                }
                Task {
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    await MainActor.run {
                        withAnimation(POSMotion.feedback) {
                            flash = false
                        }
                    }
                }
            }))
            .labelsHidden()
            .tint(POSColor.indigo500)
        }
        .padding(POSSpacing.lg)
        .background(POSColor.slate800.opacity(0.45))
        .overlay {
            if flash {
                RoundedRectangle(cornerRadius: POSRadius.notice)
                    .fill(POSColor.slate050.opacity(0.08))
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.notice))
        .animation(POSMotion.feedback, value: isOn)
    }
}

private struct ThemeButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(POSTypography.labelLarge)
            .foregroundStyle(selected ? Color.white : POSColor.slate050)
            .padding(.vertical, POSSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(selected ? POSColor.indigo500 : POSColor.slate800)
            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
