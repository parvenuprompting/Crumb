import Foundation

struct CookiePromptInput: Sendable, Codable {
    let domain: String
    let name: String
    let isSecure: Bool
    let isHttpOnly: Bool
    let isSessionOnly: Bool
    let hasExpiry: Bool
    let expiresInSeconds: Int?
    let browser: String
}

enum LLMVerdict: String, Sendable, Hashable {
    case keep
    case review
    case safe

    init?(raw: String) {
        switch raw.lowercased().replacingOccurrences(of: " ", with: "") {
        case "keep", "bewaren": self = .keep
        case "review", "reviewsuggested", "twijfel": self = .review
        case "safe", "safetoclean", "opschonen": self = .safe
        default: return nil
        }
    }
}

struct LLMCookieJudgement: Sendable {
    let domain: String
    let name: String
    let category: CookieCategory
    let verdict: LLMVerdict
    let reasoning: String
}

enum OllamaError: LocalizedError {
    case unreachable
    case modelMissing(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .unreachable:
            return "Ollama niet bereikbaar op localhost:11434."
        case .modelMissing(let model):
            return "Model '\(model)' niet gevonden in Ollama. Trek het met 'ollama pull \(model)'."
        case .badResponse(let detail):
            return "Ongeldig antwoord van Ollama: \(detail)"
        }
    }
}

struct OllamaClient: Sendable {
    var baseURL: URL
    var requestTimeout: TimeInterval
    var maxConcurrentBatches: Int = 2
    var maxBatchesPerRun: Int = 25
    var cookiesPerBatch: Int = 10

    init(baseURL: URL = URL(string: "http://localhost:11434")!, requestTimeout: TimeInterval = 90) {
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
    }

    private func makeRequest(path: String, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = requestTimeout
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func listModels() async throws -> [String] {
        let request = makeRequest(path: "api/tags", method: "GET", body: nil)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OllamaError.unreachable
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaError.unreachable
        }
        struct TagsResponse: Codable { struct Model: Codable { let name: String }; let models: [Model] }
        guard let tags = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            throw OllamaError.badResponse("onleesbare /api/tags")
        }
        return tags.models.map(\.name)
    }

    func verify(model: String) async throws {
        let models = try await listModels()
        let short = model.contains(":") ? model : model + ":latest"
        guard models.contains(model) || models.contains(short) || models.contains(where: { $0.hasPrefix(model) }) else {
            throw OllamaError.modelMissing(model)
        }
    }

    private static let systemPrompt = """
    Je bent een cookie-classificator voor een macOS privacy-app. Je beoordeelt browser-cookies op basis van ALLEEN metadata (domein, naam, vlaggen). Je krijgt nooit cookie-waarden te zien.

    Geef per cookie een JSON-object terug met:
    - "domain": het domein
    - "name": de cookienaam
    - "category": één van "essential", "functional", "analytics", "marketingTracking", "thirdPartyUnknown", "unknown"
    - "verdict": één van "keep", "review", "safe"
      - "keep": cookie is nodig of onschadelijk en moet blijven
      - "review": twijfelgeval, de gebruiker moet beslissen
      - "safe": uitsluitend tracking/advertising met geen enkele login- of sitefunctie
    - "reasoning": korte uitleg in het Nederlands (maximaal 1 zin)

    Regels:
    - Wees conservatief. Cookies die ook maar ergens een sessie-, login- of beveiligingsfunctie kunnen hebben krijgen "keep" of "review", nooit "safe".
    - Cookies van advertentie-/trackingnetwerken (DoubleClick, Criteo, Adnxs, Taboola, Rubicon e.d.) zijn "marketingTracking".
    - Bekende analytics-cookies (_ga, _gid, _fbp e.d.) zijn "analytics".

    Antwoord ALLEEN met geldige JSON in dit formaat:
    {"cookies":[{"domain":"...","name":"...","category":"...","verdict":"...","reasoning":"..."}]}
    """

    func classifyBatch(model: String, cookies: [CookiePromptInput]) async throws -> [LLMCookieJudgement] {
        guard !cookies.isEmpty else { return [] }

        struct CookieLine: Codable {
            let domain: String
            let name: String
            let secure: Bool
            let httpOnly: Bool
            let sessionOnly: Bool
            let hasExpiry: Bool
            let expiresInDays: Int?
            let browser: String
        }
        let lines = cookies.map {
            CookieLine(
                domain: $0.domain,
                name: $0.name,
                secure: $0.isSecure,
                httpOnly: $0.isHttpOnly,
                sessionOnly: $0.isSessionOnly,
                hasExpiry: $0.hasExpiry,
                expiresInDays: $0.expiresInSeconds.map { $0 / 86_400 },
                browser: $0.browser
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try String(data: encoder.encode(lines), encoding: .utf8) ?? "[]"

        let messages: [[String: String]] = [
            ["role": "system", "content": Self.systemPrompt],
            ["role": "user", "content": payload]
        ]
        struct ChatRequest: Codable {
            let model: String
            let messages: [[String: String]]
            let format: String
            let stream: Bool
            let options: [String: Double]
        }
        let body = try JSONEncoder().encode(ChatRequest(
            model: model,
            messages: messages,
            format: "json",
            stream: false,
            options: ["temperature": 0.0]
        ))

        let request = makeRequest(path: "api/chat", method: "POST", body: body)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OllamaError.unreachable
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaError.badResponse("status \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        struct ChatResponse: Codable { struct Message: Codable { let content: String }; let message: Message }
        guard let chat = try? JSONDecoder().decode(ChatResponse.self, from: data) else {
            throw OllamaError.badResponse("onleesbare /api/chat")
        }
        return Self.parseJudgements(content: chat.message.content)
    }

    static func parseJudgements(content: String) -> [LLMCookieJudgement] {
        struct JudgementDTO: Codable {
            let domain: String
            let name: String
            let category: String?
            let verdict: String?
            let reasoning: String?
        }
        struct Wrapper: Codable { let cookies: [JudgementDTO] }

        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}") else {
            return []
        }
        let json = String(content[start...end])
        let wrapper = (try? JSONDecoder().decode(Wrapper.self, from: Data(json.utf8)))
            ?? (try? JSONDecoder().decode([JudgementDTO].self, from: Data(json.utf8)))
                .map { Wrapper(cookies: $0) }
        guard let cookies = wrapper?.cookies else { return [] }

        return cookies.compactMap { dto in
            guard let verdictRaw = dto.verdict, let verdict = LLMVerdict(raw: verdictRaw) else { return nil }
            return LLMCookieJudgement(
                domain: dto.domain.lowercased(),
                name: dto.name,
                category: Self.mapCategory(dto.category ?? "unknown"),
                verdict: verdict,
                reasoning: dto.reasoning ?? ""
            )
        }
    }

    static func mapCategory(_ raw: String) -> CookieCategory {
        switch raw.lowercased().replacingOccurrences(of: " ", with: "") {
        case "essential", "essentieel": return .essential
        case "functional", "functioneel": return .functional
        case "analytics": return .analytics
        case "marketingtracking", "marketing", "tracking", "advertising": return .marketingTracking
        case "thirdpartyunknown", "thirdparty", "third_party": return .thirdPartyUnknown
        default: return .unknown
        }
    }

    /// Bepaalt welke batches de AI krijgt, deterministisch: input gesorteerd op
    /// (domein, naam), gegroepeerd per domein, gekapt op `maxBatches`. Zelfde
    /// input levert altijd dezelfde batches — ook bij een gewijzigde cap.
    static func buildBatches(
        cookies: [CookiePromptInput],
        cookiesPerBatch: Int,
        maxBatches: Int
    ) -> [[CookiePromptInput]] {
        guard cookiesPerBatch > 0, maxBatches > 0 else { return [] }
        let sorted = cookies.sorted { a, b in
            let da = a.domain.lowercased()
            let db = b.domain.lowercased()
            if da != db { return da < db }
            return a.name.lowercased() < b.name.lowercased()
        }
        let byDomain = Dictionary(grouping: sorted, by: \.domain)
        var batches: [[CookiePromptInput]] = []
        for domain in byDomain.keys.sorted() {
            let group = byDomain[domain] ?? []
            var index = group.startIndex
            while index < group.endIndex {
                let end = group.index(index, offsetBy: cookiesPerBatch, limitedBy: group.endIndex) ?? group.endIndex
                batches.append(Array(group[index..<end]))
                index = end
                if batches.count >= maxBatches { return batches }
            }
        }
        return batches
    }

    func classifyAll(model: String, cookies: [CookiePromptInput]) async -> [LLMCookieJudgement] {
        let batches = Self.buildBatches(
            cookies: cookies,
            cookiesPerBatch: cookiesPerBatch,
            maxBatches: maxBatchesPerRun
        )

        var judgements: [LLMCookieJudgement] = []
        await withTaskGroup(of: [LLMCookieJudgement].self) { group in
            var inFlight = 0
            var iterator = batches.makeIterator()

            func addNext() {
                guard let batch = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    do {
                        return try await self.classifyBatch(model: model, cookies: batch)
                    } catch {
                        return []
                    }
                }
            }

            for _ in 0..<maxConcurrentBatches { addNext() }
            while let result = await group.next() {
                inFlight -= 1
                judgements.append(contentsOf: result)
                addNext()
            }
        }
        return judgements
    }
}
