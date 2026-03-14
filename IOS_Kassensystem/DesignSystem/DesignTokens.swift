import SwiftUI
import UIKit

enum POSColor {
    static let slate950 = Color.adaptive(darkHex: 0x111827, lightHex: 0xF7FAFF)
    static let slate900 = Color.adaptive(darkHex: 0x1B2430, lightHex: 0xFFFFFF)
    static let slate850 = Color.adaptive(darkHex: 0x243040, lightHex: 0xEEF3FD)
    static let slate800 = Color.adaptive(darkHex: 0x2A3648, lightHex: 0xE7EDF8)
    static let slate700 = Color.adaptive(darkHex: 0x3A475A, lightHex: 0xC9D3E6)
    static let slate300 = Color.adaptive(darkHex: 0xB8C0CC, lightHex: 0x5B6678)
    static let slate100 = Color.adaptive(darkHex: 0xF2F4F7, lightHex: 0x1A2230)
    static let slate050 = Color.adaptive(darkHex: 0xF8FAFC, lightHex: 0x121A27)

    static let day100 = Color(hex: 0xEFF2F9)
    static let day200 = Color(hex: 0xDDE5F1)
    static let day300 = Color(hex: 0xC5D0E2)
    static let day900 = Color(hex: 0x1A2230)

    static let indigo500 = Color(hex: 0x6B4DFF)
    static let indigo400 = Color(hex: 0x836BFF)
    static let emerald500 = Color(hex: 0x2CB67D)
    static let kitchenReady500 = Color(hex: 0x2FB386)
    static let kitchenReadyOn = Color.adaptive(darkHex: 0xD4D4D4, lightHex: 0x0F3D2F)
    static let amber500 = Color(hex: 0xF59E0B)
    static let red500 = Color(hex: 0xEF4444)
}

enum POSRadius {
    static let card: CGFloat = 20
    static let innerCard: CGFloat = 16
    static let small: CGFloat = 12
    static let notice: CGFloat = 14
    static let pill: CGFloat = 999
}

enum POSSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
    static let xl: CGFloat = 14
    static let xxl: CGFloat = 16
}

enum POSMotion {
    static let quick = Animation.easeInOut(duration: 0.16)
    static let pulse = Animation.easeInOut(duration: 0.18)
    static let panel = Animation.easeInOut(duration: 0.22)
}

enum POSTypography {
    static let headlineLarge = Font.system(size: 32, weight: .bold, design: .default)
    static let titleLarge = Font.system(size: 20, weight: .semibold, design: .default)
    static let titleMedium = Font.system(size: 16, weight: .semibold, design: .default)
    static let bodyLarge = Font.system(size: 15, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 14, weight: .regular, design: .default)
    static let labelLarge = Font.system(size: 14, weight: .medium, design: .default)
    static let labelMedium = Font.system(size: 12, weight: .medium, design: .default)
}

extension Color {
    static func adaptive(
        darkHex: UInt32,
        lightHex: UInt32,
        darkAlpha: Double = 1.0,
        lightAlpha: Double = 1.0
    ) -> Color {
        Color(
            UIColor { traits in
                let useDark = traits.userInterfaceStyle == .dark
                let hex = useDark ? darkHex : lightHex
                let alpha = useDark ? darkAlpha : lightAlpha
                let red = CGFloat((hex >> 16) & 0xFF) / 255.0
                let green = CGFloat((hex >> 8) & 0xFF) / 255.0
                let blue = CGFloat(hex & 0xFF) / 255.0
                return UIColor(red: red, green: green, blue: blue, alpha: alpha)
            }
        )
    }

    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
