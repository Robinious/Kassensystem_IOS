import SwiftUI

struct OrderOverviewTabsView: View {
    let selectedTab: OrderOverviewTab
    let readyCount: Int
    let onSelectTab: (OrderOverviewTab) -> Void
    @Namespace private var orderOverviewSelectionNamespace

    var body: some View {
        let tabBarHeight: CGFloat = 46

        HStack(spacing: 0) {
            HStack(spacing: POSSpacing.xxs) {
                tabButton(tab: .orders, title: "Bestellungen")
                tabButton(tab: .ready, title: "Bereit", readyCount: readyCount)
            }
            .padding(.horizontal, POSSpacing.xs)
            .padding(.vertical, POSSpacing.xs)
            .frame(height: tabBarHeight)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: POSRadius.innerCard + 2, style: .continuous))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: POSRadius.innerCard + 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [POSColor.slate050.opacity(0.12), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: tabBarHeight * 0.55)
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.innerCard + 2, style: .continuous)
                .stroke(POSColor.slate700.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: POSColor.indigo500.opacity(0.12), radius: 16, y: 7)
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: selectedTab)
    }

    private func tabButton(tab: OrderOverviewTab, title: String, readyCount: Int = 0) -> some View {
        let isSelected = tab == selectedTab

        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                onSelectTab(tab)
            }
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    POSColor.indigo500.opacity(0.88),
                                    POSColor.indigo400.opacity(0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .matchedGeometryEffect(id: "order-overview-pill", in: orderOverviewSelectionNamespace)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(POSColor.slate050.opacity(0.18), lineWidth: 1)
                        )
                        .shadow(color: POSColor.indigo500.opacity(0.32), radius: 10, y: 5)
                }

                HStack(spacing: POSSpacing.sm) {
                    Text(title)
                        .font(POSTypography.labelLarge)
                        .foregroundStyle(isSelected ? Color.white : POSColor.slate050)
                        .lineLimit(1)

                    if readyCount > 0 {
                        Text("\(readyCount)")
                            .font(POSTypography.labelMedium)
                            .foregroundStyle(Color.adaptive(darkHex: 0xD8FFEA, lightHex: 0x121A27))
                            .padding(.horizontal, POSSpacing.sm)
                            .padding(.vertical, 2)
                            .background(POSColor.emerald500.opacity(0.28))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(POSColor.emerald500.opacity(0.95), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, POSSpacing.md)
                .padding(.vertical, POSSpacing.sm)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 38)
        }
        .buttonStyle(.plain)
    }
}

struct OrderCommandCenterView: View {
    let canSubmitOrder: Bool
    let canAdjustQty: Bool
    let canStorno: Bool
    let onSubmit: () -> Void
    let onIncrease: () -> Void
    let onDecrease: () -> Void
    let onStorno: () -> Void
    let isBusy: Bool

    var body: some View {
        HStack(spacing: POSSpacing.sm) {
            Button("Bestellen") { onSubmit() }
                .buttonStyle(POSPrimaryButtonStyle())
                .disabled(!canSubmitOrder)

            Button("+") { onIncrease() }
                .buttonStyle(POSSecondaryButtonStyle())
                .frame(width: 56)
                .disabled(!canAdjustQty || isBusy)

            Button("-") { onDecrease() }
                .buttonStyle(POSSecondaryButtonStyle())
                .frame(width: 56)
                .disabled(!canAdjustQty || isBusy)

            Button("Storno") { onStorno() }
                .buttonStyle(POSSecondaryButtonStyle())
                .disabled(!canStorno || isBusy)
        }
    }
}

struct OrderLineCardView: View {
    let line: OrderLineUI
    let selected: Bool
    let onTap: () -> Void

    @State private var hasSeenInitialQty = false
    @State private var qtyPulse = false

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(alignment: .top, spacing: POSSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(line.qty)x \(line.name)")
                        .font(POSTypography.titleMedium)
                        .foregroundStyle(POSColor.slate050)
                        .scaleEffect(qtyPulse ? 1.06 : 1)
                        .opacity(qtyPulse ? 0.72 : 1)

                    HStack(spacing: POSSpacing.xs) {
                        statusBadge
                        if line.kitchenReady {
                            Text("Bereit")
                                .font(POSTypography.labelMedium)
                                .foregroundStyle(POSColor.kitchenReadyOn)
                                .padding(.horizontal, POSSpacing.sm)
                                .padding(.vertical, 2)
                                .background(POSColor.kitchenReady500.opacity(0.28))
                                .clipShape(Capsule())
                        }
                    }
                }
                Spacer()
                Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), Double(line.qty) * line.price))
                    .font(POSTypography.bodyLarge)
                    .foregroundStyle(POSColor.slate050)
            }
            .padding(.horizontal, POSSpacing.md)
            .padding(.vertical, POSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(containerColor)
            .overlay(
                RoundedRectangle(cornerRadius: POSRadius.small)
                    .stroke(selected ? POSColor.indigo500.opacity(0.94) : borderColor, lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
        }
        .buttonStyle(.plain)
        .animation(POSMotion.quick, value: qtyPulse)
        .onChange(of: line.qty) { _, _ in
            if !hasSeenInitialQty {
                hasSeenInitialQty = true
                return
            }
            qtyPulse = true
            Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                await MainActor.run {
                    qtyPulse = false
                }
            }
        }
    }

    private var status: String {
        normalizeOrderStatus(line.status)
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(POSTypography.labelMedium)
            .foregroundStyle(statusColor)
            .padding(.horizontal, POSSpacing.sm)
            .padding(.vertical, 2)
            .background(statusContainer)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(statusBorder, lineWidth: 1)
            )
    }

    private var containerColor: Color {
        if selected {
            return statusContainer.opacity(0.44)
        }
        return statusContainer
    }

    private var borderColor: Color {
        statusBorder.opacity(0.62)
    }

    private var statusLabel: String {
        switch status {
        case "ordered":
            return "Bestellt"
        case "cancelled":
            return "Storniert"
        default:
            return "Neu"
        }
    }

    private var statusColor: Color {
        switch status {
        case "ordered":
            return Color.adaptive(darkHex: 0xCFFFE2, lightHex: 0x121A27)
        case "cancelled":
            return Color.adaptive(darkHex: 0xFFC2BA, lightHex: 0x121A27)
        default:
            return Color.adaptive(darkHex: 0xFFE0A0, lightHex: 0x121A27)
        }
    }

    private var statusContainer: Color {
        switch status {
        case "ordered":
            return POSColor.emerald500.opacity(0.30)
        case "cancelled":
            return POSColor.red500.opacity(0.28)
        default:
            return POSColor.amber500.opacity(0.30)
        }
    }

    private var statusBorder: Color {
        switch status {
        case "ordered":
            return POSColor.emerald500.opacity(0.80)
        case "cancelled":
            return POSColor.red500.opacity(0.80)
        default:
            return POSColor.amber500.opacity(0.78)
        }
    }

    private func normalizeOrderStatus(_ status: String?) -> String {
        let normalized = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch normalized {
        case "ordered", "bestellt", "ready", "bereit":
            return "ordered"
        case "cancelled", "storniert", "storno", "void":
            return "cancelled"
        default:
            return "new"
        }
    }
}

struct OrderTotalFooter: View {
    let totalGross: Double

    var body: some View {
        HStack {
            Text("Gesamt")
                .font(POSTypography.titleMedium)
                .foregroundStyle(POSColor.slate300)
            Spacer()
            Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), totalGross))
                .font(POSTypography.titleLarge)
                .foregroundStyle(POSColor.slate050)
        }
        .padding(.vertical, POSSpacing.xs)
    }
}

struct ProductCardView: View {
    let product: CatalogProductUI
    let enabled: Bool
    let showVatOnTile: Bool
    let showFullProductText: Bool
    let showPriceOnTile: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: POSSpacing.xxs) {
                Text(product.name)
                    .font(POSTypography.labelLarge)
                    .foregroundStyle(enabled ? POSColor.slate050 : POSColor.slate300)
                    .lineLimit(showFullProductText ? 2 : 1)

                if showPriceOnTile {
                    Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), product.price))
                        .font(POSTypography.bodyMedium)
                        .foregroundStyle(POSColor.slate050)
                }

                if showVatOnTile {
                    Text("MwSt \(String(format: "%.0f", product.taxRate))%")
                        .font(POSTypography.labelMedium)
                        .foregroundStyle(POSColor.slate300)
                }

                if product.isBlocked {
                    Text(product.blockReason.isEmpty ? "Gesperrt" : product.blockReason)
                        .font(POSTypography.labelMedium)
                        .foregroundStyle(Color(hex: 0xFFC2BA))
                        .padding(.top, POSSpacing.xxs)
                }
            }
            .padding(.horizontal, POSSpacing.sm)
            .padding(.vertical, POSSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(product.isBlocked ? POSColor.red500.opacity(0.14) : POSColor.slate800.opacity(0.58))
            .overlay(
                RoundedRectangle(cornerRadius: POSRadius.small)
                    .stroke(product.isBlocked ? POSColor.red500.opacity(0.8) : POSColor.slate700.opacity(0.52), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
            .opacity(enabled ? 1 : 0.72)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
