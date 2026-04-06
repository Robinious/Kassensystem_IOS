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
    case voucher = "Gutschein"
    case schlemmer = "Schlemmer Block"
}

enum SchlemmerBlockTypeUI: String, CaseIterable, Identifiable {
    case twoForOne = "2:1"
    case fourForTwo = "4:2"
    case family = "Familie"

    var id: String { rawValue }

    var coreValue: String {
        switch self {
        case .twoForOne:
            return "2:1"
        case .fourForTwo:
            return "4:2"
        case .family:
            return "familie"
        }
    }
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
    let regularPrice: Double
    let promoEnabled: Bool
    let promoPrice: Double?
    let promoActive: Bool
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
    let basePrice: Double
    let promoApplied: Bool
    let promoPrice: Double?
    let taxRate: Double
    let status: String
    let cancelReason: String
    let kitchenReady: Bool
    let kitchenReadyAt: Int64
    let kitchenReadyBy: String
}

struct AppliedVoucherUI: Identifiable {
    var id: String { code }
    let code: String
    let amount: Double
    let remaining: Double
    let appliedAt: Int64
}

struct SchlemmerEligibleLineUI: Identifiable {
    var id: String { lineId }
    let lineId: String
    let productId: String
    let name: String
    let qty: Int
    let unitPrice: Double
    let isKidsMeal: Bool
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
