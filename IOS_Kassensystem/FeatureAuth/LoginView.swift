import SwiftUI

struct LoginView: View {
    @ObservedObject var store: AppStore

    @State private var userId: String = ""
    @State private var pin: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: POSSpacing.lg) {
                statusHeader

                VStack(alignment: .leading, spacing: POSSpacing.md) {
                    Text("Service Login")
                        .font(POSTypography.titleLarge)
                        .foregroundStyle(POSColor.slate050)

                    Text("Anmeldung mit Benutzer-ID oder Loginname und 4-stelliger PIN.")
                        .font(POSTypography.bodyMedium)
                        .foregroundStyle(POSColor.slate300)

                    outlinedField(title: "Benutzer-ID / Loginname") {
                        TextField("admin", text: $userId)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .foregroundStyle(POSColor.slate050)
                    }

                    outlinedField(title: "PIN") {
                        SecureField("1234", text: $pin)
                            .keyboardType(.numberPad)
                            .foregroundStyle(POSColor.slate050)
                            .onChange(of: pin) { _, next in
                                pin = String(next.filter { $0.isNumber }.prefix(4))
                            }
                    }

                    HStack(spacing: POSSpacing.sm) {
                        Button(store.isBusy ? "Prüfe..." : "Anmelden") {
                            store.login(userId: userId, pin: pin)
                        }
                        .buttonStyle(POSPrimaryButtonStyle())
                        .disabled(store.isBusy || userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pin.count != 4)
                    }
                }
                .padding(POSSpacing.xxl)
                .frame(maxWidth: 640, alignment: .leading)
                .background(POSColor.slate900.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: POSRadius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: POSRadius.card)
                        .stroke(POSColor.slate700.opacity(0.3), lineWidth: 1)
                )

                Spacer(minLength: 0)
            }
            .padding(.vertical, POSSpacing.lg)
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
        .frame(maxWidth: 640)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: POSRadius.innerCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.innerCard, style: .continuous)
                .stroke(POSColor.slate700.opacity(0.28), lineWidth: 1)
        )
    }

    private func outlinedField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: POSSpacing.xxs) {
            Text(title)
                .font(POSTypography.labelMedium)
                .foregroundStyle(POSColor.slate300)
            content()
                .padding(.horizontal, POSSpacing.md)
                .padding(.vertical, POSSpacing.sm)
                .frame(maxWidth: .infinity)
                .background(POSColor.slate800.opacity(0.34))
                .overlay(
                    RoundedRectangle(cornerRadius: POSRadius.small)
                        .stroke(POSColor.slate700.opacity(0.75), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
        }
    }
}
