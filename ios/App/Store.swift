import SwiftUI
import WidgetKit
import UserNotifications

@MainActor
final class Store: ObservableObject {
    @Published var data: AppData
    @Published var askAI: String? = nil

    init() { data = Shared.load() }

    func save() {
        Shared.save(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func reload() { data = Shared.load() }

    func mutate(_ change: (inout AppData) -> Void) {
        change(&data)
        save()
    }

    // MARK: Tasks
    func upsert(_ t: TaskItem) {
        mutate { d in
            if let i = d.tasks.firstIndex(where: { $0.id == t.id }) { d.tasks[i] = t } else { d.tasks.append(t) }
        }
        Notifier.schedule(t)
    }

    func toggle(_ id: UUID) {
        mutate { d in
            if let i = d.tasks.firstIndex(where: { $0.id == id }) {
                d.tasks[i].done.toggle()
                d.tasks[i].doneAt = d.tasks[i].done ? Date() : nil
            }
        }
        if let t = data.tasks.first(where: { $0.id == id }) { Notifier.schedule(t) }
    }

    func toggleStar(_ id: UUID) {
        mutate { d in
            if let i = d.tasks.firstIndex(where: { $0.id == id }) { d.tasks[i].important.toggle() }
        }
    }

    func toggleSub(_ taskID: UUID, _ subID: UUID) {
        mutate { d in
            if let i = d.tasks.firstIndex(where: { $0.id == taskID }),
               let j = d.tasks[i].subtasks.firstIndex(where: { $0.id == subID }) {
                d.tasks[i].subtasks[j].done.toggle()
            }
        }
    }

    func deleteTask(_ id: UUID) {
        mutate { d in d.tasks.removeAll { $0.id == id } }
        Notifier.cancel(id)
    }

    // MARK: Goals
    func upsertGoal(_ g: Goal) {
        mutate { d in
            if let i = d.goals.firstIndex(where: { $0.id == g.id }) { d.goals[i] = g } else { d.goals.append(g) }
        }
    }

    func deleteGoal(_ id: UUID) {
        mutate { d in
            d.goals.removeAll { $0.id == id }
            for i in d.tasks.indices where d.tasks[i].goalId == id { d.tasks[i].goalId = nil }
        }
    }

    func addSampleGoals() {
        let samples: [(String, String)] = [("Работа", "💼"), ("Личное", "🙋"), ("Здоровье", "🎾"), ("Деньги", "💰"), ("Обучение", "📚"), ("Семья", "🏡")]
        mutate { d in
            for (i, s) in samples.enumerated() { d.goals.append(Goal(title: s.0, emoji: s.1, color: i)) }
        }
    }

    // MARK: Habits
    func upsertHabit(_ h: Habit) {
        mutate { d in
            if let i = d.habits.firstIndex(where: { $0.id == h.id }) { d.habits[i] = h } else { d.habits.append(h) }
        }
    }

    func tapHabit(_ id: UUID) {
        mutate { d in
            if let i = d.habits.firstIndex(where: { $0.id == id }) { d.habits[i].tap() }
        }
    }

    func deleteHabit(_ id: UUID) { mutate { d in d.habits.removeAll { $0.id == id } } }

    func setMood(_ level: Int, on day: Date) { mutate { d in d.moods[day.dayKey] = level } }

    // MARK: Money
    func addTx(_ t: Transaction) { mutate { d in d.transactions.append(t) } }
    func deleteTx(_ id: UUID) { mutate { d in d.transactions.removeAll { $0.id == id } } }

    // MARK: AI actions
    func apply(action a: [String: Any]) -> String {
        let type = a["type"] as? String ?? ""
        let title = (a["title"] as? String) ?? ""
        switch type {
        case "task":
            var t = TaskItem(title: title)
            t.note = a["note"] as? String ?? ""
            if let ds = a["date"] as? String, let d = DF.key.date(from: ds) { t.day = d.startOfDay }
            if let ts = a["time"] as? String, let tm = DF.time.date(from: ts) {
                let c = Cal.ru.dateComponents([.hour, .minute], from: tm)
                t.time = Cal.ru.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0, of: t.day)
                t.remind = (a["remind"] as? Bool) ?? true
            }
            t.important = (a["important"] as? Bool) ?? false
            if let gname = a["goal"] as? String,
               let g = data.goals.first(where: { $0.title.lowercased() == gname.lowercased() }) { t.goalId = g.id }
            if let subs = a["subtasks"] as? [String] { t.subtasks = subs.map { Subtask(title: $0) } }
            upsert(t)
            return "Задача добавлена"
        case "goal":
            upsertGoal(Goal(title: title, emoji: a["emoji"] as? String ?? "🎯", color: data.goals.count))
            return "Цель добавлена"
        case "habit":
            let target = (a["target"] as? Int) ?? Int((a["target"] as? Double) ?? 1)
            upsertHabit(Habit(title: title, emoji: a["emoji"] as? String ?? "✨", weekly: (a["weekly"] as? Bool) ?? false, target: max(1, target)))
            return "Привычка добавлена"
        case "tx":
            let amount = (a["amount"] as? Double) ?? Double((a["amount"] as? Int) ?? 0)
            addTx(Transaction(income: (a["kind"] as? String) == "in", amount: amount,
                              category: a["category"] as? String ?? "Другое", note: a["note"] as? String ?? ""))
            return "Записано"
        default:
            return "Неизвестное действие"
        }
    }
}

enum Notifier {
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func schedule(_ t: TaskItem) {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: [t.id.uuidString])
        guard t.remind, !t.done, let time = t.time, time > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = t.title
        content.body = t.note.isEmpty ? "Напоминание · \(time.timeString)" : t.note
        content.sound = .default
        let comps = Cal.ru.dateComponents([.year, .month, .day, .hour, .minute], from: time)
        c.add(UNNotificationRequest(identifier: t.id.uuidString, content: content,
                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    static func cancel(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    static func focusEnd(after seconds: Int, title: String) {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ["focus"])
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Фокус завершён 🎉"
        content.body = title
        content.sound = .default
        c.add(UNNotificationRequest(identifier: "focus", content: content,
                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)))
    }

    static func cancelFocus() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["focus"])
    }
}
