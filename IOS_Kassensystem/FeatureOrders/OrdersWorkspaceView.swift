import SwiftUI

private let promoCatalogGroupId = "__promo__"

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
    @Namespace private var catalogSelectionNamespace
    @State private var catalogSearchQuery = ""
    @State private var isCatalogSearchPresented = false
    @FocusState private var isCatalogSearchFieldFocused: Bool

    var body: some View {
        let selectedCatalogGroupId = store.selectedCatalogGroupId
        let visibleProducts = filteredCatalogProducts(
            from: store.catalogProducts,
            selectedGroupId: selectedCatalogGroupId,
            query: catalogSearchQuery
        )

        let visibleOrderLines = store.currentOrderLines.filter { $0.qty > 0 && isVisibleOrderStatus($0.status) }
        let activeOrderLines = visibleOrderLines.filter { normalizeOrderStatus($0.status) != "cancelled" }
        let cancelledOrderLines = visibleOrderLines.filter {
            normalizeOrderStatus($0.status) == "cancelled" && normalizeCancelReason($0.cancelReason) != "schlemmer_block"
        }
        let schlemmerCancelledOrderLines = visibleOrderLines.filter {
            normalizeOrderStatus($0.status) == "cancelled" && normalizeCancelReason($0.cancelReason) == "schlemmer_block"
        }
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
                            activeOrderLines: activeOrderLines,
                            cancelledOrderLines: cancelledOrderLines,
                            schlemmerCancelledOrderLines: schlemmerCancelledOrderLines,
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

                    if !isCatalogSearchPresented {
                        orderPanel(
                            visibleOrderLines: visibleOrderLines,
                            activeOrderLines: activeOrderLines,
                            cancelledOrderLines: cancelledOrderLines,
                            schlemmerCancelledOrderLines: schlemmerCancelledOrderLines,
                            canChangeQty: canChangeQty,
                            canStorno: canStorno,
                            openGross: openGross
                        )
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(POSMotion.panel, value: isCatalogSearchPresented)
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
            HStack(spacing: POSSpacing.sm) {
                Text("Warenkatalog")
                    .font(POSTypography.titleMedium)
                    .foregroundStyle(POSColor.slate050)
                Spacer()
                Button {
                    let willOpen = !isCatalogSearchPresented
                    withAnimation(POSMotion.select) {
                        isCatalogSearchPresented = willOpen
                        if !willOpen {
                            catalogSearchQuery = ""
                        }
                    }
                    POSHaptics.selection()
                    if willOpen {
                        Task { @MainActor in
                            isCatalogSearchFieldFocused = true
                        }
                    } else {
                        isCatalogSearchFieldFocused = false
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(POSColor.slate050)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(POSColor.slate800.opacity(0.8))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(POSColor.slate700.opacity(0.6), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            if isCatalogSearchPresented {
                HStack(spacing: POSSpacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(POSColor.slate300)

                    TextField("Artikel suchen", text: $catalogSearchQuery)
                        .focused($isCatalogSearchFieldFocused)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(POSTypography.bodyMedium)
                        .foregroundStyle(POSColor.slate050)
                        .submitLabel(.search)

                    if !catalogSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            withAnimation(POSMotion.feedback) {
                                catalogSearchQuery = ""
                            }
                            POSHaptics.light()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(POSColor.slate300)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, POSSpacing.md)
                .padding(.vertical, POSSpacing.sm)
                .background(POSColor.slate800.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: POSRadius.small)
                        .stroke(POSColor.slate700.opacity(0.45), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            let promoFilter = CatalogGroupUI(id: promoCatalogGroupId, name: "Aktion", listId: nil)
            let catalogTiles: [CatalogGroupUI?] = [nil] + store.catalogGroups.map { Optional($0) } + [promoFilter]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: POSSpacing.xs), count: 3), spacing: POSSpacing.xs) {
                ForEach(Array(catalogTiles.enumerated()), id: \.offset) { _, group in
                    let selected = group == nil ? store.selectedCatalogGroupId == nil : store.selectedCatalogGroupId == group?.id
                    Button {
                        withAnimation(POSMotion.select) {
                            store.selectCatalogGroup(group?.id)
                        }
                        POSHaptics.selection()
                        store.requestQuickSync(includeCatalog: false)
                    } label: {
                        ZStack {
                            if selected {
                                RoundedRectangle(cornerRadius: POSRadius.small)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                POSColor.indigo500.opacity(0.28),
                                                POSColor.indigo400.opacity(0.22)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .matchedGeometryEffect(id: "catalog-group-pill", in: catalogSelectionNamespace)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: POSRadius.small)
                                            .stroke(POSColor.indigo500.opacity(0.92), lineWidth: 1.6)
                                    )
                                    .shadow(color: POSColor.indigo500.opacity(0.28), radius: 8, y: 3)
                            }

                            Text(group?.name ?? "Alle")
                                .font(POSTypography.labelLarge)
                                .foregroundStyle(POSColor.slate050)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, POSSpacing.sm)
                        }
                        .background(selected ? Color.clear : POSColor.slate800.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: POSRadius.small)
                                .stroke(selected ? Color.clear : POSColor.slate700.opacity(0.45), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(POSMotion.select, value: store.selectedCatalogGroupId)

            if visibleProducts.isEmpty {
                Spacer()
                Text(catalogSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Keine Artikel in dieser Kategorie."
                    : "Keine Treffer für „\(catalogSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines))“.")
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
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.97)),
                                    removal: .opacity.combined(with: .scale(scale: 0.99))
                                )
                            )
                        }
                    }
                    .animation(POSMotion.overlay, value: visibleProducts.map(\.id))
                }
                .scrollDismissesKeyboard(.interactively)
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

    private func orderPanel(
        visibleOrderLines: [OrderLineUI],
        activeOrderLines: [OrderLineUI],
        cancelledOrderLines: [OrderLineUI],
        schlemmerCancelledOrderLines: [OrderLineUI],
        canChangeQty: Bool,
        canStorno: Bool,
        openGross: Double
    ) -> some View {
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
                            ForEach(activeOrderLines) { line in
                                OrderLineCardView(
                                    line: line,
                                    selected: store.selectedOrderLineId == line.id,
                                    onTap: {
                                        onSelectLine(line.id)
                                    }
                                )
                            }

                            if !cancelledOrderLines.isEmpty {
                                OrderLineSectionHeaderView(title: "Stornos", count: cancelledOrderLines.count)
                                ForEach(cancelledOrderLines) { line in
                                    OrderLineCardView(
                                        line: line,
                                        selected: store.selectedOrderLineId == line.id,
                                        onTap: {
                                            onSelectLine(line.id)
                                        }
                                    )
                                }
                            }

                            if !schlemmerCancelledOrderLines.isEmpty {
                                OrderLineSectionHeaderView(title: "Schlemmer Block Storno", count: schlemmerCancelledOrderLines.count)
                                ForEach(schlemmerCancelledOrderLines) { line in
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

    private func normalizeCancelReason(_ reason: String?) -> String {
        reason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func filteredCatalogProducts(
        from products: [CatalogProductUI],
        selectedGroupId: String?,
        query: String
    ) -> [CatalogProductUI] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopedProducts = products.filter { product in
            guard let selectedGroupId, !selectedGroupId.isEmpty else {
                return true
            }
            if selectedGroupId == promoCatalogGroupId {
                return product.promoActive
            }
            return product.groupId == selectedGroupId
        }

        if trimmedQuery.isEmpty {
            return scopedProducts
        }

        let tokens = normalizedSearchTokens(from: trimmedQuery)
        guard !tokens.isEmpty else {
            return scopedProducts
        }

        return scopedProducts
            .compactMap { product -> (CatalogProductUI, Int)? in
                guard let score = searchScore(productName: product.name, tokens: tokens) else {
                    return nil
                }
                return (product, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    private func normalizedSearchTokens(from query: String) -> [String] {
        let folded = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)

        return folded
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
    }

    private func searchScore(productName: String, tokens: [String]) -> Int? {
        let normalizedName = normalizedSearchText(productName)
        let wordParts = normalizedName
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)

        var score = 0
        for token in tokens {
            if wordParts.contains(where: { $0.hasPrefix(token) }) {
                score += 130
            } else if normalizedName.contains(token) {
                score += 90
            } else if isSubsequence(token, in: normalizedName) {
                score += 55
            } else {
                return nil
            }
        }

        if normalizedName.hasPrefix(tokens.joined(separator: " ")) {
            score += 20
        }

        score += max(0, 24 - min(normalizedName.count, 24))
        return score
    }

    private func isSubsequence(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var needleIndex = needle.startIndex
        for character in haystack {
            if character == needle[needleIndex] {
                needle.formIndex(after: &needleIndex)
                if needleIndex == needle.endIndex {
                    return true
                }
            }
        }
        return false
    }
}

private struct OrderLineSectionHeaderView: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: POSSpacing.sm) {
            Text(title.uppercased())
                .font(POSTypography.labelLarge)
                .foregroundStyle(Color.adaptive(darkHex: 0xFFC2BA, lightHex: 0x8A2B22))
            Spacer()
            Text("\(count)")
                .font(POSTypography.labelMedium)
                .foregroundStyle(Color.adaptive(darkHex: 0xFFD6D1, lightHex: 0x7D2C27))
                .padding(.horizontal, POSSpacing.sm)
                .padding(.vertical, 2)
                .background(Color.adaptive(darkHex: 0x4A2D30, lightHex: 0xEED2CE))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.adaptive(darkHex: 0xD06C63, lightHex: 0xC2675E).opacity(0.75), lineWidth: 1)
                )
        }
        .padding(.horizontal, POSSpacing.sm)
        .padding(.top, POSSpacing.xs)
        .padding(.bottom, 2)
        .background(
            RoundedRectangle(cornerRadius: POSRadius.small)
                .fill(Color.adaptive(darkHex: 0x2B2630, lightHex: 0xF7ECEA).opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.small)
                .stroke(Color.adaptive(darkHex: 0xB8665D, lightHex: 0xD59289).opacity(0.48), lineWidth: 1)
        )
    }
}
