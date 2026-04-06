import SwiftUI

struct OrderOverviewTabsView: View {
    let selectedTab: OrderOverviewTab
    let readyCount: Int
    let onSelectTab: (OrderOverviewTab) -> Void
    @Namespace private var orderOverviewSelectionNamespace
    @State private var previousReadyCount = 0
    @State private var pulseReadyBadge = false

    var body: some View {
        let tabBarHeight: CGFloat = 44

        HStack(spacing: 0) {
            HStack(spacing: POSSpacing.xxs) {
                tabButton(tab: .orders, title: "Bestellungen")
                tabButton(tab: .ready, title: "Bereit", readyCount: readyCount)
            }
            .padding(.horizontal, POSSpacing.xs)
            .padding(.vertical, POSSpacing.xxs)
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
        .animation(POSMotion.select, value: selectedTab)
        .onAppear {
            previousReadyCount = readyCount
        }
        .onChange(of: readyCount) { _, next in
            if next > previousReadyCount && next > 0 {
                pulseReadyBadge = true
                Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    await MainActor.run {
                        pulseReadyBadge = false
                    }
                }
            }
            previousReadyCount = next
        }
    }

    private func tabButton(tab: OrderOverviewTab, title: String, readyCount: Int = 0) -> some View {
        let isSelected = tab == selectedTab

        return Button {
            withAnimation(POSMotion.select) {
                onSelectTab(tab)
            }
            POSHaptics.selection()
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
                            .scaleEffect(pulseReadyBadge ? 1.1 : 1.0)
                            .opacity(pulseReadyBadge ? 1.0 : 0.94)
                            .animation(POSMotion.pulse, value: pulseReadyBadge)
                    }
                }
                .padding(.horizontal, POSSpacing.md)
                .padding(.vertical, POSSpacing.xs)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 36)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity)
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
        let commandButtonHeight: CGFloat = 42

        HStack(spacing: POSSpacing.sm) {
            Button("Bestellen") {
                POSHaptics.medium()
                onSubmit()
            }
                .buttonStyle(POSPrimaryButtonStyle())
                .frame(height: commandButtonHeight)
                .disabled(!canSubmitOrder)

            Button("+") {
                POSHaptics.light()
                onIncrease()
            }
                .buttonStyle(POSSecondaryButtonStyle())
                .frame(width: 56, height: commandButtonHeight)
                .disabled(!canAdjustQty || isBusy)

            Button("-") {
                POSHaptics.light()
                onDecrease()
            }
                .buttonStyle(POSSecondaryButtonStyle())
                .frame(width: 56, height: commandButtonHeight)
                .disabled(!canAdjustQty || isBusy)

            Button("Storno") {
                POSHaptics.warning()
                onStorno()
            }
                .buttonStyle(POSSecondaryButtonStyle())
                .frame(height: commandButtonHeight)
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
            POSHaptics.selection()
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
                        if isSchlemmerCancelled {
                            Text("Schlemmer")
                                .font(POSTypography.labelMedium)
                                .foregroundStyle(Color.adaptive(darkHex: 0xFFF5F7, lightHex: 0x7A2434))
                                .padding(.horizontal, POSSpacing.sm)
                                .padding(.vertical, 2)
                                .background(Color.adaptive(darkHex: 0x6A5660, lightHex: 0xF3D4DB).opacity(0.7))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color.adaptive(darkHex: 0xE6B2BF, lightHex: 0xCA6D84).opacity(0.85), lineWidth: 1)
                                )
                        }
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

    private var cancelReason: String {
        line.cancelReason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isSchlemmerCancelled: Bool {
        status == "cancelled" && cancelReason == "schlemmer_block"
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(POSTypography.labelMedium)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
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
            if isSchlemmerCancelled {
                return "Schlemmer Block - Storniert"
            }
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
            if isSchlemmerCancelled {
                return Color.adaptive(darkHex: 0xFFE9EE, lightHex: 0x3E1A22)
            }
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
            if isSchlemmerCancelled {
                return Color.adaptive(darkHex: 0x8E636C, lightHex: 0xF4D8DD).opacity(0.46)
            }
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
            if isSchlemmerCancelled {
                return Color.adaptive(darkHex: 0xEAB0BE, lightHex: 0xC4647B).opacity(0.86)
            }
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
    let emphasizeAmount: Bool

    var body: some View {
        HStack {
            Text("Gesamt")
                .font(emphasizeAmount ? .system(size: 30, weight: .semibold, design: .default) : POSTypography.titleMedium)
                .foregroundStyle(POSColor.slate300)
            Spacer()
            AnimatedEuroAmountText(
                value: totalGross,
                font: emphasizeAmount ? .system(size: 40, weight: .semibold, design: .default) : POSTypography.titleLarge,
                foreground: POSColor.slate050
            )
            .animation(POSMotion.feedback, value: totalGross)
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
    @State private var tapScale = false
    @State private var showFlyHint = false

    var body: some View {
        Button {
            withAnimation(POSMotion.feedback) {
                tapScale = true
                showFlyHint = true
            }
            POSHaptics.light()
            onTap()
            Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                await MainActor.run {
                    withAnimation(POSMotion.feedback) {
                        tapScale = false
                    }
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: 260_000_000)
                await MainActor.run {
                    withAnimation(POSMotion.feedback) {
                        showFlyHint = false
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: POSSpacing.xxs) {
                Text(product.name)
                    .font(POSTypography.labelLarge)
                    .foregroundStyle(enabled ? POSColor.slate050 : POSColor.slate300)
                    .lineLimit(showFullProductText ? 2 : 1)

                if showPriceOnTile {
                    if product.promoActive, let promoPrice = product.promoPrice, promoPrice > 0, promoPrice < product.regularPrice {
                        HStack(spacing: POSSpacing.xs) {
                            Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), product.regularPrice))
                                .font(POSTypography.labelMedium)
                                .foregroundStyle(POSColor.slate300)
                                .strikethrough(true, color: POSColor.slate300.opacity(0.8))
                            Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), promoPrice))
                                .font(POSTypography.bodyMedium.weight(.semibold))
                                .foregroundStyle(POSColor.slate050)
                        }
                    } else {
                        Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), product.price))
                            .font(POSTypography.bodyMedium)
                            .foregroundStyle(POSColor.slate050)
                    }
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
            .overlay(alignment: .topTrailing) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(POSColor.indigo400)
                    .padding(.top, POSSpacing.xs)
                    .padding(.trailing, POSSpacing.xs)
                    .offset(y: showFlyHint ? -14 : 0)
                    .opacity(showFlyHint ? 1 : 0)
                    .scaleEffect(showFlyHint ? 1 : 0.7)
            }
            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
            .opacity(enabled ? 1 : 0.72)
            .scaleEffect(tapScale ? 0.985 : 1.0)
            .shadow(color: tapScale ? POSColor.indigo500.opacity(0.2) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct AnimatedEuroAmountText: View, Animatable {
    var value: Double
    let font: Font
    let foreground: Color

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), value))
            .font(font)
            .foregroundStyle(foreground)
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}
