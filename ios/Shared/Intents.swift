import AppIntents
import WidgetKit

struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Отметить задачу"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Задача")
    var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        var d = Shared.load()
        if let i = d.tasks.firstIndex(where: { $0.id.uuidString == taskID }) {
            d.tasks[i].done.toggle()
            d.tasks[i].doneAt = d.tasks[i].done ? Date() : nil
            Shared.save(d)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct TapHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Отметить привычку"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Привычка")
    var habitID: String

    init() {}
    init(habitID: String) { self.habitID = habitID }

    func perform() async throws -> some IntentResult {
        var d = Shared.load()
        if let i = d.habits.firstIndex(where: { $0.id.uuidString == habitID }) {
            d.habits[i].tap()
            Shared.save(d)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
