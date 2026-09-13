import SwiftUI
import UIKit

struct AppIconOption: Identifiable {
    var id: String { alternateName ?? "stock" }
    let alternateName: String?
    let title: String

    var image: UIImage? {
        if let alternateName {
            return UIImage(named: alternateName)
        }
        return UIImage(named: "stock") ?? UIImage(named: "AppIcon")
    }

    func color() -> UIColor {
        image?.dominantColor() ?? .systemBlue
    }
}

enum AppIconCatalog {
    static let options: [AppIconOption] = [
        AppIconOption(alternateName: nil, title: "Стоковая"),
        AppIconOption(alternateName: "frame-32", title: "Frame 32"),
        AppIconOption(alternateName: "frame-33", title: "Frame 33"),
        AppIconOption(alternateName: "frame-34", title: "Frame 34"),
        AppIconOption(alternateName: "frame-35", title: "Frame 35"),
        AppIconOption(alternateName: "frame-36", title: "Frame 36"),
        AppIconOption(alternateName: "frame-37", title: "Frame 37"),
        AppIconOption(alternateName: "frame-38", title: "Frame 38"),
        AppIconOption(alternateName: "frame-39", title: "Frame 39"),
        AppIconOption(alternateName: "frame-40", title: "Frame 40"),
        AppIconOption(alternateName: "frame-41", title: "Frame 41"),
        AppIconOption(alternateName: "frame-42", title: "Frame 42")
    ]
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private static let iconKey = "appIcon"

    @Published var currentIconName: String? {
        didSet {
            UserDefaults.standard.set(currentIconName, forKey: Self.iconKey)
        }
    }
    @Published var accent: Color

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.iconKey)
        let active = UIApplication.shared.alternateIconName
        currentIconName = stored ?? active
        accent = Self.loadAccent()
    }

    private static func loadAccent() -> Color {
        let name = UserDefaults.standard.string(forKey: iconKey)
        let option = AppIconCatalog.options.first { $0.alternateName == name } ?? AppIconCatalog.options[0]
        return Color(uiColor: option.color())
    }

    func apply(option: AppIconOption) {
        currentIconName = option.alternateName
        accent = Color(uiColor: option.color())
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(option.alternateName) { _ in }
    }
}

extension UIImage {
    func dominantColor() -> UIColor {
        guard let cgImage = cgImage else { return .systemBlue }
        let size = 48
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .systemBlue }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        var buckets: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[i])
            let g = Int(pixels[i + 1])
            let b = Int(pixels[i + 2])
            let a = Int(pixels[i + 3])
            guard a >= 128 else { continue }
            let key = (r >> 6) << 4 | (g >> 6) << 2 | (b >> 6)
            var e = buckets[key] ?? (0, 0, 0, 0)
            e.count += 1
            e.r += Double(r)
            e.g += Double(g)
            e.b += Double(b)
            buckets[key] = e
        }

        guard let best = buckets.max(by: { lhs, rhs in
            let sl = saturation(lhs.value)
            let sr = saturation(rhs.value)
            if abs(sl - sr) > 0.25 { return sl < sr }
            return lhs.value.count < rhs.value.count
        }) else { return .systemBlue }

        let c = Double(best.value.count)
        return UIColor(
            red: best.value.r / c / 255.0,
            green: best.value.g / c / 255.0,
            blue: best.value.b / c / 255.0,
            alpha: 1
        )
    }

    private func saturation(_ e: (count: Int, r: Double, g: Double, b: Double)) -> Double {
        let mx = max(e.r, max(e.g, e.b))
        let mn = min(e.r, min(e.g, e.b))
        let den = mx + mn
        return den > 0 ? (mx - mn) / den : 0
    }
}