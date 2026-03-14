import SwiftUI

struct SettingsSheetView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: POSSpacing.lg) {
                    Text("Erscheinungsbild")
                        .font(POSTypography.titleMedium)
                        .foregroundStyle(POSColor.slate050)

                    HStack(spacing: POSSpacing.sm) {
                        Button("Dunkel") {
                            store.setDarkMode(true)
                        }
                        .buttonStyle(ThemeButtonStyle(selected: store.isDarkMode))

                        Button("Hell") {
                            store.setDarkMode(false)
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
            }
            .background(POSColor.slate950.ignoresSafeArea())
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(store.isDarkMode ? .dark : .light)
    }

    private func settingsToggle(title: String, subtitle: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
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
                onChange(next)
            }))
            .labelsHidden()
            .tint(POSColor.indigo500)
        }
        .padding(POSSpacing.lg)
        .background(POSColor.slate800.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.notice))
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
