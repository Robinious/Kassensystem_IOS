import SwiftUI

struct TablesGridPanel: View {
    let tables: [TableCardUI]
    let selectedTableId: Int
    let unreadReadyCountByTable: [Int: Int]
    let onSelectTable: (Int) -> Void
    let onOpenTransfer: () -> Void

    var body: some View {
        VStack(spacing: POSSpacing.sm) {
            HStack {
                Text("Tische")
                    .font(POSTypography.titleMedium)
                    .foregroundStyle(POSColor.slate050)
                Spacer()
                Button("Umsetzen") {
                    POSHaptics.selection()
                    onOpenTransfer()
                }
                .buttonStyle(POSPrimaryButtonStyle())
                .frame(width: 120)
            }

            Text("Tippe auf einen Tisch, um direkt in die Bestellung zu wechseln.")
                .font(POSTypography.labelMedium)
                .foregroundStyle(POSColor.slate300)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: POSSpacing.xs), count: 3), spacing: POSSpacing.xs) {
                    ForEach(tables) { table in
                        TableCardView(
                            table: table,
                            selected: table.id == selectedTableId,
                            unreadReadyCount: unreadReadyCountByTable[table.id] ?? 0,
                            onTap: {
                                onSelectTable(table.id)
                            }
                        )
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
}

private struct TableCardView: View {
    let table: TableCardUI
    let selected: Bool
    let unreadReadyCount: Int
    let onTap: () -> Void

    @State private var previousUnreadCount: Int = 0
    @State private var pulse = false
    @State private var tapBounce = false

    private var statusColor: Color {
        switch table.status {
        case .free:
            return POSColor.emerald500
        case .occupied:
            return POSColor.amber500
        case .locked:
            return POSColor.red500
        }
    }

    var body: some View {
        let hasUnreadReady = unreadReadyCount > 0

        Button {
            withAnimation(POSMotion.feedback) {
                tapBounce = true
            }
            POSHaptics.light()
            onTap()
            Task {
                try? await Task.sleep(nanoseconds: 160_000_000)
                await MainActor.run {
                    withAnimation(POSMotion.feedback) {
                        tapBounce = false
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: POSSpacing.xs) {
                HStack(alignment: .top) {
                    Text(table.label)
                        .font(POSTypography.titleMedium)
                        .foregroundStyle(POSColor.slate050)
                        .lineLimit(1)
                        .alignmentGuide(.top) { dimensions in
                            dimensions[.top] - 2
                        }
                    Spacer(minLength: POSSpacing.xs)

                    HStack(alignment: .top, spacing: POSSpacing.xs) {
                        if hasUnreadReady {
                            Text("\(unreadReadyCount)")
                                .font(POSTypography.labelMedium)
                                .foregroundStyle(POSColor.kitchenReadyOn)
                                .padding(.horizontal, POSSpacing.sm)
                                .padding(.vertical, 2)
                                .background(POSColor.kitchenReady500.opacity(0.28))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(POSColor.kitchenReady500.opacity(0.95), lineWidth: 1)
                                )
                                .scaleEffect(pulse ? 1.12 : 1)
                                .opacity(pulse ? 1 : 0.92)
                                .animation(POSMotion.pulse, value: pulse)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(table.seats)")
                                .font(POSTypography.labelMedium)
                        }
                        .foregroundStyle(POSColor.slate300)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }

                HStack(spacing: POSSpacing.xs) {
                    Text(statusText(table.status))
                        .font(POSTypography.labelMedium)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, POSSpacing.sm)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.2))
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Text(table.openAmount)
                    .font(POSTypography.bodyLarge)
                    .foregroundStyle(table.status == .locked ? POSColor.red500 : POSColor.slate050)
                    .lineLimit(1)
            }
            .padding(POSSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(cardBackground(hasUnreadReady: hasUnreadReady))
            .overlay(
                RoundedRectangle(cornerRadius: POSRadius.small)
                    .stroke(selected ? POSColor.indigo500 : POSColor.slate700.opacity(0.62), lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
            .scaleEffect(tapBounce ? 0.985 : 1.0)
            .shadow(color: tapBounce ? POSColor.indigo500.opacity(0.28) : .clear, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(table.status == .locked)
        .animation(POSMotion.select, value: selected)
        .onAppear {
            previousUnreadCount = unreadReadyCount
        }
        .onChange(of: unreadReadyCount) { _, next in
            if next > previousUnreadCount && next > 0 {
                pulse = true
                Task {
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    await MainActor.run {
                        pulse = false
                    }
                }
            }
            previousUnreadCount = next
        }
    }

    private func cardBackground(hasUnreadReady: Bool) -> some View {
        RoundedRectangle(cornerRadius: POSRadius.small)
            .fill(POSColor.slate800.opacity(0.58))
            .overlay {
                if hasUnreadReady {
                    RoundedRectangle(cornerRadius: POSRadius.small)
                        .fill(POSColor.kitchenReady500.opacity(pulse ? 0.24 : 0.13))
                }
            }
    }

    private func statusText(_ status: TableStatus) -> String {
        switch status {
        case .free:
            return "Frei"
        case .occupied:
            return "Belegt"
        case .locked:
            return "Gesperrt"
        }
    }
}
