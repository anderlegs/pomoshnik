import SwiftUI
import PhotosUI
import WidgetKit

// MARK: - AI service

enum AIProvider: String, CaseIterable, Identifiable {
    case pollinations, openrouter, groq, gemini
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pollinations: return "Pollinations (без ключа)"
        case .openrouter: return "OpenRouter (free)"
        case .groq: return "Groq"
        case .gemini: return "Google Gemini"
        }
    }
    var needsKey: Bool { self != .pollinations }
    var keyURL: String {
        switch self {
        case .pollinations: return "https://pollinations.ai"
        case .openrouter: return "https://openrouter.ai/keys"
        case .groq: return "https://console.groq.com/keys"
        case .gemini: return "https://aistudio.google.com/apikey"
        }
    }
}

struct AIModel: Identifiable, Hashable {
    let id: String
    let name: String
}

struct AIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum AI {
    static func key(_ p: AIProvider) -> String { Shared.defaults.string(forKey: "key_\(p.rawValue)") ?? "" }
    static func setKey(_ p: AIProvider, _ v: String) { Shared.defaults.set(v.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "key_\(p.rawValue)") }

    static func getJSON(_ url: String, headers: [String: String] = [:]) async throws -> Any {
        guard let u = URL(string: url) else { throw AIError(message: "Неверный адрес") }
        var req = URLRequest(url: u)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 {
            throw AIError(message: "Ошибка \(h.statusCode): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func models(_ p: AIProvider) async throws -> [AIModel] {
        switch p {
        case .pollinations:
            if let arr = try? await getJSON("https://text.pollinations.ai/models") as? [[String: Any]] {
                let list = arr.compactMap { m -> AIModel? in
                    guard let name = m["name"] as? String else { return nil }
                    if let tier = m["tier"] as? String, tier != "anonymous" { return nil }
                    if (m["audio"] as? Bool) == true { return nil }
                    return AIModel(id: name, name: (m["description"] as? String) ?? name)
                }
                if !list.isEmpty { return list }
            }
            return [AIModel(id: "openai-fast", name: "OpenAI fast"), AIModel(id: "openai", name: "OpenAI")]
        case .openrouter:
            let j = try await getJSON("https://openrouter.ai/api/v1/models") as? [String: Any]
            let data = j?["data"] as? [[String: Any]] ?? []
            return data.compactMap { m -> AIModel? in
                guard let id = m["id"] as? String else { return nil }
                let arch = m["architecture"] as? [String: Any]
                let outs = arch?["output_modalities"] as? [String] ?? ["text"]
                guard outs.allSatisfy({ $0 == "text" }) else { return nil }
                let pricing = m["pricing"] as? [String: Any]
                let free = id.hasSuffix(":free") || ((pricing?["prompt"] as? String) == "0" && (pricing?["completion"] as? String) == "0")
                guard free else { return nil }
                let name = (m["name"] as? String ?? id).replacingOccurrences(of: " (free)", with: "")
                return AIModel(id: id, name: name)
            }
            .sorted { $0.name < $1.name }
        case .groq:
            guard !key(.groq).isEmpty else { throw AIError(message: "Добавь ключ Groq в настройках") }
            let j = try await getJSON("https://api.groq.com/openai/v1/models", headers: ["Authorization": "Bearer \(key(.groq))"]) as? [String: Any]
            let data = j?["data"] as? [[String: Any]] ?? []
            return data.compactMap { m -> AIModel? in
                guard let id = m["id"] as? String else { return nil }
                if id.range(of: "whisper|tts|guard|orpheus|playai|distil", options: .regularExpression) != nil { return nil }
                return AIModel(id: id, name: id)
            }
            .sorted { $0.id < $1.id }
        case .gemini:
            guard !key(.gemini).isEmpty else { throw AIError(message: "Добавь ключ Gemini в настройках") }
            let k = key(.gemini).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let j = try await getJSON("https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=\(k)") as? [String: Any]
            let data = j?["models"] as? [[String: Any]] ?? []
            return data.compactMap { m -> AIModel? in
                guard let name = m["name"] as? String,
                      let methods = m["supportedGenerationMethods"] as? [String], methods.contains("generateContent") else { return nil }
                let id = name.replacingOccurrences(of: "models/", with: "")
                guard id.range(of: "gemini|gemma", options: .regularExpression) != nil,
                      id.range(of: "embedding|image|tts|audio|live", options: .regularExpression) == nil else { return nil }
                return AIModel(id: id, name: (m["displayName"] as? String) ?? id)
            }
            .reversed()
        }
    }

    static func stream(_ p: AIProvider, model: String, messages: [[String: String]]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            let task = Task {
                do {
                    var req: URLRequest
                    if p == .gemini {
                        let k = key(.gemini).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        let m = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
                        req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(m):streamGenerateContent?alt=sse&key=\(k)")!)
                        let sys = messages.first { $0["role"] == "system" }?["content"] ?? ""
                        let contents: [[String: Any]] = messages.filter { $0["role"] != "system" }.map {
                            ["role": $0["role"] == "assistant" ? "model" : "user", "parts": [["text": $0["content"] ?? ""]]]
                        }
                        let body: [String: Any] = ["contents": contents, "systemInstruction": ["parts": [["text": sys]]]]
                        req.httpBody = try JSONSerialization.data(withJSONObject: body)
                    } else {
                        let url: String
                        switch p {
                        case .openrouter: url = "https://openrouter.ai/api/v1/chat/completions"
                        case .groq: url = "https://api.groq.com/openai/v1/chat/completions"
                        default: url = "https://text.pollinations.ai/openai"
                        }
                        req = URLRequest(url: URL(string: url)!)
                        if p.needsKey { req.setValue("Bearer \(key(p))", forHTTPHeaderField: "Authorization") }
                        if p == .openrouter {
                            req.setValue("https://anderlegs.github.io/pomoshnik", forHTTPHeaderField: "HTTP-Referer")
                            req.setValue("Pomoshnik", forHTTPHeaderField: "X-Title")
                        }
                        let body: [String: Any] = ["model": model, "messages": messages, "stream": true]
                        req.httpBody = try JSONSerialization.data(withJSONObject: body)
                    }
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.timeoutInterval = 120

                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    if let h = resp as? HTTPURLResponse, h.statusCode >= 400 {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 400 { break }
                        }
                        throw AIError(message: "Ошибка \(h.statusCode): \(body.prefix(300))")
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let d = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if d == "[DONE]" { break }
                        guard let data = d.data(using: .utf8),
                              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let err = j["error"] as? [String: Any] {
                            throw AIError(message: err["message"] as? String ?? "Ошибка модели")
                        }
                        var text = ""
                        if p == .gemini {
                            let cands = j["candidates"] as? [[String: Any]]
                            let content = cands?.first?["content"] as? [String: Any]
                            let parts = content?["parts"] as? [[String: Any]] ?? []
                            text = parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
                        } else {
                            let choices = j["choices"] as? [[String: Any]]
                            let delta = choices?.first?["delta"] as? [String: Any]
                            text = delta?["content"] as? String ?? ""
                        }
                        if !text.isEmpty { cont.yield(text) }
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Message parsing

enum Segment {
    case text(String)
    case action(Int, [String: Any])
}

func parseSegments(_ s: String) -> [Segment] {
    var out: [Segment] = []
    let parts = s.components(separatedBy: "```")
    var actionIndex = 0
    for (i, p) in parts.enumerated() {
        if i % 2 == 1 {
            let lines = p.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let lang = lines.first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            let body = lines.count > 1 ? String(lines[1]) : ""
            if lang == "action", let data = body.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                out.append(.action(actionIndex, obj))
                actionIndex += 1
            } else {
                out.append(.text("`" + body.trimmingCharacters(in: .newlines) + "`"))
            }
        } else {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(.text(t)) }
        }
    }
    return out
}

func actionLabel(_ a: [String: Any], currency: String) -> String {
    let title = a["title"] as? String ?? ""
    switch a["type"] as? String ?? "" {
    case "task":
        var s = "Задача: \(title)"
        if let d = a["date"] as? String { s += " · \(d)" }
        if let t = a["time"] as? String { s += " \(t)" }
        return s
    case "goal": return "Цель: \(a["emoji"] as? String ?? "🎯") \(title)"
    case "habit": return "Привычка: \(a["emoji"] as? String ?? "✨") \(title)"
    case "tx":
        let amount = (a["amount"] as? Double) ?? Double((a["amount"] as? Int) ?? 0)
        return "\((a["kind"] as? String) == "in" ? "Доход" : "Расход"): \(formatMoney(amount, currency)) · \(a["category"] as? String ?? "")"
    default: return "Действие"
    }
}

func markdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
}

// MARK: - Chat view

struct AIView: View {
    @EnvironmentObject var store: Store
    @AppStorage("ai_provider", store: Shared.defaults) private var providerRaw = AIProvider.pollinations.rawValue
    @AppStorage("ai_model", store: Shared.defaults) private var model = ""
    @State private var models: [AIModel] = []
    @State private var modelsError: String? = nil
    @State private var input = ""
    @State private var streaming = false
    @State private var streamText = ""
    @State private var showSettings = false
    @State private var speakNext = false
    @AppStorage("ai_speak", store: Shared.defaults) private var speakAll = false
    @StateObject private var voice = VoiceIO()
    @FocusState private var inputFocused: Bool

    private var provider: AIProvider { AIProvider(rawValue: providerRaw) ?? .pollinations }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if store.data.chat.isEmpty && !streaming { emptyState }
                        ForEach(Array(store.data.chat.enumerated()), id: \.element.id) { i, m in
                            MessageBubble(message: m, index: i)
                        }
                        if streaming {
                            MessageBubble(message: ChatMessage(role: "assistant", content: streamText.isEmpty ? "…" : streamText), index: -1)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: streamText) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: store.data.chat.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .background(Palette.bg)
            .navigationTitle("ИИ-помощник")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Сервис", selection: $providerRaw) {
                            ForEach(AIProvider.allCases) { p in
                                Text(p.title + (p.needsKey && AI.key(p).isEmpty ? " 🔑" : "")).tag(p.rawValue)
                            }
                        }
                        Divider()
                        if let modelsError { Text(modelsError) }
                        Picker("Модель", selection: $model) {
                            ForEach(models) { m in Text(m.name).tag(m.id) }
                        }
                        Button { Task { await loadModels() } } label: { Label("Обновить список", systemImage: "arrow.clockwise") }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                            Text(models.first { $0.id == model }?.name ?? (model.isEmpty ? "Модель" : model))
                                .lineLimit(1)
                                .frame(maxWidth: 150)
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if voice.speaking {
                        Button { voice.stopSpeaking() } label: { Image(systemName: "speaker.slash.fill") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle(isOn: $speakAll) { Label("Озвучивать все ответы", systemImage: "speaker.wave.2") }
                        Button { showSettings = true } label: { Label("Ключи и настройки", systemImage: "gearshape") }
                        Button(role: .destructive) { store.mutate { $0.chat = [] } } label: { Label("Очистить чат", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await loadModels() } }) { SettingsView() }
            .task(id: providerRaw) { await loadModels() }
            .onAppear(perform: consumeAsk)
            .onChange(of: store.askAI) { _, _ in consumeAsk() }
            .onChange(of: voice.transcript) { _, t in if voice.recording { input = t } }
            .onChange(of: voice.recording) { was, now in
                if was && !now {
                    let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { speakNext = true; send(t) }
                }
            }
            .onDisappear { voice.stopRecording() }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Привет\(store.data.name.isEmpty ? "" : ", " + store.data.name)! 👋").font(.title2.weight(.bold))
            Text("Я вижу твои задачи, цели, привычки и финансы и могу сам их добавлять. Попробуй:")
                .font(.subheadline).foregroundStyle(Color.secondary)
            ForEach(["Составь мне план на завтра", "Потратил 450 на еду", "Напомни в 18:00 забрать посылку", "Как мне накопить на машину?", "Добавь привычку пить 8 стаканов воды"], id: \.self) { s in
                Button { send(s) } label: {
                    Text(s).font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Capsule().fill(Palette.card))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 20)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
        if let e = voice.error {
            Text(e).font(.caption).foregroundStyle(Color.orange)
        }
        if voice.recording {
            HStack(spacing: 6) {
                Circle().fill(Palette.red).frame(width: 8, height: 8)
                Text("Слушаю… нажми ⏹, чтобы отправить").font(.caption.weight(.semibold)).foregroundStyle(Palette.red)
            }
        }
        HStack(alignment: .bottom, spacing: 8) {
            Button { voice.toggleRecording() } label: {
                Image(systemName: voice.recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(voice.recording ? Color.white : Palette.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(voice.recording ? Palette.red : Palette.card))
            }
            .disabled(streaming)
            TextField("Сообщение…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20).fill(Palette.card))
            Button { send(input) } label: {
                Image(systemName: streaming ? "ellipsis" : "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(input.trimmingCharacters(in: .whitespaces).isEmpty || streaming ? Color.gray : Palette.accent))
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || streaming)
        }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, inputFocused ? 8 : 84)
        .background(.bar)
    }

    private func consumeAsk() {
        if let q = store.askAI {
            store.askAI = nil
            send(q)
        }
    }

    private func loadModels() async {
        modelsError = nil
        do {
            let list = try await AI.models(provider)
            models = list
            if !list.contains(where: { $0.id == model }) {
                let pref = list.first { $0.id.range(of: "openrouter/free|gemini-2.5-flash|gemini-flash-latest|llama-3.3|qwen3|kimi|deepseek|openai-fast", options: .regularExpression) != nil }
                model = (pref ?? list.first)?.id ?? ""
            }
        } catch {
            models = []
            modelsError = error.localizedDescription
        }
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !streaming else { return }
        if provider.needsKey && AI.key(provider).isEmpty {
            showSettings = true
            return
        }
        input = ""
        store.mutate { $0.chat.append(ChatMessage(role: "user", content: t)) }
        streaming = true
        streamText = ""
        var msgs: [[String: String]] = [["role": "system", "content": systemPrompt()]]
        msgs += store.data.chat.suffix(20).map { ["role": $0.role, "content": $0.content] }
        let p = provider
        let m = model.isEmpty ? "openai-fast" : model
        Task {
            do {
                for try await chunk in AI.stream(p, model: m, messages: msgs) {
                    streamText += chunk
                }
            } catch {
                streamText += (streamText.isEmpty ? "" : "\n\n") + "⚠️ \(error.localizedDescription)\n\nПопробуй другую модель: бесплатные иногда перегружены."
            }
            var final = streamText.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if final.isEmpty { final = "(пустой ответ — попробуй другую модель)" }
            store.mutate { $0.chat.append(ChatMessage(role: "assistant", content: final)) }
            streaming = false
            streamText = ""
            if speakNext || speakAll { voice.speak(final) }
            speakNext = false
        }
    }

    private func systemPrompt() -> String {
        let d = store.data
        let now = Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE, d MMMM yyyy, HH:mm"
        var c = "Сейчас: \(f.string(from: now)) (дата \(now.dayKey))."
        let today = d.tasks(on: now)
        c += "\nЗадачи на сегодня: " + (today.isEmpty ? "нет" : today.map { "\($0.time.map { $0.timeString + " " } ?? "")\($0.title)\($0.done ? " (сделано)" : "")" }.joined(separator: "; "))
        let upcoming = d.tasks.filter { !$0.done && $0.day > now.startOfDay }.sorted { $0.day < $1.day }.prefix(10)
        if !upcoming.isEmpty { c += "\nБлижайшие задачи: " + upcoming.map { "\($0.day.dayKey) \($0.title)" }.joined(separator: "; ") }
        c += "\nЦели: " + (d.goals.isEmpty ? "нет" : d.goals.map { g in
            let all = d.tasks.filter { $0.goalId == g.id }
            return "\(g.emoji) \(g.title) (\(all.filter(\.done).count)/\(all.count) задач)"
        }.joined(separator: "; "))
        c += "\nПривычки: " + (d.habits.isEmpty ? "нет" : d.habits.map { "\($0.title) \($0.count())/\($0.target) за \($0.weekly ? "неделю" : "день")" }.joined(separator: "; "))
        if let m = d.moods[now.dayKey] { c += "\nНастроение сегодня: \(Moods.label[m])" }
        let tot = d.monthTotals(now)
        c += "\nФинансы за месяц (\(d.currency)): доход \(Int(tot.income)), расход \(Int(tot.expense)), остаток \(Int(tot.income - tot.expense))."

        return """
        Ты — личный ИИ-помощник\(d.name.isEmpty ? "" : " пользователя по имени \(d.name)") в iPhone-приложении «Помощник». Помогаешь с рутиной, планированием дня, целями на жизнь, привычками, настроением и личными финансами. Отвечай по-русски, коротко, по делу и дружелюбно.
        \(c)

        Ты можешь добавлять данные в приложение. Когда пользователь просит что-то добавить или ты предлагаешь план, вставь блоки строго в формате (один JSON на блок):
        ```action
        {"type":"task","title":"Позвонить маме","date":"YYYY-MM-DD","time":"HH:MM","remind":true}
        ```
        Типы:
        - task: {"type":"task","title":"...","date":"YYYY-MM-DD","time":"HH:MM","remind":true,"important":false,"goal":"название существующей цели","subtasks":["..."]} (time и goal необязательны)
        - goal: {"type":"goal","title":"...","emoji":"💪"}
        - habit: {"type":"habit","title":"...","emoji":"💧","weekly":false,"target":1}
        - tx: {"type":"tx","kind":"in|out","amount":1000,"category":"...","note":"..."}
        Категории расходов: \(MoneyCats.expense.joined(separator: ", ")). Категории доходов: \(MoneyCats.income.joined(separator: ", ")).
        Пользователь сам нажмёт кнопку, чтобы подтвердить. Даты считай от текущей даты.
        """
    }
}

struct MessageBubble: View {
    @EnvironmentObject var store: Store
    let message: ChatMessage
    let index: Int

    var body: some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 50)
                Text(message.content)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.accent))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(parseSegments(message.content).enumerated()), id: \.offset) { _, seg in
                    switch seg {
                    case .text(let t):
                        Text(markdown(t)).textSelection(.enabled)
                    case .action(let ai, let a):
                        let applied = message.applied.contains(ai)
                        Button {
                            guard index >= 0, !applied else { return }
                            _ = store.apply(action: a)
                            store.mutate { d in
                                if index < d.chat.count { d.chat[index].applied.append(ai) }
                            }
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            HStack {
                                Image(systemName: applied ? "checkmark.circle.fill" : "plus.circle.fill")
                                Text(actionLabel(a, currency: store.data.currency)).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(applied ? Color.gray : Palette.green))
                        }
                        .buttonStyle(.plain)
                        .disabled(applied || index < 0)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
            .padding(.trailing, 30)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var keys: [AIProvider: String] = [:]
    @State private var bgItems: [PhotosPickerItem] = []
    @State private var bgCount = Backgrounds.files().count
    @State private var bgLoading = false
    @AppStorage("accent_index", store: Shared.defaults) private var accentIndex = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Профиль") {
                    TextField("Как тебя зовут", text: Binding(get: { store.data.name }, set: { v in store.mutate { $0.name = v } }))
                    Picker("Валюта", selection: Binding(get: { store.data.currency }, set: { v in store.mutate { $0.currency = v } })) {
                        ForEach(["сом", "₽", "$", "€", "₸"], id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    ForEach(AIProvider.allCases.filter(\.needsKey)) { p in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.title).font(.subheadline.weight(.semibold))
                            TextField("API-ключ", text: Binding(get: { keys[p] ?? AI.key(p) }, set: { keys[p] = $0 }))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.footnote.monospaced())
                            if let u = URL(string: p.keyURL) {
                                Link("Получить бесплатный ключ →", destination: u).font(.caption)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("ИИ: бесплатные модели")
                } footer: {
                    Text("Pollinations работает без ключа. Ключи хранятся только на телефоне.")
                }
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(Palette.accentOptions.indices, id: \.self) { i in
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle().fill(Color(hex: Palette.accentOptions[i].hex)).frame(width: 36, height: 36)
                                    if accentIndex == i {
                                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                    }
                                }
                                Text(Palette.accentOptions[i].name).font(.system(size: 9)).foregroundStyle(Color.secondary).lineLimit(1)
                            }
                            .onTapGesture {
                                accentIndex = i
                                store.objectWillChange.send()
                                WidgetCenter.shared.reloadAllTimelines()
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Цвет оформления")
                } footer: {
                    Text("Меняет цвет галочек, кнопок, сообщений и виджетов.")
                }
                Section {
                    PhotosPicker(selection: $bgItems, maxSelectionCount: 30, matching: .images) {
                        Label(bgLoading ? "Загружаю фото…" : "Выбрать фото для фона", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(bgLoading)
                    if bgCount > 0 {
                        Button("Убрать все фото (вернуть горы)", role: .destructive) {
                            Backgrounds.clear()
                            bgCount = 0
                        }
                    }
                } header: {
                    Text("Фон «Сегодня»")
                } footer: {
                    Text(bgCount > 0 ? "Фото: \(bgCount). Меняются каждые 8 секунд, нажми на фон — переключится сразу." : "Выбери одно или несколько фото из галереи — они будут сменять друг друга.")
                }
                .onChange(of: bgItems) { _, items in
                    guard !items.isEmpty else { return }
                    bgLoading = true
                    Task {
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self) { Backgrounds.add(data) }
                        }
                        bgItems = []
                        bgCount = Backgrounds.files().count
                        bgLoading = false
                        NotificationCenter.default.post(name: Backgrounds.changed, object: nil)
                    }
                }
                Section("Виджеты") {
                    Text("Зажми пустое место на экране «Домой» → «Изменить» → «Добавить виджет» → «Помощник». Для экрана блокировки: зажми экран блокировки → «Настроить» → «Экран блокировки» → блок виджетов.")
                        .font(.footnote)
                    Text(Shared.hasGroup ? "✅ Общая папка: \(Shared.groupID)" : "❌ Общая папка недоступна (\(Shared.groupID))")
                        .font(.caption2).foregroundStyle(Color.secondary)
                    if !Shared.hasGroup {
                        Text("⚠️ Общая папка приложения недоступна: виджеты могут не видеть данные. Переустанови приложение через Sideloadly/AltStore с поддержкой App Groups.")
                            .font(.footnote).foregroundStyle(Color.orange)
                    }
                }
                Section("Данные") {
                    ShareLink(item: Shared.fileURL) { Label("Экспорт резервной копии", systemImage: "square.and.arrow.up") }
                    Button("Очистить чат", role: .destructive) { store.mutate { $0.chat = [] } }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        for (p, v) in keys { AI.setKey(p, v) }
                        dismiss()
                    }
                }
            }
        }
    }
}
