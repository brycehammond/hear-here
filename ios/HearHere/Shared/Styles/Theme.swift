import SwiftUI

/// Centralized design tokens for colors, typography, and spacing.
///
/// All views reference ``Theme`` for consistent styling. Colors adapt
/// to light/dark mode via semantic definitions. Typography uses only
/// semantic font styles (`.title`, `.body`, `.caption`) for Dynamic Type support.
enum Theme {

    // MARK: - Colors

    /// The primary accent color used for interactive elements and highlights.
    static let accent = Color.accentColor

    /// Primary content color (text, icons).
    static let primary = Color.primary

    /// Secondary content color (subtitles, supplementary text).
    static let secondary = Color.secondary

    /// Semantic color for error states and destructive actions.
    static let error = Color.red

    /// Semantic color for warnings and pending states.
    static let warning = Color.orange

    /// Semantic color for success and approved states.
    static let success = Color.green

    /// Surface background color that adapts to light/dark mode.
    #if os(iOS)
    static let surface = Color(uiColor: .systemBackground)
    #else
    static let surface = Color(nsColor: .windowBackgroundColor)
    #endif

    /// Secondary surface for cards and grouped content.
    #if os(iOS)
    static let surfaceSecondary = Color(uiColor: .secondarySystemBackground)
    #else
    static let surfaceSecondary = Color(nsColor: .controlBackgroundColor)
    #endif

    /// Tertiary surface for nested groupings.
    #if os(iOS)
    static let surfaceTertiary = Color(uiColor: .tertiarySystemBackground)
    #else
    static let surfaceTertiary = Color(nsColor: .underPageBackgroundColor)
    #endif

    /// Content color on surfaces.
    #if os(iOS)
    static let onSurface = Color(uiColor: .label)
    #else
    static let onSurface = Color(nsColor: .labelColor)
    #endif

    /// Secondary content color on surfaces.
    #if os(iOS)
    static let onSurfaceSecondary = Color(uiColor: .secondaryLabel)
    #else
    static let onSurfaceSecondary = Color(nsColor: .secondaryLabelColor)
    #endif

    // MARK: - Waveform & Editing Colors

    /// Accent-based color for waveform bars.
    static let waveformForeground = Color.accentColor

    /// Subtle background for waveform container.
    #if os(iOS)
    static let waveformBackground = Color(uiColor: .tertiarySystemFill)
    #else
    static let waveformBackground = Color(nsColor: .controlBackgroundColor)
    #endif

    /// Semi-transparent overlay for selected region.
    static let selectionHighlight = Color.accentColor.opacity(0.2)

    /// Bright color for the playhead line.
    static let playheadColor = Color.accentColor

    /// Red color for clipping warnings.
    static let clippingIndicator = Color.red

    // MARK: - Spacing

    /// Extra-small spacing: 4pt.
    static let spacingXS: CGFloat = 4

    /// Small spacing: 8pt.
    static let spacingSM: CGFloat = 8

    /// Medium spacing: 16pt.
    static let spacingMD: CGFloat = 16

    /// Large spacing: 24pt.
    static let spacingLG: CGFloat = 24

    /// Extra-large spacing: 32pt.
    static let spacingXL: CGFloat = 32

    // MARK: - Corner Radii

    /// Small corner radius for badges and chips.
    static let cornerRadiusSM: CGFloat = 8

    /// Medium corner radius for cards and buttons.
    static let cornerRadiusMD: CGFloat = 12

    /// Large corner radius for sheets and modals.
    static let cornerRadiusLG: CGFloat = 16

    // MARK: - Minimum Tap Target

    /// Minimum tap target dimension per Apple HIG (44x44pt).
    static let minTapTarget: CGFloat = 44
}
