import SwiftUI

struct TransferPanelView: View {
    let isTablet: Bool
    let tables: [TableCardUI]
    let selectedTableId: Int
    let tableOrderLinesByTableId: [Int: [OrderLineUI]]
    let initialTargetTableId: Int?
    let isOnline: Bool
    let isBusy: Bool
    let onMoveAll: (Int) -> Void
    let onMoveSelection: (Int, [String: Int]) -> Void

    @State private var sourceTableId: Int
    @State private var targetTableId: Int?
    @State private var selectionByLineId: [String: Int] = [:]
    @State private var showSelectionDialog = false
    @State private var highlightedDropTableId: Int?
    @State private var expandedDropTableId: Int?
    @State private var dropPulseTableId: Int?

    init(
        isTablet: Bool,
        tables: [TableCardUI],
        selectedTableId: Int,
        tableOrderLinesByTableId: [Int: [OrderLineUI]],
        initialTargetTableId: Int?,
        isOnline: Bool,
        isBusy: Bool,
        onMoveAll: @escaping (Int) -> Void,
        onMoveSelection: @escaping (Int, [String: Int]) -> Void
    ) {
        self.isTablet = isTablet
        self.tables = tables
        self.selectedTableId = selectedTableId
        self.tableOrderLinesByTableId = tableOrderLinesByTableId
        self.initialTargetTableId = initialTargetTableId
        self.isOnline = isOnline
        self.isBusy = isBusy
        self.onMoveAll = onMoveAll
        self.onMoveSelection = onMoveSelection
        _sourceTableId = State(initialValue: selectedTableId)
    }

    var body: some View {
        let sortedTables = tables.sorted { $0.id < $1.id }

        ZStack {
            VStack(alignment: .leading, spacing: POSSpacing.md) {
                Text("Umsetzen")
                    .font(POSTypography.titleLarge)
                    .foregroundStyle(POSColor.slate050)

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: POSSpacing.xs), count: 3), spacing: POSSpacing.xs) {
                        ForEach(sortedTables) { table in
                            transferTableCard(table)
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

            if showSelectionDialog, let targetTableId {
                Color.black.opacity(0.52)
                    .ignoresSafeArea()
                    .transition(.opacity)

                transferSelectionDialog(targetTableId: targetTableId)
                    .padding(.horizontal, isTablet ? POSSpacing.md : POSSpacing.xxs)
                    .padding(.vertical, POSSpacing.sm)
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: showSelectionDialog)
        .onAppear {
            initializeSourceAndTarget(preferredSourceId: selectedTableId)
        }
        .onChange(of: selectedTableId) { _, next in
            initializeSourceAndTarget(preferredSourceId: next)
        }
    }

    private func transferTableCard(_ table: TableCardUI) -> some View {
        let canBeSource = canDragFromTable(table.id)
        let isSource = table.id == sourceTableId && canBeSource
        let canBeDropTarget = table.status != .locked
        let isDropTarget = table.id == highlightedDropTableId
        let isExpandedTarget = expandedDropTableId == table.id
        let isDropPulseTarget = dropPulseTableId == table.id

        let content = VStack(alignment: .leading, spacing: POSSpacing.xxs) {
            Text(table.label)
                .font(POSTypography.titleLarge)
                .foregroundStyle(POSColor.slate050)
                .lineLimit(1)

            Text(statusLabel(for: table.status))
                .font(POSTypography.labelLarge)
                .foregroundStyle(statusColor(for: table.status))
                .padding(.horizontal, POSSpacing.sm)
                .padding(.vertical, 2)
                .background(statusColor(for: table.status).opacity(0.2))
                .clipShape(Capsule())
                .lineLimit(1)

            Text(table.openAmount)
                .font(POSTypography.bodyLarge)
                .foregroundStyle(POSColor.slate300)
                .lineLimit(1)

        }
        .padding(POSSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: POSRadius.small)
                .fill(isSource ? POSColor.indigo500.opacity(0.2) : POSColor.slate800.opacity(0.56))
                .overlay {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: POSRadius.small)
                            .fill(POSColor.indigo500.opacity(0.14))
                    }
                    if isExpandedTarget || isDropPulseTarget {
                        RoundedRectangle(cornerRadius: POSRadius.small)
                            .fill(POSColor.indigo400.opacity(isDropPulseTarget ? 0.2 : 0.1))
                    }
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.small)
                .stroke(cardBorderColor(isSource: isSource, isDropTarget: isDropTarget, table: table), lineWidth: isDropTarget || isSource || isDropPulseTarget ? 2 : 1)
        )
        .shadow(color: (isDropTarget || isExpandedTarget || isDropPulseTarget) ? POSColor.indigo500.opacity(0.48) : .clear, radius: isDropPulseTarget ? 20 : 16)
        .scaleEffect(isDropPulseTarget ? 1.08 : (isExpandedTarget ? 1.045 : 1))
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isExpandedTarget)
        .animation(.spring(response: 0.2, dampingFraction: 0.68), value: isDropPulseTarget)

        if canBeSource {
            return AnyView(
                content
                    .draggable("table:\(table.id)") {
                        compactDragPreview(tableLabel: table.label)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        handleTableDrop(onTargetTableId: table.id, items: items)
                    } isTargeted: { targeted in
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                            highlightedDropTableId = targeted ? table.id : (highlightedDropTableId == table.id ? nil : highlightedDropTableId)
                            expandedDropTableId = targeted ? table.id : (expandedDropTableId == table.id ? nil : expandedDropTableId)
                        }
                    }
            )
        }

        if canBeDropTarget {
            return AnyView(
                content
                    .dropDestination(for: String.self) { items, _ in
                        handleTableDrop(onTargetTableId: table.id, items: items)
                    } isTargeted: { targeted in
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                            highlightedDropTableId = targeted ? table.id : (highlightedDropTableId == table.id ? nil : highlightedDropTableId)
                            expandedDropTableId = targeted ? table.id : (expandedDropTableId == table.id ? nil : expandedDropTableId)
                        }
                    }
            )
        }

        return AnyView(content.opacity(table.status == .locked ? 0.72 : 1.0))
    }

    private func transferSelectionDialog(targetTableId: Int) -> some View {
        let sourceLines = orderedLines(for: sourceTableId)
        let targetLines = orderedLines(for: targetTableId)
        let previewLines = buildTransferPreviewLines(sourceLines: sourceLines)

        return VStack(alignment: .leading, spacing: POSSpacing.md) {
            HStack(alignment: .center, spacing: POSSpacing.sm) {
                HStack(spacing: POSSpacing.sm) {
                    transferRouteBadge(
                        label: "QUELLE",
                        value: "Tisch \(sourceTableId)",
                        tint: POSColor.emerald500
                    )

                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(POSColor.slate300)

                    transferRouteBadge(
                        label: "ZIEL",
                        value: "Tisch \(targetTableId)",
                        tint: POSColor.indigo500
                    )
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: POSSpacing.sm) {
                    Button {
                        withAnimation(POSMotion.quick) {
                            showSelectionDialog = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(POSColor.indigo400)
                            .frame(width: 38, height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(POSColor.slate800.opacity(0.92))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(POSColor.indigo500.opacity(0.42), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(width: 44)
            }

            if isTablet {
                HStack(spacing: POSSpacing.sm) {
                    sourceSelectionPanel(sourceLines: sourceLines)
                        .frame(maxWidth: .infinity)
                    targetSelectionPanel(targetLines: targetLines, previewLines: previewLines)
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: POSSpacing.sm) {
                    sourceSelectionPanel(sourceLines: sourceLines)
                    targetSelectionPanel(targetLines: targetLines, previewLines: previewLines)
                }
            }

            Button("Umsetzen") {
                onMoveSelection(targetTableId, selectionByLineId)
                withAnimation(POSMotion.quick) {
                    showSelectionDialog = false
                }
            }
            .buttonStyle(POSPrimaryButtonStyle())
            .disabled(!isOnline || isBusy || selectionByLineId.isEmpty)
        }
        .padding(POSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: POSRadius.card + 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.card + 4, style: .continuous)
                .stroke(POSColor.slate700.opacity(0.36), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 24, y: 8)
    }

    private func transferRouteBadge(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(POSTypography.labelMedium)
                .foregroundStyle(POSColor.slate050)
            Text(value)
                .font(POSTypography.titleLarge)
                .foregroundStyle(POSColor.slate050)
                .lineLimit(1)
        }
        .padding(.horizontal, POSSpacing.md)
        .padding(.vertical, POSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.innerCard, style: .continuous)
                .stroke(tint.opacity(0.75), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.innerCard, style: .continuous))
    }

    private func sourceSelectionPanel(sourceLines: [OrderLineUI]) -> some View {
        VStack(alignment: .leading, spacing: POSSpacing.xs) {
            HStack {
                Text("Quelle")
                    .font(POSTypography.titleMedium)
                    .foregroundStyle(POSColor.slate050)
                Spacer()
                Button {
                    selectionByLineId = Dictionary(uniqueKeysWithValues: sourceLines.map { ($0.id, $0.qty) })
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(POSColor.slate050)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(POSColor.slate800.opacity(0.9))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(POSColor.slate700.opacity(0.68), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(sourceLines.isEmpty)
                .opacity(sourceLines.isEmpty ? 0.55 : 1)
            }

            if sourceLines.isEmpty {
                VStack {
                    Spacer(minLength: 0)
                    Text("Keine bestellten Positionen.")
                        .font(POSTypography.bodyMedium)
                        .foregroundStyle(POSColor.slate300)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(POSColor.slate800.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: POSRadius.notice))
            } else {
                ScrollView {
                    VStack(spacing: POSSpacing.sm) {
                        ForEach(sourceLines) { line in
                            sourceSelectionRow(line: line)
                        }
                    }
                }
                .frame(minHeight: 220)
            }
        }
        .padding(POSSpacing.sm)
        .background(POSColor.slate800.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.notice))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.notice)
                .stroke(POSColor.slate700.opacity(0.62), lineWidth: 1)
        )
    }

    private func targetSelectionPanel(targetLines: [OrderLineUI], previewLines: [TransferPreviewLine]) -> some View {
        VStack(alignment: .leading, spacing: POSSpacing.xs) {
            Text("Ziel (aktueller Inhalt + Vorschau)")
                .font(POSTypography.titleMedium)
                .foregroundStyle(POSColor.slate050)

            if targetLines.isEmpty && previewLines.isEmpty {
                VStack {
                    Spacer(minLength: 0)
                    Text("Zieltisch ist aktuell leer.")
                        .font(POSTypography.bodyMedium)
                        .foregroundStyle(POSColor.slate300)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(POSColor.slate800.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: POSRadius.notice))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: POSSpacing.sm) {
                        if !targetLines.isEmpty {
                            Text("Aktuell am Ziel")
                                .font(POSTypography.labelMedium)
                                .foregroundStyle(POSColor.slate300)
                                .padding(.horizontal, 2)

                            ForEach(targetLines) { line in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(line.qty)x \(line.name)")
                                            .font(POSTypography.titleMedium)
                                            .foregroundStyle(POSColor.slate050)
                                            .lineLimit(2)
                                        Text(String(format: "%.2f EUR / Stk", locale: Locale(identifier: "de_DE"), line.price))
                                            .font(POSTypography.labelMedium)
                                            .foregroundStyle(POSColor.slate300)
                                    }
                                    Spacer()
                                    Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), Double(line.qty) * line.price))
                                        .font(POSTypography.bodyLarge)
                                        .foregroundStyle(POSColor.slate050)
                                }
                                .padding(POSSpacing.md)
                                .background(POSColor.slate800.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
                            }
                        }

                        if !previewLines.isEmpty {
                            Text("Vorschau Umsetzen")
                                .font(POSTypography.labelMedium)
                                .foregroundStyle(POSColor.indigo500)
                                .padding(.horizontal, 2)

                            ForEach(previewLines) { preview in
                                HStack(spacing: POSSpacing.sm) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("+\(preview.qty)x \(preview.name)")
                                            .font(POSTypography.titleMedium)
                                            .foregroundStyle(POSColor.slate050)
                                            .lineLimit(2)
                                        Text("Neu aus Tisch \(sourceTableId)")
                                            .font(POSTypography.labelMedium)
                                            .foregroundStyle(POSColor.indigo400)
                                    }
                                    Spacer()
                                    Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), preview.totalPrice))
                                        .font(POSTypography.bodyLarge)
                                        .foregroundStyle(POSColor.slate050)

                                    Button {
                                        selectionByLineId.removeValue(forKey: preview.sourceLineId)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(POSColor.indigo400)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(POSSpacing.md)
                                .background(POSColor.indigo500.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: POSRadius.small)
                                        .stroke(POSColor.indigo500.opacity(0.9), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
                            }
                        }
                    }
                }
                .frame(minHeight: 220)
            }
        }
        .padding(POSSpacing.sm)
        .background(POSColor.slate800.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.notice))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.notice)
                .stroke(POSColor.slate700.opacity(0.62), lineWidth: 1)
        )
    }

    private func sourceSelectionRow(line: OrderLineUI) -> some View {
        let selectedQty = selectionByLineId[line.id] ?? 0

        return HStack(spacing: POSSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(line.qty)x \(line.name)")
                    .font(POSTypography.titleMedium)
                    .foregroundStyle(POSColor.slate050)
                    .lineLimit(2)
                Text("Ausgewählt: \(selectedQty) / \(line.qty)")
                    .font(POSTypography.labelMedium)
                    .foregroundStyle(POSColor.slate300)
            }
            Spacer()
            Text(String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), line.price))
                .font(POSTypography.bodyLarge)
                .foregroundStyle(POSColor.slate050)

            HStack(spacing: POSSpacing.xs) {
                Button("-") {
                    let next = max(0, selectedQty - 1)
                    if next == 0 {
                        selectionByLineId.removeValue(forKey: line.id)
                    } else {
                        selectionByLineId[line.id] = next
                    }
                }
                .buttonStyle(StepperButtonStyle())

                Text("\(selectedQty)")
                    .font(POSTypography.titleMedium)
                    .foregroundStyle(POSColor.slate050)
                    .frame(width: 28)

                Button("+") {
                    let next = min(line.qty, selectedQty + 1)
                    selectionByLineId[line.id] = next
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

    private func initializeSourceAndTarget(preferredSourceId: Int) {
        let resolvedSourceId = resolveSourceTableId(preferredSourceId: preferredSourceId)
        sourceTableId = resolvedSourceId

        if let initialTargetTableId, initialTargetTableId != resolvedSourceId, tables.contains(where: { $0.id == initialTargetTableId && $0.status != .locked }) {
            targetTableId = initialTargetTableId
        } else {
            targetTableId = tables.first(where: { $0.id != resolvedSourceId && $0.status != .locked })?.id
        }

        selectionByLineId = [:]
        highlightedDropTableId = nil
        expandedDropTableId = nil
        dropPulseTableId = nil
    }

    private func resolveSourceTableId(preferredSourceId: Int) -> Int {
        if canDragFromTable(preferredSourceId) {
            return preferredSourceId
        }

        if let firstDragSource = tables
            .sorted(by: { $0.id < $1.id })
            .first(where: { canDragFromTable($0.id) }) {
            return firstDragSource.id
        }

        return preferredSourceId
    }

    private func canDragFromTable(_ tableId: Int) -> Bool {
        guard let table = tables.first(where: { $0.id == tableId }) else {
            return false
        }
        return table.status == .occupied
    }

    private func parseDraggedTableId(_ payload: String) -> Int? {
        guard payload.hasPrefix("table:") else {
            return nil
        }
        return Int(payload.dropFirst(6))
    }

    private func handleTableDrop(onTargetTableId targetTableId: Int, items: [String]) -> Bool {
        guard let droppedSourceTableId = items.compactMap(parseDraggedTableId).first else {
            return false
        }
        guard droppedSourceTableId != targetTableId else {
            return false
        }
        guard canDragFromTable(droppedSourceTableId) else {
            return false
        }
        guard tables.contains(where: { $0.id == targetTableId && $0.status != .locked }) else {
            return false
        }

        withAnimation(.spring(response: 0.2, dampingFraction: 0.68)) {
            sourceTableId = droppedSourceTableId
            expandedDropTableId = targetTableId
            dropPulseTableId = targetTableId
            highlightedDropTableId = targetTableId
        }

        Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    self.targetTableId = targetTableId
                    selectionByLineId = [:]
                    showSelectionDialog = true
                }
                withAnimation(POSMotion.quick) {
                    highlightedDropTableId = nil
                    expandedDropTableId = nil
                }
            }

            try? await Task.sleep(nanoseconds: 170_000_000)
            await MainActor.run {
                withAnimation(POSMotion.quick) {
                    dropPulseTableId = nil
                }
            }
        }

        return true
    }

    private func compactDragPreview(tableLabel: String) -> some View {
        Text(tableLabel)
            .font(POSTypography.titleMedium)
            .foregroundStyle(POSColor.slate050)
            .lineLimit(1)
            .padding(.horizontal, POSSpacing.md)
            .padding(.vertical, POSSpacing.sm)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: POSRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: POSRadius.small, style: .continuous)
                    .stroke(POSColor.indigo500.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: POSColor.indigo500.opacity(0.28), radius: 10, y: 4)
    }

    private func buildTransferPreviewLines(sourceLines: [OrderLineUI]) -> [TransferPreviewLine] {
        sourceLines.compactMap { line in
            let selectedQty = selectionByLineId[line.id] ?? 0
            guard selectedQty > 0 else {
                return nil
            }
            return TransferPreviewLine(
                sourceLineId: line.id,
                name: line.name,
                qty: selectedQty,
                unitPrice: line.price
            )
        }
    }

    private func orderedLines(for tableId: Int) -> [OrderLineUI] {
        (tableOrderLinesByTableId[tableId] ?? [])
            .filter { $0.qty > 0 && normalizeOrderStatus($0.status) == "ordered" }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func cardBorderColor(isSource: Bool, isDropTarget: Bool, table: TableCardUI) -> Color {
        if isDropTarget {
            return POSColor.indigo500
        }
        if isSource {
            return POSColor.indigo500
        }
        if table.status == .locked {
            return POSColor.red500.opacity(0.76)
        }
        return POSColor.slate700.opacity(0.72)
    }

    private func statusLabel(for status: TableStatus) -> String {
        switch status {
        case .free:
            return "Frei"
        case .occupied:
            return "Belegt"
        case .locked:
            return "Gesperrt"
        }
    }

    private func statusColor(for status: TableStatus) -> Color {
        switch status {
        case .free:
            return POSColor.emerald500
        case .occupied:
            return POSColor.amber500
        case .locked:
            return POSColor.red500
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

private struct TransferPreviewLine: Identifiable {
    let sourceLineId: String
    let name: String
    let qty: Int
    let unitPrice: Double

    var id: String { sourceLineId }
    var totalPrice: Double { Double(qty) * unitPrice }
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
