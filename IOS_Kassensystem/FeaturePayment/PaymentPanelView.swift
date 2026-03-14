import SwiftUI

struct PaymentPanelView: View {
    let isOnline: Bool
    let isBusy: Bool
    let hasUnsubmittedLines: Bool
    let openGross: Double
    @Binding var selectedMethod: PaymentMethod
    let canTriggerPayment: Bool
    let onPaymentTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: POSSpacing.md) {
            Text("Zahlung")
                .font(POSTypography.titleMedium)
                .foregroundStyle(POSColor.slate050)

            Text(infoText)
                .font(POSTypography.labelMedium)
                .foregroundStyle((!isOnline || hasUnsubmittedLines) ? POSColor.red500 : POSColor.slate300)

            VStack(alignment: .leading, spacing: POSSpacing.xs) {
                Text("OFFEN")
                    .font(POSTypography.labelLarge)
                    .foregroundStyle(POSColor.slate300)
                Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), openGross))
                    .font(POSTypography.headlineLarge)
                    .foregroundStyle(POSColor.slate050)
            }
            .padding(POSSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(POSColor.slate800.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: POSRadius.innerCard))

            HStack(spacing: POSSpacing.sm) {
                ForEach(PaymentMethod.allCases) { method in
                    Button(method.rawValue) {
                        selectedMethod = method
                    }
                    .buttonStyle(PaymentMethodButtonStyle(selected: method == selectedMethod))
                }
            }

            Button("Zahlung") {
                onPaymentTap()
            }
            .buttonStyle(POSPrimaryButtonStyle())
            .disabled(!canTriggerPayment || isBusy)

            Spacer(minLength: 0)
        }
        .padding(POSSpacing.md)
        .background(POSColor.slate900.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.card)
                .stroke(POSColor.slate700.opacity(0.3), lineWidth: 1)
        )
    }

    private var infoText: String {
        if !isOnline {
            return "Offline: Zahlung ist blockiert."
        }
        if hasUnsubmittedLines {
            return "Offene unbestellte Positionen vorhanden. Bitte zuerst bestellen."
        }
        return "Zahlung wird direkt ueber Core gebucht."
    }
}

private struct PaymentMethodButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(POSTypography.labelLarge)
            .foregroundStyle(POSColor.slate050)
            .padding(.vertical, POSSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(selected ? POSColor.indigo500.opacity(0.22) : POSColor.slate800.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: POSRadius.small)
                    .stroke(selected ? POSColor.indigo500 : POSColor.slate700.opacity(0.8), lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
