import SwiftUI

struct SplitPanelView: View {
    let isTablet: Bool
    let splitCandidates: [SplitCandidateUI]
    @Binding var splitSelection: [String: Int]
    @Binding var splitMethod: PaymentMethod
    let splitGross: Double
    let isOnline: Bool
    let isBusy: Bool
    let onSplitTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: POSSpacing.sm) {
            Text("Split-Zahlung")
                .font(POSTypography.titleMedium)
                .foregroundStyle(POSColor.slate050)

            Text("Wähle Positionen und Mengen für Teilzahlung.")
                .font(POSTypography.labelMedium)
                .foregroundStyle(POSColor.slate300)

            if splitCandidates.isEmpty {
                Spacer()
                Text("Keine bestellten Positionen für Split.")
                    .font(POSTypography.bodyMedium)
                    .foregroundStyle(POSColor.slate300)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                if isTablet {
                    HStack(spacing: POSSpacing.sm) {
                        VStack(alignment: .leading, spacing: POSSpacing.xs) {
                            Text("QUELLE")
                                .font(POSTypography.labelMedium)
                                .foregroundStyle(POSColor.kitchenReady500)
                            ScrollView {
                                VStack(spacing: POSSpacing.sm) {
                                    ForEach(splitCandidates) { candidate in
                                        splitCandidateRow(candidate)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(POSSpacing.sm)
                        .background(POSColor.kitchenReady500.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: POSRadius.innerCard)
                                .stroke(POSColor.kitchenReady500.opacity(0.72), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: POSRadius.innerCard))

                        VStack(alignment: .leading, spacing: POSSpacing.xs) {
                            Text("SPLIT")
                                .font(POSTypography.labelMedium)
                                .foregroundStyle(POSColor.indigo500)
                            selectedSplitPanel
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(POSSpacing.sm)
                        .background(POSColor.indigo500.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: POSRadius.innerCard)
                                .stroke(POSColor.indigo500.opacity(0.72), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: POSRadius.innerCard))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: POSSpacing.sm) {
                            ForEach(splitCandidates) { candidate in
                                splitCandidateRow(candidate)
                            }
                        }
                    }
                }
            }

            if isTablet {
                HStack(spacing: POSSpacing.sm) {
                    summaryCard(title: "Aktuelle Bestellung", amount: splitCandidates.reduce(0) { $0 + (Double($1.qty) * $1.price) }, tint: POSColor.kitchenReady500)
                    summaryCard(title: "Split-Rechnung", amount: splitGross, tint: POSColor.indigo500)
                }
            }

            HStack(spacing: POSSpacing.sm) {
                ForEach(PaymentMethod.allCases) { method in
                    Button(method.rawValue) {
                        splitMethod = method
                    }
                    .buttonStyle(SplitMethodButtonStyle(selected: method == splitMethod))
                }
            }

            Text("Split-Betrag: \(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), splitGross))")
                .font(POSTypography.titleMedium)
                .foregroundStyle(POSColor.slate050)

            Button("Split buchen") {
                onSplitTap()
            }
            .buttonStyle(POSPrimaryButtonStyle())
            .disabled(!isOnline || isBusy || splitSelection.isEmpty)
        }
        .padding(POSSpacing.md)
        .background(POSColor.slate900.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.card)
                .stroke(POSColor.slate700.opacity(0.3), lineWidth: 1)
        )
    }

    private func splitCandidateRow(_ candidate: SplitCandidateUI) -> some View {
        let selectedQty = splitSelection[candidate.productId] ?? 0
        return HStack(spacing: POSSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(candidate.qty)x \(candidate.name)")
                    .font(POSTypography.titleMedium)
                    .foregroundStyle(POSColor.slate050)
                Text(String(format: "%.2f EUR / Stk", locale: Locale(identifier: "de_DE"), candidate.price))
                    .font(POSTypography.labelMedium)
                    .foregroundStyle(POSColor.slate300)
            }
            Spacer()
            HStack(spacing: POSSpacing.xs) {
                Button("-") {
                    let next = max(0, selectedQty - 1)
                    if next == 0 {
                        splitSelection.removeValue(forKey: candidate.productId)
                    } else {
                        splitSelection[candidate.productId] = next
                    }
                }
                .buttonStyle(StepperButtonStyle())

                Text("\(selectedQty)")
                    .font(POSTypography.titleMedium)
                    .foregroundStyle(POSColor.slate050)
                    .frame(width: 36)

                Button("+") {
                    let next = min(candidate.qty, selectedQty + 1)
                    splitSelection[candidate.productId] = next
                }
                .buttonStyle(StepperButtonStyle())
            }
        }
        .padding(POSSpacing.md)
        .background(POSColor.slate800.opacity(0.58))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.small)
                .stroke(POSColor.slate700.opacity(selectedQty > 0 ? 1 : 0.7), lineWidth: selectedQty > 0 ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
    }

    private var selectedSplitPanel: some View {
        let selectedRows: [SplitCandidateUI] = splitCandidates.compactMap { candidate in
            let selectedQty = splitSelection[candidate.productId] ?? 0
            guard selectedQty > 0 else { return nil }
            return SplitCandidateUI(
                productId: candidate.productId,
                name: candidate.name,
                qty: selectedQty,
                price: candidate.price
            )
        }

        return Group {
            if selectedRows.isEmpty {
                VStack {
                    Spacer()
                    Text("Noch keine Positionen ausgewählt.")
                        .font(POSTypography.bodyMedium)
                        .foregroundStyle(POSColor.slate300)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: POSSpacing.sm) {
                        ForEach(selectedRows) { row in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(row.qty)x \(row.name)")
                                        .font(POSTypography.titleMedium)
                                        .foregroundStyle(POSColor.slate050)
                                    Text(String(format: "%.2f EUR / Stk", locale: Locale(identifier: "de_DE"), row.price))
                                        .font(POSTypography.labelMedium)
                                        .foregroundStyle(POSColor.slate300)
                                }
                                Spacer()
                                Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), Double(row.qty) * row.price))
                                    .font(POSTypography.bodyLarge)
                                    .foregroundStyle(POSColor.slate050)
                            }
                            .padding(POSSpacing.md)
                            .background(POSColor.slate800.opacity(0.58))
                            .overlay(
                                RoundedRectangle(cornerRadius: POSRadius.small)
                                    .stroke(POSColor.slate700.opacity(0.72), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
                        }
                    }
                }
            }
        }
    }

    private func summaryCard(title: String, amount: Double, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(POSTypography.titleMedium)
                .foregroundStyle(POSColor.slate050)
            Spacer()
            Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), amount))
                .font(POSTypography.headlineLarge)
                .foregroundStyle(POSColor.slate050)
        }
        .padding(.horizontal, POSSpacing.md)
        .padding(.vertical, POSSpacing.sm)
        .background(tint.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.small)
                .stroke(tint.opacity(0.84), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
    }
}

private struct SplitMethodButtonStyle: ButtonStyle {
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

private struct StepperButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(POSTypography.titleMedium)
            .foregroundStyle(POSColor.slate050)
            .frame(width: 44, height: 36)
            .background(POSColor.slate900.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: POSRadius.small)
                    .stroke(POSColor.slate700.opacity(0.8), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
