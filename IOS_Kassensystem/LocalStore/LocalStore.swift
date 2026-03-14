import Foundation

struct DeviceCredentials: Codable {
    let deviceId: String
    let deviceKey: String
}

final class LocalStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadEndpoint(defaultHost: String = "127.0.0.1", defaultPort: Int = 8787) -> CoreEndpoint {
        let host = defaults.string(forKey: Keys.host)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = (host?.isEmpty == false ? host! : defaultHost)
        let savedPort = defaults.integer(forKey: Keys.port)
        let port = savedPort > 0 ? max(1, min(65535, savedPort)) : defaultPort
        return CoreEndpoint(host: normalizedHost, port: port)
    }

    func saveEndpoint(host: String, port: Int) {
        defaults.set(host.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.host)
        defaults.set(max(1, min(65535, port)), forKey: Keys.port)
    }

    func loadCoreApiToken() -> String {
        defaults.string(forKey: Keys.coreApiToken)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func saveCoreApiToken(_ token: String) {
        defaults.set(token.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.coreApiToken)
    }

    func loadDeviceCredentials() -> DeviceCredentials? {
        guard let id = defaults.string(forKey: Keys.deviceId)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let key = defaults.string(forKey: Keys.deviceKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty,
              !key.isEmpty else {
            return nil
        }
        return DeviceCredentials(deviceId: id, deviceKey: key)
    }

    func saveDeviceCredentials(deviceId: String, deviceKey: String) {
        defaults.set(deviceId.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.deviceId)
        defaults.set(deviceKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.deviceKey)
    }

    func loadSessionToken() -> String {
        defaults.string(forKey: Keys.sessionToken)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func saveSessionToken(_ token: String) {
        defaults.set(token.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.sessionToken)
    }

    func clearSessionToken() {
        defaults.removeObject(forKey: Keys.sessionToken)
    }

    func loadPendingSubmitOrderKeys() -> [String: String] {
        loadStringMap(forKey: Keys.pendingSubmitOrderKeys)
    }

    func savePendingSubmitOrderKeys(_ entries: [String: String]) {
        saveStringMap(entries, forKey: Keys.pendingSubmitOrderKeys)
    }

    func clearPendingSubmitOrderKeys() {
        defaults.removeObject(forKey: Keys.pendingSubmitOrderKeys)
    }

    func loadPendingPaymentKeys() -> [String: String] {
        loadStringMap(forKey: Keys.pendingPaymentKeys)
    }

    func savePendingPaymentKeys(_ entries: [String: String]) {
        saveStringMap(entries, forKey: Keys.pendingPaymentKeys)
    }

    func clearPendingPaymentKeys() {
        defaults.removeObject(forKey: Keys.pendingPaymentKeys)
    }

    func loadDarkMode(defaultValue: Bool = true) -> Bool {
        defaults.object(forKey: Keys.darkMode) == nil ? defaultValue : defaults.bool(forKey: Keys.darkMode)
    }

    func saveDarkMode(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.darkMode)
    }

    func loadShowVatOnProductTiles(defaultValue: Bool = false) -> Bool {
        defaults.object(forKey: Keys.showVatOnTiles) == nil ? defaultValue : defaults.bool(forKey: Keys.showVatOnTiles)
    }

    func saveShowVatOnProductTiles(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.showVatOnTiles)
    }

    func loadShowFullProductText(defaultValue: Bool = true) -> Bool {
        defaults.object(forKey: Keys.showFullProductText) == nil ? defaultValue : defaults.bool(forKey: Keys.showFullProductText)
    }

    func saveShowFullProductText(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.showFullProductText)
    }

    func loadShowPriceOnProductTiles(defaultValue: Bool = true) -> Bool {
        defaults.object(forKey: Keys.showPriceOnTiles) == nil ? defaultValue : defaults.bool(forKey: Keys.showPriceOnTiles)
    }

    func saveShowPriceOnProductTiles(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.showPriceOnTiles)
    }

    func loadPrintStornoInfoEnabled(defaultValue: Bool = true) -> Bool {
        defaults.object(forKey: Keys.printStornoInfo) == nil ? defaultValue : defaults.bool(forKey: Keys.printStornoInfo)
    }

    func savePrintStornoInfoEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.printStornoInfo)
    }

    func loadSyncCursor() -> Int64 {
        Int64(defaults.object(forKey: Keys.syncCursor) as? Int ?? 0)
    }

    func saveSyncCursor(_ cursor: Int64) {
        defaults.set(Int(cursor), forKey: Keys.syncCursor)
    }

    func loadKitchenNoticeCursor() -> Int64 {
        Int64(defaults.object(forKey: Keys.kitchenCursor) as? Int ?? 0)
    }

    func saveKitchenNoticeCursor(_ cursor: Int64) {
        defaults.set(Int(cursor), forKey: Keys.kitchenCursor)
    }

    func loadReadyLastSeenCursorByTable() -> [Int: Int64] {
        let raw = loadStringMap(forKey: Keys.readyLastSeenByTable)
        var mapped: [Int: Int64] = [:]
        raw.forEach { key, value in
            if let tableId = Int(key), let cursor = Int64(value), tableId > 0, cursor > 0 {
                mapped[tableId] = cursor
            }
        }
        return mapped
    }

    func saveReadyLastSeenCursorByTable(_ map: [Int: Int64]) {
        let serialized = Dictionary(uniqueKeysWithValues: map.map { (String($0.key), String($0.value)) })
        saveStringMap(serialized, forKey: Keys.readyLastSeenByTable)
    }

    func loadSeenReadyEventIds() -> [String] {
        guard let raw = defaults.array(forKey: Keys.seenReadyEventIds) as? [String] else {
            return []
        }
        return raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    func saveSeenReadyEventIds(_ ids: [String]) {
        defaults.set(ids, forKey: Keys.seenReadyEventIds)
    }

    private func loadStringMap(forKey key: String) -> [String: String] {
        guard let data = defaults.data(forKey: key) else {
            return [:]
        }
        do {
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            return decoded
                .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.value.isEmpty }
        } catch {
            return [:]
        }
    }

    private func saveStringMap(_ map: [String: String], forKey key: String) {
        if map.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        do {
            let data = try JSONEncoder().encode(map)
            defaults.set(data, forKey: key)
        } catch {
            defaults.removeObject(forKey: key)
        }
    }

    private enum Keys {
        static let host = "core_api_host"
        static let port = "core_api_port"
        static let coreApiToken = "core_api_token"
        static let deviceId = "device_id"
        static let deviceKey = "device_key"
        static let sessionToken = "session_token"
        static let pendingSubmitOrderKeys = "pending_submit_order_idempotency_keys"
        static let pendingPaymentKeys = "pending_payment_idempotency_keys"
        static let darkMode = "ui_dark_mode"
        static let showVatOnTiles = "ui_show_vat_on_product_tiles"
        static let showFullProductText = "ui_show_full_product_text"
        static let showPriceOnTiles = "ui_show_price_on_product_tiles"
        static let printStornoInfo = "ui_print_storno_info_enabled"
        static let syncCursor = "sync_cursor"
        static let kitchenCursor = "kitchen_notice_cursor"
        static let readyLastSeenByTable = "kitchen_ready_last_seen_cursor_by_table"
        static let seenReadyEventIds = "kitchen_ready_seen_event_ids"
    }
}
