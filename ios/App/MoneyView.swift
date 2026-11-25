import SwiftUI
import Charts

enum MoneyCats {
    static let expense = ["Еда", "Транспорт", "Жильё", "Связь", "Здоровье", "Одежда", "Развлечения", "Подписки", "Долги", "Другое"]
    static let income = ["Зарплата", "Бизнес", "Майнинг", "Подработка", "Инвестиции", "Подарок", "Другое"]
}

struct MoneyView: View {
    @EnvironmentObject var store: Store
    @State private var month = Date()
    @State private var income = false
    @State private var amount = ""
    @State private var category = "Еда"
    @State private var note = ""
    @FocusState private var amountFocused: Bool

    var body: some View {
        let cur = store.data.currency
        let list = store.data.transactions
            .filter { Cal.ru.isDate($0.date, equalTo: month, toGranularity: .month) }
            .sorted { $0.date > $1.date }
        let totals = store.data.monthTotals(month)
        var cats: [String: Double] = [:]
        for t in list where !t.income { cats[t.category, default: 0] += t.amount }
        let catList = cats.sorted { $0.value > $1.value }

        return NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Button { month = Cal.ru.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text(DF.monthYear.string(from: month).capFirst).font(.headline)
                        Spacer()
                        Button { month = Cal.ru.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)

                    HStack(spacing: 10) {
                        StatTile(title: "Доходы", value: formatMoney(totals.income, cur), color: Palette.green)
                        StatTile(title: "Расходы", value: formatMoney(totals.expense, cur), color: Palette.red)
                    }
                    StatTile(title: "Остаток за месяц", value: formatMoney(totals.income - totals.expense, cur),
                             color: totals.income - totals.expense >= 0 ? Palette.accent : Palette.red)

                    VStack(spacing: 10) {
                        Picker("", selection: $income) {
                            Text("Расход").tag(false)
                            Text("Доход").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: income) { _, v in category = v ? MoneyCats.income[0] : MoneyCats.expense[0] }

                        HStack {
                            TextField("Сумма", text: $amount)
                                .keyboardType(.decimalPad)
                                .focused($amountFocused)
                                .font(.title3.weight(.bold))
                            Menu {
                                ForEach(income ? MoneyCats.income : MoneyCats.expense, id: \.self) { c in
                                    Button(c) { category = c }
                                }
                            } label: { Chip(icon: "tag", text: category, color: Palette.accent) }
                        }
                        TextField("Комментарий", text: $note)
                        Button {
                            let v = Double(amount.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")) ?? 0
                            guard v > 0 else { return }
                            store.addTx(Transaction(income: income, amount: v, category: category, note: note))
                            amount = ""; note = ""; amountFocused = false
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            Text("Записать").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .card(16)

                    if !catList.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("РАСХОДЫ ПО КАТЕГОРИЯМ").font(.footnote.weight(.bold)).foregroundStyle(Color.secondary)
                            Chart(catList, id: \.key) { item in
                                BarMark(x: .value("Сумма", item.value), y: .value("Категория", item.key))
                                    .foregroundStyle(Palette.red.gradient)
                                    .cornerRadius(6)
                                    .annotation(position: .trailing) {
                                        Text(formatMoney(item.value, cur)).font(.caption2).foregroundStyle(Color.secondary)
                                    }
                            }
                            .chartXAxis(.hidden)
                            .frame(height: CGFloat(catList.count) * 34 + 10)
                        }
                        .card(16)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("ОПЕРАЦИИ").font(.footnote.weight(.bold)).foregroundStyle(Color.secondary).padding(.bottom, 8)
                        if list.isEmpty {
                            Text("Нет операций в этом месяце").font(.subheadline).foregroundStyle(Color.secondary).padding(.vertical, 8)
                        }
                        ForEach(list) { t in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.category).font(.subheadline.weight(.semibold))
                                    Text((t.note.isEmpty ? "" : t.note + " · ") + DF.dayMonth.string(from: t.date))
                                        .font(.caption).foregroundStyle(Color.secondary)
                                }
                                Spacer()
                                Text((t.income ? "+" : "−") + formatMoney(t.amount, cur))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(t.income ? Palette.green : Palette.red)
                            }
                            .padding(.vertical, 8)
                            .contextMenu {
                                Button(role: .destructive) { store.deleteTx(t.id) } label: { Label("Удалить", systemImage: "trash") }
                            }
                            Divider()
                        }
                    }
                    .card(16)
                }
                .padding(16)
                .padding(.bottom, 100)
            }
            .background(Palette.bg)
            .navigationTitle("Деньги")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.askAI = "Проанализируй мои доходы и расходы за этот месяц и дай советы, где сэкономить и как быстрее прийти к финансовым целям."
                    } label: { Image(systemName: "sparkles") }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { amountFocused = false }
                }
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.secondary)
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(14)
    }
}

// MARK: - Stats

struct StatBar: Identifiable {
    let id = UUID()
    let bucket: String
    let order: Int
    let goal: String
    let count: Int
}

struct StatsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var period = 1
    @State private var anchor = Date()

    var body: some View {
        let range = currentRange()
        let prev = previousRange()
        let done = store.data.tasks.filter { t in t.done && range.contains(t.doneAt ?? t.day) }
        let prevDone = store.data.tasks.filter { t in t.done && prev.contains(t.doneAt ?? t.day) }.count
        let important = done.filter(\.important).count
        let change = prevDone == 0 ? nil : Int((Double(done.count - prevDone) / Double(prevDone) * 100).rounded())
        let bars = makeBars(done)
        var byGoal: [UUID?: Int] = [:]
        for t in done { byGoal[t.goalId, default: 0] += 1 }
        let goalRows = byGoal.sorted { $0.value > $1.value }
        let goalNames = store.data.goals.map { "\($0.emoji) \($0.title)" } + ["Без цели"]
        let goalColors = store.data.goals.map { Palette.goal($0.color) } + [Color.gray.opacity(0.5)]

        return NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("", selection: $period) {
                        Text("Неделя").tag(0)
                        Text("Месяц").tag(1)
                        Text("Год").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: period) { _, _ in anchor = Date() }

                    HStack {
                        Button { shift(-1) } label: { Image(systemName: "arrow.left") }
                        Spacer()
                        Text(title(range)).font(.headline).foregroundStyle(Palette.accent)
                        Spacer()
                        Button { shift(1) } label: { Image(systemName: "arrow.right") }
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        StatTile(title: "✅ Выполнено", value: "\(done.count)", color: Color.primary)
                        StatTile(title: "⭐ Важных", value: "\(important)", color: Color.primary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("ВЫПОЛНЕННЫЕ ЗАДАЧИ").font(.footnote.weight(.bold)).foregroundStyle(Color.secondary)
                        Chart(bars) { b in
                            BarMark(x: .value("Период", b.bucket), y: .value("Задачи", b.count))
                                .foregroundStyle(by: .value("Цель", b.goal))
                                .cornerRadius(3)
                        }
                        .chartForegroundStyleScale(domain: goalNames, range: goalColors)
                        .chartLegend(.hidden)
                        .frame(height: 200)
                        HStack(spacing: 10) {
                            StatTile(title: "К прошлому периоду",
                                     value: change.map { ($0 >= 0 ? "▲ " : "▼ ") + "\(abs($0))%" } ?? "—",
                                     color: (change ?? 0) >= 0 ? Palette.green : Palette.red)
                            StatTile(title: "Привычек сегодня",
                                     value: "\(store.data.habits.filter { $0.isDone() }.count)/\(store.data.habits.count)",
                                     color: Palette.accent)
                        }
                    }
                    .card(16)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("ПО ЦЕЛЯМ").font(.footnote.weight(.bold)).foregroundStyle(Color.secondary).padding(.bottom, 6)
                        if goalRows.isEmpty {
                            Text("Пока ничего не выполнено").font(.subheadline).foregroundStyle(Color.secondary).padding(.vertical, 8)
                        }
                        ForEach(goalRows, id: \.key) { row in
                            let g = store.data.goal(row.key)
                            HStack {
                                Text(g.map { "\($0.title) \($0.emoji)" } ?? "Без цели").font(.body.weight(.semibold))
                                Spacer()
                                Text("\(row.value)").font(.body.weight(.bold))
                                    .foregroundStyle(g.map { Palette.goal($0.color) } ?? Color.secondary)
                            }
                            .padding(.vertical, 10)
                            Divider()
                        }
                    }
                    .card(16)
                }
                .padding(16)
            }
            .background(Palette.bg)
            .navigationTitle("Итоги")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }

    private var unit: Calendar.Component { [.weekOfYear, .month, .year][period] }

    private func currentRange() -> Range<Date> {
        let i = Cal.ru.dateInterval(of: unit, for: anchor) ?? DateInterval(start: anchor, duration: 86400)
        return i.start..<i.end
    }
    private func previousRange() -> Range<Date> {
        let p = Cal.ru.date(byAdding: unit, value: -1, to: anchor) ?? anchor
        let i = Cal.ru.dateInterval(of: unit, for: p) ?? DateInterval(start: p, duration: 86400)
        return i.start..<i.end
    }
    private func shift(_ n: Int) { anchor = Cal.ru.date(byAdding: unit, value: n, to: anchor) ?? anchor }

    private func title(_ r: Range<Date>) -> String {
        switch period {
        case 0: return "\(Cal.ru.component(.day, from: r.lowerBound))–\(DF.dayMonth.string(from: r.upperBound.adding(days: -1)))"
        case 1: return DF.monthYear.string(from: r.lowerBound).capFirst
        default: return "\(Cal.ru.component(.year, from: r.lowerBound))"
        }
    }

    private func makeBars(_ done: [TaskItem]) -> [StatBar] {
        let range = currentRange()
        var buckets: [(String, Range<Date>)] = []
        if period == 2 {
            for m in 0..<12 {
                let s = Cal.ru.date(byAdding: .month, value: m, to: range.lowerBound)!
                let e = Cal.ru.date(byAdding: .month, value: 1, to: s)!
                buckets.append((DF.monthShort.string(from: s).capFirst, s..<e))
            }
        } else {
            var d = range.lowerBound
            while d < range.upperBound {
                let label = period == 0 ? DF.weekdayShort.string(from: d).capFirst : "\(Cal.ru.component(.day, from: d))"
                buckets.append((label, d..<d.adding(days: 1)))
                d = d.adding(days: 1)
            }
        }
        var out: [StatBar] = []
        for (i, b) in buckets.enumerated() {
            let inB = done.filter { b.1.contains($0.doneAt ?? $0.day) }
            var byGoal: [String: Int] = [:]
            for t in inB {
                let name = store.data.goal(t.goalId).map { "\($0.emoji) \($0.title)" } ?? "Без цели"
                byGoal[name, default: 0] += 1
            }
            if byGoal.isEmpty {
                out.append(StatBar(bucket: b.0, order: i, goal: "Без цели", count: 0))
            }
            for (g, c) in byGoal { out.append(StatBar(bucket: b.0, order: i, goal: g, count: c)) }
        }
        return out
    }
}
