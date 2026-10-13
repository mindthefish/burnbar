import Testing
@testable import Burnbar

struct QuotaColorsTests {
    @Test
    func validatesOnlySixDigitRGBHex() {
        #expect(QuotaColors.isValidHex("#aB09Ff"))
        for invalid in ["", "FF0000", "#FFF", "#FF000000", "#GG0000", "#FF0000\n"] {
            #expect(!QuotaColors.isValidHex(invalid))
        }
    }

    @Test
    func preservesEndpointsClampsAndPassesThroughYellow() {
        let colors = QuotaColors(full: "#00FF00", empty: "#FF0000")
        let red = QuotaColors.RGB(red: 1, green: 0, blue: 0)
        let green = QuotaColors.RGB(red: 0, green: 1, blue: 0)
        #expect(colors.rgb(remainingFraction: 0) == red)
        #expect(colors.rgb(remainingFraction: -1) == red)
        #expect(colors.rgb(remainingFraction: 1) == green)
        #expect(colors.rgb(remainingFraction: 2) == green)
        let midpoint = colors.rgb(remainingFraction: 0.5)
        #expect(abs(midpoint.red - 1) < 0.000001)
        #expect(abs(midpoint.green - 1) < 0.000001)
        #expect(midpoint.blue == 0)
        let standardMidpoint = QuotaColors.standard.rgb(remainingFraction: 0.5)
        #expect(standardMidpoint.red > 0.7)
        #expect(standardMidpoint.green > 0.8)
        #expect(standardMidpoint.blue < 0.3)
    }

    @Test
    func takesShortestHuePathAcrossRed() {
        let colors = QuotaColors(full: "#FF0080", empty: "#FF8000")
        let midpoint = colors.rgb(remainingFraction: 0.5)
        #expect(midpoint.red == 1)
        #expect(midpoint.green < 0.000001)
        #expect(midpoint.blue < 0.000001)
    }

    @Test
    func neutralEndpointsUseChromaticHue() {
        for colors in [
            QuotaColors(full: "#0000FF", empty: "#808080"),
            QuotaColors(full: "#808080", empty: "#0000FF")
        ] {
            let midpoint = colors.rgb(remainingFraction: 0.5)
            #expect(abs(midpoint.red - midpoint.green) < 0.000001)
            #expect(midpoint.blue > midpoint.red)
        }
        let gray = QuotaColors(full: "#FFFFFF", empty: "#000000").rgb(remainingFraction: 0.5)
        #expect(gray == QuotaColors.RGB(red: 0.5, green: 0.5, blue: 0.5))
    }

    @Test
    func malformedEndpointsAndNonfiniteFractionsRemainUsable() {
        let colors = QuotaColors(full: "invalid", empty: "invalid")
        #expect(colors.rgb(remainingFraction: 0.5) == QuotaColors.standard.rgb(remainingFraction: 0.5))
        #expect(colors.rgb(remainingFraction: .nan) == QuotaColors.standard.rgb(remainingFraction: 0))
        #expect(colors.rgb(remainingFraction: .infinity) == QuotaColors.standard.rgb(remainingFraction: 1))
        #expect(colors.rgb(remainingFraction: -.infinity) == QuotaColors.standard.rgb(remainingFraction: 0))
    }
}
