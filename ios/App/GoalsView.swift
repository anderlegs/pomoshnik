import SwiftUI

struct GoalsView: View {
    @EnvironmentObject var store: Store
    @State private var editGoal: Goal? = nil
    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.data.goals.isEmpty {
                    VStack(spacing: 14) {
                        Text("🎯").font(.system(size: 60))
                        Text("Запиши цели на жизнь").font(.title3.weight(.bold))
                        Text("Работа, здоровье, деньги, семья… Привязывай к ним задачи и следи за прогрессом.")
                            .font(.subheadline).foregroundStyle(Color.secondary).multilineTextAlignment(.center)
                        Button("Добавить базовые цели") { store.addSampleGoals() }
                            .buttonStyle(.borderedProminent)
                        Button("Создать свою") { editGoal = Goal(title: "") }
                    }
                    .padding(30)
                    .padding(.top, 40)
                }
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(store.data.goals) { g in
                        NavigationLink(value: g.id) {
                            GoalTile(goal: g,
                                     total: store.data.tasks.filter { $0.goalId == g.id }.count,
                                     done: store.data.tasks.filter { $0.goalId == g.id && $0.done }.count)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { editGoal = g } label: { Label("Изменить", systemImage: "pencil") }
                            Button(role: .destructive) { store.deleteGoal(g.id) } label: { Label("Удалить", systemImage: "trash") }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 100)
            }
            .background(Palette.bg)
            .navigationTitle("Цели")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editGoal = Goal(title: "", color: store.data.goals.count) } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: UUID.self) { id in GoalDetail(goalID: id) }
            .sheet(item: $editGoal) { g in GoalEditor(goal: g) }
        }
    }
}

struct GoalTile: View {
    let goal: Goal
    let total: Int
    let done: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.goal(goal.color).gradient)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(goal.title) \(goal.emoji)")
                    .font(.headline.weight(.bold))
                    .lineLimit(2)
                Text(total == 0 ? "Нет задач" : "\(done)/\(total) задач")
                    .font(.caption.weight(.medium))
                    .opacity(0.85)
                if total > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.3))
                            Capsule().fill(.white).frame(width: geo.size.width * CGFloat(done) / CGFloat(total))
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 4)
                }
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .frame(height: 140)
    }
}

struct GoalDetail: View {
    @EnvironmentObject var store: Store
    let goalID: UUID
    @State private var editing: TaskItem? = nil
    @State private var focusTask: TaskItem? = nil
    @State private var editGoal: Goal? = nil

    var body: some View {
        if let goal = store.data.goal(goalID) {
            let tasks = store.data.tasks.filter { $0.goalId == goalID }
                .sorted { a, b in a.done != b.done ? !a.done : a.day < b.day }
            let done = tasks.filter(\.done).count
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(goal.emoji) \(goal.title)").font(.title.weight(.bold))
                        if let d = goal.deadline {
                            Text("Срок: \(DF.dayMonth.string(from: d))").font(.subheadline).opacity(0.85)
                        }
                        ProgressView(value: Double(done), total: Double(max(tasks.count, 1)))
                            .tint(.white)
                        Text("Выполнено \(done) из \(tasks.count)").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.goal(goal.color).gradient))

                    HStack {
                        Button {
                            var t = TaskItem(title: "")
                            t.goalId = goalID
                            editing = t
                        } label: { Label("Задача", systemImage: "plus") }
                            .buttonStyle(.bordered)
                        Button {
                            store.askAI = "Помоги достичь цели «\(goal.title)». Разбей её на конкретные шаги и добавь задачи на ближайшую неделю (с привязкой к цели «\(goal.title)»)."
                        } label: { Label("План от ИИ", systemImage: "sparkles") }
                            .buttonStyle(.borderedProminent)
                    }

                    if tasks.isEmpty { EmptyCard(text: "Пока нет задач для этой цели") }
                    ForEach(tasks) { t in
                        TaskRow(task: t, onOpen: { editing = t }, onFocus: { focusTask = t })
                    }
                }
                .padding(16)
                .padding(.bottom, 100)
            }
            .background(Palette.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Изменить") { editGoal = goal }
                }
            }
            .sheet(item: $editing) { t in TaskEditor(task: t, isNew: !store.data.tasks.contains(where: { $0.id == t.id })) }
            .fullScreenCover(item: $focusTask) { t in FocusView(task: t) }
            .sheet(item: $editGoal) { g in GoalEditor(goal: g) }
        } else {
            Text("Цель удалена").foregroundStyle(Color.secondary)
        }
    }
}

struct GoalEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var goal: Goal
    @State private var hasDeadline = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название цели", text: $goal.title)
                    TextField("Эмодзи", text: $goal.emoji)
                        .onChange(of: goal.emoji) { _, v in if v.count > 2 { goal.emoji = String(v.suffix(1)) } }
                }
                Section("Цвет") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8)) {
                        ForEach(0..<Palette.goals.count, id: \.self) { i in
                            Circle().fill(Palette.goals[i])
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.primary, lineWidth: goal.color == i ? 3 : 0))
                                .onTapGesture { goal.color = i }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Toggle("Срок", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Дата", selection: Binding(get: { goal.deadline ?? Date().adding(days: 30) },
                                                              set: { goal.deadline = $0 }),
                                   displayedComponents: .date)
                    }
                }
                if store.data.goals.contains(where: { $0.id == goal.id }) {
                    Section {
                        Button("Удалить цель", role: .destructive) { store.deleteGoal(goal.id); dismiss() }
                    }
                }
            }
            .navigationTitle(goal.title.isEmpty ? "Новая цель" : goal.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        if !hasDeadline { goal.deadline = nil } else if goal.deadline == nil { goal.deadline = Date().adding(days: 30) }
                        store.upsertGoal(goal)
                        dismiss()
                    }
                    .disabled(goal.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { hasDeadline = goal.deadline != nil }
        }
    }
}
