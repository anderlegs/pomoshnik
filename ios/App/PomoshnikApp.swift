import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

@main
struct PomoshnikApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onAppear { Notifier.requestAuth() }
        }
    }
}

enum Tab: Int, CaseIterable {
    case goals, today, habits, money, ai

    var title: String { ["Цели", "Сегодня", "Привычки", "Деньги", "ИИ"][rawValue] }
    var icon: String { ["folder", "calendar", "square.grid.2x2", "creditcard", "sparkles"][rawValue] }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase
    @State private var tab: Tab = .today
    @State private var newTask: TaskItem? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .goals: GoalsView()
                case .today: TodayView()
                case .habits: HabitsView()
                case .money: MoneyView()
                case .ai: AIView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(tab: $tab) { newTask = TaskItem(title: "") }
                .ignoresSafeArea(.keyboard)
        }
        .sheet(item: $newTask) { t in TaskEditor(task: t, isNew: true) }
        .onChange(of: phase) { _, p in if p == .active { store.reload() } }
        .onChange(of: store.askAI) { _, v in if v != nil { tab = .ai } }
    }
}

struct TabBar: View {
    @Binding var tab: Tab
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button {
                        withAnimation(.snappy) { tab = t }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.icon).font(.system(size: 17, weight: .medium))
                            Text(t.title).font(.system(size: 10, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(tab == t ? Color.primary.opacity(0.1) : Color.clear)
                        )
                        .foregroundStyle(tab == t ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08)))

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.primary)
                    .frame(width: 58, height: 58)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }
}

// MARK: - Small shared UI pieces

struct SectionHeader: View {
    let title: String
    @Binding var open: Bool
    var body: some View {
        Button {
            withAnimation(.snappy) { open.toggle() }
        } label: {
            HStack {
                Text(title).font(.footnote.weight(.bold)).foregroundStyle(Color.secondary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .rotationEffect(.degrees(open ? 0 : -90))
            }
            .padding(.top, 14)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    var icon: String? = nil
    let text: String
    var color: Color = .secondary
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(text).font(.caption.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

struct EmptyCard: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card))
    }
}

extension View {
    func card(_ padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
    }
}
