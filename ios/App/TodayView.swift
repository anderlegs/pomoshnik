import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: Store
    @State private var selected = Date().startOfDay
    @State private var editing: TaskItem? = nil
    @State private var focusTask: TaskItem? = nil
    @State private var showStats = false
    @State private var showSettings = false
    @State private var showMonth = false
    @State private var eventsOpen = true
    @State private var tasksOpen = true
    @State private var habitsOpen = true

    var body: some View {
        let items = store.data.tasks(on: selected)
        let events = items.filter { $0.time != nil }
        let tasks = items.filter { $0.time == nil }
        let dailyHabits = store.data.habits.filter { !$0.weekly }

        ScrollView {
            VStack(spacing: 0) {
                TodayHeader(selected: $selected,
                            onCalendar: { showMonth = true },
                            onStats: { showStats = true },
                            onSettings: { showSettings = true })

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "СОБЫТИЯ", open: $eventsOpen)
                    if eventsOpen {
                        if events.isEmpty { EmptyCard(text: "Нет событий со временем") }
                        ForEach(events) { t in
                            TaskRow(task: t, onOpen: { editing = t }, onFocus: { focusTask = t })
                        }
                    }

                    SectionHeader(title: "ЗАДАЧИ", open: $tasksOpen)
                    if tasksOpen {
                        if tasks.isEmpty { EmptyCard(text: "Нажми «+», чтобы добавить задачу") }
                        ForEach(tasks) { t in
                            TaskRow(task: t, onOpen: { editing = t }, onFocus: { focusTask = t })
                        }
                    }

                    if !dailyHabits.isEmpty && selected.isSameDay(Date()) {
                        SectionHeader(title: "ПРИВЫЧКИ НА СЕГОДНЯ", open: $habitsOpen)
                        if habitsOpen {
                            ForEach(dailyHabits) { h in HabitRow(habit: h) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Palette.bg)
        .sheet(item: $editing) { t in TaskEditor(task: t, isNew: false) }
        .fullScreenCover(item: $focusTask) { t in FocusView(task: t) }
        .sheet(isPresented: $showStats) { StatsView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showMonth) {
            MonthCalendar(selected: $selected)
                .presentationDetents([.large])
        }
    }
}

// MARK: - Month calendar

struct MonthCalendar: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: Date
    @State private var month = Date()
    @State private var allMonths = false
    @State private var year = Cal.ru.component(.year, from: Date())

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("", selection: $allMonths) {
                    Text("Месяц").tag(false)
                    Text("Все месяцы").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)

                if allMonths {
                    VStack(spacing: 12) {
                        HStack {
                            Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                            Spacer()
                            Text(String(year)).font(.title2.weight(.bold))
                            Spacer()
                            Button { year += 1 } label: { Image(systemName: "chevron.right") }
                        }
                        .buttonStyle(.plain)
                        .font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                            ForEach(1...12, id: \.self) { m in
                                let date = Cal.ru.date(from: DateComponents(year: year, month: m, day: 1)) ?? Date()
                                Button {
                                    month = date
                                    withAnimation(.snappy) { allMonths = false }
                                } label: {
                                    MiniMonth(month: date, selected: selected)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Нажми на месяц, чтобы открыть его").font(.caption).foregroundStyle(Color.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                } else {
                    VStack(spacing: 14) {
                        HStack {
                            Button { month = Cal.ru.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }
                            Spacer()
                            Text(DF.monthYear.string(from: month).capFirst).font(.title3.weight(.bold))
                            Spacer()
                            Button { month = Cal.ru.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }
                        }
                        .buttonStyle(.plain)
                        .font(.headline)
                        MonthGrid(month: month, selected: selected) { d in pick(d) }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                }
            }
            .padding(.top, 8)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Сегодня") { pick(Date()) }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .onAppear { month = selected; year = Cal.ru.component(.year, from: selected) }
        }
    }

    private func pick(_ d: Date) {
        selected = d.startOfDay
        dismiss()
    }
}

struct MiniMonth: View {
    @EnvironmentObject var store: Store
    let month: Date
    let selected: Date

    var body: some View {
        let start = Cal.ru.dateInterval(of: .month, for: month)?.start ?? month
        let daysCount = Cal.ru.range(of: .day, in: .month, for: month)?.count ?? 30
        let offset = (Cal.ru.component(.weekday, from: start) + 5) % 7
        let cells: [Date?] = Array(repeating: nil, count: offset) + (0..<daysCount).map { start.adding(days: $0) }
        let isCurrent = Cal.ru.isDate(month, equalTo: Date(), toGranularity: .month)
        VStack(alignment: .leading, spacing: 4) {
            Text(DF.monthShort.string(from: month).capFirst.replacingOccurrences(of: ".", with: ""))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isCurrent ? Palette.accent : Color.primary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let today = day.isSameDay(Date())
                        let on = day.isSameDay(selected)
                        let has = !store.data.tasks(on: day).isEmpty
                        Text("\(Cal.ru.component(.day, from: day))")
                            .font(.system(size: 9, weight: has || today ? .bold : .regular))
                            .foregroundStyle(today ? Color.white : (has ? Palette.accent : (on ? Palette.accent : Color.primary)))
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(today ? Palette.accent : Color.clear))
                            .overlay(Circle().stroke(on && !today ? Palette.accent : Color.clear, lineWidth: 1))
                    } else {
                        Color.clear.frame(width: 14, height: 14)
                    }
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(isCurrent ? Palette.accent.opacity(0.08) : Color.clear))
    }
}

struct MonthGrid: View {
    @EnvironmentObject var store: Store
    let month: Date
    let selected: Date
    var onPick: (Date) -> Void

    var body: some View {
        let start = Cal.ru.dateInterval(of: .month, for: month)?.start ?? month
        let daysCount = Cal.ru.range(of: .day, in: .month, for: month)?.count ?? 30
        let offset = (Cal.ru.component(.weekday, from: start) + 5) % 7
        let cells: [Date?] = Array(repeating: nil, count: offset) + (0..<daysCount).map { start.adding(days: $0) }
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { d in
                Text(d).font(.caption.weight(.semibold)).foregroundStyle(Color.secondary)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    let items = store.data.tasks(on: day)
                    let on = day.isSameDay(selected)
                    let today = day.isSameDay(Date())
                    Button { onPick(day) } label: {
                        VStack(spacing: 3) {
                            Text("\(Cal.ru.component(.day, from: day))")
                                .font(.system(size: 16, weight: today || on ? .bold : .regular))
                                .foregroundStyle(on ? Color.white : (today ? Palette.accent : Color.primary))
                            HStack(spacing: 2) {
                                ForEach(0..<min(items.count, 3), id: \.self) { i in
                                    Circle()
                                        .fill(on ? Color.white : (items[i].done ? Color.secondary : Palette.goal(store.data.goal(items[i].goalId)?.color ?? 0)))
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .frame(height: 5)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(on ? Palette.accent : Color.clear))
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }
}

// MARK: - Header with landscape

struct TodayHeader: View {
    @Binding var selected: Date
    var onCalendar: () -> Void
    var onStats: () -> Void
    var onSettings: () -> Void
    @State private var backgrounds: [UIImage] = Backgrounds.loadAll()

    private var isNight: Bool {
        let h = Cal.ru.component(.hour, from: Date())
        return h >= 19 || h < 6
    }

    var body: some View {
        let isToday = selected.isSameDay(Date())
        ZStack(alignment: .top) {
            if backgrounds.isEmpty {
                Landscape(night: isNight)
                    .frame(height: 330)
            } else {
                Slideshow(images: backgrounds)
                    .frame(height: 330)
                    .clipped()
                    .overlay(
                        LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.05), .black.opacity(0.4)],
                                       startPoint: .top, endPoint: .bottom)
                            .allowsHitTesting(false)
                    )
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isToday ? "Сегодня" : DF.weekday.string(from: selected).capFirst)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                            .onTapGesture { withAnimation { selected = Date().startOfDay } }
                        Text(DF.dayMonth.string(from: selected))
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    HStack(spacing: 18) {
                        Button(action: onCalendar) {
                            Image(systemName: "calendar")
                        }
                        Button(action: onStats) { Image(systemName: "chart.bar") }
                        Button(action: onSettings) { Image(systemName: "gearshape") }
                    }
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 18)
                .padding(.top, 62)

                Spacer()

                WeekStrip(selected: $selected)
                    .padding(.bottom, 14)
            }
            .frame(height: 330)
        }
        .frame(height: 330)
        .onReceive(NotificationCenter.default.publisher(for: Backgrounds.changed)) { _ in
            backgrounds = Backgrounds.loadAll()
        }
    }
}

struct Slideshow: View {
    let images: [UIImage]
    @State private var index = 0
    private let timer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(images.indices, id: \.self) { i in
                    if i == index % max(images.count, 1) {
                        Image(uiImage: images[i])
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .transition(.opacity)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { next() }
        .onReceive(timer) { _ in next() }
    }

    private func next() {
        guard images.count > 1 else { return }
        withAnimation(.easeInOut(duration: 1.2)) { index = (index + 1) % images.count }
    }
}

struct Landscape: View {
    let night: Bool

    var body: some View {
        let sky: [Color] = night ? [Color(hex: 0x4B3DB5), Color(hex: 0x9C82E6)] : [Color(hex: 0x16A9EC), Color(hex: 0x86DBFB)]
        let far = night ? Color(hex: 0xC2B3F2) : Color(hex: 0xC9EEFC)
        let mid = night ? Color(hex: 0x8770D3) : Color(hex: 0x62C0E8)
        let near = night ? Color(hex: 0x3E3277) : Color(hex: 0x2C7FA6)
        let trees = night ? Color(hex: 0x1F1940) : Color(hex: 0x1B5875)

        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: sky, startPoint: .top, endPoint: .bottom)
                if night {
                    ForEach(0..<28, id: \.self) { i in
                        Circle().fill(.white.opacity(i % 3 == 0 ? 0.9 : 0.5))
                            .frame(width: i % 4 == 0 ? 2.5 : 1.5)
                            .position(x: CGFloat((i * 137) % 400) / 400 * geo.size.width,
                                      y: CGFloat((i * 89) % 160) + 20)
                    }
                }
                Circle()
                    .fill(night ? Color(hex: 0xF4F1FF) : Color(hex: 0xFFF6C8))
                    .frame(width: 64, height: 64)
                    .shadow(color: .white.opacity(0.6), radius: 20)
                    .position(x: geo.size.width * 0.58, y: 200)
                Ridge(points: [0.75, 0.45, 0.6, 0.3, 0.55, 0.25, 0.5, 0.4, 0.7])
                    .fill(far)
                    .frame(height: 170)
                    .position(x: geo.size.width / 2, y: geo.size.height - 85)
                Ridge(points: [0.8, 0.5, 0.65, 0.4, 0.75, 0.45, 0.6, 0.5, 0.8])
                    .fill(mid)
                    .frame(height: 120)
                    .position(x: geo.size.width / 2, y: geo.size.height - 60)
                Ridge(points: [0.6, 0.55, 0.7, 0.5, 0.65, 0.6, 0.45, 0.65, 0.55])
                    .fill(near)
                    .frame(height: 80)
                    .position(x: geo.size.width / 2, y: geo.size.height - 40)
                Ridge(points: (0..<41).map { i in i % 2 == 0 ? 0.25 + Double((i * 7) % 5) * 0.08 : 0.75 })
                    .fill(trees)
                    .frame(height: 46)
                    .position(x: geo.size.width / 2, y: geo.size.height - 23)
                LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .center, endPoint: .bottom)
            }
        }
    }
}

struct Ridge: Shape {
    let points: [Double]
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        for (i, h) in points.enumerated() {
            let x = r.minX + r.width * CGFloat(i) / CGFloat(max(points.count - 1, 1))
            p.addLine(to: CGPoint(x: x, y: r.minY + r.height * CGFloat(h)))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct WeekStrip: View {
    @Binding var selected: Date
    private let days: [Date] = (-21...21).map { Date().startOfDay.adding(days: $0) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { d in
                        let on = d.isSameDay(selected)
                        Button {
                            withAnimation(.snappy) { selected = d }
                        } label: {
                            VStack(spacing: 2) {
                                Text(DF.weekdayShort.string(from: d).capFirst)
                                    .font(.system(size: 11, weight: .semibold))
                                Text("\(Cal.ru.component(.day, from: d))")
                                    .font(.system(size: 20, weight: .bold))
                            }
                            .frame(width: 48, height: 58)
                            .foregroundStyle(on ? Color.black : Color.white.opacity(0.85))
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(on ? Color.white : Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(on ? 0 : 0.35), lineWidth: 1)
                            )
                            .overlay(alignment: .bottom) {
                                if d.isSameDay(Date()) && !on {
                                    Circle().fill(.white).frame(width: 4, height: 4).padding(.bottom, 5)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(d)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, v in withAnimation { proxy.scrollTo(v, anchor: .center) } }
        }
    }
}

// MARK: - Task row

struct TaskRow: View {
    @EnvironmentObject var store: Store
    let task: TaskItem
    var onOpen: () -> Void
    var onFocus: () -> Void

    var body: some View {
        let goal = store.data.goal(task.goalId)
        let color = goal.map { Palette.goal($0.color) } ?? Color.secondary.opacity(0.3)

        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            Button {
                withAnimation(.snappy) { store.toggle(task.id) }
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(task.done ? Palette.accent : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 7) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? Color.secondary : Color.primary)
                if !task.note.isEmpty {
                    Text(task.note).font(.footnote).foregroundStyle(Color.secondary).lineLimit(2)
                }
                if task.time != nil || goal != nil || task.remind {
                    HStack(spacing: 6) {
                        if let t = task.time { Chip(icon: "clock", text: t.timeString) }
                        if let g = goal { Chip(text: "\(g.emoji) \(g.title)", color: Palette.goal(g.color)) }
                        if task.remind { Image(systemName: "bell.fill").font(.caption2).foregroundStyle(Color.orange) }
                    }
                }
                ForEach(task.subtasks) { s in
                    Button {
                        store.toggleSub(task.id, s.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: s.done ? "checkmark.square.fill" : "square")
                                .foregroundStyle(s.done ? Palette.red : Color.secondary)
                            Text(s.title)
                                .font(.subheadline)
                                .strikethrough(s.done)
                                .foregroundStyle(s.done ? Color.secondary : Color.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            Button {
                store.toggleStar(task.id)
            } label: {
                Image(systemName: task.important ? "star.fill" : "star")
                    .foregroundStyle(task.important ? Palette.yellow : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button { onFocus() } label: { Label("Фокус-таймер", systemImage: "timer") }
            Button { store.toggle(task.id) } label: { Label(task.done ? "Вернуть" : "Выполнено", systemImage: "checkmark") }
            Button(role: .destructive) { store.deleteTask(task.id) } label: { Label("Удалить", systemImage: "trash") }
        }
    }
}

// MARK: - Task editor

struct TaskEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var task: TaskItem
    @State private var hasTime: Bool
    @State private var timeValue: Date
    @State private var newSub = ""
    @FocusState private var titleFocused: Bool
    let isNew: Bool

    init(task: TaskItem, isNew: Bool) {
        _task = State(initialValue: task)
        _hasTime = State(initialValue: task.time != nil)
        let defaultTime = Cal.ru.date(bySettingHour: Cal.ru.component(.hour, from: Date()) + 1, minute: 0, second: 0, of: Date()) ?? Date()
        _timeValue = State(initialValue: task.time ?? defaultTime)
        self.isNew = isNew
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                Spacer()
                if !isNew {
                    Button(role: .destructive) {
                        store.deleteTask(task.id); dismiss()
                    } label: { Image(systemName: "trash").foregroundStyle(Palette.red) }
                        .padding(.trailing, 12)
                }
                Button { save() } label: {
                    Text("Сохранить")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(UIColor.systemBackground))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(Color.primary))
                }
                .buttonStyle(.plain)
                .disabled(task.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24))
                            .foregroundStyle(task.done ? Palette.accent : Color.secondary)
                            .onTapGesture { task.done.toggle() }
                        TextField("Что нужно сделать?", text: $task.title, axis: .vertical)
                            .font(.title3.weight(.bold))
                            .focused($titleFocused)
                        Image(systemName: task.important ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(task.important ? Palette.yellow : Color.secondary)
                            .onTapGesture { task.important.toggle() }
                    }

                    TextField("Заметка", text: $task.note, axis: .vertical)
                        .font(.subheadline)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

                    ForEach($task.subtasks) { $s in
                        HStack {
                            Image(systemName: s.done ? "checkmark.square.fill" : "square")
                                .foregroundStyle(s.done ? Palette.red : Color.secondary)
                                .onTapGesture { s.done.toggle() }
                            TextField("Подзадача", text: $s.title)
                            Button { task.subtasks.removeAll { $0.id == s.id } } label: {
                                Image(systemName: "xmark").font(.caption).foregroundStyle(Color.secondary)
                            }
                        }
                    }
                    HStack {
                        Image(systemName: "plus.square").foregroundStyle(Color.secondary)
                        TextField("Добавить подзадачу", text: $newSub)
                            .onSubmit {
                                let t = newSub.trimmingCharacters(in: .whitespaces)
                                if !t.isEmpty { task.subtasks.append(Subtask(title: t)) }
                                newSub = ""
                            }
                    }
                    .font(.subheadline)

                    Divider()

                    DatePicker(selection: $task.day, displayedComponents: .date) {
                        Label("Дата", systemImage: "calendar")
                    }
                    Toggle(isOn: $hasTime.animation()) { Label("Время", systemImage: "clock") }
                    if hasTime {
                        DatePicker(selection: $timeValue, displayedComponents: .hourAndMinute) {
                            Label("Во сколько", systemImage: "clock.arrow.circlepath")
                        }
                        Toggle(isOn: $task.remind) { Label("Напомнить", systemImage: "bell") }
                    }

                    HStack {
                        Label("Цель", systemImage: "folder")
                        Spacer()
                        Menu {
                            Button("Без цели") { task.goalId = nil }
                            ForEach(store.data.goals) { g in
                                Button("\(g.emoji) \(g.title)") { task.goalId = g.id }
                            }
                        } label: {
                            if let g = store.data.goal(task.goalId) {
                                Chip(text: "\(g.emoji) \(g.title)", color: Palette.goal(g.color))
                            } else {
                                Chip(text: "Выбрать")
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .presentationDetents([.large])
        .onAppear { if isNew { titleFocused = true } }
    }

    private func save() {
        var t = task
        t.title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        t.day = t.day.startOfDay
        if hasTime {
            let c = Cal.ru.dateComponents([.hour, .minute], from: timeValue)
            t.time = Cal.ru.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0, of: t.day)
        } else {
            t.time = nil
            t.remind = false
        }
        if t.done && t.doneAt == nil { t.doneAt = Date() }
        if !t.done { t.doneAt = nil }
        let s = newSub.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { t.subtasks.append(Subtask(title: s)) }
        store.upsert(t)
        dismiss()
    }
}

// MARK: - Focus timer

struct FocusView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    @State private var total = 25 * 60
    @State private var left = 25 * 60
    @State private var running = false
    @State private var endDate: Date? = nil
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let progress = 1 - Double(left) / Double(max(total, 1))
        ZStack {
            Color.black.ignoresSafeArea()
            TimelineView(.animation) { ctx in
                let phase = ctx.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        Wave(phase: phase * 1.3, amplitude: 14, level: 0.25 + 0.6 * progress)
                            .fill(Palette.green.opacity(0.55))
                        Wave(phase: phase * 0.9 + 1, amplitude: 18, level: 0.22 + 0.6 * progress)
                            .fill(Palette.green)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .ignoresSafeArea()
            }

            VStack(spacing: 18) {
                HStack {
                    Button { stop(); dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                    Spacer()
                    Text("Фокус-таймер").font(.headline)
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 18)

                Spacer()
                if let g = store.data.goal(task.goalId) {
                    Text("\(g.emoji) \(g.title)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                }
                Text(task.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Text(String(format: "%02d:%02d", left / 60, left % 60))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.top, 10)
                HStack(spacing: 36) {
                    Button { adjust(-5) } label: { Image(systemName: "backward.end.fill").font(.title2) }
                    Button { running ? pause() : start() } label: {
                        Image(systemName: running ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundStyle(.black)
                            .frame(width: 72, height: 72)
                            .background(Circle().fill(.white))
                    }
                    Button { adjust(5) } label: { Image(systemName: "forward.end.fill").font(.title2) }
                }
                Text("−5 / +5 минут").font(.caption).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button {
                    stop()
                    if !task.done { store.toggle(task.id) }
                    dismiss()
                } label: {
                    Label("Задача выполнена", systemImage: "checkmark")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 26).padding(.vertical, 15)
                        .background(Capsule().fill(.white))
                }
                .padding(.bottom, 30)
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)
        }
        .onReceive(ticker) { _ in
            guard running, let end = endDate else { return }
            left = max(0, Int(end.timeIntervalSinceNow.rounded()))
            if left == 0 {
                running = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func start() {
        if left == 0 { left = total }
        endDate = Date().addingTimeInterval(TimeInterval(left))
        running = true
        Notifier.focusEnd(after: left, title: task.title)
    }
    private func pause() { running = false; endDate = nil; Notifier.cancelFocus() }
    private func stop() { pause() }
    private func adjust(_ minutes: Int) {
        let delta = minutes * 60
        total = max(60, total + delta)
        left = max(60, left + delta)
        if running { start() }
    }
}

struct Wave: Shape {
    var phase: Double
    var amplitude: Double
    var level: Double

    func path(in r: CGRect) -> Path {
        var p = Path()
        let baseY = r.maxY - r.height * CGFloat(min(max(level, 0), 1))
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        var x: CGFloat = 0
        while x <= r.width {
            let y = baseY + CGFloat(sin(Double(x) / Double(r.width) * 2 * .pi * 1.2 + phase) * amplitude)
            p.addLine(to: CGPoint(x: x, y: y))
            x += 4
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
