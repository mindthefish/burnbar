struct QuotaColors: Codable, Equatable, Sendable {
    var full: String
    var empty: String

    static let standard = QuotaColors(full: "#34C759", empty: "#FF3B30")

    struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
    }

    static func isValidHex(_ value: String) -> Bool {
        value.utf8.count == 7 && value.first == "#" && value.dropFirst().utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    func rgb(remainingFraction: Double) -> RGB {
        let start = Self.parse(empty) ?? Self.parse(Self.standard.empty) ?? RGB(red: 1, green: 0, blue: 0)
        let end = Self.parse(full) ?? Self.parse(Self.standard.full) ?? RGB(red: 0, green: 1, blue: 0)
        let fraction = remainingFraction.isNaN ? 0 : min(1, max(0, remainingFraction))
        if fraction == 0 { return start }
        if fraction == 1 { return end }
        var startHSV = HSV(start)
        var endHSV = HSV(end)
        // Neutral colors have no meaningful hue; use the chromatic endpoint's hue.
        if startHSV.saturation == 0 { startHSV.hue = endHSV.hue }
        if endHSV.saturation == 0 { endHSV.hue = startHSV.hue }
        var hueDelta = endHSV.hue - startHSV.hue
        if hueDelta > 0.5 { hueDelta -= 1 }
        if hueDelta < -0.5 { hueDelta += 1 }
        let hue = (startHSV.hue + hueDelta * fraction + 1).truncatingRemainder(dividingBy: 1)
        return HSV(
            hue: hue,
            saturation: startHSV.saturation + (endHSV.saturation - startHSV.saturation) * fraction,
            value: startHSV.value + (endHSV.value - startHSV.value) * fraction
        ).rgb
    }

    private static func parse(_ hex: String) -> RGB? {
        guard isValidHex(hex), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return RGB(
            red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255
        )
    }

    private struct HSV {
        var hue: Double
        let saturation: Double
        let value: Double

        init(hue: Double, saturation: Double, value: Double) {
            self.hue = hue
            self.saturation = saturation
            self.value = value
        }

        init(_ rgb: RGB) {
            let maximum = max(rgb.red, rgb.green, rgb.blue)
            let minimum = min(rgb.red, rgb.green, rgb.blue)
            let delta = maximum - minimum
            value = maximum
            saturation = maximum == 0 ? 0 : delta / maximum
            if delta == 0 {
                hue = 0
            } else if maximum == rgb.red {
                hue = ((rgb.green - rgb.blue) / delta + 6).truncatingRemainder(dividingBy: 6) / 6
            } else if maximum == rgb.green {
                hue = ((rgb.blue - rgb.red) / delta + 2) / 6
            } else {
                hue = ((rgb.red - rgb.green) / delta + 4) / 6
            }
        }

        var rgb: RGB {
            let chroma = value * saturation
            let sector = hue * 6
            let secondary = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
            let offset = value - chroma
            let components: (Double, Double, Double)
            switch sector {
            case ..<1: components = (chroma, secondary, 0)
            case ..<2: components = (secondary, chroma, 0)
            case ..<3: components = (0, chroma, secondary)
            case ..<4: components = (0, secondary, chroma)
            case ..<5: components = (secondary, 0, chroma)
            default: components = (chroma, 0, secondary)
            }
            return RGB(red: components.0 + offset, green: components.1 + offset, blue: components.2 + offset)
        }
    }
}
