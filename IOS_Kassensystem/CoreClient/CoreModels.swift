import Foundation

struct PayloadRequest<T: Encodable>: Encodable {
    let payload: T
}

struct CoreHealthResponse: Decodable {
    let success: Bool
    let error: String?
    let service: String?
    let host: String?
    let port: Int?
}

struct CoreContractResponse: Decodable {
    let success: Bool
    let error: String?
    let version: Int?
    let contractVersion: String?
    let endpoints: CoreContractEndpoints?
    let commandNames: [String]
}

struct CoreContractEndpoints: Decodable {
    let read: [String]
    let auth: [String]
    let commands: [String]
}

struct CoreEventsResponse: Decodable {
    let success: Bool
    let error: String?
    let cursor: Int64?
    let hasMore: Bool
    let cursorReset: Bool
    let headCursor: Int64?
    let oldestCursor: Int64?
    let events: [CoreSyncEventDTO]
}

struct CoreKitchenNoticesResponse: Decodable {
    let success: Bool
    let error: String?
    let cursor: Int64?
    let hasMore: Bool
    let cursorReset: Bool
    let headCursor: Int64?
    let oldestCursor: Int64?
    let notices: [CoreKitchenNoticeDTO]
}

struct CoreSyncEventDTO: Decodable {
    let id: String?
    let cursor: Int64?
    let type: String?
    let createdAt: Int64?
    let payload: [String: JSONValue]?
}

struct CoreKitchenNoticeDTO: Decodable {
    let eventId: String?
    let eventCursor: Int64?
    let eventType: String?
    let schema: String?
    let kind: String?
    let text: String?
    let noticeText: String?
    let createdAt: Int64?
    let tableId: String?
    let tableLabel: String?
    let bonNr: String?
    let ticketId: String?
    let lineId: String?
    let lineName: String?
    let qty: Double?
    let doneBy: String?
    let terminalId: String?
    let targetScope: String?
    let targetClientIds: [String]
    let ticketCompleted: Bool?
    let lineCompleted: Bool?
}

struct PairingCreatePayload: Encodable {
    let expiresInMs: Int64?
    let createdBy: String?
}

struct PairingCreateResponse: Decodable {
    let success: Bool
    let error: String?
    let pairing: PairingData?
}

struct PairingData: Decodable {
    let pairingId: String?
    let pairingCode: String?
    let createdAt: Int64?
    let expiresAt: Int64?
    let qrText: String?
    let qrPayload: [String: JSONValue]?
}

struct PairingClaimPayload: Encodable {
    let pairingCode: String
    let device: DeviceDescriptor
}

struct DeviceDescriptor: Encodable {
    let id: String
    let name: String
    let platform: String
    let appVersion: String
    let model: String
}

struct PairingClaimResponse: Decodable {
    let success: Bool
    let error: String?
    let device: BoundDevice?
    let deviceKey: String?
    let pairing: PairingClaimResult?
}

struct PairingClaimResult: Decodable {
    let pairingId: String?
    let pairingCode: String?
    let pairedAt: Int64?
}

struct BoundDevice: Decodable {
    let bindingId: String?
    let deviceId: String?
    let deviceName: String?
    let status: String?
    let lastSeenAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case bindingId
        case deviceId
        case deviceName
        case status
        case lastSeenAt
        case binding_id
        case device_id
        case device_name
        case last_seen_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bindingId = try c.decodeIfPresent(String.self, forKey: .bindingId) ?? c.decodeIfPresent(String.self, forKey: .binding_id)
        deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId) ?? c.decodeIfPresent(String.self, forKey: .device_id)
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName) ?? c.decodeIfPresent(String.self, forKey: .device_name)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        lastSeenAt = try c.decodeIfPresent(Int64.self, forKey: .lastSeenAt) ?? c.decodeIfPresent(Int64.self, forKey: .last_seen_at)
    }
}

struct LoginPayload: Encodable {
    let deviceId: String
    let deviceKey: String
    let userId: String
    let pin: String
    let sessionTtlMs: Int64?
}

struct LoginResponse: Decodable {
    let success: Bool
    let error: String?
    let session: SessionData?
    let user: SessionUser?
    let device: BoundDevice?
}

struct SessionData: Decodable {
    let token: String?
    let sessionId: String?
    let createdAt: Int64?
    let expiresAt: Int64?
    let lastSeenAt: Int64?
    let businessDayAnchor: String?
}

struct SessionUser: Decodable {
    let id: String?
    let loginName: String?
    let displayName: String?
    let role: String?
    let mustChangePassword: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case login_name
        case display_name
        case must_change_password
        case loginName
        case displayName
        case mustChangePassword
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        loginName = try c.decodeIfPresent(String.self, forKey: .loginName) ?? c.decodeIfPresent(String.self, forKey: .login_name)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? c.decodeIfPresent(String.self, forKey: .display_name)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        mustChangePassword = try c.decodeIfPresent(Bool.self, forKey: .mustChangePassword) ?? c.decodeIfPresent(Bool.self, forKey: .must_change_password)
    }
}

struct SessionResponse: Decodable {
    let success: Bool
    let error: String?
    let session: SessionData?
    let user: SessionUser?
    let device: BoundDevice?
}

struct AuthFeaturesResponse: Decodable {
    let success: Bool
    let error: String?
    let valid: Bool?
    let features: [String: Bool]?
    let modules: [AuthFeatureModule]
}

struct AuthFeatureModule: Decodable {
    let key: String
    let name: String?
    let description: String?
    let active: Bool

    private enum CodingKeys: String, CodingKey {
        case key
        case name
        case description
        case active
        case featureKey
        case feature_key
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawKey = try c.decodeIfPresent(String.self, forKey: .key)
            ?? c.decodeIfPresent(String.self, forKey: .featureKey)
            ?? c.decodeIfPresent(String.self, forKey: .feature_key)
            ?? ""
        key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
    }
}

struct CoreCatalogResponse: Decodable {
    let success: Bool
    let error: String?
    let catalog: CatalogData?
}

struct CatalogData: Decodable {
    let lists: [CatalogListDTO]
    let groups: [CatalogGroupDTO]
    let products: [CatalogProductDTO]
}

struct CatalogListDTO: Decodable {
    let id: String?
    let name: String?
}

struct CatalogGroupDTO: Decodable {
    let id: String?
    let name: String?
    let listId: String?
}

struct CatalogProductDTO: Decodable {
    let id: String?
    let name: String?
    let price: Double?
    let taxRate: Double?
    let groupId: String?
    let listId: String?
    let printer: String?
    let isBlocked: Bool?
    let is_blocked: Bool?
    let is_blocked_flag: Bool?
    let blocked: Bool?
    let blockReason: String?
    let block_reason: String?
    let basePrice: Double?
    let base_price: Double?
    let promoEnabled: Bool?
    let promo_enabled: Bool?
    let actionPriceEnabled: Bool?
    let action_price_enabled: Bool?
    let promoApplied: Bool?
    let promo_applied: Bool?
    let promoPrice: Double?
    let promo_price: Double?
    let actionPrice: Double?
    let action_price: Double?

    init(
        id: String? = nil,
        name: String? = nil,
        price: Double? = nil,
        taxRate: Double? = nil,
        groupId: String? = nil,
        listId: String? = nil,
        printer: String? = nil,
        isBlocked: Bool? = nil,
        is_blocked: Bool? = nil,
        is_blocked_flag: Bool? = nil,
        blocked: Bool? = nil,
        blockReason: String? = nil,
        block_reason: String? = nil,
        basePrice: Double? = nil,
        base_price: Double? = nil,
        promoEnabled: Bool? = nil,
        promo_enabled: Bool? = nil,
        actionPriceEnabled: Bool? = nil,
        action_price_enabled: Bool? = nil,
        promoApplied: Bool? = nil,
        promo_applied: Bool? = nil,
        promoPrice: Double? = nil,
        promo_price: Double? = nil,
        actionPrice: Double? = nil,
        action_price: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.taxRate = taxRate
        self.groupId = groupId
        self.listId = listId
        self.printer = printer
        self.isBlocked = isBlocked
        self.is_blocked = is_blocked
        self.is_blocked_flag = is_blocked_flag
        self.blocked = blocked
        self.blockReason = blockReason
        self.block_reason = block_reason
        self.basePrice = basePrice
        self.base_price = base_price
        self.promoEnabled = promoEnabled
        self.promo_enabled = promo_enabled
        self.actionPriceEnabled = actionPriceEnabled
        self.action_price_enabled = action_price_enabled
        self.promoApplied = promoApplied
        self.promo_applied = promo_applied
        self.promoPrice = promoPrice
        self.promo_price = promo_price
        self.actionPrice = actionPrice
        self.action_price = action_price
    }
}

struct TablePlannerReadResponse: Decodable {
    let success: Bool
    let error: String?
    let planner: PlannerData?
    let tableLocks: [String: TableLockDTO]
}

struct PlannerData: Decodable {
    let rooms: [PlannerRoomDTO]
    let tables: [PlannerTableDTO]
    let reservations: [PlannerReservationDTO]
}

struct PlannerRoomDTO: Decodable {
    let id: String?
    let name: String?
}

struct PlannerTableDTO: Decodable {
    let id: String?
    let label: String?
    let room_id: String?
    let seats_max: Int?
    let locked: Bool?
}

struct PlannerReservationDTO: Decodable {
    let id: String?
    let table_id: String?
    let status: String?
    let start_at: Int64?
    let end_at: Int64?
}

struct TableLockDTO: Decodable {
    let reason: String?
    let note: String?
    let lockedAt: Int64?
    let lockedUntil: Int64?
    let lockedBy: String?
}

struct OrderStoreReadResponse: Decodable {
    let success: Bool
    let error: String?
    let store: OrderStoreDTO?
}

struct OrderStoreDTO: Decodable {
    let currentTable: String?
    let tableOrders: [String: TableOrderEntryDTO]
}

struct TableOrderEntryDTO: Decodable {
    let order: [OrderLineDTO]
    let orderHistory: [String]
    let appliedVouchers: [AppliedVoucherDTO]?
    let orderCode: String?
    let updatedAt: Int64?
    let lastOrderAt: Int64?
}

struct AppliedVoucherDTO: Decodable {
    let code: String?
    let amount: Double?
    let remaining: Double?
    let appliedAt: Int64?
}

struct OrderLineDTO: Decodable {
    let id: String?
    let productId: String?
    let name: String?
    let qty: Int?
    let price: Double?
    let taxRate: Double?
    let status: String?
    let kitchenReady: Bool?
    let kitchenReadyAt: Int64?
    let kitchenReadyBy: String?
    let basePrice: Double?
    let base_price: Double?
    let promoApplied: Bool?
    let promo_applied: Bool?
    let promoPrice: Double?
    let promo_price: Double?
    let cancelledReason: String?
    let cancelled_reason: String?
}

struct StatefulCommandResponse: Decodable {
    let success: Bool
    let error: String?
    let result: CoreCommandResult?
    let store: OrderStoreDTO?
    let activeTableId: String?
    let activeEntry: TableOrderEntryDTO?
    let idempotency: IdempotencyMeta?
}

struct CoreCommandResult: Decodable {
    let ok: Bool?
    let error: String?
    let value: [String: JSONValue]?
}

struct IdempotencyMeta: Decodable {
    let key: String?
    let replayed: Bool?
}

struct AddLinePayload: Encodable {
    let tableId: String
    let product: OrderProductPayload
    let newStatus: String

    init(tableId: String, product: OrderProductPayload, newStatus: String = "new") {
        self.tableId = tableId
        self.product = product
        self.newStatus = newStatus
    }
}

struct RemoveOneLinePayload: Encodable {
    let tableId: String
    let lineId: String
}

struct OrderProductPayload: Encodable {
    let id: String
    let name: String
    let price: Double
    let taxRate: Double
    let basePrice: Double?
    let promoApplied: Bool?
    let promoPrice: Double?

    init(
        id: String,
        name: String,
        price: Double,
        taxRate: Double,
        basePrice: Double? = nil,
        promoApplied: Bool? = nil,
        promoPrice: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.taxRate = taxRate
        self.basePrice = basePrice
        self.promoApplied = promoApplied
        self.promoPrice = promoPrice
    }
}

struct SubmitOrderPayload: Encodable {
    let tableId: String
}

struct SwitchTablePayload: Encodable {
    let nextTableId: String
}

struct TransferItemsPayload: Encodable {
    let sourceTableId: String
    let targetTableId: String
    let selectionEntries: [TransferSelectionEntryPayload]
}

struct TransferSelectionEntryPayload: Encodable {
    let lineId: String?
    let productId: String?
    let qty: Int
}

struct CancelOrderedLinePayload: Encodable {
    let tableId: String
    let lineId: String
    let sourceTicketId: String?
}

struct FinalizePaymentPayload: Encodable {
    let tableId: String
    let method: String
    let currentUserId: String?
}

struct FinalizeSplitPaymentPayload: Encodable {
    let tableId: String
    let method: String
    let splitSelection: [String: Int]
    let currentUserId: String?
}

struct VoucherApplyPayload: Encodable {
    let tableId: String
    let code: String
}

struct VoucherRemovePayload: Encodable {
    let tableId: String
    let code: String
}

struct SchlemmerPreviewPayload: Encodable {
    let tableId: String
    let type: String
    let selection: [String: Int]?
}

struct SchlemmerApplyPayload: Encodable {
    let tableId: String
    let type: String
    let selection: [String: Int]
}

struct CoreErrorEnvelope: Decodable {
    let success: Bool?
    let error: String?
    let result: CoreCommandResult?
}
