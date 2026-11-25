import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Palette {
    static let accentOptions: [(name: String, hex: UInt32)] = [
        ("Голубой", 0x1EB8F5), ("Синий", 0x3B6FE0), ("Фиолетовый", 0x8E6CF0), ("Розовый", 0xF0609E),
        ("Красный", 0xF05A5A), ("Оранжевый", 0xFF8A3D), ("Жёлтый", 0xE0A800), ("Зелёный", 0x34C27A),
        ("Бирюзовый", 0x18B8A8), ("Графит", 0x6B7686)
    ]
    static var accentIndex: Int {
        min(max(Shared.defaults.integer(forKey: "accent_index"), 0), accentOptions.count - 1)
    }
    static var accent: Color { Color(hex: accentOptions[accentIndex].hex) }
    static let green = Color(hex: 0x5FCF5A)
    static let red = Color(hex: 0xF0605D)
    static let yellow = Color(hex: 0xF7C948)
    static let goals: [Color] = [0x1EB8F5, 0xF9D45C, 0x66D35E, 0xDE9BE6, 0xF66BA8, 0xA9B6BE, 0x4F6573, 0xFF8A4C]
        .map { Color(hex: $0) }
    static func goal(_ i: Int) -> Color { goals[((i % goals.count) + goals.count) % goals.count] }
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    static let bg = Color(UIColor.systemGroupedBackground)
}
