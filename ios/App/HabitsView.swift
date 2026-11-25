import SwiftUI
import Charts

struct HabitsView: View {
    @EnvironmentObject var store: Store
    @State private var moodOpen = true
    @State private var dailyOpen = true
    @State private var weeklyOpen = true
    @State private var editHabit: Habit? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "ТРЕКЕР НАСТРОЕНИЯ", open: $moodOpen)
                    if moodOpen { MoodCard() }

                    let daily = store.data.habits.filter { !$0.weekly }
                    let weekly = store.data.habits.filter { $0.weekly }

                    SectionHeader(title: "ЕЖЕДНЕВНЫЕ", open: $dailyOpen)
                    if dailyOpen {
                        if daily.isEmpty { EmptyCard(text: "Например: 20 отжиманий, вода, чтение") }
                        ForEach(daily) { h in HabitRow(habit: h, onEdit: { editHabit = h }) }
                    }

                    SectionHeader(title: "ЕЖЕНЕДЕЛЬНЫЕ", open: $weeklyOpen)
                    if weeklyOpen {
                        if weekly.isEmpty { EmptyCard(text: "Например: спортзал 3 раза, звонок родителям") }
                        ForEach(weekly) { h in HabitRow(habit: h, onEdit: { editHabit = h }) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
            .background(Palette.bg)
            .navigationTitle("Привычки")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editHabit = Habit(title: "") } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editHabit) { h in HabitEditor(habit: h) }
        }
    }
}

struct HabitRow: View {
    @EnvironmentObject var store: Store
    let habit: Habit
    var onEdit: (() -> Void)? = nil

    var body: some View {
        let count = habit.count()
        let done = count >= habit.target
        let color = habit.weekly ? Palette.red : Palette.green
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { store.tapHabit(habit.id) }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(Double(count) / Double(max(habit.target, 1)), 1)))
                        .stroke(done ? Palette.accent : color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if done {
                        Circle().fill(Palette.accent).padding(4)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.secondary.opacity(0.5))
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            Text(habit.emoji).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                if let t = habit.remindTime {
                    Label(t.timeString, systemImage: "bell.fill").font(.caption2).foregroundStyle(Color.orange)
                }
            }
            Spacer()
            Text("\(count)/\(habit.target)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(done ? Palette.accent : (count > 0 ? color : Color.secondary))
        }
        .card(12)
        .opacity(done ? 0.75 : 1)
        .contextMenu {
            if let onEdit { Button { onEdit() } label: { Label("Изменить", systemImage: "pencil") } }
            Button(role: .destructive) { store.deleteHabit(habit.id) } label: { Label("Удалить", systemImage: "trash") }
        }
    }
}

struct HabitEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var habit: Habit

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $habit.title)
                    TextField("Эмодзи", text: $habit.emoji)
                        .onChange(of: habit.emoji) { _, v in if v.count > 2 { habit.emoji = String(v.suffix(1)) } }
                }
                Section {
                    Picker("Период", selection: $habit.weekly) {
                        Text("Каждый день").tag(false)
                        Text("Каждую неделю").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Stepper("Сколько раз: \(habit.target)", value: $habit.target, in: 1...20)
                }
                Section {
                    Toggle(isOn: Binding(get: { habit.remindTime != nil },
                                         set: { on in
                                             habit.remindTime = on ? (Cal.ru.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()) : nil
                                             if on { Notifier.requestAuth() }
                                         })) {
                        Label("Напоминание", systemImage: "bell")
                    }
                    if habit.remindTime != nil {
                        DatePicker("Время", selection: Binding(get: { habit.remindTime ?? Date() }, set: { habit.remindTime = $0 }),
                                   displayedComponents: .hourAndMinute)
                        if habit.weekly {
                            Picker("День недели", selection: Binding(get: { habit.remindWeekday ?? 2 }, set: { habit.remindWeekday = $0 })) {
                                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                                    Text(["", "Воскресенье", "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота"][wd]).tag(wd)
                                }
                            }
                        }
                    }
                } footer: {
                    Text(habit.remindTime == nil ? "" : (habit.weekly ? "Уведомление раз в неделю" : "Уведомление каждый день"))
                }
                if store.data.habits.contains(where: { $0.id == habit.id }) {
                    Section {
                        Button("Удалить привычку", role: .destructive) { store.deleteHabit(habit.id); dismiss() }
                    }
                }
            }
            .navigationTitle(habit.title.isEmpty ? "Новая привычка" : habit.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { store.upsertHabit(habit); dismiss() }
                        .disabled(habit.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct MoodPoint: Identifiable {
    let id: Int
    let label: String
    let level: Int?
    let isToday: Bool
}

struct MoodCard: View {
    @EnvironmentObject var store: Store
    @State private var day = Date().startOfDay
    @State private var weekOffset = 0

    var body: some View {
        let current = store.data.moods[day.dayKey]
        let weekStart = (Cal.ru.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()).adding(days: weekOffset * 7)
        let points: [MoodPoint] = (0..<7).map { i in
            let d = weekStart.adding(days: i)
            return MoodPoint(id: i, label: DF.weekdayShort.string(from: d).capFirst,
                             level: store.data.moods[d.dayKey], isToday: d.isSameDay(Date()))
        }
        let weekEnd = weekStart.adding(days: 6)

        VStack(spacing: 12) {
            Text("Как ты себя чувствуешь?").font(.headline)
            Text(day.isSameDay(Date()) ? "Сегодня, \(DF.dayMonth.string(from: day))" : DF.dayMonth.string(from: day))
                .font(.caption).foregroundStyle(Color.secondary)
            HStack(spacing: 6) {
                ForEach(0..<Moods.emoji.count, id: \.self) { i in
                    Button {
                        withAnimation(.spring(duration: 0.3)) { store.setMood(i, on: day) }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(Moods.emoji[i])
                            .font(.system(size: current == i ? 30 : 22))
                            .grayscale(current == nil || current == i ? 0 : 0.9)
                            .opacity(current == nil || current == i ? 1 : 0.6)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(current == i ? Palette.yellow.opacity(0.35) : Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let c = current {
                Text(Moods.label[c]).font(.subheadline.weight(.semibold)).foregroundStyle(Color.orange)
            }

            Divider().padding(.vertical, 4)

            HStack {
                Button { weekOffset -= 1 } label: { Image(systemName: "arrow.left") }
                Spacer()
                Text("\(Cal.ru.component(.day, from: weekStart))–\(DF.dayMonth.string(from: weekEnd))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { weekOffset += 1 } label: { Image(systemName: "arrow.right") }
                    .disabled(weekOffset >= 0)
            }
            .buttonStyle(.plain)

            Chart {
                ForEach(points) { p in
                    if let l = p.level {
                        LineMark(x: .value("День", p.label), y: .value("Настроение", l))
                            .foregroundStyle(Palette.yellow)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        PointMark(x: .value("День", p.label), y: .value("Настроение", l))
                            .symbol { Text(Moods.emoji[l]).font(.title3) }
                    } else {
                        PointMark(x: .value("День", p.label), y: .value("Настроение", 3))
                            .opacity(0)
                    }
                }
            }
            .chartYScale(domain: -0.5...6.5)
            .chartYAxis(.hidden)
            .frame(height: 150)

            Button {
                let summary = points.compactMap { p in p.level.map { "\(p.label): \(Moods.label[$0])" } }.joined(separator: "; ")
                store.askAI = "Вот моё настроение за неделю: \(summary.isEmpty ? "нет записей" : summary). Дай короткие практичные советы, что мне сделать, чтобы чувствовать себя лучше."
            } label: {
                Text("✨ Советы, что делать")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.yellow.opacity(0.22)))
            }
            .buttonStyle(.plain)
        }
        .card(16)
    }
}
