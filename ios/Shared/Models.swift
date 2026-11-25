import Foundation

// MARK: - Calendar / formatting helpers

enum Cal {
    static let ru: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "ru_RU")
        c.timeZone = .current
        return c
    }()
}

enum DF {
    static let key: DateFormatter = make("yyyy-MM-dd", posix: true)
    static let dayMonth: DateFormatter = make("d MMMM")
    static let weekday: DateFormatter = make("EEEE")
    static let weekdayShort: DateFormatter = make("EE")
    static let monthYear: DateFormatter = make("LLLL yyyy")
    static let monthShort: DateFormatter = make("LLL")
    static let time: DateFormatter = make("HH:mm", posix: true)

    static func make(_ format: String, posix: Bool = false) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Cal.ru
        f.locale = Locale(identifier: posix ? "en_US_POSIX" : "ru_RU")
        f.timeZone = .current
        f.dateFormat = format
        return f
    }
}

extension Date {
    var dayKey: String { DF.key.string(from: self) }
    var startOfDay: Date { Cal.ru.startOfDay(for: self) }
    var timeString: String { DF.time.string(from: self) }
    func adding(days: Int) -> Date { Cal.ru.date(byAdding: .day, value: days, to: self) ?? self }
    func isSameDay(_ other: Date) -> Bool { Cal.ru.isDate(self, inSameDayAs: other) }
}

extension String {
    var capFirst: String { prefix(1).uppercased() + dropFirst() }
}

func formatMoney(_ v: Double, _ currency: String) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = " "
    f.maximumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
    return (f.string(from: NSNumber(value: v)) ?? "\(v)") + " " + currency
}

// MARK: - Models

struct Subtask: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var done = false
}

struct TaskItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var note: String = ""
    var day: Date = Date().startOfDay
    var time: Date? = nil
    var goalId: UUID? = nil
    var important = false
    var remind = false
    var done = false
    var doneAt: Date? = nil
    var subtasks: [Subtask] = []
}

struct Goal: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var emoji: String = "🎯"
    var color: Int = 0
    var deadline: Date? = nil
}

struct Habit: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var emoji: String = "✨"
    var weekly = false
    var target = 1
    var log: [String: Int] = [:]
    var remindTime: Date? = nil
    var remindWeekday: Int? = nil
    var remindTimes: [Date]? = nil

    /// All reminder times (supports old single-time data).
    var times: [Date] {
        get { remindTimes ?? (remindTime.map { [$0] } ?? []) }
        set { remindTimes = newValue.isEmpty ? nil : newValue.sorted { $0.timeString < $1.timeString }; remindTime = nil }
    }

    func periodDays(_ date: Date) -> [Date] {
        if !weekly { return [date.startOfDay] }
        guard let week = Cal.ru.dateInterval(of: .weekOfYear, for: date) else { return [date.startOfDay] }
        return (0..<7).map { week.start.adding(days: $0) }
    }
    func count(on date: Date = Date()) -> Int {
        periodDays(date).reduce(0) { $0 + (log[$1.dayKey] ?? 0) }
    }
    func isDone(on date: Date = Date()) -> Bool { count(on: date) >= target }
    mutating func tap(on date: Date = Date()) {
        if isDone(on: date) {
            for d in periodDays(date) { log[d.dayKey] = nil }
        } else {
            log[date.dayKey, default: 0] += 1
        }
    }
}

struct Transaction: Codable, Identifiable, Hashable {
    var id = UUID()
    var income: Bool
    var amount: Double
    var category: String
    var note: String = ""
    var date: Date = Date()
}

struct ChatMessage: Codable, Identifiable, Hashable {
    var id = UUID()
    var role: String
    var content: String
    var applied: [Int] = []
}

struct AppData: Codable {
    var tasks: [TaskItem] = []
    var goals: [Goal] = []
    var habits: [Habit] = []
    var moods: [String: Int] = [:]
    var transactions: [Transaction] = []
    var chat: [ChatMessage] = []
    var name: String = ""
    var currency: String = "сом"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = (try? c.decode([TaskItem].self, forKey: .tasks)) ?? []
        goals = (try? c.decode([Goal].self, forKey: .goals)) ?? []
        habits = (try? c.decode([Habit].self, forKey: .habits)) ?? []
        moods = (try? c.decode([String: Int].self, forKey: .moods)) ?? [:]
        transactions = (try? c.decode([Transaction].self, forKey: .transactions)) ?? []
        chat = (try? c.decode([ChatMessage].self, forKey: .chat)) ?? []
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        currency = (try? c.decode(String.self, forKey: .currency)) ?? "сом"
    }

    func goal(_ id: UUID?) -> Goal? {
        guard let id else { return nil }
        return goals.first { $0.id == id }
    }

    func tasks(on day: Date) -> [TaskItem] {
        tasks.filter { $0.day.isSameDay(day) }.sorted { a, b in
            switch (a.time, b.time) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if a.important != b.important { return a.important }
                return a.title < b.title
            }
        }
    }

    func monthTotals(_ date: Date) -> (income: Double, expense: Double) {
        let list = transactions.filter { Cal.ru.isDate($0.date, equalTo: date, toGranularity: .month) }
        let inc = list.filter { $0.income }.reduce(0) { $0 + $1.amount }
        let out = list.filter { !$0.income }.reduce(0) { $0 + $1.amount }
        return (inc, out)
    }
}

enum Moods {
    static let emoji = ["😞", "😨", "😠", "😐", "🙂", "😎", "🤩"]
    static let label = ["Грустно, подавленно", "Тревожно, страшно", "Злость, раздражение", "Нейтрально", "Спокойно, нормально", "Уверенно, оптимистично", "Восторг, полон энергии"]
}

// MARK: - Shared storage (app + widget)

enum Shared {
    static let defaultGroup = "group.com.anderlegs.pomoshnik"

    static let groupID: String = {
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String], let g = groups.first {
            return g
        }
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: defaultGroup) != nil {
            return defaultGroup
        }
        if let g = provisionedGroups().first { return g }
        return defaultGroup
    }()

    /// Reads app groups from embedded.mobileprovision (re-signing tools may rename the group).
    static func provisionedGroups() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return [] }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let ent = plist["Entitlements"] as? [String: Any],
              let groups = ent["com.apple.security.application-groups"] as? [String] else { return [] }
        return groups
            .filter { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
            .sorted { a, _ in a.lowercased().contains("pomoshnik") }
    }

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var hasGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    static var fileURL: URL { containerURL.appendingPathComponent("data.json") }

    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    static func load() -> AppData {
        guard let d = try? Data(contentsOf: fileURL),
              let a = try? JSONDecoder().decode(AppData.self, from: d) else { return AppData() }
        return a
    }

    static func save(_ a: AppData) {
        if let d = try? JSONEncoder().encode(a) {
            try? d.write(to: fileURL, options: .atomic)
        }
    }
}
