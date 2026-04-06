import SwiftUI
import Foundation

struct TablesScreenView: View {
    @ObservedObject var store: AppStore

    @Namespace private var topNavSelectionNamespace
    @State private var paymentMethod: PaymentMethod = .cash
    @State private var splitMethod: PaymentMethod = .cash
    @State private var splitSelection: [String: Int] = [:]
    @State private var moveTargetId: Int?
    @State private var showSettingsDialog = false
    @State private var scrollTopNavToTransferOnce = false

    var body: some View {
        GeometryReader { geo in
            let isTablet = geo.size.width >= 800
            let isLargeTabletPortrait = isTablet && geo.size.height > geo.size.width
            let readyUnreadCountByTable = buildReadyUnreadCountByTable()
            let readyNoticesForSelectedTable = (store.kitchenReadyNoticesByTable[store.selectedTableId] ?? []).sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.eventCursor > $1.eventCursor
                }
                return $0.createdAt > $1.createdAt
            }
            let selectedReadyLastSeen = store.kitchenReadyLastSeenCursorByTable[store.selectedTableId] ?? 0
            let readyNoticeCount = readyNoticesForSelectedTable.filter { $0.eventCursor > selectedReadyLastSeen }.count
            let visibleOrderLines = store.currentOrderLines.filter { $0.qty > 0 && isVisibleOrderStatus($0.status) }
            let orderedLines = visibleOrderLines.filter { normalizeOrderStatus($0.status) == "ordered" }
            let hasUnsubmittedLines = visibleOrderLines.contains { normalizeOrderStatus($0.status) == "new" }
            let openGross = visibleOrderLines.filter { isOpenOrderStatus($0.status) }.reduce(0) { $0 + Double($1.qty) * $1.price }
            let splitCandidates = buildSplitCandidates(from: orderedLines)
            let splitGross = splitSelection.reduce(0.0) { partial, pair in
                let candidate = splitCandidates.first(where: { $0.productId == pair.key })
                return partial + (Double(pair.value) * (candidate?.price ?? 0))
            }
            let canTriggerPayment = store.isOnline && !store.isBusy && !orderedLines.isEmpty && !hasUnsubmittedLines

            VStack(spacing: POSSpacing.xs) {
                topNavigation(isTablet: isTablet)

                Divider().overlay(POSColor.slate700.opacity(0.24))

                Group {
                    switch store.activeWorkTab {
                    case .tables:
                        TablesGridPanel(
                            tables: store.tables.sorted(by: { a, b in
                                let countA = readyUnreadCountByTable[a.id] ?? 0
                                let countB = readyUnreadCountByTable[b.id] ?? 0
                                if countA == countB {
                                    return a.id < b.id
                                }
                                return countA > countB
                            }),
                            selectedTableId: store.selectedTableId,
                            unreadReadyCountByTable: readyUnreadCountByTable,
                            onSelectTable: { tableId in
                                store.requestQuickSync(includeCatalog: false)
                                store.selectTable(tableId)
                                store.activeWorkTab = .orders
                            },
                            onOpenTransfer: {
                                withAnimation(POSMotion.select) {
                                    store.activeWorkTab = .transfer
                                }
                                POSHaptics.selection()
                                scrollTopNavToTransferOnce = true
                            }
                        )

                    case .orders:
                        OrdersWorkspaceView(
                            store: store,
                            isTablet: isTablet,
                            isLargeTabletPortrait: isLargeTabletPortrait,
                            readyNoticeCount: readyNoticeCount,
                            readyNoticesForSelectedTable: readyNoticesForSelectedTable,
                            onProductTap: { productId in
                                store.onProductTap(productId)
                            },
                            onSubmit: {
                                store.onSubmitOrderTap()
                            },
                            onIncrease: {
                                store.onIncreaseSelectedLineTap()
                            },
                            onDecrease: {
                                store.onDecreaseSelectedLineTap()
                            },
                            onCancelOrdered: {
                                store.onCancelOrderedLineTap()
                            },
                            onSelectLine: { lineId in
                                store.onSelectOrderLine(lineId)
                            }
                        )

                    case .payment:
                        PaymentPanelView(
                            isOnline: store.isOnline,
                            isBusy: store.isBusy,
                            hasUnsubmittedLines: hasUnsubmittedLines,
                            openGross: openGross,
                            selectedMethod: $paymentMethod,
                            canTriggerPayment: canTriggerPayment,
                            onPaymentTap: {
                                store.onPaymentTap(method: paymentMethod.coreValue)
                            }
                        )

                    case .split:
                        SplitPanelView(
                            isTablet: isTablet,
                            splitCandidates: splitCandidates,
                            splitSelection: $splitSelection,
                            splitMethod: $splitMethod,
                            splitGross: splitGross,
                            isOnline: store.isOnline,
                            isBusy: store.isBusy,
                            onSplitTap: {
                                store.onSplitTap(splitSelection: splitSelection, method: splitMethod.coreValue)
                            }
                        )

                    case .transfer:
                        TransferPanelView(
                            isTablet: isTablet,
                            tables: store.tables,
                            selectedTableId: store.selectedTableId,
                            tableOrderLinesByTableId: store.tableOrderLinesByTableId,
                            initialTargetTableId: moveTargetId,
                            isOnline: store.isOnline,
                            isBusy: store.isBusy,
                            onMoveAll: { targetId in
                                moveTargetId = targetId
                                store.onMoveTap(targetTableId: targetId)
                            },
                            onMoveSelection: { targetId, selection in
                                moveTargetId = targetId
                                store.onTransferSelectionTap(
                                    sourceTableId: store.selectedTableId,
                                    targetTableId: targetId,
                                    selectionByLineId: selection
                                )
                            }
                        )

                    case .voucher:
                        VoucherPanelView(
                            tableId: store.selectedTableId,
                            openGross: openGross,
                            appliedVouchers: store.currentAppliedVouchers,
                            voucherCodeInput: store.voucherCodeInput,
                            isOnline: store.isOnline,
                            isBusy: store.isBusy,
                            onVoucherInputChange: { store.setVoucherCodeInput($0) },
                            onApplyVoucher: { store.applyVoucherCode() },
                            onRemoveVoucher: { store.removeVoucherCode($0) }
                        )

                    case .schlemmer:
                        SchlemmerPanelView(
                            tableId: store.selectedTableId,
                            selectedType: store.schlemmerType,
                            eligibleLines: store.schlemmerEligibleLines,
                            selection: store.schlemmerSelection,
                            availableUnits: store.schlemmerAvailableUnits,
                            requiredFoodUnits: store.schlemmerRequiredFoodUnits,
                            requiredSelectionCount: store.schlemmerRequiredSelectionCount,
                            selectedUnits: store.schlemmerSelectedUnits,
                            previewInFlight: store.schlemmerPreviewInFlight,
                            showLoadingIndicator: store.schlemmerPreviewShowLoader,
                            isOnline: store.isOnline,
                            isBusy: store.isBusy,
                            onTypeChange: { store.selectSchlemmerType($0) },
                            onRefresh: { store.refreshSchlemmerPreview() },
                            onSetSelection: { lineId, qty in
                                store.setSchlemmerSelection(lineId: lineId, qty: qty)
                            },
                            onApply: { store.applySchlemmerSelection() }
                        )
                    }
                }
                .animation(POSMotion.panel, value: store.activeWorkTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .sheet(isPresented: $showSettingsDialog) {
                SettingsSheetView(store: store)
            }
            .onChange(of: store.selectedTableId) { _, _ in
                splitSelection = [:]
                if store.activeWorkTab == .schlemmer {
                    store.refreshSchlemmerPreview()
                }
            }
            .onChange(of: store.currentOrderCode) { _, _ in
                splitSelection = [:]
            }
            .onChange(of: store.activeWorkTab) { _, tab in
                if tab == .schlemmer {
                    store.refreshSchlemmerPreview()
                }
            }
        }
    }

    private func topNavigation(isTablet: Bool) -> some View {
        let topNavHeight: CGFloat = isTablet ? 56 : 46
        let topNavActionWidth: CGFloat = isTablet ? 68 : 52

        return HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: POSSpacing.xxs) {
                        ForEach(store.visibleWorkTabs, id: \.self) { tab in
                            let isSelected = tab == store.activeWorkTab
                            Button {
                                withAnimation(POSMotion.select) {
                                    store.activeWorkTab = tab
                                }
                                POSHaptics.selection()
                                let refreshCatalog = (tab == .orders || tab == .tables)
                                store.requestQuickSync(includeCatalog: refreshCatalog)
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
                                            .matchedGeometryEffect(id: "top-nav-pill", in: topNavSelectionNamespace)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(POSColor.slate050.opacity(0.18), lineWidth: 1)
                                            )
                                            .shadow(color: POSColor.indigo500.opacity(0.32), radius: 10, y: 5)
                                    }

                                    Text(tab.rawValue)
                                        .font(isTablet ? POSTypography.bodyLarge : POSTypography.labelLarge)
                                        .foregroundStyle(isSelected ? Color.white : POSColor.slate050)
                                        .padding(.horizontal, isTablet ? 20 : 14)
                                        .padding(.vertical, isTablet ? 10 : 8)
                                        .lineLimit(1)
                                }
                                .frame(height: topNavHeight - 8)
                            }
                            .buttonStyle(.plain)
                            .id(tab)
                        }
                    }
                    .padding(.horizontal, POSSpacing.xs)
                    .padding(.vertical, POSSpacing.xs)
                    .frame(height: topNavHeight)
                }
                .onChange(of: scrollTopNavToTransferOnce) { _, shouldScroll in
                    guard shouldScroll else { return }
                    withAnimation(POSMotion.panel) {
                        if store.visibleWorkTabs.contains(.transfer) {
                            proxy.scrollTo(WorkTab.transfer, anchor: .trailing)
                        }
                    }
                    DispatchQueue.main.async {
                        scrollTopNavToTransferOnce = false
                    }
                }
            }

            Menu {
                Button("Einstellungen") {
                    showSettingsDialog = true
                }
                Button("Jetzt synchronisieren") {
                    store.requestQuickSync(includeCatalog: true, force: true)
                }
                Button("Queue senden") {
                    store.flushOfflineQueue()
                }
                .disabled(!(store.isOnline && store.offlineQueueCount > 0))
                Button("Logout") {
                    store.logout()
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(POSColor.slate050)
                    .frame(width: topNavActionWidth, height: topNavHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(POSColor.slate800.opacity(0.42))
                    )
                    .padding(.trailing, POSSpacing.xs)
            }
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
                .frame(height: topNavHeight * 0.55)
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.innerCard + 2, style: .continuous)
                .stroke(POSColor.slate700.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: POSColor.indigo500.opacity(0.12), radius: 16, y: 7)
    }

    private func buildReadyUnreadCountByTable() -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: store.kitchenReadyNoticesByTable.map { tableId, notices in
            let lastSeen = store.kitchenReadyLastSeenCursorByTable[tableId] ?? 0
            let unreadCount = notices.filter { $0.eventCursor > lastSeen }.count
            return (tableId, unreadCount)
        })
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

    private func isOpenOrderStatus(_ status: String?) -> Bool {
        let normalized = normalizeOrderStatus(status)
        return normalized.isEmpty || normalized == "new" || normalized == "ordered"
    }

    private func isVisibleOrderStatus(_ status: String?) -> Bool {
        let normalized = normalizeOrderStatus(status)
        return normalized != "paid" && normalized != "void"
    }

    private func buildSplitCandidates(from lines: [OrderLineUI]) -> [SplitCandidateUI] {
        let grouped = Dictionary(grouping: lines) { $0.productId }
        return grouped.compactMap { productId, items in
            guard !productId.isEmpty else { return nil }
            let qty = items.reduce(0) { $0 + $1.qty }
            guard qty > 0 else { return nil }
            return SplitCandidateUI(productId: productId, name: items[0].name, qty: qty, price: items[0].price)
        }
        .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}

private struct VoucherPanelView: View {
    let tableId: Int
    let openGross: Double
    let appliedVouchers: [AppliedVoucherUI]
    let voucherCodeInput: String
    let isOnline: Bool
    let isBusy: Bool
    let onVoucherInputChange: (String) -> Void
    let onApplyVoucher: () -> Void
    let onRemoveVoucher: (String) -> Void

    private var totalVoucherAmount: Double {
        appliedVouchers.reduce(0) { $0 + max(0, $1.remaining) }
    }

    private var payableAmount: Double {
        max(0, openGross - totalVoucherAmount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: POSSpacing.md) {
            Text("Gutschein")
                .font(POSTypography.titleLarge)
                .foregroundStyle(POSColor.slate050)

            VStack(alignment: .leading, spacing: POSSpacing.xs) {
                Text("Tisch \(tableId)")
                    .font(POSTypography.labelLarge)
                    .foregroundStyle(POSColor.slate300)
                Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), payableAmount))
                    .font(.system(size: 34, weight: .semibold, design: .default))
                    .foregroundStyle(POSColor.slate050)
                Text("Offen: \(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), openGross))")
                    .font(POSTypography.labelLarge)
                    .foregroundStyle(POSColor.slate300)
            }
            .padding(POSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(POSColor.slate800.opacity(0.52))
            .clipShape(RoundedRectangle(cornerRadius: POSRadius.innerCard))
            .overlay(
                RoundedRectangle(cornerRadius: POSRadius.innerCard)
                    .stroke(POSColor.slate700.opacity(0.4), lineWidth: 1)
            )

            if appliedVouchers.isEmpty {
                Text("Noch kein Gutschein gebucht.")
                    .font(POSTypography.bodyMedium)
                    .foregroundStyle(POSColor.slate300)
            } else {
                VStack(spacing: POSSpacing.xs) {
                    ForEach(appliedVouchers) { voucher in
                        HStack(spacing: POSSpacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(voucher.code)
                                    .font(POSTypography.titleMedium)
                                    .foregroundStyle(POSColor.slate050)
                                Text("Verfügbar: \(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), voucher.remaining))")
                                    .font(POSTypography.labelLarge)
                                    .foregroundStyle(POSColor.emerald500)
                            }
                            Spacer()
                            Button {
                                onRemoveVoucher(voucher.code)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(POSColor.red500)
                                    .frame(width: 28, height: 28)
                                    .background(POSColor.slate900.opacity(0.56))
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle().stroke(POSColor.red500.opacity(0.55), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(!isOnline || isBusy)
                        }
                        .padding(.horizontal, POSSpacing.md)
                        .padding(.vertical, POSSpacing.sm)
                        .background(POSColor.emerald500.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
                        .overlay(
                            RoundedRectangle(cornerRadius: POSRadius.small)
                                .stroke(POSColor.emerald500.opacity(0.58), lineWidth: 1)
                        )
                    }
                }
            }

            HStack(spacing: POSSpacing.sm) {
                TextField("Gutscheincode", text: Binding(
                    get: { voucherCodeInput },
                    set: { onVoucherInputChange($0) }
                ))
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .font(POSTypography.bodyLarge)
                .foregroundStyle(POSColor.slate050)
                .padding(.horizontal, POSSpacing.md)
                .padding(.vertical, POSSpacing.sm)
                .background(POSColor.slate800.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: POSRadius.small)
                        .stroke(POSColor.slate700.opacity(0.5), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
                .disabled(!isOnline || isBusy)

                Button("Anwenden") {
                    POSHaptics.medium()
                    onApplyVoucher()
                }
                .buttonStyle(POSPrimaryButtonStyle())
                .disabled(!isOnline || isBusy || voucherCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Spacer()
        }
        .padding(POSSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(POSColor.slate900.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.card)
                .stroke(POSColor.slate700.opacity(0.3), lineWidth: 1)
        )
    }
}

private struct SchlemmerPanelView: View {
    let tableId: Int
    let selectedType: SchlemmerBlockTypeUI
    let eligibleLines: [SchlemmerEligibleLineUI]
    let selection: [String: Int]
    let availableUnits: Int
    let requiredFoodUnits: Int
    let requiredSelectionCount: Int
    let selectedUnits: Int
    let previewInFlight: Bool
    let showLoadingIndicator: Bool
    let isOnline: Bool
    let isBusy: Bool
    let onTypeChange: (SchlemmerBlockTypeUI) -> Void
    let onRefresh: () -> Void
    let onSetSelection: (String, Int) -> Void
    let onApply: () -> Void

    private var canApply: Bool {
        guard isOnline, !isBusy, !previewInFlight else { return false }
        guard !selection.isEmpty else { return false }
        if requiredSelectionCount > 0 {
            return selectedUnits == requiredSelectionCount
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: POSSpacing.md) {
            HStack {
                Text("Schlemmer Block")
                    .font(POSTypography.titleLarge)
                    .foregroundStyle(POSColor.slate050)
                Spacer()
                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(POSColor.slate050)
                        .frame(width: 30, height: 30)
                        .background(POSColor.slate800.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
                }
                .buttonStyle(.plain)
                .disabled(previewInFlight || isBusy)
            }

            HStack(spacing: POSSpacing.sm) {
                ForEach(SchlemmerBlockTypeUI.allCases) { type in
                    let selected = selectedType == type
                    Button {
                        POSHaptics.selection()
                        onTypeChange(type)
                    } label: {
                        Text(type.rawValue)
                            .font(POSTypography.labelLarge)
                            .foregroundStyle(selected ? Color.white : POSColor.slate050)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, POSSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: POSRadius.small)
                                    .fill(selected ? POSColor.indigo500.opacity(0.86) : POSColor.slate800.opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: POSRadius.small)
                                    .stroke(selected ? POSColor.indigo500.opacity(0.95) : POSColor.slate700.opacity(0.45), lineWidth: selected ? 1.5 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(previewInFlight || isBusy)
                }
            }

            VStack(alignment: .leading, spacing: POSSpacing.xxs) {
                Text("Tisch \(tableId)")
                    .font(POSTypography.labelLarge)
                    .foregroundStyle(POSColor.slate300)
                Text("Verfügbar: \(availableUnits) • Mindestmenge: \(requiredFoodUnits)")
                    .font(POSTypography.bodyMedium)
                    .foregroundStyle(POSColor.slate050)
                if requiredSelectionCount > 0 {
                    Text("Auswahl: \(selectedUnits)/\(requiredSelectionCount)")
                        .font(POSTypography.labelLarge)
                        .foregroundStyle(selectedUnits == requiredSelectionCount ? POSColor.emerald500 : POSColor.amber500)
                }
            }
            .padding(POSSpacing.md)
            .background(POSColor.slate800.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: POSRadius.small)
                    .stroke(POSColor.slate700.opacity(0.4), lineWidth: 1)
            )

            if previewInFlight && showLoadingIndicator {
                HStack(spacing: POSSpacing.sm) {
                    ProgressView()
                        .tint(POSColor.indigo500)
                    Text("Schlemmer Vorschau wird geladen...")
                        .font(POSTypography.bodyMedium)
                        .foregroundStyle(POSColor.slate300)
                }
            } else if eligibleLines.isEmpty {
                Spacer()
                Text("Keine berechtigten Speisen gefunden.")
                    .font(POSTypography.bodyMedium)
                    .foregroundStyle(POSColor.slate300)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: POSSpacing.xs) {
                        ForEach(eligibleLines) { line in
                            let selectedQty = selection[line.lineId] ?? 0
                            HStack(spacing: POSSpacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(line.qty)x \(line.name)")
                                        .font(POSTypography.titleMedium)
                                        .foregroundStyle(POSColor.slate050)
                                        .lineLimit(2)
                                    HStack(spacing: POSSpacing.xs) {
                                        if line.isKidsMeal {
                                            Text("Kindergericht")
                                                .font(POSTypography.labelMedium)
                                                .foregroundStyle(Color.adaptive(darkHex: 0xD8FFEA, lightHex: 0x121A27))
                                                .padding(.horizontal, POSSpacing.sm)
                                                .padding(.vertical, 2)
                                                .background(POSColor.emerald500.opacity(0.28))
                                                .clipShape(Capsule())
                                        }
                                        Text("Ausgewählt \(selectedQty)/\(line.qty)")
                                            .font(POSTypography.labelLarge)
                                            .foregroundStyle(POSColor.slate300)
                                    }
                                }
                                Spacer()
                                Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), line.unitPrice))
                                    .font(POSTypography.bodyLarge)
                                    .foregroundStyle(POSColor.slate050)
                                HStack(spacing: POSSpacing.xs) {
                                    Button {
                                        onSetSelection(line.lineId, max(0, selectedQty - 1))
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(POSColor.slate050)
                                            .frame(width: 28, height: 28)
                                            .background(POSColor.slate900.opacity(0.65))
                                            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(previewInFlight || isBusy)

                                    Text("\(selectedQty)")
                                        .font(POSTypography.titleMedium)
                                        .foregroundStyle(POSColor.slate050)
                                        .frame(width: 22)

                                    Button {
                                        onSetSelection(line.lineId, min(line.qty, selectedQty + 1))
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(POSColor.slate050)
                                            .frame(width: 28, height: 28)
                                            .background(POSColor.slate900.opacity(0.65))
                                            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(previewInFlight || isBusy)
                                }
                            }
                            .padding(.horizontal, POSSpacing.md)
                            .padding(.vertical, POSSpacing.sm)
                            .background((selectedQty > 0 ? POSColor.indigo500.opacity(0.22) : POSColor.slate800.opacity(0.58)))
                            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
                            .overlay(
                                RoundedRectangle(cornerRadius: POSRadius.small)
                                    .stroke(selectedQty > 0 ? POSColor.indigo500.opacity(0.82) : POSColor.slate700.opacity(0.35), lineWidth: 1)
                            )
                        }
                    }
                }
            }

            Button("Schlemmer Block anwenden") {
                POSHaptics.medium()
                onApply()
            }
            .buttonStyle(POSPrimaryButtonStyle())
            .disabled(!canApply)
        }
        .padding(POSSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(POSColor.slate900.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.card)
                .stroke(POSColor.slate700.opacity(0.3), lineWidth: 1)
        )
    }
}

struct SplitCandidateUI: Identifiable {
    var id: String { productId }
    let productId: String
    let name: String
    let qty: Int
    let price: Double
}
