import SwiftUI

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
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                                    store.activeWorkTab = .transfer
                                }
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
            }
            .onChange(of: store.currentOrderCode) { _, _ in
                splitSelection = [:]
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
                        ForEach(WorkTab.allCases, id: \.self) { tab in
                            let isSelected = tab == store.activeWorkTab
                            Button {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                                    store.activeWorkTab = tab
                                }
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
                    withAnimation(.easeInOut(duration: 0.24)) {
                        proxy.scrollTo(WorkTab.transfer, anchor: .trailing)
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

struct SplitCandidateUI: Identifiable {
    var id: String { productId }
    let productId: String
    let name: String
    let qty: Int
    let price: Double
}
