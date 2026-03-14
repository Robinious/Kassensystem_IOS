import Foundation

struct CoreEndpoint: Equatable {
    let host: String
    let port: Int

    var baseURL: URL {
        URL(string: "http://\(host):\(port)/api/core/v1/")!
    }
}

enum CoreClientError: LocalizedError {
    case invalidURL
    case network(message: String)
    case http(statusCode: Int, code: String, message: String)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "INVALID_URL"
        case .network(let message):
            return message
        case .http(_, let code, let message):
            if message.isEmpty {
                return code
            }
            return "\(code): \(message)"
        case .decoding(let message):
            return "DECODE_ERROR: \(message)"
        }
    }

    var statusCode: Int? {
        switch self {
        case .http(let statusCode, _, _):
            return statusCode
        default:
            return nil
        }
    }

    var errorCode: String {
        switch self {
        case .invalidURL:
            return "INVALID_URL"
        case .network:
            return "NETWORK_ERROR"
        case .http(_, let code, _):
            return code
        case .decoding:
            return "DECODE_ERROR"
        }
    }
}

final class CoreAPIClient {
    private var endpoint: CoreEndpoint
    private let coreTokenProvider: () -> String
    private let sessionTokenProvider: () -> String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        endpoint: CoreEndpoint,
        coreTokenProvider: @escaping () -> String,
        sessionTokenProvider: @escaping () -> String
    ) {
        self.endpoint = endpoint
        self.coreTokenProvider = coreTokenProvider
        self.sessionTokenProvider = sessionTokenProvider

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func setEndpoint(host: String, port: Int) {
        let normalizedHost = Self.normalizeHost(host)
        let normalizedPort = max(1, min(65535, port))
        endpoint = CoreEndpoint(host: normalizedHost, port: normalizedPort)
    }

    func getEndpoint() -> CoreEndpoint {
        endpoint
    }

    func health() async throws -> CoreHealthResponse {
        try await request(path: "health", method: "GET", body: Optional<String>.none)
    }

    func contract() async throws -> CoreContractResponse {
        try await request(path: "contract", method: "GET", body: Optional<String>.none)
    }

    func createPairing(expiresInMs: Int64?, createdBy: String?) async throws -> PairingCreateResponse {
        let payload = PairingCreatePayload(expiresInMs: expiresInMs, createdBy: createdBy)
        return try await request(path: "auth/pairing/create", method: "POST", body: PayloadRequest(payload: payload))
    }

    func claimPairing(pairingCode: String, deviceName: String, model: String, deviceId: String) async throws -> PairingClaimResponse {
        let payload = PairingClaimPayload(
            pairingCode: pairingCode,
            device: DeviceDescriptor(
                id: deviceId,
                name: deviceName,
                platform: "ios",
                appVersion: "0.1.0",
                model: model
            )
        )
        return try await request(path: "auth/pairing/claim", method: "POST", body: PayloadRequest(payload: payload))
    }

    func login(deviceId: String, deviceKey: String, userId: String, pin: String) async throws -> LoginResponse {
        let payload = LoginPayload(
            deviceId: deviceId,
            deviceKey: deviceKey,
            userId: userId,
            pin: pin,
            sessionTtlMs: nil
        )
        return try await request(path: "auth/login", method: "POST", body: PayloadRequest(payload: payload))
    }

    func sessionInfo() async throws -> SessionResponse {
        try await request(path: "auth/session", method: "GET", body: Optional<String>.none)
    }

    func logout() async throws -> SessionResponse {
        try await request(path: "auth/logout", method: "POST", body: PayloadRequest(payload: [String: String]()))
    }

    func readCatalog() async throws -> CoreCatalogResponse {
        try await request(path: "read/catalog", method: "GET", body: Optional<String>.none)
    }

    func readTablePlanner() async throws -> TablePlannerReadResponse {
        try await request(path: "read/table-planner", method: "GET", body: Optional<String>.none)
    }

    func readOrderStore() async throws -> OrderStoreReadResponse {
        try await request(path: "read/order-store", method: "GET", body: Optional<String>.none)
    }

    func readEvents(cursor: Int64?, limit: Int?) async throws -> CoreEventsResponse {
        var query: [URLQueryItem] = []
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: String(cursor)))
        }
        if let limit {
            query.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        return try await request(path: "read/events", method: "GET", query: query, body: Optional<String>.none)
    }

    func readKitchenNotices(cursor: Int64?, limit: Int?) async throws -> CoreKitchenNoticesResponse {
        var query: [URLQueryItem] = []
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: String(cursor)))
        }
        if let limit {
            query.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        return try await request(path: "read/kitchen-notices", method: "GET", query: query, body: Optional<String>.none)
    }

    func addLine(tableId: String, product: CatalogProductDTO) async throws -> StatefulCommandResponse {
        let payload = AddLinePayload(
            tableId: tableId,
            product: OrderProductPayload(
                id: product.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                name: product.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                price: product.price ?? 0,
                taxRate: product.taxRate ?? 19
            )
        )
        return try await request(
            path: "commands/orders/add-line",
            method: "POST",
            body: PayloadRequest(payload: payload),
            idempotencyKey: IdempotencyKeyFactory.next(scope: "orders-add-line", platformPrefix: "ios")
        )
    }

    func removeOneLine(tableId: String, lineId: String) async throws -> StatefulCommandResponse {
        let payload = RemoveOneLinePayload(tableId: tableId, lineId: lineId)
        return try await request(
            path: "commands/orders/remove-one-line",
            method: "POST",
            body: PayloadRequest(payload: payload),
            idempotencyKey: IdempotencyKeyFactory.next(scope: "orders-remove-one-line", platformPrefix: "ios")
        )
    }

    func submitOrder(tableId: String, idempotencyKey: String) async throws -> StatefulCommandResponse {
        let payload = SubmitOrderPayload(tableId: tableId)
        return try await request(
            path: "commands/orders/submit",
            method: "POST",
            body: PayloadRequest(payload: payload),
            idempotencyKey: idempotencyKey
        )
    }

    func switchTable(nextTableId: String) async throws -> StatefulCommandResponse {
        let payload = SwitchTablePayload(nextTableId: nextTableId)
        return try await request(
            path: "commands/orders/switch-table",
            method: "POST",
            body: PayloadRequest(payload: payload),
            idempotencyKey: IdempotencyKeyFactory.next(scope: "orders-switch-table", platformPrefix: "ios")
        )
    }

    func cancelOrderedLine(tableId: String, lineId: String, sourceTicketId: String?) async throws -> StatefulCommandResponse {
        let payload = CancelOrderedLinePayload(tableId: tableId, lineId: lineId, sourceTicketId: sourceTicketId)
        return try await request(
            path: "commands/orders/cancel-ordered-line",
            method: "POST",
            body: PayloadRequest(payload: payload),
            idempotencyKey: IdempotencyKeyFactory.next(scope: "orders-cancel-ordered-line", platformPrefix: "ios")
        )
    }

    func transferItems(sourceTableId: String, targetTableId: String, selectionEntries: [TransferSelectionEntryPayload]) async throws -> StatefulCommandResponse {
        let payload = TransferItemsPayload(
            sourceTableId: sourceTableId,
            targetTableId: targetTableId,
            selectionEntries: selectionEntries
        )
        return try await request(
            path: "commands/orders/transfer-items",
            method: "POST",
            body: PayloadRequest(payload: payload),
            idempotencyKey: IdempotencyKeyFactory.next(scope: "orders-transfer-items", platformPrefix: "ios")
        )
    }

    func finalizePayment(tableId: String, method: String, currentUserId: String?, idempotencyKey: String) async throws -> StatefulCommandResponse {
        let payload = FinalizePaymentPayload(tableId: tableId, method: method, currentUserId: currentUserId)
        return try await request(
            path: "commands/payments/finalize",
            method: "POST",
            body: PayloadRequest(payload: payload),
            idempotencyKey: idempotencyKey
        )
    }

    func finalizeSplitPayment(tableId: String, method: String, splitSelection: [String: Int], currentUserId: String?, idempotencyKey: String) async throws -> StatefulCommandResponse {
        let payload = FinalizeSplitPaymentPayload(
            tableId: tableId,
            method: method,
            splitSelection: splitSelection,
            currentUserId: currentUserId
        )
        return try await request(
            path: "commands/payments/finalize-split",
            method: "POST",
            body: PayloadRequest(payload: payload),
            idempotencyKey: idempotencyKey
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Body?,
        idempotencyKey: String? = nil
    ) async throws -> Response {
        guard let url = makeURL(path: path, query: query) else {
            throw CoreClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let coreToken = coreTokenProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        if !coreToken.isEmpty {
            request.setValue(coreToken, forHTTPHeaderField: "x-core-api-token")
        }

        let sessionToken = sessionTokenProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        if !sessionToken.isEmpty {
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }

        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CoreClientError.network(message: "INVALID_HTTP_RESPONSE")
            }

            if (200..<300).contains(http.statusCode) {
                do {
                    return try decoder.decode(Response.self, from: data)
                } catch {
                    let raw = String(data: data, encoding: .utf8) ?? ""
                    throw CoreClientError.decoding(message: "\(error.localizedDescription) [\(raw)]")
                }
            }

            let decodedError = try? decoder.decode(CoreErrorEnvelope.self, from: data)
            let errorCode = decodedError?.result?.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? decodedError?.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "HTTP_\(http.statusCode)"
            let message = String(data: data, encoding: .utf8) ?? ""
            throw CoreClientError.http(statusCode: http.statusCode, code: errorCode, message: message)
        } catch let error as CoreClientError {
            throw error
        } catch {
            throw CoreClientError.network(message: "NETWORK_ERROR: \(error.localizedDescription)")
        }
    }

    private func makeURL(path: String, query: [URLQueryItem]) -> URL? {
        let base = endpoint.baseURL
        guard var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            return nil
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        return components.url
    }

    private static func normalizeHost(_ host: String) -> String {
        host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
