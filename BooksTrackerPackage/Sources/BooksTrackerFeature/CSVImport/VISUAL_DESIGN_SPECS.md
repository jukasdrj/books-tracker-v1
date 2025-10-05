# CSV Import Live Activity - Visual Design Specifications

**iOS 26 Liquid Glass Design System**
**Version:** 1.0
**Designer Reference:** Apple HIG iOS 26

## Design Philosophy

The CSV import Live Activity embraces iOS 26's **Liquid Glass** design language with:

- **Fluid Motion:** Smooth, physics-based animations
- **Glass Effects:** Frosted material backgrounds with depth
- **Dynamic Color:** Theme-aware gradients and accents
- **Adaptive Layout:** Responsive to screen size and orientation
- **Accessible First:** WCAG AA contrast, Dynamic Type, VoiceOver

## Color System

### Primary Colors (Theme-Aware)

```swift
// Liquid Blue Theme (Default)
Primary:   #007AFF (0, 122, 255)
Secondary: #4DA6FF (77, 166, 255)
Gradient:  Linear from Primary → Secondary

// Progress Indicators
Success:   #34C759 (52, 199, 89)
Warning:   #FF9500 (255, 149, 0)
Error:     #FF3B30 (255, 59, 48)
```

### Semantic Colors (System)

```swift
// ALWAYS use system semantic colors for text!
.primary        → Automatic contrast on any background
.secondary      → 75% opacity, WCAG AA compliant
.tertiary       → 50% opacity, decorative only

// Material Backgrounds
.ultraThinMaterial   → Glass effect
.thinMaterial        → Subtle glass
.regularMaterial     → Standard glass
.thickMaterial       → Heavy glass
```

### Accessibility Contrast Ratios

| Element Type | Foreground | Background | Ratio | WCAG |
|-------------|------------|------------|-------|------|
| Headline    | .primary   | Glass      | 7:1   | AAA  |
| Body Text   | .primary   | Glass      | 4.5:1 | AA   |
| Secondary   | .secondary | Glass      | 4.5:1 | AA   |
| Icons       | Primary    | Glass      | 3:1   | AA   |
| Decorative  | .tertiary  | Glass      | 2.5:1 | -    |

## Typography

### Font Hierarchy

```swift
// San Francisco (System Font)

Title:          .largeTitle.bold()     → 34pt, Bold
Headline:       .title.bold()          → 28pt, Bold
Subheadline:    .headline              → 17pt, Semibold
Body:           .body                  → 17pt, Regular
Caption:        .caption               → 12pt, Regular
Caption2:       .caption2              → 11pt, Regular

// Dynamic Type Scaling
Supports all accessibility sizes:
- XS (75%)
- S (88%)
- M (100% - default)
- L (112%)
- XL (124%)
- XXL (142%)
- XXXL (160%+)
```

### Text Styles

```swift
// Progress Title
Font: .headline
Color: .primary
Weight: .bold
Line Height: 1.2

// Current Book Title
Font: .caption
Color: .secondary
Weight: .regular
Line Height: 1.3
Max Lines: 1
Truncation: .tail

// Statistics Labels
Font: .caption2
Color: .secondary
Weight: .regular
Letter Spacing: 0.5pt (slightly looser)
```

## Layout Specifications

### Lock Screen Live Activity

```
┌─────────────────────────────────────────────────────┐
│  Padding: 16pt all sides                            │
│  ┌─────────────────────────────────────────────┐   │
│  │  [Icon 40x40]  [Content]    [Badge]         │   │
│  │                                              │   │
│  │  📚 Importing Books                 20/min   │   │
│  │  my_books.csv                               │   │
│  │                                              │   │
│  │  ▓▓▓▓▓▓▓▓▓░░░░░░░░░░  (Progress Bar)      │   │
│  │  750 of 1500                        5 min   │   │
│  │                                              │   │
│  │  📖 The Way of Kings by Brandon...          │   │
│  │                                              │   │
│  │  ✓ 725    📋 20    ✗ 5                     │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘

Dimensions:
- Height: ~140pt (variable based on content)
- Corner Radius: 16pt
- Icon Size: 40x40pt
- Progress Bar: 12pt height, 6pt corner radius
- Spacing: 12pt between sections
- Badge: 8pt padding, 8pt corner radius
```

### Dynamic Island - Compact

```
┌───────────────────────────────────────┐
│  Leading: 44pt width                  │
│  ┌────────┐                           │
│  │   📚   │  •••  65%  ⭕            │
│  └────────┘                           │
│           Trailing: 60pt width        │
└───────────────────────────────────────┘

Leading:
- Icon: 24pt SF Symbol
- Pulse animation: 1s duration, infinite

Trailing:
- Text: 14pt, .bold
- Progress Ring: 20pt diameter, 3pt stroke
```

### Dynamic Island - Expanded

```
┌─────────────────────────────────────────────────┐
│  Leading Region: 80pt x 80pt                    │
│  ┌──────────┐                                   │
│  │    📚    │     Center Content                │
│  │   975    │   Importing books...              │
│  │ imported │     1500 books                    │
│  └──────────┘                                   │
│                                      Trailing:  │
│                                      ┌────────┐ │
│                                      │   ⭕   │ │
│                                      │  65%   │ │
│                                      │ 5 min  │ │
│                                      └────────┘ │
│                                                 │
│  Bottom Region (Full Width)                    │
│  ┌─────────────────────────────────────────┐   │
│  │  📖 The Way of Kings                    │   │
│  │  ▓▓▓▓▓▓▓▓▓░░░░░░░░░                   │   │
│  │  ✓ 950  📋 20  ✗ 5                     │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘

Dimensions:
- Leading: 80x80pt
- Trailing: 60x80pt
- Center: Variable width
- Bottom: Full width, 80pt height
- Padding: 16pt all regions
- Inter-element spacing: 8pt
```

### Background Import Banner

```
┌───────────────────────────────────────────────────┐
│  Padding: 16pt horizontal, 12pt vertical          │
│  ┌───────────────────────────────────────────┐   │
│  │  [Icon]  [Content]              [Chevron]  │   │
│  │                                            │   │
│  │   ⚡     Importing Books            65%    │   │
│  │   40pt   ▓▓▓▓▓▓▓░░░░░░  (4pt height)  ˅   │   │
│  │          750 of 1500 books                │   │
│  └───────────────────────────────────────────┘   │
│                                                   │
│  Expanded Details (Optional)                      │
│  ┌───────────────────────────────────────────┐   │
│  │  Divider (1pt, .quaternary)               │   │
│  │                                            │   │
│  │  📖 Current Book Title                    │   │
│  │                                            │   │
│  │  [View Import Progress] Button             │   │
│  └───────────────────────────────────────────┘   │
└───────────────────────────────────────────────────┘

Dimensions:
- Min Height: 68pt (collapsed)
- Max Height: 140pt (expanded)
- Corner Radius: 12pt
- Icon Circle: 40pt diameter
- Progress Bar: 4pt height, 2pt corner radius
- Button: 40pt height, 8pt corner radius
- Shadow: 8pt blur, 4pt offset, 10% opacity
```

### Floating Action Button

```
┌─────────────────────────────────────┐
│  Capsule Shape                      │
│  ┌───────────────────────────────┐  │
│  │  📥  Import in Progress       │  │
│  └───────────────────────────────┘  │
│                                     │
│  Dimensions:                        │
│  - Height: 44pt (touch target)      │
│  - Padding: 20pt horizontal         │
│  - Corner Radius: 22pt (full pill)  │
│  - Icon: 16pt SF Symbol             │
│  - Text: 14pt, .bold                │
│  - Shadow: 12pt blur, 6pt offset    │
│  - Glow: Primary color, 40% opacity │
└─────────────────────────────────────┘
```

## Animation Specifications

### Progress Bar Fill

```swift
Animation: .smooth(duration: 0.5)
Easing: ease-in-out
Interpolation: Linear for width change
```

### Pulse Icon

```swift
.symbolEffect(.pulse)
Duration: 1.0s
Repeat: infinite
Scale: 1.0 → 1.15 → 1.0
Opacity: 1.0 → 0.8 → 1.0
```

### Banner Slide In

```swift
Animation: .smooth(duration: 0.4)
Transform: translateY(-120 → 0)
Easing: ease-out with slight bounce
```

### Notification Spring

```swift
Animation: .spring(duration: 0.5, bounce: 0.3)
Transform: translateY(-200 → 0)
Damping: 0.7
Response: 0.5
```

### Expansion/Collapse

```swift
Animation: .smooth(duration: 0.3)
Height: 68pt ↔ 140pt
Chevron Rotation: 0° ↔ 180°
Opacity fade: 0.0 ↔ 1.0 (content)
```

## Component States

### Progress Bar States

```swift
// Loading (0-5%)
Fill: Minimal
Color: Primary gradient
Animation: None

// Active (5-95%)
Fill: Progressive
Color: Primary → Secondary gradient
Animation: Smooth width transition

// Nearly Complete (95-99%)
Fill: Almost full
Color: Primary → Success gradient
Animation: Slight pulse

// Complete (100%)
Fill: Full width
Color: Success solid
Animation: Scale pulse once
```

### Icon States

```swift
// Importing
Icon: books.vertical.fill
Color: Primary gradient
Effect: .pulse (continuous)

// Success
Icon: checkmark.circle.fill
Color: Success gradient
Effect: .bounce (once)

// Error
Icon: exclamationmark.triangle.fill
Color: Error gradient
Effect: .shake (once)
```

## Spacing System

### Padding Scale

```swift
// iOS 26 Standard Spacing
XXS: 2pt  → Fine details
XS:  4pt  → Tight spacing
S:   8pt  → Default inner padding
M:   12pt → Component spacing
L:   16pt → Section padding
XL:  24pt → Major sections
XXL: 32pt → Screen margins
```

### Component Spacing

```swift
// Lock Screen Activity
Outer Padding: 16pt (L)
Inner Spacing: 12pt (M)
Icon Padding: 8pt (S)

// Background Banner
Horizontal Padding: 16pt (L)
Vertical Padding: 12pt (M)
Element Spacing: 12pt (M)

// Floating Button
Horizontal Padding: 20pt
Vertical Padding: 12pt (M)
Icon-Text Gap: 8pt (S)
```

## Icon Usage

### System SF Symbols

```swift
// Primary Icons (24-48pt)
books.vertical.fill      → Import activity
arrow.down.doc.fill      → Download/Import
checkmark.circle.fill    → Success
xmark.circle.fill        → Error
exclamationmark.triangle → Warning

// Secondary Icons (16-20pt)
book.closed              → Current book
clock                    → Time remaining
speedometer              → Processing rate
doc.on.doc.fill          → Duplicates

// Tertiary Icons (12-16pt)
chevron.down             → Expand/collapse
chevron.right            → Navigation
info.circle              → Information
```

### Icon Weights

```swift
// Match text weight for visual consistency
Light Text   → Light Icons
Regular Text → Regular Icons
Semibold Text → Semibold Icons
Bold Text    → Bold Icons
```

## Accessibility Features

### VoiceOver Focus Order

```
1. Activity Title ("Importing Books")
2. Progress Percentage ("65 percent complete")
3. Current Book Title
4. Statistics (Success, Duplicates, Errors)
5. Time Remaining
6. Custom Actions (if available)
```

### High Contrast Mode

```swift
// Automatic adjustments when enabled
Border Width: 1pt → 2pt
Text Weight: Regular → Semibold
Icon Weight: Regular → Bold
Background Opacity: 0.3 → 0.5
```

### Reduce Motion

```swift
// When Reduce Motion is enabled
Disable: .pulse animations
Disable: Spring animations
Replace: Crossfade instead of slide
Replace: Opacity instead of scale
Keep: Progress bar fill (critical feedback)
```

### Dynamic Type

```swift
// Layout adaptations for large text sizes

XL and above:
- Stack statistics vertically
- Increase line spacing to 1.5
- Minimum touch targets: 44pt

XXXL (Accessibility sizes):
- Single column layout
- Increase all padding by 25%
- Maximum 2 elements per row
- Icon size scales proportionally
```

## Glass Effect Materials

### Material Hierarchy

```swift
// Background layers (back to front)
Level 1: .ultraThinMaterial     → Main background
Level 2: .thinMaterial          → Elevated cards
Level 3: .regularMaterial       → Floating elements
Level 4: .thickMaterial         → Overlays

// Blur Radius
UltraThin: 20pt
Thin:      30pt
Regular:   40pt
Thick:     60pt

// Opacity
UltraThin: 0.3
Thin:      0.4
Regular:   0.5
Thick:     0.7
```

### Vibrancy

```swift
// iOS 26 Liquid Glass vibrancy
Primary Vibrancy:   1.0 → Full color through glass
Secondary Vibrancy: 0.75 → Subtle color through glass
Tertiary Vibrancy:  0.5 → Minimal color through glass

// Apply to text on glass backgrounds
.foregroundStyle(.primary, .secondary)
```

## Dark Mode Support

### Automatic Adaptation

```swift
// All colors automatically adapt!
System colors:     Light → Dark inverse
Glass materials:   Lighter → Darker blur
Shadows:          Black → Enhanced black
Glows:            Reduced → Enhanced

// Manual overrides (avoid if possible)
@Environment(\.colorScheme) var colorScheme

if colorScheme == .dark {
    // Only for custom non-system colors
}
```

## Performance Guidelines

### Render Optimization

```swift
// Efficient rendering
✅ Use .drawingGroup() for complex composites
✅ Limit simultaneous animations to 3
✅ Cache expensive calculations
✅ Use .onAppear for setup only

// Avoid
❌ Per-frame updates
❌ Nested .background() calls
❌ Large image assets in widgets
❌ Complex gradients with 5+ stops
```

### Battery Impact

```swift
// Target metrics
Live Activity Updates: Max 1/second
Animation FPS:        60fps (or 120fps ProMotion)
Battery Drain:        < 5% per hour
Memory Usage:         < 20MB

// Optimization strategies
- Throttle updates
- Use .task for async work
- Avoid Timer-based animations
- Prefer .onChange over .onReceive
```

## Testing Checklist

### Visual Testing

- [ ] All text readable at 20ft distance (driving test)
- [ ] Colors distinguishable with protanopia/deuteranopia filters
- [ ] Layout works on iPhone SE (smallest screen)
- [ ] Layout works on iPhone 15 Pro Max (largest screen)
- [ ] Dynamic Island works on iPhone 14 Pro+
- [ ] Dark mode looks polished
- [ ] Animations feel smooth (no jank)
- [ ] Glass effects visible but subtle

### Accessibility Testing

- [ ] VoiceOver navigation is logical
- [ ] All elements have labels
- [ ] Touch targets minimum 44pt
- [ ] Text contrast verified with Accessibility Inspector
- [ ] Dynamic Type tested at all sizes
- [ ] Reduce Motion respected
- [ ] High Contrast mode tested
- [ ] Color Filters tested (protanopia, deuteranopia, tritanopia)

## Design Resources

### Figma Template
*[Would include actual Figma file link]*

### SF Symbols App
Download from Apple Developer website for icon exploration

### Color Contrast Checker
- [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/)
- [Stark Plugin for Figma](https://www.getstark.co/)

### References
- [Apple HIG - Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- [Apple HIG - Dynamic Island](https://developer.apple.com/design/human-interface-guidelines/dynamic-island)
- [SF Symbols Documentation](https://developer.apple.com/sf-symbols/)
- [iOS 26 Liquid Glass Design](https://developer.apple.com/design/)

---

**Design Review:** October 2025
**Next Review:** With iOS 27 Beta (June 2026)
