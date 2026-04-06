import Foundation
import SwiftUI
import UIKit
import Combine

@MainActor
final class AppStore: ObservableObject {
    private let featureKeySchlemmerBlockModule = "schlemmer_block_module"

    private struct PairingQrScanPayload {
        let host: String?
        let port: Int?
        let pairingCode: String?
        let expiresAt: Int64?
    }

    private let autoSyncIntervalNs: UInt64 = 2_000_000_000
    private let autoConnectivityIntervalTicks = 3
    private let autoTableRefreshIntervalTicks = 3
    private let autoCatalogRefreshIntervalTicks = 15
    private let autoEventsLimit = 120
    private let autoQuickSyncMinIntervalMs: Int64 = 750
    private let kitchenReadyDedupeLimit = 480
    private let kitchenReadyMessagesPerTableMax = 120

    private let requiredCommandPaths: Set<String> = [
        "/api/core/v1/commands/orders/add-line",
        "/api/core/v1/commands/orders/remove-one-line",
        "/api/core/v1/commands/orders/submit",
        "/api/core/v1/commands/orders/switch-table",
        "/api/core/v1/commands/orders/transfer-items",
        "/api/core/v1/commands/orders/cancel-ordered-line",
        "/api/core/v1/commands/payments/finalize",
        "/api/core/v1/commands/payments/finalize-split",
        "/api/core/v1/commands/vouchers/apply",
        "/api/core/v1/commands/vouchers/remove",
        "/api/core/v1/commands/vouchers/schlemmer-preview",
        "/api/core/v1/commands/vouchers/schlemmer-apply"
    ]

    private let localStore: LocalStore
    private lazy var repository: CoreAPIClient = {
        CoreAPIClient(
            endpoint: endpoint,
            coreTokenProvider: { [weak self] in self?.coreApiToken ?? "" },
            sessionTokenProvider: { [weak self] in self?.sessionToken ?? "" }
        )
    }()

    private var endpoint: CoreEndpoint
    private var coreApiToken: String
    private var sessionToken: String

    private var latestOrderStore: OrderStoreDTO?
    private var latestPlanner: PlannerData?
    private var latestTableLocks: [String: TableLockDTO] = [:]
    private var schlemmerPreviewRequestGeneration: UInt64 = 0

    private var syncCursor: Int64
    private var kitchenNoticeCursor: Int64
    private var seenReadyEventIdsOrder: [String]
    private var seenReadyEventIdsSet: Set<String>
    private var seenReadyEventIdsDirty = false

    private var autoSyncTask: Task<Void, Never>?
    private var autoSyncStarted = false
    private var lastQuickSyncAt: Int64 = 0
    private var pendingSubmitOrderIdempotencyKeysByTableId: [String: String]
    private var pendingPaymentIdempotencyKeysByScope: [String: String]

    @Published var route: AppRoute = .pairing
    @Published var activeWorkTab: WorkTab = .orders

    @Published var isDarkMode: Bool
    @Published var showVatOnProductTiles: Bool
    @Published var showFullProductText: Bool
    @Published var showPriceOnProductTiles: Bool
    @Published var printStornoInfoEnabled: Bool

    @Published var isOnline: Bool = false
    @Published var isBusy: Bool = false
    @Published var hostAddress: String
    @Published var hostPort: Int
    @Published var apiReachable: Bool = false
    @Published var requiredCommandsReady: Bool = false
    @Published var missingCommandPaths: [String] = []

    @Published var connectedDevices: Int = 0
    @Published var pairCode: String?
    @Published var pairCodeInput: String = ""
    @Published var pairCodeValidUntil: String?
    @Published var pairedDeviceLabel: String?
    @Published var pairedDeviceId: String?
    @Published var isPaired: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var activeUserId: String?
    @Published var activeUserDisplayName: String?
    @Published var isSchlemmerBlockModuleEnabled: Bool = false

    @Published var offlineQueueCount: Int = 0

    @Published var selectedTableId: Int = 1
    @Published var currentOrderCode: String = ""
    @Published var currentOrderLines: [OrderLineUI] = []
    @Published var tableOrderLinesByTableId: [Int: [OrderLineUI]] = [:]
    @Published var currentAppliedVouchers: [AppliedVoucherUI] = []
    @Published var appliedVouchersByTableId: [Int: [AppliedVoucherUI]] = [:]
    @Published var kitchenReadyNoticesByTable: [Int: [KitchenReadyNoticeUI]] = [:]
    @Published var kitchenReadyLastSeenCursorByTable: [Int: Int64]
    @Published var orderOverviewTab: OrderOverviewTab = .orders
    @Published var selectedOrderLineId: String?
    @Published var voucherCodeInput: String = ""

    @Published var schlemmerType: SchlemmerBlockTypeUI = .twoForOne
    @Published var schlemmerEligibleLines: [SchlemmerEligibleLineUI] = []
    @Published var schlemmerSelection: [String: Int] = [:]
    @Published var schlemmerAutoSelection: [String: Int] = [:]
    @Published var schlemmerRequiredFoodUnits: Int = 0
    @Published var schlemmerAvailableUnits: Int = 0
    @Published var schlemmerRequiredSelectionCount: Int = 0
    @Published var schlemmerSelectedUnits: Int = 0
    @Published var schlemmerLastErrorCode: String?
    @Published var schlemmerPreviewInFlight: Bool = false
    @Published var schlemmerPreviewShowLoader: Bool = false

    @Published var catalogGroups: [CatalogGroupUI] = []
    @Published var selectedCatalogGroupId: String?
    @Published var catalogProducts: [CatalogProductUI] = []

    @Published var tables: [TableCardUI] = [
        TableCardUI(id: 1, label: "Tisch 1", seats: 4, openAmount: "14,00 EUR", status: .occupied),
        TableCardUI(id: 2, label: "Tisch 2", seats: 2, openAmount: "0,00 EUR", status: .free),
        TableCardUI(id: 3, label: "Tisch 3", seats: 6, openAmount: "33,50 EUR", status: .occupied),
        TableCardUI(id: 4, label: "Tisch 4", seats: 4, openAmount: "Gesperrt", status: .locked),
        TableCardUI(id: 5, label: "Tisch 5", seats: 4, openAmount: "7,00 EUR", status: .occupied),
        TableCardUI(id: 6, label: "Tisch 6", seats: 4, openAmount: "0,00 EUR", status: .free)
    ]

    @Published var noticeMessage: String?

    var visibleWorkTabs: [WorkTab] {
        var tabs: [WorkTab] = [.tables, .orders, .payment, .split, .transfer, .voucher]
        if isSchlemmerBlockModuleEnabled {
            tabs.append(.schlemmer)
        }
        return tabs
    }

    init(localStore: LocalStore? = nil) {
        let resolvedLocalStore = localStore ?? LocalStore()
        self.localStore = resolvedLocalStore

        let endpoint = resolvedLocalStore.loadEndpoint()
        self.endpoint = endpoint
        self.coreApiToken = resolvedLocalStore.loadCoreApiToken()
        self.sessionToken = resolvedLocalStore.loadSessionToken()

        self.isDarkMode = resolvedLocalStore.loadDarkMode()
        self.showVatOnProductTiles = resolvedLocalStore.loadShowVatOnProductTiles()
        self.showFullProductText = resolvedLocalStore.loadShowFullProductText()
        self.showPriceOnProductTiles = resolvedLocalStore.loadShowPriceOnProductTiles()
        self.printStornoInfoEnabled = resolvedLocalStore.loadPrintStornoInfoEnabled()

        self.hostAddress = endpoint.host
        self.hostPort = endpoint.port

        self.syncCursor = resolvedLocalStore.loadSyncCursor()
        self.kitchenNoticeCursor = resolvedLocalStore.loadKitchenNoticeCursor()

        let seenIds = resolvedLocalStore.loadSeenReadyEventIds()
        self.seenReadyEventIdsOrder = seenIds
        self.seenReadyEventIdsSet = Set(seenIds)

        self.kitchenReadyLastSeenCursorByTable = resolvedLocalStore.loadReadyLastSeenCursorByTable()

        self.pendingSubmitOrderIdempotencyKeysByTableId = resolvedLocalStore.loadPendingSubmitOrderKeys()
        self.pendingPaymentIdempotencyKeysByScope = resolvedLocalStore.loadPendingPaymentKeys()
        self.selectedTableId = resolvedLocalStore.loadSelectedTableId(userId: nil, defaultValue: 1)

        if resolvedLocalStore.loadDeviceCredentials() != nil {
            isPaired = true
            route = sessionToken.isEmpty ? .login : .tables
        } else {
            route = .pairing
        }
    }

    func start() {
        Task {
            await refreshCoreConnectivity()
            await refreshFeatureFlagsFromCoreInternal()
            await refreshCatalogFromCoreInternal()
            await refreshSession()
            await refreshTablesFromCoreInternal()
        }
        startAutoSyncLoop()
    }

    func stop() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
        autoSyncStarted = false
    }

    func applyHostSettings(host: String, portText: String) {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            noticeMessage = "Host darf nicht leer sein."
            return
        }
        guard let parsedPort = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)), parsedPort >= 1, parsedPort <= 65535 else {
            noticeMessage = "Port ist ungültig."
            return
        }

        endpoint = CoreEndpoint(host: normalizedHost, port: parsedPort)
        repository.setEndpoint(host: normalizedHost, port: parsedPort)
        localStore.saveEndpoint(host: normalizedHost, port: parsedPort)

        hostAddress = normalizedHost
        hostPort = parsedPort
        resetEventFeedCursors(clearKitchenNotices: true)

        noticeMessage = "Core-Host aktualisiert."

        Task {
            await refreshCoreConnectivity()
            await refreshFeatureFlagsFromCoreInternal()
            await refreshCatalogFromCoreInternal()
            await refreshTablesFromCoreInternal()
        }
    }

    func generatePairCode() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let response = try await repository.createPairing(expiresInMs: 10 * 60 * 1000, createdBy: "ios-app")
                if response.success, let pairing = response.pairing {
                    pairCode = pairing.pairingCode
                    pairCodeInput = pairing.pairingCode ?? ""
                    pairCodeValidUntil = formatTimestamp(pairing.expiresAt)
                    noticeMessage = "Pairing-Code wurde erstellt."
                } else {
                    noticeMessage = "Pairing fehlgeschlagen: \(response.error ?? "UNKNOWN_ERROR")"
                }
            } catch {
                noticeMessage = "Pairing fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func setPairCodeInput(_ value: String) {
        pairCodeInput = value.uppercased()
    }

    func scanAndPairFromQrPayload(_ rawText: String) {
        guard !isBusy else { return }
        let parsed = parsePairingQrScanPayload(rawText)
        let scannedCode = parsed?.pairingCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        guard !scannedCode.isEmpty else {
            noticeMessage = "QR-Code ungültig. Bitte Pairing-QR der Hauptkasse scannen."
            return
        }

        let hasEndpointInQr = (parsed?.host?.isEmpty == false) && parsed?.port != nil
        let nextHost = hasEndpointInQr ? (parsed?.host ?? hostAddress) : hostAddress
        let nextPort = hasEndpointInQr ? (parsed?.port ?? hostPort) : hostPort

        if hasEndpointInQr {
            endpoint = CoreEndpoint(host: nextHost, port: nextPort)
            repository.setEndpoint(host: nextHost, port: nextPort)
            localStore.saveEndpoint(host: nextHost, port: nextPort)
            resetEventFeedCursors(clearKitchenNotices: true)
        }

        hostAddress = nextHost
        hostPort = nextPort
        pairCode = scannedCode
        pairCodeInput = scannedCode
        pairCodeValidUntil = formatTimestamp(parsed?.expiresAt)
        noticeMessage = "QR erkannt. Verbinde mit Hauptkasse..."

        pairDevice(scannedCode)
    }

    func pairDevice(_ providedPairingCode: String? = nil) {
        let code = providedPairingCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().isEmpty == false
            ? providedPairingCode!.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            : pairCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard !code.isEmpty else {
            noticeMessage = "Bitte Pairing-Code aus der Hauptkasse eingeben."
            return
        }
        guard !isBusy else { return }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let existingDeviceId = localStore.loadDeviceCredentials()?.deviceId ?? "ios-\(UUID().uuidString.prefix(8))"
                let model = UIDevice.current.model
                let response = try await repository.claimPairing(
                    pairingCode: code,
                    deviceName: "Service iOS",
                    model: model,
                    deviceId: existingDeviceId
                )

                guard response.success, let device = response.device else {
                    noticeMessage = "Pairing fehlgeschlagen: \(response.error ?? "PAIRING_FAILED")"
                    return
                }

                let deviceKey = response.deviceKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !deviceKey.isEmpty {
                    localStore.saveDeviceCredentials(deviceId: existingDeviceId, deviceKey: deviceKey)
                }

                isPaired = true
                connectedDevices = 1
                pairCodeInput = code
                pairedDeviceLabel = device.deviceName ?? "Service iOS"
                pairedDeviceId = device.deviceId
                await refreshFeatureFlagsFromCoreInternal()
                setRoute(.login)
                noticeMessage = "Gerät erfolgreich gekoppelt."
            } catch {
                noticeMessage = "Pairing fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func login(userId: String, pin: String) {
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPin = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserId.isEmpty, normalizedPin.count == 4 else {
            noticeMessage = "Bitte Benutzer und 4-stellige PIN eingeben."
            return
        }
        guard !isBusy else { return }

        guard let creds = localStore.loadDeviceCredentials() else {
            noticeMessage = "Gerät ist nicht gekoppelt."
            setRoute(.pairing)
            return
        }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let response = try await repository.login(
                    deviceId: creds.deviceId,
                    deviceKey: creds.deviceKey,
                    userId: normalizedUserId,
                    pin: normalizedPin
                )
                guard response.success, let session = response.session else {
                    noticeMessage = "Login fehlgeschlagen: \(response.error ?? "INVALID_CREDENTIALS")"
                    return
                }

                sessionToken = session.token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                localStore.saveSessionToken(sessionToken)
                isAuthenticated = !sessionToken.isEmpty
                let resolvedUserId = (response.user?.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? normalizedUserId)
                activeUserId = resolvedUserId.isEmpty ? nil : resolvedUserId
                activeUserDisplayName = resolveUserDisplayName(user: response.user, fallbackUserId: activeUserId ?? normalizedUserId)
                selectedTableId = localStore.loadSelectedTableId(userId: activeUserId, defaultValue: selectedTableId)
                setRoute(isAuthenticated ? .tables : .login)
                noticeMessage = isAuthenticated ? "Anmeldung erfolgreich." : "Login fehlgeschlagen."

                await refreshCoreConnectivity()
                await refreshFeatureFlagsFromCoreInternal()
                await refreshCatalogFromCoreInternal()
                await refreshTablesFromCoreInternal()
            } catch {
                noticeMessage = "Login fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func logout() {
        localStore.clearSessionToken()
        sessionToken = ""
        isAuthenticated = false
        activeUserId = nil
        activeUserDisplayName = nil
        setRoute(isPaired ? .login : .pairing)
        resetEventFeedCursors(clearKitchenNotices: true)

        pendingSubmitOrderIdempotencyKeysByTableId.removeAll()
        localStore.clearPendingSubmitOrderKeys()
        pendingPaymentIdempotencyKeysByScope.removeAll()
        localStore.clearPendingPaymentKeys()

        noticeMessage = "Abgemeldet."
    }

    func returnToPairing() {
        guard !isBusy else { return }
        setRoute(.pairing)
    }

    func requestQuickSync(includeCatalog: Bool = false, force: Bool = false) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if !force, now - lastQuickSyncAt < autoQuickSyncMinIntervalMs {
            return
        }
        lastQuickSyncAt = now

        Task {
            await refreshCoreConnectivity()
            guard isOnline, isAuthenticated else {
                return
            }
            if includeCatalog {
                await refreshCatalogFromCoreInternal()
            }
            await refreshTablesFromCoreInternal()
        }
    }

    func enqueueOfflineAction() {
        offlineQueueCount += 1
        noticeMessage = "Aktion wurde offline gepuffert."
    }

    func flushOfflineQueue() {
        offlineQueueCount = 0
        noticeMessage = "Offline-Queue wurde synchronisiert."
    }

    func setDarkMode(_ enabled: Bool) {
        isDarkMode = enabled
        localStore.saveDarkMode(enabled)
    }

    func setShowVatOnProductTiles(_ enabled: Bool) {
        showVatOnProductTiles = enabled
        localStore.saveShowVatOnProductTiles(enabled)
    }

    func setShowFullProductText(_ enabled: Bool) {
        showFullProductText = enabled
        localStore.saveShowFullProductText(enabled)
    }

    func setShowPriceOnProductTiles(_ enabled: Bool) {
        showPriceOnProductTiles = enabled
        localStore.saveShowPriceOnProductTiles(enabled)
    }

    func setPrintStornoInfoEnabled(_ enabled: Bool) {
        printStornoInfoEnabled = enabled
        localStore.savePrintStornoInfoEnabled(enabled)
    }

    func selectCatalogGroup(_ groupId: String?) {
        let normalized = groupId?.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedCatalogGroupId = (normalized?.isEmpty == false) ? normalized : nil
    }

    func selectOrderOverviewTab(_ tab: OrderOverviewTab) {
        orderOverviewTab = tab
        if tab == .ready {
            markKitchenReadyNoticesSeenForTable(selectedTableId)
        }
    }

    func selectTable(_ tableId: Int) {
        guard let table = tables.first(where: { $0.id == tableId }) else { return }
        if table.status == .locked {
            noticeMessage = "Tisch ist gesperrt und kann nicht genutzt werden."
            return
        }

        let snapshot = extractCurrentOrderFromStore(latestOrderStore, tableId: tableId)
        selectedTableId = tableId
        currentOrderLines = snapshot.lines
        currentOrderCode = snapshot.code
        currentAppliedVouchers = snapshot.appliedVouchers
        voucherCodeInput = ""
        selectedOrderLineId = nil
        activeWorkTab = .orders
        localStore.saveSelectedTableId(tableId, userId: activeUserId)

        if isSchlemmerBlockModuleEnabled {
            // Avoid carrying stale Schlemmer selection across tables.
            schlemmerEligibleLines = []
            schlemmerSelection = [:]
            schlemmerAutoSelection = [:]
            schlemmerRequiredFoodUnits = 0
            schlemmerAvailableUnits = 0
            schlemmerRequiredSelectionCount = 0
            schlemmerSelectedUnits = 0
            schlemmerLastErrorCode = nil
            schlemmerPreviewInFlight = false
            schlemmerPreviewShowLoader = false

            if isOnline {
                // Lock selection immediately so stale taps cannot race the pending preview refresh.
                schlemmerPreviewInFlight = true
                schlemmerPreviewShowLoader = false
                Task {
                    await refreshSchlemmerPreviewInternal(silent: true, lockInteraction: true)
                }
            }
        }

        if !isOnline {
            noticeMessage = "Offline: nur lokaler Wechsel."
        }
    }

    func onProductTap(_ productId: String) {
        guard let product = catalogProducts.first(where: { $0.id == productId }) else {
            noticeMessage = "Artikel nicht gefunden."
            return
        }
        if product.isBlocked {
            noticeMessage = "Artikel ausverkauft."
            return
        }
        if !isOnline {
            enqueueOfflineAction()
            return
        }
        if isBusy {
            return
        }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let dto = CatalogProductDTO(
                    id: product.id,
                    name: product.name,
                    price: product.price,
                    taxRate: product.taxRate,
                    groupId: product.groupId,
                    listId: nil,
                    printer: nil,
                    isBlocked: product.isBlocked,
                    is_blocked: nil,
                    is_blocked_flag: nil,
                    blocked: nil,
                    blockReason: product.blockReason,
                    block_reason: nil,
                    basePrice: product.regularPrice,
                    promoEnabled: product.promoEnabled,
                    promoApplied: product.promoActive,
                    promoPrice: product.promoActive ? product.promoPrice : nil
                )
                let result = try await repository.addLine(tableId: String(selectedTableId), product: dto)
                if result.success, result.result?.ok == true {
                    switchOrderOverviewToOrders()
                    activeWorkTab = .orders
                    await refreshTablesFromCoreInternal(noticeOnSuccess: "Artikel hinzugefügt.")
                } else {
                    let commandError = result.result?.error ?? result.error ?? "ADD_LINE_FAILED"
                    if isProductBlockedError(commandError) {
                        markProductBlockedInUi(productId: product.id, reason: extractBlockedReason(result.result).isEmpty ? "Ausverkauft" : extractBlockedReason(result.result))
                        noticeMessage = "Artikel ausverkauft."
                        await refreshCatalogFromCoreInternal()
                    } else {
                        noticeMessage = "Hinzufügen fehlgeschlagen: \(commandError)"
                    }
                }
            } catch {
                if isProductBlockedError(error.localizedDescription) {
                    markProductBlockedInUi(productId: product.id, reason: "Ausverkauft")
                    await refreshCatalogFromCoreInternal()
                    noticeMessage = "Artikel ausverkauft."
                } else {
                    noticeMessage = "Hinzufügen fehlgeschlagen: \(error.localizedDescription)"
                }
            }
        }
    }

    func onSubmitOrderTap() {
        if !isOnline {
            enqueueOfflineAction()
            return
        }
        if isBusy {
            return
        }
        let tableId = String(selectedTableId)
        let submitKey = getOrCreateSubmitOrderRetryKey(tableId: tableId)

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let result = try await repository.submitOrder(tableId: tableId, idempotencyKey: submitKey)
                removeSubmitOrderRetryKey(tableId: tableId)
                if result.success, result.result?.ok == true {
                    await refreshTablesFromCoreInternal(noticeOnSuccess: "Bestellung gesendet.")
                } else {
                    let commandError = result.result?.error ?? result.error ?? "SUBMIT_FAILED"
                    noticeMessage = "Bestellen fehlgeschlagen: \(commandError)"
                }
            } catch {
                if shouldResetRetryKey(error: error) {
                    removeSubmitOrderRetryKey(tableId: tableId)
                }
                noticeMessage = "Bestellen fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func onSelectOrderLine(_ lineId: String) {
        selectedOrderLineId = lineId
    }

    func onDecreaseSelectedLineTap() {
        guard let lineId = selectedOrderLineId?.trimmingCharacters(in: .whitespacesAndNewlines), !lineId.isEmpty else {
            noticeMessage = "Bitte Position wählen."
            return
        }
        guard let line = currentOrderLines.first(where: { $0.id == lineId }) else {
            noticeMessage = "Position nicht gefunden."
            return
        }

        let status = normalizeOrderStatus(line.status)
        if status == "cancelled" {
            noticeMessage = "Stornierte Position kann nicht geändert werden."
            return
        }
        if !isOnline {
            enqueueOfflineAction()
            return
        }
        if isBusy {
            return
        }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let result: StatefulCommandResponse
                if status == "ordered" {
                    result = try await repository.cancelOrderedLine(
                        tableId: String(selectedTableId),
                        lineId: line.id,
                        sourceTicketId: currentOrderCode.isEmpty ? nil : currentOrderCode
                    )
                } else {
                    result = try await repository.removeOneLine(tableId: String(selectedTableId), lineId: line.id)
                }

                if result.success, result.result?.ok == true {
                    switchOrderOverviewToOrders()
                    let applied = applyCommandStoreSnapshot(response: result, noticeOnSuccess: "Position angepasst.")
                    if !applied {
                        await refreshTablesFromCoreInternal(noticeOnSuccess: "Position angepasst.")
                    }
                } else {
                    let commandError = result.result?.error ?? result.error ?? "REMOVE_ONE_FAILED"
                    noticeMessage = "Ändern fehlgeschlagen: \(commandError)"
                }
            } catch {
                noticeMessage = "Ändern fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func onIncreaseSelectedLineTap() {
        guard let lineId = selectedOrderLineId?.trimmingCharacters(in: .whitespacesAndNewlines), !lineId.isEmpty else {
            noticeMessage = "Bitte Position wählen."
            return
        }
        guard let line = currentOrderLines.first(where: { $0.id == lineId }) else {
            noticeMessage = "Position nicht gefunden."
            return
        }

        let status = normalizeOrderStatus(line.status)
        if status == "cancelled" {
            noticeMessage = "Stornierte Position kann nicht geändert werden."
            return
        }
        if line.productId.isEmpty {
            noticeMessage = "Artikel-ID fehlt."
            return
        }

        if catalogProducts.first(where: { $0.id == line.productId })?.isBlocked == true {
            noticeMessage = "Artikel ausverkauft."
            return
        }

        if !isOnline {
            enqueueOfflineAction()
            return
        }
        if isBusy {
            return
        }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let dto = CatalogProductDTO(
                    id: line.productId,
                    name: line.name,
                    price: line.price,
                    taxRate: line.taxRate,
                    groupId: nil,
                    listId: nil,
                    printer: nil,
                    isBlocked: false,
                    is_blocked: nil,
                    is_blocked_flag: nil,
                    blocked: nil,
                    blockReason: nil,
                    block_reason: nil,
                    basePrice: line.basePrice,
                    promoApplied: line.promoApplied,
                    promoPrice: line.promoPrice
                )
                let result = try await repository.addLine(tableId: String(selectedTableId), product: dto)

                if result.success, result.result?.ok == true {
                    let applied = applyCommandStoreSnapshot(response: result, noticeOnSuccess: "Position angepasst.")
                    if !applied {
                        await refreshTablesFromCoreInternal(noticeOnSuccess: "Position angepasst.")
                    }
                } else {
                    let commandError = result.result?.error ?? result.error ?? "ADD_LINE_FAILED"
                    if isProductBlockedError(commandError) {
                        markProductBlockedInUi(productId: line.productId, reason: extractBlockedReason(result.result))
                        await refreshCatalogFromCoreInternal()
                        noticeMessage = "Artikel ausverkauft."
                    } else {
                        noticeMessage = "Ändern fehlgeschlagen: \(commandError)"
                    }
                }
            } catch {
                if isProductBlockedError(error.localizedDescription) {
                    markProductBlockedInUi(productId: line.productId, reason: "Ausverkauft")
                    await refreshCatalogFromCoreInternal()
                    noticeMessage = "Artikel ausverkauft."
                } else {
                    noticeMessage = "Ändern fehlgeschlagen: \(error.localizedDescription)"
                }
            }
        }
    }

    func onCancelOrderedLineTap() {
        guard let lineId = selectedOrderLineId?.trimmingCharacters(in: .whitespacesAndNewlines), !lineId.isEmpty else {
            noticeMessage = "Bitte Position wählen."
            return
        }
        guard let line = currentOrderLines.first(where: { $0.id == lineId }) else {
            noticeMessage = "Position nicht gefunden."
            return
        }
        guard normalizeOrderStatus(line.status) == "ordered" else {
            noticeMessage = "Nur bestellte Positionen können storniert werden."
            return
        }
        if !isOnline {
            enqueueOfflineAction()
            return
        }
        if isBusy {
            return
        }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let result = try await repository.cancelOrderedLine(
                    tableId: String(selectedTableId),
                    lineId: line.id,
                    sourceTicketId: currentOrderCode.isEmpty ? nil : currentOrderCode
                )
                if result.success, result.result?.ok == true {
                    await refreshTablesFromCoreInternal(noticeOnSuccess: "Position storniert.")
                } else {
                    let commandError = result.result?.error ?? result.error ?? "CANCEL_FAILED"
                    noticeMessage = "Storno fehlgeschlagen: \(commandError)"
                }
            } catch {
                noticeMessage = "Storno fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func onPaymentTap(method: String) {
        if !isOnline {
            noticeMessage = "Zahlung ist nur online möglich."
            return
        }
        if isBusy {
            return
        }
        let hasUnorderedLines = currentOrderLines.contains { $0.qty > 0 && normalizeOrderStatus($0.status) == "new" }
        if hasUnorderedLines {
            noticeMessage = "Bitte erst bestellen. Zahlung nur mit bestellten Positionen."
            return
        }
        let hasPayableLines = currentOrderLines.contains { $0.qty > 0 && normalizeOrderStatus($0.status) == "ordered" }
        if !hasPayableLines {
            noticeMessage = "Keine offenen Positionen für Zahlung."
            return
        }

        let tableId = String(selectedTableId)
        let retryScope = buildPaymentRetryScope(
            type: "sale",
            tableId: tableId,
            orderCode: currentOrderCode,
            method: method,
            splitSelection: [:]
        )
        let idempotencyKey = getOrCreatePaymentRetryKey(scope: retryScope, idempotencyScope: "payments-finalize")

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let result = try await repository.finalizePayment(
                    tableId: tableId,
                    method: method,
                    currentUserId: activeUserId,
                    idempotencyKey: idempotencyKey
                )
                removePaymentRetryKey(scope: retryScope)
                if result.success, result.result?.ok == true {
                    let applied = applyCommandStoreSnapshot(response: result, noticeOnSuccess: "Zahlung gebucht.")
                    if !applied {
                        await refreshTablesFromCoreInternal(noticeOnSuccess: "Zahlung gebucht.")
                    }
                } else {
                    let commandError = result.result?.error ?? result.error ?? "PAYMENT_FAILED"
                    noticeMessage = "Zahlung fehlgeschlagen: \(commandError)"
                }
            } catch {
                if shouldResetRetryKey(error: error) {
                    removePaymentRetryKey(scope: retryScope)
                }
                noticeMessage = "Zahlung fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func onSplitTap(splitSelection: [String: Int], method: String) {
        if !isOnline {
            noticeMessage = "Split-Zahlung ist nur online möglich."
            return
        }
        if isBusy {
            return
        }
        if splitSelection.isEmpty {
            noticeMessage = "Bitte mindestens eine Position für Split auswählen."
            return
        }

        let availableByProductId: [String: Int] = Dictionary(grouping: currentOrderLines.filter {
            $0.qty > 0 && normalizeOrderStatus($0.status) == "ordered"
        }, by: { $0.productId }).mapValues { group in
            group.reduce(0) { $0 + $1.qty }
        }

        let invalid = splitSelection.contains { productId, qty in
            let available = availableByProductId[productId] ?? 0
            return productId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || qty <= 0 || qty > available
        }

        if invalid {
            noticeMessage = "Split-Auswahl ist ungültig."
            return
        }

        let tableId = String(selectedTableId)
        let retryScope = buildPaymentRetryScope(
            type: "split",
            tableId: tableId,
            orderCode: currentOrderCode,
            method: method,
            splitSelection: splitSelection
        )
        let idempotencyKey = getOrCreatePaymentRetryKey(scope: retryScope, idempotencyScope: "payments-finalize-split")

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let result = try await repository.finalizeSplitPayment(
                    tableId: tableId,
                    method: method,
                    splitSelection: splitSelection,
                    currentUserId: activeUserId,
                    idempotencyKey: idempotencyKey
                )
                removePaymentRetryKey(scope: retryScope)
                if result.success, result.result?.ok == true {
                    let applied = applyCommandStoreSnapshot(response: result, noticeOnSuccess: "Split-Zahlung gebucht.")
                    if !applied {
                        await refreshTablesFromCoreInternal(noticeOnSuccess: "Split-Zahlung gebucht.")
                    }
                } else {
                    let commandError = result.result?.error ?? result.error ?? "SPLIT_FAILED"
                    noticeMessage = "Split fehlgeschlagen: \(commandError)"
                }
            } catch {
                if shouldResetRetryKey(error: error) {
                    removePaymentRetryKey(scope: retryScope)
                }
                noticeMessage = "Split fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func onMoveTap(targetTableId: Int?) {
        if !isOnline {
            enqueueOfflineAction()
            return
        }
        if isBusy {
            return
        }
        guard let targetTableId else {
            noticeMessage = "Bitte Ziel-Tisch wählen."
            return
        }
        if targetTableId == selectedTableId {
            noticeMessage = "Quelle und Ziel dürfen nicht identisch sein."
            return
        }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let result = try await repository.transferItems(
                    sourceTableId: String(selectedTableId),
                    targetTableId: String(targetTableId),
                    selectionEntries: []
                )
                if result.success, result.result?.ok == true {
                    await refreshTablesFromCoreInternal(noticeOnSuccess: "Umsetzen erfolgreich.")
                } else {
                    let commandError = result.result?.error ?? result.error ?? "TRANSFER_FAILED"
                    noticeMessage = "Umsetzen fehlgeschlagen: \(commandError)"
                }
            } catch {
                noticeMessage = "Umsetzen fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func setVoucherCodeInput(_ value: String) {
        voucherCodeInput = value.uppercased()
    }

    func applyVoucherCode() {
        let code = voucherCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            noticeMessage = "Bitte Gutscheincode eingeben."
            return
        }
        guard isOnline else {
            noticeMessage = "Gutschein nur online verfügbar."
            return
        }
        guard !isBusy else { return }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let result = try await repository.applyVoucher(tableId: String(selectedTableId), code: code)
                if result.success, result.result?.ok == true {
                    voucherCodeInput = ""
                    let applied = applyCommandStoreSnapshot(response: result, noticeOnSuccess: "Gutschein erfolgreich eingelöst.")
                    if !applied {
                        await refreshTablesFromCoreInternal(noticeOnSuccess: "Gutschein erfolgreich eingelöst.")
                    }
                    if activeWorkTab == .schlemmer {
                        await refreshSchlemmerPreviewInternal()
                    }
                } else {
                    let errorCode = result.result?.error ?? result.error ?? "VOUCHER_APPLY_FAILED"
                    noticeMessage = describeVoucherError(errorCode)
                }
            } catch {
                noticeMessage = describeVoucherError((error as? CoreClientError)?.errorCode ?? error.localizedDescription)
            }
        }
    }

    func removeVoucherCode(_ code: String) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return }
        guard isOnline else {
            noticeMessage = "Gutschein nur online verfügbar."
            return
        }
        guard !isBusy else { return }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let result = try await repository.removeVoucher(tableId: String(selectedTableId), code: normalized)
                if result.success, result.result?.ok == true {
                    let applied = applyCommandStoreSnapshot(response: result, noticeOnSuccess: "Gutschein entfernt.")
                    if !applied {
                        await refreshTablesFromCoreInternal(noticeOnSuccess: "Gutschein entfernt.")
                    }
                    if activeWorkTab == .schlemmer {
                        await refreshSchlemmerPreviewInternal()
                    }
                } else {
                    let errorCode = result.result?.error ?? result.error ?? "VOUCHER_REMOVE_FAILED"
                    noticeMessage = describeVoucherError(errorCode)
                }
            } catch {
                noticeMessage = describeVoucherError((error as? CoreClientError)?.errorCode ?? error.localizedDescription)
            }
        }
    }

    func selectSchlemmerType(_ type: SchlemmerBlockTypeUI) {
        guard schlemmerType != type else { return }
        schlemmerType = type
        schlemmerSelection = [:]
        schlemmerAutoSelection = [:]
        schlemmerSelectedUnits = 0
        schlemmerPreviewInFlight = true
        schlemmerPreviewShowLoader = true
        Task {
            await refreshSchlemmerPreviewInternal()
        }
    }

    func setSchlemmerSelection(lineId: String, qty: Int) {
        guard !schlemmerPreviewInFlight, !isBusy else { return }
        let normalizedLineId = lineId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLineId.isEmpty else { return }
        let maxForLine = schlemmerEligibleLines.first(where: { $0.lineId == normalizedLineId })?.qty ?? 0
        let nextQty = min(max(0, qty), maxForLine)
        if nextQty <= 0 {
            schlemmerSelection.removeValue(forKey: normalizedLineId)
        } else {
            schlemmerSelection[normalizedLineId] = nextQty
        }
        schlemmerSelectedUnits = schlemmerSelection.values.reduce(0, +)
    }

    func applySchlemmerSelection() {
        guard isSchlemmerBlockModuleEnabled else {
            noticeMessage = "Schlemmer Block Modul ist nicht aktiv."
            return
        }
        guard isOnline else {
            noticeMessage = "Schlemmer Block nur online verfügbar."
            return
        }
        guard !isBusy, !schlemmerPreviewInFlight else { return }

        let minimumFoodUnits = schlemmerMinimumFoodUnits(for: schlemmerType)
        if minimumFoodUnits > 0, schlemmerAvailableUnits < minimumFoodUnits {
            noticeMessage = schlemmerInsufficientItemsMessage(for: schlemmerType)
            return
        }

        let compactSelection = schlemmerSelection
            .mapValues { max(0, $0) }
            .filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.value > 0 }

        guard !compactSelection.isEmpty else {
            noticeMessage = "Bitte Auswahl für Schlemmer Block treffen."
            return
        }
        if schlemmerRequiredSelectionCount > 0 && schlemmerSelectedUnits != schlemmerRequiredSelectionCount {
            noticeMessage = "Auswahl unvollständig: \(schlemmerSelectedUnits)/\(schlemmerRequiredSelectionCount)."
            return
        }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let result = try await repository.applySchlemmer(
                    tableId: String(selectedTableId),
                    type: schlemmerType.coreValue,
                    selection: compactSelection
                )
                if result.success, result.result?.ok == true {
                    let applied = applyCommandStoreSnapshot(response: result, noticeOnSuccess: "Schlemmer Block erfolgreich angewendet.")
                    if !applied {
                        await refreshTablesFromCoreInternal(noticeOnSuccess: "Schlemmer Block erfolgreich angewendet.")
                    }
                    await refreshSchlemmerPreviewInternal()
                } else {
                    let errorCode = result.result?.error ?? result.error ?? "SCHLEMMER_APPLY_FAILED"
                    schlemmerLastErrorCode = errorCode
                    noticeMessage = describeSchlemmerError(errorCode)
                }
            } catch {
                let errorCode = (error as? CoreClientError)?.errorCode ?? error.localizedDescription
                schlemmerLastErrorCode = errorCode
                noticeMessage = describeSchlemmerError(errorCode)
            }
        }
    }

    func refreshSchlemmerPreview() {
        schlemmerPreviewInFlight = true
        schlemmerPreviewShowLoader = true
        Task {
            await refreshSchlemmerPreviewInternal()
        }
    }

    func onTransferSelectionTap(sourceTableId: Int, targetTableId: Int, selectionByLineId: [String: Int]) {
        if !isOnline {
            enqueueOfflineAction()
            return
        }
        if isBusy {
            return
        }
        if sourceTableId <= 0 || targetTableId <= 0 || sourceTableId == targetTableId {
            noticeMessage = "Umsetzen nicht möglich."
            return
        }

        let sourceLines = tableOrderLinesByTableId[sourceTableId] ?? []
        let entries = selectionByLineId.compactMap { lineId, qtyRaw -> TransferSelectionEntryPayload? in
            guard let line = sourceLines.first(where: { $0.id == lineId }) else { return nil }
            guard normalizeOrderStatus(line.status) == "ordered" else { return nil }
            let qty = min(max(0, qtyRaw), line.qty)
            guard qty > 0 else { return nil }
            return TransferSelectionEntryPayload(lineId: line.id, productId: line.productId, qty: qty)
        }

        if entries.isEmpty {
            noticeMessage = "Keine bestellten Positionen zum Umsetzen ausgewählt."
            return
        }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let result = try await repository.transferItems(
                    sourceTableId: String(sourceTableId),
                    targetTableId: String(targetTableId),
                    selectionEntries: entries
                )
                if result.success, result.result?.ok == true {
                    let applied = applyCommandStoreSnapshot(response: result, noticeOnSuccess: "Umsetzen erfolgreich.")
                    if !applied {
                        await refreshTablesFromCoreInternal(noticeOnSuccess: "Umsetzen erfolgreich.")
                    }
                } else {
                    let commandError = result.result?.error ?? result.error ?? "TRANSFER_FAILED"
                    noticeMessage = "Umsetzen nicht möglich: \(commandError)"
                }
            } catch {
                noticeMessage = "Umsetzen nicht möglich: \(error.localizedDescription)"
            }
        }
    }

    func clearNotice() {
        noticeMessage = nil
    }

    func pushNotice(_ message: String) {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty {
            noticeMessage = normalized
        }
    }

    private func startAutoSyncLoop() {
        guard !autoSyncStarted else { return }
        autoSyncStarted = true

        autoSyncTask = Task { [weak self] in
            guard let self else { return }
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: autoSyncIntervalNs)
                if Task.isCancelled { break }

                if tick % autoConnectivityIntervalTicks == 0 {
                    await refreshCoreConnectivity()
                }
                if isOnline && isAuthenticated {
                    await pollCoreEventsAndRefresh()
                    if tick % autoTableRefreshIntervalTicks == 0 {
                        await refreshTablesFromCoreInternal()
                    }
                    if tick % autoCatalogRefreshIntervalTicks == 0 {
                        await refreshCatalogFromCoreInternal()
                    }
                }
                tick += 1
            }
        }
    }

    private func pollCoreEventsAndRefresh() async {
        var shouldRefreshTables = false
        var shouldRefreshCatalog = false

        do {
            let result = try await repository.readEvents(cursor: syncCursor, limit: autoEventsLimit)
            if result.success {
                if result.cursorReset {
                    if let cursor = result.cursor {
                        syncCursor = cursor
                    }
                    localStore.saveSyncCursor(syncCursor)
                }
                let events = result.events
                let nextCursor = result.cursor ?? events.last?.cursor ?? syncCursor
                if nextCursor > syncCursor {
                    syncCursor = nextCursor
                    localStore.saveSyncCursor(syncCursor)
                }

                for event in events {
                    let type = event.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

                    if type == "kitchen-ready.notice" {
                        ingestKitchenReadyEvent(event)
                    }

                    if type == "catalog.updated" || type == "catalog.availability.updated" || type.hasPrefix("catalog.") {
                        shouldRefreshCatalog = true
                    }

                    if type.hasPrefix("orders.") ||
                        type.hasPrefix("table-") ||
                        type.hasPrefix("kitchen.") ||
                        type.hasPrefix("kitchen-") ||
                        type.hasPrefix("payments.") ||
                        type.hasPrefix("receipts.") ||
                        type.hasPrefix("production-queue.") {
                        shouldRefreshTables = true
                    }
                }
            }
        } catch {
            // connectivity is tracked by periodic refreshCoreConnectivity.
        }

        await pollKitchenReadyNoticesOptional()
        persistSeenReadyEventIdsIfNeeded()

        if shouldRefreshCatalog {
            await refreshCatalogFromCoreInternal()
        }
        if shouldRefreshTables || shouldRefreshCatalog {
            await refreshTablesFromCoreInternal()
        }
    }

    private func pollKitchenReadyNoticesOptional() async {
        do {
            let result = try await repository.readKitchenNotices(cursor: kitchenNoticeCursor, limit: autoEventsLimit)
            guard result.success else { return }

            let notices = result.notices
            let nextCursor = result.cursor ?? notices.last?.eventCursor ?? kitchenNoticeCursor
            if nextCursor > kitchenNoticeCursor || result.cursorReset {
                kitchenNoticeCursor = nextCursor
                localStore.saveKitchenNoticeCursor(kitchenNoticeCursor)
            }

            for notice in notices {
                ingestKitchenNoticeDTO(notice)
            }
        } catch {
            // Optional endpoint fallback only.
        }
    }

    private func ingestKitchenReadyEvent(_ event: CoreSyncEventDTO) {
        guard let eventId = event.id?.trimmingCharacters(in: .whitespacesAndNewlines), !eventId.isEmpty else {
            return
        }
        guard rememberReadyEventId(eventId) else {
            return
        }

        let payload = event.payload ?? [:]
        let schema = payload["schema"]?.stringValue?.lowercased()
        guard schema == "kitchen.notice.v1" else {
            return
        }

        let kindRaw = payload["kind"]?.stringValue?.lowercased() ?? ""
        guard kindRaw == "line-ready" || kindRaw == "ticket-completed" else {
            return
        }

        guard let tableId = readTableIdFromPayload(payload), tableId > 0 else {
            return
        }

        let text = (payload["text"]?.stringValue ?? payload["noticeText"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        let createdAt = payload["createdAt"]?.intValue.map(Int64.init) ?? event.createdAt ?? Int64(Date().timeIntervalSince1970 * 1000)
        let eventCursor = event.cursor ?? 0
        let tableLabel = (payload["tableLabel"]?.stringValue ?? "Tisch \(tableId)").trimmingCharacters(in: .whitespacesAndNewlines)
        let terminalId = payload["terminalId"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        appendKitchenReadyNotice(
            KitchenReadyNoticeUI(
                id: "event:\(eventId)",
                eventId: eventId,
                tableId: tableId,
                tableLabel: tableLabel,
                text: text,
                type: kindRaw,
                createdAt: createdAt,
                eventCursor: eventCursor,
                terminalId: terminalId
            )
        )
    }

    private func ingestKitchenNoticeDTO(_ dto: CoreKitchenNoticeDTO) {
        guard let eventId = dto.eventId?.trimmingCharacters(in: .whitespacesAndNewlines), !eventId.isEmpty else {
            return
        }
        guard rememberReadyEventId(eventId) else {
            return
        }

        let schema = dto.schema?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard schema == "kitchen.notice.v1" else {
            return
        }

        let kind = dto.kind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard kind == "line-ready" || kind == "ticket-completed" else {
            return
        }

        guard let tableId = toTableNumber(dto.tableId), tableId > 0 else {
            return
        }

        let text = (dto.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? dto.text : dto.noticeText)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            return
        }

        appendKitchenReadyNotice(
            KitchenReadyNoticeUI(
                id: "event:\(eventId)",
                eventId: eventId,
                tableId: tableId,
                tableLabel: dto.tableLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? dto.tableLabel! : "Tisch \(tableId)",
                text: text,
                type: kind,
                createdAt: dto.createdAt ?? Int64(Date().timeIntervalSince1970 * 1000),
                eventCursor: dto.eventCursor ?? 0,
                terminalId: dto.terminalId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        )
    }

    private func appendKitchenReadyNotice(_ notice: KitchenReadyNoticeUI) {
        var next = kitchenReadyNoticesByTable
        var entries = next[notice.tableId] ?? []
        if entries.contains(where: { $0.eventId == notice.eventId }) {
            return
        }
        entries.append(notice)
        while entries.count > kitchenReadyMessagesPerTableMax {
            entries.removeFirst()
        }
        next[notice.tableId] = entries
        kitchenReadyNoticesByTable = next

        if orderOverviewTab == .ready {
            markKitchenReadyNoticesSeenForTable(selectedTableId)
        }
    }

    func markKitchenReadyNoticesSeenForTable(_ tableId: Int) {
        guard tableId > 0 else { return }
        let notices = kitchenReadyNoticesByTable[tableId] ?? []
        guard !notices.isEmpty else { return }
        let maxCursor = notices.map { $0.eventCursor }.max() ?? 0
        guard maxCursor > 0 else { return }
        let current = kitchenReadyLastSeenCursorByTable[tableId] ?? 0
        guard maxCursor > current else { return }

        kitchenReadyLastSeenCursorByTable[tableId] = maxCursor
        localStore.saveReadyLastSeenCursorByTable(kitchenReadyLastSeenCursorByTable)
    }

    private func rememberReadyEventId(_ eventIdRaw: String) -> Bool {
        let eventId = eventIdRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventId.isEmpty else { return false }
        if seenReadyEventIdsSet.contains(eventId) {
            return false
        }

        seenReadyEventIdsSet.insert(eventId)
        seenReadyEventIdsOrder.append(eventId)

        while seenReadyEventIdsOrder.count > kitchenReadyDedupeLimit {
            let removed = seenReadyEventIdsOrder.removeFirst()
            seenReadyEventIdsSet.remove(removed)
        }

        seenReadyEventIdsDirty = true
        return true
    }

    private func persistSeenReadyEventIdsIfNeeded() {
        guard seenReadyEventIdsDirty else { return }
        localStore.saveSeenReadyEventIds(seenReadyEventIdsOrder)
        seenReadyEventIdsDirty = false
    }

    private func refreshCoreConnectivity() async {
        let wasOnline = isOnline
        let wasReady = requiredCommandsReady

        async let healthTask = try? repository.health()
        async let contractTask = try? repository.contract()

        let healthResult = await healthTask
        let contractResult = await contractTask

        let apiReachableNow = (healthResult?.success == true)
        let missingCommands: [String]

        if let contract = contractResult, contract.success {
            let provided = Set(contract.endpoints?.commands ?? [])
            missingCommands = requiredCommandPaths.filter { !provided.contains($0) }.sorted()
        } else {
            missingCommands = Array(requiredCommandPaths).sorted()
        }

        let isReadyNow = missingCommands.isEmpty

        let connectivityNotice: String?
        if !wasOnline && apiReachableNow && isReadyNow {
            connectivityNotice = "Core-API verbunden."
        } else if !wasOnline && apiReachableNow && !isReadyNow {
            connectivityNotice = "Core verbunden, aber Commands fehlen."
        } else if wasOnline && !apiReachableNow {
            connectivityNotice = "Core-API nicht erreichbar."
        } else if apiReachableNow && wasReady != isReadyNow && isReadyNow {
            connectivityNotice = "Core Commands jetzt bereit."
        } else if apiReachableNow && wasReady != isReadyNow && !isReadyNow {
            connectivityNotice = "Core verbunden, aber Commands fehlen."
        } else {
            connectivityNotice = nil
        }

        isOnline = apiReachableNow
        apiReachable = apiReachableNow
        requiredCommandsReady = isReadyNow
        missingCommandPaths = missingCommands
        if let connectivityNotice {
            noticeMessage = connectivityNotice
        }
    }

    private func refreshSession() async {
        guard !sessionToken.isEmpty else {
            isAuthenticated = false
            activeUserId = nil
            activeUserDisplayName = nil
            setRoute(isPaired ? .login : .pairing)
            return
        }

        do {
            let response = try await repository.sessionInfo()
            if response.success {
                let freshToken = response.session?.token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? sessionToken
                sessionToken = freshToken
                localStore.saveSessionToken(freshToken)
                isAuthenticated = true
                let fallbackUserId = response.user?.id?.trimmingCharacters(in: .whitespacesAndNewlines)
                activeUserId = fallbackUserId?.isEmpty == true ? nil : fallbackUserId
                activeUserDisplayName = resolveUserDisplayName(user: response.user, fallbackUserId: activeUserId)
                selectedTableId = localStore.loadSelectedTableId(userId: activeUserId, defaultValue: selectedTableId)
                await refreshFeatureFlagsFromCoreInternal()
                setRoute(.tables)
            } else {
                isAuthenticated = false
                activeUserId = nil
                activeUserDisplayName = nil
                setRoute(isPaired ? .login : .pairing)
            }
        } catch {
            isAuthenticated = false
            activeUserId = nil
            activeUserDisplayName = nil
            setRoute(isPaired ? .login : .pairing)
        }
    }

    private func resolveUserDisplayName(user: SessionUser?, fallbackUserId: String?) -> String? {
        let candidates: [String?] = [
            user?.displayName,
            user?.loginName,
            user?.id,
            fallbackUserId
        ]
        for candidate in candidates {
            let normalized = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !normalized.isEmpty {
                return normalized
            }
        }
        return nil
    }

    private func setRoute(_ nextRoute: AppRoute) {
        guard route != nextRoute else { return }
        withAnimation(POSMotion.panel) {
            route = nextRoute
        }
    }

    private func refreshFeatureFlagsFromCoreInternal() async {
        do {
            let response = try await repository.authFeatures()
            guard response.success else { return }
            let schlemmerEnabled = response.modules.contains { module in
                module.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == featureKeySchlemmerBlockModule &&
                    module.active
            }
            if isSchlemmerBlockModuleEnabled != schlemmerEnabled {
                isSchlemmerBlockModuleEnabled = schlemmerEnabled
                enforceModuleDependentUiState()
            }
        } catch {
            // Keep last known module state when endpoint is temporarily unavailable.
        }
    }

    private func enforceModuleDependentUiState() {
        if !isSchlemmerBlockModuleEnabled && activeWorkTab == .schlemmer {
            activeWorkTab = .voucher
        }
    }

    private func refreshCatalogFromCoreInternal() async {
        do {
            let result = try await repository.readCatalog()
            guard result.success else { return }

            let lists = result.catalog?.lists.compactMap { list -> CatalogGroupUI? in
                let id = list.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !id.isEmpty else { return nil }
                return CatalogGroupUI(
                    id: id,
                    name: list.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? list.name! : "Warenkatalog",
                    listId: id
                )
            }.sorted { $0.name.lowercased() < $1.name.lowercased() } ?? []

            let listNameById = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0.name) })
            let listIdByGroupId = Dictionary(uniqueKeysWithValues:
                (result.catalog?.groups ?? []).compactMap { group -> (String, String)? in
                    let groupId = group.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let listId = group.listId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !groupId.isEmpty, !listId.isEmpty else { return nil }
                    return (groupId, listId)
                }
            )

            let products = (result.catalog?.products ?? []).compactMap { product -> CatalogProductUI? in
                let id = product.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !id.isEmpty else { return nil }
                let productListId = product.listId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let fallbackListId = listIdByGroupId[product.groupId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""] ?? ""
                let resolvedListId = !productListId.isEmpty ? productListId : (!fallbackListId.isEmpty ? fallbackListId : "")
                let isBlocked = normalizeCatalogProductBlocked(product)
                let blockReason = isBlocked ? normalizeCatalogProductBlockReason(product) : ""
                let pricing = resolveCatalogProductPricing(product)
                return CatalogProductUI(
                    id: id,
                    name: product.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? product.name! : "Artikel",
                    price: pricing.effectivePrice,
                    regularPrice: pricing.regularPrice,
                    promoEnabled: pricing.promoEnabled,
                    promoPrice: pricing.promoPrice,
                    promoActive: pricing.promoActive,
                    taxRate: product.taxRate ?? 19,
                    groupId: resolvedListId.isEmpty ? nil : resolvedListId,
                    groupName: resolvedListId.isEmpty ? nil : listNameById[resolvedListId],
                    isBlocked: isBlocked,
                    blockReason: blockReason
                )
            }.sorted { $0.name.lowercased() < $1.name.lowercased() }

            let previousSelection = selectedCatalogGroupId
            let nextSelection: String?
            if previousSelection == "__promo__" {
                nextSelection = "__promo__"
            } else if let previousSelection, lists.contains(where: { $0.id == previousSelection }) {
                nextSelection = previousSelection
            } else {
                // Default to "Alle" (nil) if there is no valid previous selection.
                nextSelection = nil
            }

            catalogGroups = lists
            selectedCatalogGroupId = nextSelection
            catalogProducts = products
        } catch {
            // keep old catalog as fallback
        }
    }

    private func refreshTablesFromCoreInternal(noticeOnSuccess: String? = nil) async {
        async let plannerTask = try? repository.readTablePlanner()
        async let orderTask = try? repository.readOrderStore()

        let plannerResult = await plannerTask
        let orderResult = await orderTask

        guard let plannerBody = plannerResult, plannerBody.success,
              let orderBody = orderResult, orderBody.success else {
            return
        }

        latestOrderStore = orderBody.store
        reconcileSubmitOrderRetryKeysFromStore(store: orderBody.store)
        reconcilePaymentRetryKeysFromStore(store: orderBody.store)
        latestPlanner = plannerBody.planner
        latestTableLocks = plannerBody.tableLocks

        let preferredTableId = localStore.loadSelectedTableId(userId: activeUserId, defaultValue: selectedTableId)
        _ = applyStoreSnapshot(store: orderBody.store, preferredTableId: preferredTableId, noticeOnSuccess: noticeOnSuccess)
    }

    private func applyCommandStoreSnapshot(response: StatefulCommandResponse, noticeOnSuccess: String) -> Bool {
        guard let store = response.store else {
            return false
        }
        reconcileSubmitOrderRetryKeysFromStore(store: store)
        reconcilePaymentRetryKeysFromStore(store: store)
        latestOrderStore = store

        let preferred = localStore.loadSelectedTableId(userId: activeUserId, defaultValue: selectedTableId)
        return applyStoreSnapshot(store: store, preferredTableId: preferred, noticeOnSuccess: noticeOnSuccess)
    }

    private func applyStoreSnapshot(store: OrderStoreDTO?, preferredTableId: Int?, noticeOnSuccess: String?) -> Bool {
        guard let planner = latestPlanner else { return false }

        let mapped = mapTables(planner: planner, locks: latestTableLocks, store: store)
        if mapped.isEmpty {
            return false
        }

        let nextSelected: Int
        if let preferredTableId, mapped.contains(where: { $0.id == preferredTableId }) {
            nextSelected = preferredTableId
        } else if mapped.contains(where: { $0.id == selectedTableId }) {
            nextSelected = selectedTableId
        } else {
            nextSelected = mapped.first?.id ?? 1
        }

        let snapshot = extractCurrentOrderFromStore(store, tableId: nextSelected)
        let tableOrderMap = extractAllTableOrders(store)
        let tableVoucherMap = extractAllAppliedVouchers(store)

        let selectedStillExists: Bool
        if let selectedOrderLineId {
            selectedStillExists = snapshot.lines.contains(where: { $0.id == selectedOrderLineId })
        } else {
            selectedStillExists = false
        }

        tables = mapped
        selectedTableId = nextSelected
        currentOrderLines = snapshot.lines
        currentOrderCode = snapshot.code
        tableOrderLinesByTableId = tableOrderMap
        currentAppliedVouchers = snapshot.appliedVouchers
        appliedVouchersByTableId = tableVoucherMap
        selectedOrderLineId = selectedStillExists ? selectedOrderLineId : nil

        if let noticeOnSuccess {
            noticeMessage = noticeOnSuccess
        }
        localStore.saveSelectedTableId(nextSelected, userId: activeUserId)

        if orderOverviewTab == .ready {
            markKitchenReadyNoticesSeenForTable(nextSelected)
        }

        if activeWorkTab == .schlemmer {
            schlemmerPreviewInFlight = true
            schlemmerPreviewShowLoader = false
            Task {
                // Periodic table refresh should update data without a visible loading flash.
                await refreshSchlemmerPreviewInternal(silent: true, lockInteraction: false)
            }
        }

        return true
    }

    private func mapTables(planner: PlannerData, locks: [String: TableLockDTO], store: OrderStoreDTO?) -> [TableCardUI] {
        let lockKeys = Set(locks.keys.compactMap { toTableNumber($0) })
        let orderMap = Dictionary(uniqueKeysWithValues:
            (store?.tableOrders ?? [:]).compactMap { key, value -> (Int, TableOrderEntryDTO)? in
                guard let table = toTableNumber(key) else { return nil }
                return (table, value)
            }
        )

        return planner.tables.compactMap { table -> TableCardUI? in
            guard let number = toTableNumber(table.label ?? table.id) else {
                return nil
            }
            let entry = orderMap[number]
            let lines = entry?.order ?? []
            let total = computeOpenGross(lines)
            let hasActiveLines = lines.contains { line in
                let status = line.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                return (line.qty ?? 0) > 0 && isOpenOrderStatus(status)
            }

            let locked = lockKeys.contains(number) || table.locked == true
            let status: TableStatus
            if locked {
                status = .locked
            } else if hasActiveLines {
                status = .occupied
            } else {
                status = .free
            }

            return TableCardUI(
                id: number,
                label: "Tisch \(number)",
                seats: table.seats_max ?? 4,
                openAmount: locked ? "Gesperrt" : formatEuro(total),
                status: status
            )
        }.sorted { $0.id < $1.id }
    }

    private func extractCurrentOrderFromStore(_ store: OrderStoreDTO?, tableId: Int) -> (lines: [OrderLineUI], code: String, appliedVouchers: [AppliedVoucherUI]) {
        guard let entry = store?.tableOrders[String(tableId)] else {
            return ([], "", [])
        }
        let lines = entry.order.compactMap(mapOrderLine).sorted {
            normalizeOrderStatus($0.status) == "ordered" && normalizeOrderStatus($1.status) != "ordered"
        }
        let appliedVouchers = (entry.appliedVouchers ?? []).compactMap(mapAppliedVoucher).sorted { $0.appliedAt > $1.appliedAt }
        return (lines, entry.orderCode ?? "", appliedVouchers)
    }

    private func extractAllTableOrders(_ store: OrderStoreDTO?) -> [Int: [OrderLineUI]] {
        var mapped: [Int: [OrderLineUI]] = [:]
        for (tableKey, entry) in store?.tableOrders ?? [:] {
            guard let tableId = toTableNumber(tableKey) else { continue }
            mapped[tableId] = entry.order.compactMap(mapOrderLine).sorted {
                normalizeOrderStatus($0.status) == "ordered" && normalizeOrderStatus($1.status) != "ordered"
            }
        }
        return mapped
    }

    private func extractAllAppliedVouchers(_ store: OrderStoreDTO?) -> [Int: [AppliedVoucherUI]] {
        var mapped: [Int: [AppliedVoucherUI]] = [:]
        for (tableKey, entry) in store?.tableOrders ?? [:] {
            guard let tableId = toTableNumber(tableKey) else { continue }
            mapped[tableId] = (entry.appliedVouchers ?? [])
                .compactMap(mapAppliedVoucher)
                .sorted { $0.appliedAt > $1.appliedAt }
        }
        return mapped
    }

    private func mapOrderLine(_ line: OrderLineDTO) -> OrderLineUI? {
        let lineId = line.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let productId = line.productId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !lineId.isEmpty, !productId.isEmpty else {
            return nil
        }
        let promotionMeta = resolveOrderLinePromotionMeta(line)

        return OrderLineUI(
            id: lineId,
            productId: productId,
            name: line.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? line.name! : "Artikel",
            qty: line.qty ?? 0,
            price: line.price ?? 0,
            basePrice: promotionMeta.basePrice,
            promoApplied: promotionMeta.promoApplied,
            promoPrice: promotionMeta.promoPrice,
            taxRate: line.taxRate ?? 19,
            status: line.status?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? line.status! : "new",
            cancelReason: (line.cancelledReason ?? line.cancelled_reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            kitchenReady: line.kitchenReady == true,
            kitchenReadyAt: line.kitchenReadyAt ?? 0,
            kitchenReadyBy: line.kitchenReadyBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    private func mapAppliedVoucher(_ voucher: AppliedVoucherDTO) -> AppliedVoucherUI? {
        let code = voucher.code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        guard !code.isEmpty else {
            return nil
        }
        return AppliedVoucherUI(
            code: code,
            amount: max(0, voucher.amount ?? 0),
            remaining: max(0, voucher.remaining ?? 0),
            appliedAt: voucher.appliedAt ?? 0
        )
    }

    private func computeOpenGross(_ lines: [OrderLineDTO]) -> Double {
        lines.reduce(0) { partial, line in
            let qty = line.qty ?? 0
            let price = line.price ?? 0
            let status = line.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if qty <= 0 || !isOpenOrderStatus(status) {
                return partial
            }
            return partial + (Double(qty) * price)
        }
    }

    private func switchOrderOverviewToOrders() {
        if orderOverviewTab != .orders {
            orderOverviewTab = .orders
        }
    }

    private func resetEventFeedCursors(clearKitchenNotices: Bool = false) {
        syncCursor = 0
        kitchenNoticeCursor = 0
        localStore.saveSyncCursor(syncCursor)
        localStore.saveKitchenNoticeCursor(kitchenNoticeCursor)

        seenReadyEventIdsOrder.removeAll()
        seenReadyEventIdsSet.removeAll()
        seenReadyEventIdsDirty = false
        localStore.saveSeenReadyEventIds([])

        if clearKitchenNotices {
            kitchenReadyNoticesByTable = [:]
            kitchenReadyLastSeenCursorByTable = [:]
            localStore.saveReadyLastSeenCursorByTable([:])
            orderOverviewTab = .orders
        }
    }

    private func shouldResetRetryKey(error: Error) -> Bool {
        guard let apiError = error as? CoreClientError else {
            return false
        }
        if apiError.errorCode.uppercased().contains("IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD") {
            return true
        }
        if let status = apiError.statusCode, (400...499).contains(status), status != 408, status != 429 {
            return true
        }
        return false
    }

    private func getOrCreateSubmitOrderRetryKey(tableId: String) -> String {
        let normalizedTableId = tableId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = pendingSubmitOrderIdempotencyKeysByTableId[normalizedTableId], !existing.isEmpty {
            return existing
        }
        let created = IdempotencyKeyFactory.next(scope: "orders-submit", platformPrefix: "ios")
        pendingSubmitOrderIdempotencyKeysByTableId[normalizedTableId] = created
        localStore.savePendingSubmitOrderKeys(pendingSubmitOrderIdempotencyKeysByTableId)
        return created
    }

    private func removeSubmitOrderRetryKey(tableId: String) {
        let normalizedTableId = tableId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTableId.isEmpty else { return }
        if pendingSubmitOrderIdempotencyKeysByTableId.removeValue(forKey: normalizedTableId) != nil {
            localStore.savePendingSubmitOrderKeys(pendingSubmitOrderIdempotencyKeysByTableId)
        }
    }

    private func reconcileSubmitOrderRetryKeysFromStore(store: OrderStoreDTO?) {
        guard !pendingSubmitOrderIdempotencyKeysByTableId.isEmpty else { return }
        let tableHasNewLines = Dictionary(uniqueKeysWithValues:
            (store?.tableOrders ?? [:]).map { key, entry -> (String, Bool) in
                let hasNew = entry.order.contains { line in
                    (line.qty ?? 0) > 0 && normalizeOrderStatus(line.status ?? "") == "new"
                }
                return (key, hasNew)
            }
        )

        var changed = false
        for key in Array(pendingSubmitOrderIdempotencyKeysByTableId.keys) {
            if tableHasNewLines[key] != true {
                pendingSubmitOrderIdempotencyKeysByTableId.removeValue(forKey: key)
                changed = true
            }
        }
        if changed {
            localStore.savePendingSubmitOrderKeys(pendingSubmitOrderIdempotencyKeysByTableId)
        }
    }

    private func normalizePaymentMethodToken(_ method: String) -> String {
        method
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func canonicalSplitSelectionToken(_ splitSelection: [String: Int]) -> String {
        if splitSelection.isEmpty {
            return "-"
        }
        let token = splitSelection
            .map { (productId: $0.key.trimmingCharacters(in: .whitespacesAndNewlines), qty: max(0, $0.value)) }
            .filter { !$0.productId.isEmpty && $0.qty > 0 }
            .sorted { $0.productId < $1.productId }
            .map { "\($0.productId):\($0.qty)" }
            .joined(separator: ",")
        return token.isEmpty ? "-" : token
    }

    private func buildPaymentRetryScope(type: String, tableId: String, orderCode: String, method: String, splitSelection: [String: Int]) -> String {
        let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().isEmpty ? "sale" : type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTableId = tableId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOrderCode = orderCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMethod = normalizePaymentMethodToken(method)
        let splitToken = normalizedType == "split" ? canonicalSplitSelectionToken(splitSelection) : "-"
        return "\(normalizedType)|\(normalizedTableId)|\(normalizedOrderCode)|\(normalizedMethod)|\(splitToken)"
    }

    private func getOrCreatePaymentRetryKey(scope: String, idempotencyScope: String) -> String {
        let normalized = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = pendingPaymentIdempotencyKeysByScope[normalized], !existing.isEmpty {
            return existing
        }
        let created = IdempotencyKeyFactory.next(scope: idempotencyScope, platformPrefix: "ios")
        pendingPaymentIdempotencyKeysByScope[normalized] = created
        localStore.savePendingPaymentKeys(pendingPaymentIdempotencyKeysByScope)
        return created
    }

    private func removePaymentRetryKey(scope: String) {
        let normalized = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if pendingPaymentIdempotencyKeysByScope.removeValue(forKey: normalized) != nil {
            localStore.savePendingPaymentKeys(pendingPaymentIdempotencyKeysByScope)
        }
    }

    private func reconcilePaymentRetryKeysFromStore(store: OrderStoreDTO?) {
        guard !pendingPaymentIdempotencyKeysByScope.isEmpty else { return }
        var changed = false
        for scope in Array(pendingPaymentIdempotencyKeysByScope.keys) {
            let parts = scope.split(separator: "|").map(String.init)
            if parts.count < 3 {
                pendingPaymentIdempotencyKeysByScope.removeValue(forKey: scope)
                changed = true
                continue
            }
            let tableId = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let scopedOrderCode = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            if tableId.isEmpty || scopedOrderCode.isEmpty {
                pendingPaymentIdempotencyKeysByScope.removeValue(forKey: scope)
                changed = true
                continue
            }
            let currentOrderCode = store?.tableOrders[tableId]?.orderCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if currentOrderCode.isEmpty || currentOrderCode != scopedOrderCode {
                pendingPaymentIdempotencyKeysByScope.removeValue(forKey: scope)
                changed = true
            }
        }
        if changed {
            localStore.savePendingPaymentKeys(pendingPaymentIdempotencyKeysByScope)
        }
    }

    private func normalizeCatalogProductPromoEnabled(_ product: CatalogProductDTO) -> Bool {
        product.promoEnabled == true ||
            product.promo_enabled == true ||
            product.actionPriceEnabled == true ||
            product.action_price_enabled == true
    }

    private func normalizeCatalogProductPromoPrice(_ product: CatalogProductDTO) -> Double? {
        let candidate = product.promoPrice ?? product.promo_price ?? product.actionPrice ?? product.action_price
        guard let candidate else {
            return nil
        }
        return max(0, candidate)
    }

    private func resolveCatalogProductPricing(_ product: CatalogProductDTO) -> (
        regularPrice: Double,
        promoEnabled: Bool,
        promoPrice: Double?,
        promoActive: Bool,
        effectivePrice: Double
    ) {
        let regularPrice = max(0, product.price ?? 0)
        let promoEnabled = normalizeCatalogProductPromoEnabled(product)
        let promoPrice = normalizeCatalogProductPromoPrice(product)
        let promoActive = promoEnabled && (promoPrice ?? 0) > 0 && (promoPrice ?? 0) < regularPrice
        let effectivePrice = promoActive ? (promoPrice ?? regularPrice) : regularPrice
        return (regularPrice, promoEnabled, promoPrice, promoActive, effectivePrice)
    }

    private func resolveOrderLinePromotionMeta(_ line: OrderLineDTO) -> (basePrice: Double, promoApplied: Bool, promoPrice: Double?) {
        let unitPrice = max(0, line.price ?? 0)
        let basePrice = max(unitPrice, line.basePrice ?? line.base_price ?? unitPrice)
        let explicitPromoApplied = line.promoApplied == true || line.promo_applied == true
        let promoPriceCandidate = max(0, line.promoPrice ?? line.promo_price ?? unitPrice)
        let inferredPromoApplied = promoPriceCandidate > 0 && promoPriceCandidate < basePrice
        let promoApplied = explicitPromoApplied || inferredPromoApplied || (unitPrice + 0.001) < basePrice
        return (basePrice, promoApplied, promoApplied ? promoPriceCandidate : nil)
    }

    private func normalizeCatalogProductBlocked(_ product: CatalogProductDTO) -> Bool {
        product.isBlocked == true || product.is_blocked == true || product.is_blocked_flag == true || product.blocked == true
    }

    private func normalizeCatalogProductBlockReason(_ product: CatalogProductDTO) -> String {
        (product.blockReason ?? product.block_reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isProductBlockedError(_ errorCodeOrMessage: String?) -> Bool {
        let normalized = errorCodeOrMessage?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        if normalized == "PRODUCT_BLOCKED" {
            return true
        }
        return normalized.contains("PRODUCT_BLOCKED") || normalized.contains("OUT_OF_STOCK") || normalized.contains("SOLD_OUT")
    }

    private func extractBlockedReason(_ result: CoreCommandResult?) -> String {
        result?.value?["reason"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func markProductBlockedInUi(productId: String, reason: String) {
        let normalizedId = productId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedId.isEmpty else { return }
        catalogProducts = catalogProducts.map { product in
            guard product.id == normalizedId else { return product }
            return CatalogProductUI(
                id: product.id,
                name: product.name,
                price: product.price,
                regularPrice: product.regularPrice,
                promoEnabled: product.promoEnabled,
                promoPrice: product.promoPrice,
                promoActive: product.promoActive,
                taxRate: product.taxRate,
                groupId: product.groupId,
                groupName: product.groupName,
                isBlocked: true,
                blockReason: reason.isEmpty ? "Ausverkauft" : reason
            )
        }
    }

    private func refreshSchlemmerPreviewInternal(silent: Bool = false, lockInteraction: Bool = true) async {
        guard isSchlemmerBlockModuleEnabled else {
            schlemmerPreviewRequestGeneration &+= 1
            schlemmerEligibleLines = []
            schlemmerSelection = [:]
            schlemmerAutoSelection = [:]
            schlemmerRequiredFoodUnits = 0
            schlemmerAvailableUnits = 0
            schlemmerRequiredSelectionCount = 0
            schlemmerSelectedUnits = 0
            schlemmerLastErrorCode = nil
            schlemmerPreviewInFlight = false
            schlemmerPreviewShowLoader = false
            return
        }
        guard isOnline else {
            schlemmerPreviewRequestGeneration &+= 1
            schlemmerPreviewInFlight = false
            schlemmerPreviewShowLoader = false
            if !silent {
                noticeMessage = "Schlemmer Block nur online verfügbar."
            }
            return
        }

        schlemmerPreviewRequestGeneration &+= 1
        let requestGeneration = schlemmerPreviewRequestGeneration
        schlemmerPreviewInFlight = true
        schlemmerPreviewShowLoader = lockInteraction ? !silent : false
        defer {
            if requestGeneration == schlemmerPreviewRequestGeneration {
                schlemmerPreviewInFlight = false
                schlemmerPreviewShowLoader = false
            }
        }
        do {
            let payloadSelection = schlemmerSelection.isEmpty ? nil : schlemmerSelection
            let result = try await repository.previewSchlemmer(
                tableId: String(selectedTableId),
                type: schlemmerType.coreValue,
                selection: payloadSelection
            )
            guard requestGeneration == schlemmerPreviewRequestGeneration else { return }
            if result.success, result.result?.ok == true {
                schlemmerLastErrorCode = nil
                applySchlemmerPreviewValue(result.result?.value)
            } else {
                let errorCode = result.result?.error ?? result.error ?? "SCHLEMMER_PREVIEW_FAILED"
                schlemmerLastErrorCode = errorCode
                if errorCode.uppercased() == "SCHLEMMER_MODULE_DISABLED" {
                    isSchlemmerBlockModuleEnabled = false
                    enforceModuleDependentUiState()
                }
                if !silent {
                    noticeMessage = describeSchlemmerError(errorCode)
                }
            }
        } catch {
            guard requestGeneration == schlemmerPreviewRequestGeneration else { return }
            let errorCode = (error as? CoreClientError)?.errorCode ?? error.localizedDescription
            schlemmerLastErrorCode = errorCode
            if !silent {
                noticeMessage = describeSchlemmerError(errorCode)
            }
        }
    }

    private func applySchlemmerPreviewValue(_ value: [String: JSONValue]?) {
        let payload = value ?? [:]
        let parsedAvailable = payload["availableUnits"]?.intValue ?? 0
        let parsedRequiredFood = payload["requiredFoodUnits"]?.intValue ?? 0
        let parsedRequiredSelection = payload["requiredSelectionCount"]?.intValue ?? 0
        let parsedEligible = parseSchlemmerEligibleLines(payload["eligibleLines"])
        let parsedAutoSelection = normalizeSchlemmerSelection(
            parseSchlemmerSelectionPayload(payload["autoSelection"]),
            eligibleLines: parsedEligible
        )
        let parsedSelection = normalizeSchlemmerSelection(
            parseSchlemmerSelectionPayload(payload["selection"]),
            eligibleLines: parsedEligible
        )

        schlemmerAvailableUnits = max(0, parsedAvailable)
        schlemmerRequiredFoodUnits = max(0, parsedRequiredFood)
        schlemmerRequiredSelectionCount = max(0, parsedRequiredSelection)
        schlemmerEligibleLines = parsedEligible
        schlemmerAutoSelection = parsedAutoSelection

        let fallbackSelection = parsedSelection.isEmpty ? parsedAutoSelection : parsedSelection
        schlemmerSelection = fallbackSelection
        let selectedUnitsFromPayload = payload["selectedUnits"]?.intValue ?? fallbackSelection.values.reduce(0, +)
        schlemmerSelectedUnits = max(0, selectedUnitsFromPayload)
    }

    private func parseSchlemmerEligibleLines(_ value: JSONValue?) -> [SchlemmerEligibleLineUI] {
        guard case .array(let array)? = value else { return [] }
        return array.compactMap { item in
            guard case .object(let raw) = item else { return nil }
            let lineId = raw["lineId"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let productId = raw["productId"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !lineId.isEmpty, !productId.isEmpty else { return nil }
            let resolvedName = raw["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return SchlemmerEligibleLineUI(
                lineId: lineId,
                productId: productId,
                name: resolvedName.isEmpty ? "Artikel" : resolvedName,
                qty: max(0, raw["qty"]?.intValue ?? 0),
                unitPrice: max(0, raw["unitPrice"]?.doubleValue ?? 0),
                isKidsMeal: raw["isKidsMeal"]?.boolValue == true
            )
        }
    }

    private func parseSchlemmerSelectionPayload(_ value: JSONValue?) -> [String: Int] {
        guard case .object(let object)? = value else { return [:] }
        var parsed: [String: Int] = [:]
        for (key, rawValue) in object {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty else { continue }
            let qty = max(0, rawValue.intValue ?? 0)
            if qty > 0 {
                parsed[normalizedKey] = qty
            }
        }
        return parsed
    }

    private func normalizeSchlemmerSelection(_ selection: [String: Int], eligibleLines: [SchlemmerEligibleLineUI]) -> [String: Int] {
        let maxByLine = Dictionary(uniqueKeysWithValues: eligibleLines.map { ($0.lineId, max(0, $0.qty)) })
        var normalized: [String: Int] = [:]
        for (lineIdRaw, qtyRaw) in selection {
            let lineId = lineIdRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lineId.isEmpty, let maxQty = maxByLine[lineId], maxQty > 0 else { continue }
            let qty = min(max(0, qtyRaw), maxQty)
            if qty > 0 {
                normalized[lineId] = qty
            }
        }
        return normalized
    }

    private func describeVoucherError(_ rawCode: String) -> String {
        let normalized = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "INVALID_VOUCHER_CODE":
            return "Gutschein Nummer ungültig."
        case "VOUCHER_NOT_FOUND":
            return "Gutschein Nummer unbekannt."
        case "VOUCHER_EXPIRED":
            return "Gutschein abgelaufen."
        case "VOUCHER_ALREADY_REDEEMED":
            return "Gutschein bereits verwendet."
        case "VOUCHER_RESERVED_FOR_OTHER_TABLE":
            return "Gutschein ist bereits an einem anderen Tisch reserviert."
        case "VOUCHER_NOT_APPLIED":
            return "Gutschein wurde auf diesem Tisch nicht angewendet."
        default:
            return "Gutschein konnte nicht verarbeitet werden: \(normalized.isEmpty ? rawCode : normalized)"
        }
    }

    private func describeSchlemmerError(_ rawCode: String) -> String {
        let normalized = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.contains("SCHLEMMER_NOT_ENOUGH_FOOD_ITEMS")
            || normalized.contains("SCHLEMMER_INSUFFICIENT_FOOD_UNITS")
            || normalized.contains("SCHLEMMER_NO_ELIGIBLE_LINES")
            || normalized.contains("SCHLEMMER_NO_ELIGIBLE_ITEMS") {
            return schlemmerInsufficientItemsMessage(for: schlemmerType)
        }
        if normalized.contains("HTTP_422") || normalized.contains("UNPROCESSABLE_ENTITY") {
            return schlemmerInsufficientItemsMessage(for: schlemmerType)
        }
        switch normalized {
        case "INVALID_SCHLEMMER_TYPE":
            return "Ungültiger Schlemmer-Block-Typ."
        case "SCHLEMMER_MODULE_DISABLED":
            return "Schlemmer Block Modul ist nicht aktiv."
        case "SCHLEMMER_SELECTION_EMPTY":
            return "Bitte mindestens eine Schlemmer-Position auswählen."
        case "SCHLEMMER_SELECTION_INVALID":
            return "Schlemmer-Auswahl ist ungültig."
        case "SCHLEMMER_SELECTION_MISMATCH":
            return "Schlemmer-Auswahl ist ungültig."
        case "SCHLEMMER_KIDS_MEAL_REQUIRED":
            return "Für Familie muss mindestens ein Kinderessen bestellt sein."
        case "SCHLEMMER_CANCEL_FAILED":
            return "Schlemmer Block konnte nicht angewendet werden."
        default:
            return "Schlemmer Block fehlgeschlagen: \(normalized.isEmpty ? rawCode : normalized)"
        }
    }

    private func schlemmerMinimumFoodUnits(for type: SchlemmerBlockTypeUI) -> Int {
        switch type {
        case .twoForOne:
            return 2
        case .fourForTwo:
            return 4
        case .family:
            return 1
        }
    }

    private func schlemmerInsufficientItemsMessage(for type: SchlemmerBlockTypeUI) -> String {
        switch type {
        case .twoForOne:
            return "Mindestens 2 Essen müssen bestellt sein."
        case .fourForTwo:
            return "Mindestens 4 Essen müssen bestellt sein."
        case .family:
            return "Für Familie muss mindestens ein Kinderessen bestellt sein."
        }
    }

    private func isOpenOrderStatus(_ status: String?) -> Bool {
        let normalized = normalizeOrderStatus(status)
        return normalized.isEmpty || normalized == "new" || normalized == "ordered"
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

    private func formatEuro(_ value: Double) -> String {
        String(format: "%.2f EUR", locale: Locale(identifier: "de_DE"), value)
    }

    private func toTableNumber(_ value: String?) -> Int? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed), parsed > 0 else {
            return nil
        }
        return parsed
    }

    private func formatTimestamp(_ timestamp: Int64?) -> String {
        guard let timestamp, timestamp > 0 else {
            return "-"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0))
    }

    private func parsePairingQrScanPayload(_ rawText: String) -> PairingQrScanPayload? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = trimmed.data(using: .utf8),
           let rawJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let protocolValue = readString(rawJson, keys: ["protocol"])?.lowercased()
            guard protocolValue == "kasse-core-pairing.v1" else {
                return nil
            }

            guard let pairingCodeRaw = readString(rawJson, keys: ["pairingCode", "pairing_code", "code"]) else {
                return nil
            }
            let pairingCode = pairingCodeRaw.uppercased()
            guard !pairingCode.isEmpty else {
                return nil
            }

            let hostDirect = readString(rawJson, keys: ["host", "ipAddress", "coreApiHost"])
            let portDirect = readPort(rawJson, keys: ["port", "coreApiPort"])
            let urlFallback = readHostAndPortFromBaseUrl(rawJson, keys: ["coreApiBaseUrl", "baseUrl", "coreApiUrl"])

            if hasAnyKey(rawJson, keys: ["port", "coreApiPort"]),
               portDirect == nil {
                return nil
            }

            let host = normalizeHost(hostDirect ?? urlFallback.host)
            let port = normalizePort(portDirect ?? urlFallback.port)
            let expiresAt = readInt64(rawJson, keys: ["expiresAt", "expires_at"])

            return PairingQrScanPayload(
                host: host,
                port: port,
                pairingCode: pairingCode,
                expiresAt: expiresAt
            )
        }

        let fallback = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        if fallback.count >= 4 && fallback.count <= 32 {
            return PairingQrScanPayload(host: nil, port: nil, pairingCode: fallback, expiresAt: nil)
        }
        return nil
    }

    private func hasAnyKey(_ json: [String: Any], keys: [String]) -> Bool {
        keys.contains { json[$0] != nil }
    }

    private func readString(_ json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = json[key] else { continue }
            if let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
                continue
            }
            if let number = value as? NSNumber {
                let text = number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private func readPort(_ json: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            guard let value = json[key] else { continue }
            if let portInt = value as? Int {
                return normalizePort(portInt)
            }
            if let portString = value as? String,
               let portInt = Int(portString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return normalizePort(portInt)
            }
            if let number = value as? NSNumber {
                return normalizePort(number.intValue)
            }
        }
        return nil
    }

    private func readInt64(_ json: [String: Any], keys: [String]) -> Int64? {
        for key in keys {
            guard let value = json[key] else { continue }
            if let int64 = value as? Int64 {
                return int64
            }
            if let intValue = value as? Int {
                return Int64(intValue)
            }
            if let text = value as? String,
               let intValue = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return intValue
            }
            if let number = value as? NSNumber {
                return number.int64Value
            }
        }
        return nil
    }

    private func readHostAndPortFromBaseUrl(_ json: [String: Any], keys: [String]) -> (host: String?, port: Int?) {
        for key in keys {
            guard let raw = readString(json, keys: [key]) else { continue }
            if let extracted = parseHostAndPortFromUrlString(raw) {
                return extracted
            }
        }
        return (host: nil, port: nil)
    }

    private func parseHostAndPortFromUrlString(_ raw: String) -> (host: String?, port: Int?)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let valueWithScheme: String
        if trimmed.contains("://") {
            valueWithScheme = trimmed
        } else {
            valueWithScheme = "http://\(trimmed)"
        }

        guard let components = URLComponents(string: valueWithScheme) else {
            return nil
        }

        let host = normalizeHost(components.host)
        let port = normalizePort(components.port)
        if host == nil, port == nil {
            return nil
        }
        return (host: host, port: port)
    }

    private func normalizeHost(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func normalizePort(_ value: Int?) -> Int? {
        guard let value, (1...65535).contains(value) else {
            return nil
        }
        return value
    }

    private func readTableIdFromPayload(_ payload: [String: JSONValue]) -> Int? {
        if let direct = payload["tableId"]?.intValue, direct > 0 {
            return direct
        }
        if let snake = payload["table_id"]?.intValue, snake > 0 {
            return snake
        }
        if let text = payload["tableId"]?.stringValue, let parsed = Int(text), parsed > 0 {
            return parsed
        }
        if let text = payload["table_id"]?.stringValue, let parsed = Int(text), parsed > 0 {
            return parsed
        }
        return nil
    }
}
