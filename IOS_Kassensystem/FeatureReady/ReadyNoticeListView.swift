import SwiftUI

struct ReadyNoticeListView: View {
    let tableId: Int
    let notices: [KitchenReadyNoticeUI]
    let markSeen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: POSSpacing.xs) {
            Text("Bereit für Tisch \(tableId)")
                .font(POSTypography.titleMedium)
                .foregroundStyle(POSColor.slate050)

            if notices.isEmpty {
                Spacer()
                Text("Noch keine Bereit-Meldungen.")
                    .font(POSTypography.bodyMedium)
                    .foregroundStyle(POSColor.slate300)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: POSSpacing.xs) {
                        ForEach(notices) { notice in
                            ReadyNoticeCard(notice: notice)
                        }
                    }
                }
            }
        }
        .onAppear {
            markSeen()
        }
    }
}

private struct ReadyNoticeCard: View {
    let notice: KitchenReadyNoticeUI

    var body: some View {
        HStack(alignment: .top, spacing: POSSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.type == "ticket-completed" ? "Alles bereit" : "Artikel bereit")
                    .font(POSTypography.labelLarge)
                    .foregroundStyle(POSColor.kitchenReadyOn)
                Text(notice.text)
                    .font(POSTypography.bodyMedium)
                    .foregroundStyle(POSColor.slate050)
                    .lineLimit(3)
                Text(timestampText)
                    .font(POSTypography.labelMedium)
                    .foregroundStyle(POSColor.slate300)
            }
            Spacer()
            Text(notice.tableLabel)
                .font(POSTypography.labelMedium)
                .foregroundStyle(POSColor.slate300)
                .lineLimit(1)
        }
        .padding(POSSpacing.sm)
        .background(POSColor.kitchenReady500.opacity(0.13))
        .overlay(
            RoundedRectangle(cornerRadius: POSRadius.small)
                .stroke(POSColor.kitchenReady500.opacity(0.56), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: POSRadius.small))
    }

    private var timestampText: String {
        guard notice.createdAt > 0 else { return "-" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(notice.createdAt) / 1000.0))
    }
}
