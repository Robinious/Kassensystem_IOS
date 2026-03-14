import SwiftUI

struct PairingView: View {
    @ObservedObject var store: AppStore

    @State private var hostInput: String = ""
    @State private var portInput: String = ""
    @State private var pairCodeInput: String = ""
    @State private var qrPayloadInput: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: POSSpacing.lg) {
                statusHeader

                card {
                    VStack(alignment: .leading, spacing: POSSpacing.md) {
                        Text("Gerät verbinden")
                            .font(POSTypography.titleLarge)
                            .foregroundStyle(POSColor.slate050)

                        Text("Kopple das Bediengerät per QR oder manuell mit der Hauptkasse.")
                            .font(POSTypography.bodyMedium)
                            .foregroundStyle(POSColor.slate300)

                        HStack(spacing: POSSpacing.sm) {
                            PairInfoCard(
                                title: "QR Pairing",
                                value: store.pairCode ?? "Noch kein Code",
                                subtitle: "Gültig: \(store.pairCodeValidUntil ?? "-")"
                            )

                            PairInfoCard(
                                title: "Gerät",
                                value: store.pairedDeviceLabel ?? "Nicht gekoppelt",
                                subtitle: "\(store.connectedDevices) aktive Verbindung(en)"
                            )
                        }

                        fieldset(title: "Pairing-Code aus Hauptkasse") {
                            TextField("N4JZU2XA", text: $pairCodeInput)
                                .textInputAutocapitalization(.characters)
                                .disableAutocorrection(true)
                                .foregroundStyle(POSColor.slate050)
                                .onChange(of: pairCodeInput) { _, next in
                                    let normalized = next.uppercased().filter { $0.isLetter || $0.isNumber }
                                    pairCodeInput = String(normalized.prefix(12))
                                    store.setPairCodeInput(pairCodeInput)
                                }
                        }

                        HStack(spacing: POSSpacing.sm) {
                            Button("QR scannen") {
                                if !qrPayloadInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    store.scanAndPairFromQrPayload(qrPayloadInput)
                                } else {
                                    noticeHint("QR-Scanner folgt. Nutze bis dahin QR Payload oder Code.")
                                }
                            }
                            .buttonStyle(POSPrimaryButtonStyle())
                            .disabled(store.isBusy)

                            Button("Koppeln") {
                                store.pairDevice(pairCodeInput)
                            }
                            .buttonStyle(POSSecondaryButtonStyle())
                            .disabled(store.isBusy || pairCodeInput.isEmpty)
                        }

                        Button("QR erzeugen (optional)") {
                            store.generatePairCode()
                        }
                        .buttonStyle(POSSecondaryButtonStyle())
                        .disabled(store.isBusy)

                        VStack(alignment: .leading, spacing: POSSpacing.xs) {
                            Text("QR Payload (optional, von Scanner einfügen)")
                                .font(POSTypography.labelMedium)
                                .foregroundStyle(POSColor.slate300)

                            TextField("{\"protocol\":\"kasse-core-pairing.v1\", ...}", text: $qrPayloadInput, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(POSSpacing.md)
                                .background(POSColor.slate800.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))

                            Button("QR Payload übernehmen") {
                                store.scanAndPairFromQrPayload(qrPayloadInput)
                            }
                            .buttonStyle(POSSecondaryButtonStyle())
                            .disabled(store.isBusy || qrPayloadInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                Text("Host Verbindung")
                    .font(POSTypography.titleMedium)
                    .foregroundStyle(POSColor.slate050)

                card {
                    VStack(alignment: .leading, spacing: POSSpacing.sm) {
                        fieldset(title: "Host") {
                            TextField("192.168.1.151", text: $hostInput)
                                .foregroundStyle(POSColor.slate050)
                        }

                        fieldset(title: "Port") {
                            TextField("8787", text: $portInput)
                                .keyboardType(.numberPad)
                                .foregroundStyle(POSColor.slate050)
                                .onChange(of: portInput) { _, next in
                                    portInput = String(next.filter { $0.isNumber }.prefix(5))
                                }
                        }

                        Button("Host übernehmen") {
                            store.applyHostSettings(host: hostInput, portText: portInput)
                        }
                        .buttonStyle(POSSecondaryButtonStyle())
                        .disabled(store.isBusy)

                        Text("Aktiv: \(store.hostAddress):\(store.hostPort)")
                            .font(POSTypography.bodyMedium)
                            .foregroundStyle(POSColor.slate300)
                        Text("Simulator: falls nötig Host vom Kassensystem verwenden (nicht localhost innerhalb externer Umgebungen).")
                            .font(POSTypography.labelMedium)
                            .foregroundStyle(POSColor.slate300)
                    }
                }
            }
            .padding(.vertical, POSSpacing.lg)
        }
        .onAppear {
            hostInput = store.hostAddress
            portInput = String(store.hostPort)
            pairCodeInput = store.pairCodeInput
        }
    }

    private var statusHeader: some View {
        HStack {
            Text("Kassensystem Mobile")
                .font(POSTypography.titleMedium)
                .foregroundStyle(POSColor.slate050)
            Spacer()
            Text(store.isOnline ? "Online" : "Offline")
                .font(POSTypography.labelLarge)
                .foregroundStyle(store.isOnline ? POSColor.slate050 : Color.white)
                .padding(.horizontal, POSSpacing.lg)
                .padding(.vertical, POSSpacing.xs)
                .background(store.isOnline ? POSColor.slate800.opacity(0.7) : POSColor.red500.opacity(0.78))
                .clipShape(Capsule())
        }
        .padding(POSSpacing.md)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: POSRadius.innerCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.innerCard, style: .continuous)
                .stroke(POSColor.slate700.opacity(0.28), lineWidth: 1)
        )
    }

    private func fieldset<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: POSSpacing.xxs) {
            Text(title)
                .font(POSTypography.labelMedium)
                .foregroundStyle(POSColor.slate300)
            content()
                .padding(.horizontal, POSSpacing.md)
                .padding(.vertical, POSSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(POSColor.slate800.opacity(0.34))
                .overlay(
                    RoundedRectangle(cornerRadius: POSRadius.small)
                        .stroke(POSColor.slate700.opacity(0.75), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
        }
    }

    private func noticeHint(_ text: String) {
        store.pushNotice(text)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(POSSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(POSColor.slate900.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: POSRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: POSRadius.card)
                    .stroke(POSColor.slate700.opacity(0.3), lineWidth: 1)
            )
    }
}

private struct PairInfoCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: POSSpacing.sm) {
            HStack(spacing: POSSpacing.xs) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(POSColor.indigo500.opacity(0.24))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: title == "QR Pairing" ? "qrcode" : "iphone")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(POSColor.indigo500)
                    )
                Text(title)
                    .font(POSTypography.labelLarge)
                    .foregroundStyle(POSColor.slate300)
            }

            Text(value)
                .font(POSTypography.titleMedium)
                .foregroundStyle(POSColor.slate050)
                .lineLimit(2)
            Text(subtitle)
                .font(POSTypography.labelLarge)
                .foregroundStyle(POSColor.slate300)
                .lineLimit(2)
        }
        .padding(POSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(POSColor.slate800.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.innerCard))
    }
}

struct POSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(POSTypography.labelLarge)
            .foregroundStyle(.white)
            .padding(.vertical, POSSpacing.sm)
            .padding(.horizontal, POSSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(POSColor.indigo500.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
    }
}

struct POSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(POSTypography.labelLarge)
            .foregroundStyle(POSColor.slate050)
            .padding(.vertical, POSSpacing.sm)
            .padding(.horizontal, POSSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(POSColor.slate800.opacity(configuration.isPressed ? 0.8 : 0.95))
            .overlay(
                RoundedRectangle(cornerRadius: POSRadius.small)
                    .stroke(POSColor.slate700.opacity(0.8), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
    }
}
