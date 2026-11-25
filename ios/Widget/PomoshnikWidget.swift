import WidgetKit
import SwiftUI
import AppIntents

struct DayEntry: TimelineEntry {
    let date: Date
    let data: AppData
}

extension AppData {
    static var sample: AppData {
        var d = AppData()
        let g = Goal(title: "Работа", emoji: "💼", color: 0)
        d.goals = [g]
        d.tasks = [
            TaskItem(title: "Обзор проекта", goalId: g.id),
            TaskItem(title: "Купить подарок", important: true),
            TaskItem(title: "Тренировка", done: true)
        ]
        d.habits = [Habit(title: "20 отжиманий", emoji: "💪", target: 2), Habit(title: "Дневник", emoji: "✍️")]
        return d
    }
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: Date(), data: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        let d = Shared.load()
        completion(DayEntry(date: Date(), data: (context.isPreview && d.tasks.isEmpty) ? .sample : d))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let now = Date()
        let midnight = now.startOfDay.adding(days: 1)
        let next = min(midnight, now.addingTimeInterval(30 * 60))
        completion(Timeline(entries: [DayEntry(date: now, data: Shared.load())], policy: .after(next)))
    }
}

// MARK: - Rows

struct WTaskRow: View {
    let task: TaskItem
    let data: AppData
    var compact = false

    var body: some View {
        let color = data.goal(task.goalId).map { Palette.goal($0.color) } ?? Color.secondary.opacity(0.35)
        Button(intent: ToggleTaskIntent(taskID: task.id.uuidString)) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2.5, height: 14)
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: compact ? 13 : 15))
                    .foregroundStyle(task.done ? Palette.accent : Color.secondary)
                Text(task.title)
                    .font(.system(size: compact ? 12 : 13, weight: .medium))
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if task.important { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Palette.yellow) }
            }
        }
        .buttonStyle(.plain)
    }
}

struct WHabitRow: View {
    let habit: Habit
    var body: some View {
        let count = habit.count()
        let done = count >= habit.target
        Button(intent: TapHabitIntent(habitID: habit.id.uuidString)) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1).fill(habit.weekly ? Palette.red : Palette.green).frame(width: 2.5, height: 14)
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                    Circle().trim(from: 0, to: CGFloat(min(Double(count) / Double(max(habit.target, 1)), 1)))
                        .stroke(done ? Palette.accent : Palette.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if done { Circle().fill(Palette.accent).padding(2.5) }
                }
                .frame(width: 14, height: 14)
                Text("\(habit.emoji) \(habit.title)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Today widget

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: DayEntry

    var tasks: [TaskItem] { entry.data.tasks(on: entry.date) }
    var doneCount: Int { tasks.filter(\.done).count }
    var habits: [Habit] { entry.data.habits.filter { !$0.weekly } + entry.data.habits.filter { $0.weekly } }
    var habitsDone: Int { entry.data.habits.filter { $0.isDone() }.count }
    var totalAll: Int { tasks.count + entry.data.habits.count }
    var doneAll: Int { doneCount + habitsDone }

    var header: some View {
        HStack {
            Text("Сегодня").font(.system(size: 15, weight: .bold))
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                Text("\(doneAll)/\(totalAll)").font(.system(size: 13, weight: .bold))
            }
        }
    }

    var body: some View {
        if !Shared.hasGroup && entry.data.tasks.isEmpty && entry.data.habits.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("⚠️ Нет доступа к данным").font(.system(size: 13, weight: .bold))
                Text("Виджет не видит общую папку приложения. Открой «Помощник» → ⚙️ Настройки → раздел «Виджеты».")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
        } else {
            content
        }
    }

    @ViewBuilder var content: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(doneAll), in: 0...Double(max(totalAll, 1))) {
                Image(systemName: "checkmark")
            } currentValueLabel: {
                Text("\(doneAll)/\(totalAll)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()

        case .accessoryRectangular:
            let open = tasks.filter { !$0.done }
            VStack(alignment: .leading, spacing: 1) {
                if open.isEmpty {
                    Text("Всё сделано ✓").font(.headline)
                    Text("\(doneCount) задач за сегодня").font(.caption)
                } else {
                    ForEach(open.prefix(3)) { t in
                        Button(intent: ToggleTaskIntent(taskID: t.id.uuidString)) {
                            HStack(spacing: 4) {
                                Image(systemName: "circle").font(.system(size: 10))
                                Text(t.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .accessoryInline:
            let next = tasks.first { !$0.done }
            Text("✓ \(doneCount)/\(tasks.count) · \(next?.title ?? "всё сделано")")

        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                header
                if tasks.isEmpty && habits.isEmpty { Spacer(); Text("Нет задач 🎉").font(.footnote).foregroundStyle(Color.secondary); Spacer() }
                ForEach(tasks.prefix(4)) { t in WTaskRow(task: t, data: entry.data, compact: true) }
                if tasks.count < 4 {
                    ForEach(habits.prefix(4 - tasks.count)) { h in WHabitRow(habit: h) }
                }
                Spacer(minLength: 0)
            }

        case .systemLarge:
            VStack(alignment: .leading, spacing: 8) {
                header
                Text("ЗАДАЧИ").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.secondary)
                if tasks.isEmpty { Text("Нет задач на сегодня").font(.footnote).foregroundStyle(Color.secondary) }
                ForEach(tasks.prefix(7)) { t in WTaskRow(task: t, data: entry.data) }
                if !habits.isEmpty {
                    Text("ПРИВЫЧКИ").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.secondary).padding(.top, 4)
                    ForEach(habits.prefix(5)) { h in WHabitRow(habit: h) }
                }
                Spacer(minLength: 0)
            }

        default:
            VStack(alignment: .leading, spacing: 7) {
                header
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        if tasks.isEmpty { Text("Нет задач").font(.footnote).foregroundStyle(Color.secondary) }
                        ForEach(tasks.prefix(5)) { t in WTaskRow(task: t, data: entry.data, compact: true) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        if habits.isEmpty { Text("Нет привычек").font(.footnote).foregroundStyle(Color.secondary) }
                        ForEach(habits.prefix(5)) { h in WHabitRow(habit: h) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: DayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
        }
        .configurationDisplayName("Сегодня")
        .description("Задачи и привычки на сегодня. Отмечай прямо с экрана.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Money widget

struct MoneyWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: DayEntry

    var body: some View {
        let t = entry.data.monthTotals(entry.date)
        let cur = entry.data.currency
        let balance = t.income - t.expense
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("💰 Остаток").font(.caption.weight(.semibold))
                Text(formatMoney(balance, cur)).font(.headline).minimumScaleFactor(0.6)
                Text("−\(formatMoney(t.expense, cur))").font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text(DF.monthYear.string(from: entry.date).capFirst).font(.caption.weight(.bold)).foregroundStyle(Color.secondary)
                Text(formatMoney(balance, cur))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(balance >= 0 ? Palette.accent : Palette.red)
                    .minimumScaleFactor(0.5).lineLimit(1)
                Spacer(minLength: 0)
                HStack { Image(systemName: "arrow.down").foregroundStyle(Palette.green); Text(formatMoney(t.income, cur)).lineLimit(1).minimumScaleFactor(0.6) }
                    .font(.caption.weight(.semibold))
                HStack { Image(systemName: "arrow.up").foregroundStyle(Palette.red); Text(formatMoney(t.expense, cur)).lineLimit(1).minimumScaleFactor(0.6) }
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MoneyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoneyWidget", provider: DayProvider()) { entry in
            MoneyWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
        }
        .configurationDisplayName("Финансы")
        .description("Доходы, расходы и остаток за месяц.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

// MARK: - Mood widget

struct MoodWidgetView: View {
    let entry: DayEntry
    var body: some View {
        let m = entry.data.moods[entry.date.dayKey]
        VStack(spacing: 6) {
            Text("Настроение").font(.caption.weight(.bold)).foregroundStyle(Color.secondary)
            Text(m.map { Moods.emoji[$0] } ?? "🫥").font(.system(size: 44))
            Text(m.map { Moods.label[$0] } ?? "Отметь в приложении")
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.orange)
        }
        .widgetURL(URL(string: "pomoshnik://habits"))
    }
}

struct MoodWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoodWidget", provider: DayProvider()) { entry in
            MoodWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
        }
        .configurationDisplayName("Настроение")
        .description("Твоё настроение сегодня.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct PomoshnikWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        MoneyWidget()
        MoodWidget()
    }
}
