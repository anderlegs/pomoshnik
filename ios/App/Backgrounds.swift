import UIKit

enum Backgrounds {
    static let changed = Notification.Name("pomoshnik.backgrounds.changed")

    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("backgrounds")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func loadAll() -> [UIImage] {
        files().compactMap { UIImage(contentsOfFile: $0.path) }
    }

    static func add(_ data: Data) {
        guard let img = UIImage(data: data) else { return }
        let maxW: CGFloat = 1400
        let scale = min(1, maxW / max(img.size.width, 1))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpg = resized.jpegData(compressionQuality: 0.85) else { return }
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6)).jpg"
        try? jpg.write(to: dir.appendingPathComponent(name))
    }

    static func clear() {
        for f in files() { try? FileManager.default.removeItem(at: f) }
        NotificationCenter.default.post(name: changed, object: nil)
    }
}
