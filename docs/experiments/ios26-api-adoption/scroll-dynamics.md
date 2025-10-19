# Scroll Dynamics - iOS 26 API Discoveries

**Category:** Scroll Dynamics
**Last Updated:** October 18, 2025
**APIs Discovered:** 2
**APIs Implemented:** 0

---

## Overview

This document tracks all iOS 26 ScrollView and scroll-related API discoveries, implementation observations, and behavioral learnings for the BooksTrack app.

**Key Focus Areas:**
- Edge effects and blending
- Scroll behavior and bounce control
- Performance optimizations
- Visual polish enhancements

---

## Discovered APIs

### 1. `.scrollEdgeEffectStyle(.soft, for: .top)`

**Status:** 📋 Backlog - [Issue #110](https://github.com/jukasdrj/books-tracker-v1/issues/110)

**Description:**
Creates softer visual transition as content scrolls under navigation bar, enhancing Liquid Glass depth perception.

**Expected Implementation:**
```swift
// In iOS26LiquidLibraryView.swift
ScrollView {
    LazyVStack(spacing: 16) {
        // Book cards...
    }
}
.scrollEdgeEffectStyle(.soft, for: .top)
// iOS 26 API: Softer fade transition as content slides under nav bar
// Expected: Enhanced Liquid Glass depth perception
.scrollPosition($scrollPosition)
```

**Testing Plan:**
- [ ] Simulator: iPhone 17 Pro
- [ ] Physical Device: (TBD - note model)
- [ ] Dark mode validation
- [ ] All 5 themes (liquidBlue, cosmicPurple, forestGreen, sunsetOrange, moonlightSilver)
- [ ] Edge cases: Empty list, single item, rapid scrolling

**Implementation Date:** Not yet implemented

**Findings:** _Will be documented after implementation_

---

### 2. `.tabBarMinimizeBehavior(.onScrollDown)`

**Status:** 📋 Backlog - [Issue #111](https://github.com/jukasdrj/books-tracker-v1/issues/111)

**Description:**
Tab bar shrinks gracefully as user scrolls, creating more immersive content-focused experience.

**Expected Implementation:**
```swift
// In ContentView.swift
TabView(selection: $selectedTab) {
    LibraryView()
        .tabItem {
            Label("Library", systemImage: "books.vertical")
        }
        .tag(Tab.library)

    // Other tabs...
}
.tabBarMinimizeBehavior(.onScrollDown)
// iOS 26 API: Dynamic tab hiding on scroll for immersive content viewing
```

**Testing Plan:**
- [ ] Simulator: iPhone 17 Pro
- [ ] Physical Device: (TBD - note model)
- [ ] Dark mode validation
- [ ] All 5 themes
- [ ] Edge cases: Rapid scroll direction changes, short content
- [ ] Multi-tab testing: Behavior consistency across all tabs

**Implementation Date:** Not yet implemented

**Findings:** _Will be documented after implementation_

**Notes:**
- Cross-category API (Scroll + Tab/Navigation)
- May batch with `.scrollEdgeEffectStyle` for efficient review

---

## Implementation Observations

_This section will be populated as APIs are implemented and tested._

### General Patterns

_To be discovered during implementation..._

### Performance Notes

_To be measured during testing..._

### Theme Compatibility

_To be validated across all 5 Liquid Glass themes..._

---

## Future Exploration Ideas

**Potential APIs to investigate:**
- `.scrollBounceBehavior` - Control bounce at scroll boundaries
- `.scrollTargetBehavior` - Snap-to-grid scrolling behavior
- `.scrollPosition` enhancements - Advanced position tracking
- `.scrollContentBackground` - Background styling options

**Discovery Sessions Planned:**
- Session 1 (30 min) - Explore `.scroll*` autocomplete in Xcode
- Session 2 (30 min) - Review iOS 26 release notes for ScrollView
- Session 3 (30 min) - Test undocumented behaviors on physical device

---

## Related Documentation

- **Master Tracker:** `audit-checklist.md`
- **Lessons Learned:** `lessons-learned.md`
- **Root Plan:** `/iOS26_API_AUDIT.md`
- **Related Category:** Tab & Navigation (see `.tabBarMinimizeBehavior`)

---

## Quick Reference

**Files Modified (or to be modified):**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Views/Library/iOS26LiquidLibraryView.swift`
- `BooksTracker/ContentView.swift`

**Testing Devices:**
- TBD (will note specific iPhone/iPad models during implementation)

**Implementation Target:**
- Build 52 (Batch 1: Scroll Dynamics)
