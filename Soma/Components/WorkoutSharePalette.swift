import SwiftUI

/// The selected export design uses a fixed print palette, independent of the sheet's appearance.
enum WorkoutSharePalette {
    static let paper = Color.white
    static let ink = Color.black
    static let secondaryInk = Color(white: 0.38)
    static let rule = Color(white: 0.83)
    static let cardRule = Color(white: 0.90)
    static let groupSurface = Color(white: 0.965)
    static let hero = Color(red: 1, green: 0.71, blue: 0.21)
    static let activeMuscle = Color(red: 0.86, green: 0.25, blue: 0)
    static let secondaryMuscle = activeMuscle.opacity(0.60)
}
