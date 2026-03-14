import Foundation

enum AppRoute {
    case pairing
    case login
    case tables
}

enum OrderOverviewTab: String, CaseIterable {
    case orders
    case ready
}

enum WorkTab: String, CaseIterable {
    case tables = "Tische"
    case orders = "Bestellen"
    case payment = "Zahlung"
    case split = "Split"
    case transfer = "Umsetzen"
}

enum PaymentMethod: String, CaseIterable, Identifiable {
    case cash = "Bar"
    case ec = "EC"
    case card = "Kreditkarte"

    var id: String { rawValue }

    var coreValue: String {
        rawValue
    }
}

enum TableStatus {
    case free
    case occupied
    case locked
}

struct TableCardUI: Identifiable {
    let id: Int
    let label: String
    let seats: Int
    let openAmount: String
    let status: TableStatus
}

struct CatalogGroupUI: Identifiable {
    let id: String
    let name: String
    let listId: String?
}

struct CatalogProductUI: Identifiable {
    let id: String
    let name: String
    let price: Double
    let taxRate: Double
    let groupId: String?
    let groupName: String?
    let isBlocked: Bool
    let blockReason: String
}

struct OrderLineUI: Identifiable {
    let id: String
    let productId: String
    let name: String
    let qty: Int
    let price: Double
    let taxRate: Double
    let status: String
    let kitchenReady: Bool
    let kitchenReadyAt: Int64
    let kitchenReadyBy: String
}

struct KitchenReadyNoticeUI: Identifiable {
    let id: String
    let eventId: String
    let tableId: Int
    let tableLabel: String
    let text: String
    let type: String
    let createdAt: Int64
    let eventCursor: Int64
    let terminalId: String
}
