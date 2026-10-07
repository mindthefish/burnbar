import AppKit
import SwiftUI

extension Color {
    static func accent(for accent: ProviderQuotaSnapshot.Accent) -> Color {
        switch accent {
        case .claude:
            Color(red: 0.91, green: 0.43, blue: 0.02)
        case .privateOpenAI:
            Color(red: 0.16, green: 0.76, blue: 0.44)
        case .workOpenAI:
            Color(red: 0.49, green: 0.20, blue: 0.91)
        case let .custom(hex):
            if let rgb = UInt32(hex.dropFirst(), radix: 16) {
                Color(red: Double((rgb >> 16) & 255) / 255,
                      green: Double((rgb >> 8) & 255) / 255,
                      blue: Double(rgb & 255) / 255)
            } else {
                Color.gray
            }
        }
    }

    var hexRGB: String {
        let rgb = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X",
                      Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()),
                      Int((rgb.blueComponent * 255).rounded()))
    }
}
