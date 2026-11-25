import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Palette {
    static let accent = Color(hex: 0x1EB8F5)
    static let green = Color(hex: 0x5FCF5A)
    static let red = Color(hex: 0xF0605D)
    static let yellow = Color(hex: 0xF7C948)
    static let goals: [Color] = [0x1EB8F5, 0xF9D45C, 0x66D35E, 0xDE9BE6, 0xF66BA8, 0xA9B6BE, 0x4F6573, 0xFF8A4C]
        .map { Color(hex: $0) }
    static func goal(_ i: Int) -> Color { goals[((i % goals.count) + goals.count) % goals.count] }
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    static let bg = Color(UIColor.systemGroupedBackground)
}
