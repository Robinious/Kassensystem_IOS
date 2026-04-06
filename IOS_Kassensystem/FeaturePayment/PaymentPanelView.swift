import SwiftUI

struct PaymentPanelView: View {
    let isOnline: Bool
    let isBusy: Bool
    let hasUnsubmittedLines: Bool
    let openGross: Double
    @Binding var selectedMethod: PaymentMethod
    let canTriggerPayment: Bool
    let onPaymentTap: () -> Void
    @Namespace private var paymentMethodNamespace

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
                        withAnimation(POSMotion.select) {
                            selectedMethod = method
                        }
                        POSHaptics.selection()
                    }
                    .buttonStyle(PaymentMethodButtonStyle(selected: method == selectedMethod, namespace: paymentMethodNamespace))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 48)
            .animation(POSMotion.select, value: selectedMethod)

            Button("Zahlung") {
                POSHaptics.medium()
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
        return "Zahlung wird direkt über Core gebucht."
    }
}

private struct PaymentMethodButtonStyle: ButtonStyle {
    let selected: Bool
    let namespace: Namespace.ID

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            if selected {
                RoundedRectangle(cornerRadius: POSRadius.small, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                POSColor.indigo500.opacity(0.82),
                                POSColor.indigo400.opacity(0.86)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .matchedGeometryEffect(id: "payment-method-pill", in: namespace)
                    .overlay(
                        RoundedRectangle(cornerRadius: POSRadius.small, style: .continuous)
                            .stroke(POSColor.slate050.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: POSColor.indigo500.opacity(0.18), radius: 5, y: 2)
            }

            configuration.label
                .font(POSTypography.labelLarge)
                .foregroundStyle(selected ? Color.white : POSColor.slate050)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(selected ? Color.clear : POSColor.slate800.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.small)
                .stroke(selected ? Color.clear : POSColor.slate700.opacity(0.8), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
        .scaleEffect(configuration.isPressed ? 0.992 : 1)
        .opacity(configuration.isPressed ? 0.95 : 1)
    }
}
