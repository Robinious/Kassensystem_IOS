import SwiftUI

struct OrdersWorkspaceView: View {
    @ObservedObject var store: AppStore
    let isTablet: Bool
    let isLargeTabletPortrait: Bool
    let readyNoticeCount: Int
    let readyNoticesForSelectedTable: [KitchenReadyNoticeUI]
    let onProductTap: (String) -> Void
    let onSubmit: () -> Void
    let onIncrease: () -> Void
    let onDecrease: () -> Void
    let onCancelOrdered: () -> Void
    let onSelectLine: (String) -> Void

    var body: some View {
        let selectedCatalogGroupId = store.selectedCatalogGroupId
        let visibleProducts = store.catalogProducts.filter { product in
            guard let selectedCatalogGroupId, !selectedCatalogGroupId.isEmpty else {
                return true
            }
            return product.groupId == selectedCatalogGroupId
        }

        let visibleOrderLines = store.currentOrderLines.filter { $0.qty > 0 && isVisibleOrderStatus($0.status) }
        let selectedLine = visibleOrderLines.first(where: { $0.id == store.selectedOrderLineId })

        let canChangeQty = store.isOnline && !store.isBusy && selectedLine != nil && normalizeOrderStatus(selectedLine?.status) != "cancelled"
        let canStorno = store.isOnline && !store.isBusy && selectedLine != nil && normalizeOrderStatus(selectedLine?.status) == "ordered"

        let openGross = visibleOrderLines.filter { isOpenOrderStatus($0.status) }.reduce(0.0) { $0 + Double($1.qty) * $1.price }
        let positionsCount = visibleOrderLines.reduce(0) { $0 + $1.qty }
        let newPositionsCount = visibleOrderLines.reduce(0) { partial, line in
            if normalizeOrderStatus(line.status) == "new" {
                return partial + line.qty
            }
            return partial
        }

        Group {
            if isTablet {
                VStack(spacing: POSSpacing.xs) {
                    HStack(spacing: POSSpacing.xs) {
                        orderPanel(
                            visibleOrderLines: visibleOrderLines,
                            canChangeQty: canChangeQty,
                            canStorno: canStorno,
                            openGross: openGross
                        )
                        .frame(maxWidth: .infinity)

                        catalogPanel(visibleProducts: visibleProducts)
                            .frame(maxWidth: .infinity)
                    }

                    tabletOrderDock(
                        positionsCount: positionsCount,
                        newPositionsCount: newPositionsCount
                    )
                }
            } else {
                VStack(spacing: POSSpacing.xs) {
                    catalogPanel(visibleProducts: visibleProducts)
                        .frame(maxHeight: .infinity)
                    orderPanel(
                        visibleOrderLines: visibleOrderLines,
                        canChangeQty: canChangeQty,
                        canStorno: canStorno,
                        openGross: openGross
                    )
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func tabletOrderDock(positionsCount: Int, newPositionsCount: Int) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tisch \(store.selectedTableId)")
                    .font(POSTypography.titleLarge)
                    .foregroundStyle(POSColor.slate050)
                Text(store.currentOrderCode.isEmpty ? "Bon -" : "Bon \(store.currentOrderCode)")
                    .font(POSTypography.labelLarge)
                    .foregroundStyle(POSColor.slate300)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(positionsCount) Positionen")
                    .font(POSTypography.titleMedium)
                    .foregroundStyle(POSColor.slate050)
                Text("\(newPositionsCount) Neu")
                    .font(POSTypography.labelLarge)
                    .foregroundStyle(newPositionsCount > 0 ? POSColor.amber500 : POSColor.slate300)
            }
        }
        .padding(POSSpacing.md)
        .background(POSColor.slate800.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.innerCard))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.innerCard)
                .stroke(POSColor.slate700.opacity(0.3), lineWidth: 1)
        )
    }

    private func catalogPanel(visibleProducts: [CatalogProductUI]) -> some View {
        VStack(alignment: .leading, spacing: POSSpacing.xs) {
            Text("Warenkatalog")
                .font(POSTypography.titleMedium)
                .foregroundStyle(POSColor.slate050)

            let catalogTiles: [CatalogGroupUI?] = [nil] + store.catalogGroups.map { Optional($0) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: POSSpacing.xs), count: 3), spacing: POSSpacing.xs) {
                ForEach(Array(catalogTiles.enumerated()), id: \.offset) { _, group in
                    let selected = group == nil ? store.selectedCatalogGroupId == nil : store.selectedCatalogGroupId == group?.id
                    Button {
                        store.selectCatalogGroup(group?.id)
                        store.requestQuickSync(includeCatalog: false)
                    } label: {
                        Text(group?.name ?? "Alle")
                            .font(POSTypography.labelLarge)
                            .foregroundStyle(POSColor.slate050)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, POSSpacing.sm)
                            .background(selected ? POSColor.indigo500.opacity(0.22) : POSColor.slate800.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: POSRadius.small)
                                    .stroke(selected ? POSColor.indigo500 : POSColor.slate700.opacity(0.45), lineWidth: selected ? 2 : 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
                    }
                    .buttonStyle(.plain)
                }
            }

            if visibleProducts.isEmpty {
                Spacer()
                Text("Keine Artikel in dieser Kategorie.")
                    .font(POSTypography.bodyMedium)
                    .foregroundStyle(POSColor.slate300)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: tileSpacing), count: 2), spacing: tileSpacing) {
                        ForEach(visibleProducts) { product in
                            ProductCardView(
                                product: product,
                                enabled: store.isOnline && !product.isBlocked,
                                showVatOnTile: store.showVatOnProductTiles,
                                showFullProductText: store.showFullProductText,
                                showPriceOnTile: store.showPriceOnProductTiles,
                                onTap: {
                                    onProductTap(product.id)
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding(POSSpacing.md)
        .background(POSColor.slate900.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.card)
                .stroke(POSColor.slate700.opacity(0.3), lineWidth: 1)
        )
    }

    private var tileSpacing: CGFloat {
        (store.showPriceOnProductTiles || store.showVatOnProductTiles) ? POSSpacing.xs : POSSpacing.xxs
    }

    private func orderPanel(visibleOrderLines: [OrderLineUI], canChangeQty: Bool, canStorno: Bool, openGross: Double) -> some View {
        VStack(alignment: .leading, spacing: POSSpacing.xs) {
            HStack {
                Text("Tisch \(store.selectedTableId)")
                    .font(POSTypography.titleMedium)
                    .foregroundStyle(POSColor.slate050)
                Spacer()
                Text(store.currentOrderCode.isEmpty ? "Bon -" : "Bon \(store.currentOrderCode)")
                    .font(POSTypography.labelLarge)
                    .foregroundStyle(POSColor.slate300)
            }

            OrderOverviewTabsView(selectedTab: store.orderOverviewTab, readyCount: readyNoticeCount) { nextTab in
                store.selectOrderOverviewTab(nextTab)
            }

            if store.orderOverviewTab == .orders {
                OrderCommandCenterView(
                    canSubmitOrder: store.isOnline && !visibleOrderLines.isEmpty && !store.isBusy,
                    canAdjustQty: canChangeQty,
                    canStorno: canStorno,
                    onSubmit: onSubmit,
                    onIncrease: onIncrease,
                    onDecrease: onDecrease,
                    onStorno: onCancelOrdered,
                    isBusy: store.isBusy
                )

                if visibleOrderLines.isEmpty {
                    Spacer()
                    Text("Noch keine Positionen.")
                        .font(POSTypography.bodyMedium)
                        .foregroundStyle(POSColor.slate300)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: POSSpacing.xs) {
                            ForEach(visibleOrderLines) { line in
                                OrderLineCardView(
                                    line: line,
                                    selected: store.selectedOrderLineId == line.id,
                                    onTap: {
                                        onSelectLine(line.id)
                                    }
                                )
                            }
                        }
                    }
                }

                OrderTotalFooter(totalGross: openGross, emphasizeAmount: isLargeTabletPortrait)
            } else {
                ReadyNoticeListView(
                    tableId: store.selectedTableId,
                    notices: readyNoticesForSelectedTable,
                    markSeen: {
                        store.markKitchenReadyNoticesSeenForTable(store.selectedTableId)
                    }
                )
            }
        }
        .padding(.horizontal, POSSpacing.md)
        .padding(.vertical, POSSpacing.sm)
        .background(POSColor.slate900.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.card)
                .stroke(POSColor.slate700.opacity(0.3), lineWidth: 1)
        )
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
}
