# 📚 BooksTracker - Your Library, Supercharged! ⚡

```
╔══════════════════════════════════════════════════════════╗
║  🎉 CSV IMPORT REVOLUTION! v1.10 IS HERE! 🚀           ║
║                                                          ║
║  ✅ Import 1500+ Books    ✅ iOS 26 Liquid Glass       ║
║  ✅ 100 books/minute!     ✅ Auto-Enrichment Magic     ║
║  ✅ Smart Duplicates      ✅ Zero Memory Issues        ║
║  ✅ Swift 6 Concurrency   ✅ Cloudflare Backend        ║
╚══════════════════════════════════════════════════════════╝
```

A **stunning iOS application** for tracking your personal book library with cultural diversity insights! Built with **Swift 6.1+**, **SwiftUI**, and **iOS 26 Liquid Glass** design system.

**Current Status**: 🟢 **PRODUCTION READY** - Import your entire Goodreads library in minutes!

Features a modern **workspace + SPM package** architecture with **CSV import wizardry** and **showcase-quality code**! 🚀✨

## 🎉 Latest & Greatest (October 2025)

### 📚 CSV Import Revolution - v1.10.0

**The Game Changer**: Remember manually adding 1,500 books one by one? Yeah, **we don't do that anymore**! 🚀

```
   Before: 25-50 hours of manual entry 😴
    After: 15 minutes bulk import! ⚡
```

**What's New:**
- **🔥 Stream-Based Import**: Handles 1500+ books without breaking a sweat (<200MB memory!)
- **🧠 Smart Column Detection**: Auto-detects Goodreads, LibraryThing, StoryGraph formats
- **🎯 95%+ Duplicate Detection**: ISBN-first strategy with Title+Author fallback
- **✨ Auto-Enrichment**: Priority queue fetches covers, ISBNs, metadata from Cloudflare Worker
- **📊 20+ Test Cases**: 90%+ coverage, all performance targets crushed!

**Import Speed**: ~100 books/minute 🏃💨
**Formats Supported**: Goodreads, LibraryThing, StoryGraph
**Architecture**: Pure Swift 6 concurrency magic with @globalActor parsing!

### 🔧 Recent Wins

- **✅ Swift 6 Concurrency**: Full compliance with MainActor/actors/AsyncStream
- **✅ iOS 26 Liquid Glass**: WCAG AA accessible contrast (4.5:1+)
- **✅ Widget Extension**: Fixed version mismatch (now 41 across the board!)
- **✅ Advanced Search**: Backend-driven filtering (no more client-side hacks!)
- **✅ Accessibility**: 74 contrast fixes across 11 files

### 📱 What's Working Right Now

- **📚 Bulk Import**: CSV wizard with duplicate resolution UI
- **🎨 Gorgeous UI**: iOS 26 Liquid Glass with 5 built-in themes
- **📊 Cultural Analytics**: Diversity tracking with regional insights
- **🔍 Advanced Search**: Multi-field backend filtering
- **📷 Barcode Scanning**: Complete ISBN detection system
- **☁️ Data Sync**: SwiftData + CloudKit (with simulator fallback!)
- **🚀 Priority Queue**: User scrolls → book enriches instantly!

### 🏆 Performance Stats

| Metric | Achievement |
|--------|------------|
| Import Speed | ~100 books/minute ⚡ |
| Memory Usage | <200MB (1500+ books) 💾 |
| Duplicate Detection | >95% accuracy 🎯 |
| Enrichment Success | 90%+ multi-provider 🌟 |
| Contrast Ratio | 4.5:1+ WCAG AA ♿ |
| Test Coverage | 90%+ ✅ |

**Bottom line**: From manual entry hell to bulk import heaven in one release! 🚀

## AI Assistant Rules Files

This template includes **opinionated rules files** for popular AI coding assistants. These files establish coding standards, architectural patterns, and best practices for modern iOS development using the latest APIs and Swift features.

### Included Rules Files
- **Claude Code**: `CLAUDE.md` - Claude Code rules (recently condensed by 76%! 🎯)
- **Cursor**: `.cursor/*.mdc` - Cursor-specific rules
- **GitHub Copilot**: `.github/copilot-instructions.md` - GitHub Copilot rules

### Customization Options
These rules files are **starting points** - feel free to:
- ✅ **Edit them** to match your team's coding standards
- ✅ **Delete them** if you prefer different approaches
- ✅ **Add your own** rules for other AI tools
- ✅ **Update them** as new iOS APIs become available

### What Makes These Rules Opinionated
- **No ViewModels**: Embraces pure SwiftUI state management patterns
- **Swift 6+ Concurrency**: Enforces modern async/await over legacy patterns
- **Latest APIs**: Recommends iOS 18+ features with optional iOS 26 guidelines
- **Testing First**: Promotes Swift Testing framework over XCTest
- **Performance Focus**: Emphasizes @Observable over @Published for better performance

**Note for AI assistants**: You MUST read the relevant rules files before making changes to ensure consistency with project standards.

## Project Architecture

```
BooksTracker/
├── BooksTracker.xcworkspace/              # Open this file in Xcode
├── BooksTracker.xcodeproj/                # App shell project
├── BooksTracker/                          # App target (minimal)
│   ├── Assets.xcassets/                # App-level assets (icons, colors)
│   ├── BooksTrackerApp.swift              # App entry point
│   └── BooksTracker.xctestplan            # Test configuration
├── BooksTrackerPackage/                   # 🚀 Primary development area
│   ├── Package.swift                   # Package configuration
│   ├── Sources/BooksTrackerFeature/       # Your feature code
│   └── Tests/BooksTrackerFeatureTests/    # Unit tests
├── Scripts/                               # 🛠️ Build automation magic
│   ├── update_version.sh                  # Smart version management
│   ├── release.sh                         # One-command releases
│   └── setup_hooks.sh                     # Git hook installer
├── .githooks/                             # 🪝 Git automation
└── BooksTrackerUITests/                   # UI automation tests
```

## Key Architecture Points

### Workspace + SPM Structure
- **App Shell**: `BooksTracker/` contains minimal app lifecycle code
- **Feature Code**: `BooksTrackerPackage/Sources/BooksTrackerFeature/` is where most development happens
- **Separation**: Business logic lives in the SPM package, app target just imports and displays it

### Buildable Folders (Xcode 16)
- Files added to the filesystem automatically appear in Xcode
- No need to manually add files to project targets
- Reduces project file conflicts in teams

## 🚀 Quick Start & Automation

### Automated Version Management
Get started with zero-hassle version and release management:

```bash
# One-time setup (install git hooks for auto-versioning)
./Scripts/setup_hooks.sh

# Version bumping made easy
./Scripts/update_version.sh patch    # Bug fixes
./Scripts/update_version.sh minor    # New features
./Scripts/update_version.sh major    # Breaking changes

# Complete release workflow
./Scripts/release.sh minor "Added awesome new features! 🎉"
```

**Pro tip**: After running `setup_hooks.sh`, your build numbers automatically update on every commit - no more manual version management! 🧠

### 📚 Recent Project Updates (October 2025)

```
   ╔════════════════════════════════════════════════╗
   ║  📚 THE CSV IMPORT BREAKTHROUGH! 🚀           ║
   ║                                                ║
   ║  ✅ CSV Import: 100 books/min                 ║
   ║  ✅ Auto-Enrichment: Priority Queue Magic     ║
   ║  ✅ Smart Duplicates: 95%+ Detection          ║
   ║  ✅ Widget Extension: Version Sync Fixed      ║
   ║  ✅ WCAG AA: 4.5:1+ Contrast Everywhere       ║
   ╚════════════════════════════════════════════════╝
```

**What's working**: CSV import, enrichment, widgets, accessibility - everything! 🎉
**What's next**: Phase 2 background tasks, Phase 3 Live Activities 🎯
**See**: `docs/archive/csvMoon-implementation-notes.md` for the complete roadmap!

## Development Notes

### Code Organization
Most development happens in `BooksTrackerPackage/Sources/BooksTrackerFeature/` - organize your code as you prefer.

### Public API Requirements
Types exposed to the app target need `public` access:
```swift
public struct NewView: View {
    public init() {}
    
    public var body: some View {
        // Your view code
    }
}
```

### Adding Dependencies
Edit `BooksTrackerPackage/Package.swift` to add SPM dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/example/SomePackage", from: "1.0.0")
],
targets: [
    .target(
        name: "BooksTrackerFeature",
        dependencies: ["SomePackage"]
    ),
]
```

### Test Structure
- **Unit Tests**: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/` (Swift Testing framework)
- **UI Tests**: `BooksTrackerUITests/` (XCUITest framework)
- **Test Plan**: `BooksTracker.xctestplan` coordinates all tests

## Configuration

### XCConfig Build Settings
Build settings are managed through **XCConfig files** in `Config/`:
- `Config/Shared.xcconfig` - Common settings (bundle ID, versions, deployment target)
- `Config/Debug.xcconfig` - Debug-specific settings  
- `Config/Release.xcconfig` - Release-specific settings
- `Config/Tests.xcconfig` - Test-specific settings

### Entitlements Management
App capabilities are managed through a **declarative entitlements file**:
- `Config/BooksTracker.entitlements` - All app entitlements and capabilities
- AI agents can safely edit this XML file to add HealthKit, CloudKit, Push Notifications, etc.
- No need to modify complex Xcode project files

### Asset Management
- **App-Level Assets**: `BooksTracker/Assets.xcassets/` (app icon, accent color)
- **Feature Assets**: Add `Resources/` folder to SPM package if needed

### SPM Package Resources
To include assets in your feature package:
```swift
.target(
    name: "BooksTrackerFeature",
    dependencies: [],
    resources: [.process("Resources")]
)
```

### Generated with XcodeBuildMCP
This project was scaffolded using [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP), which provides tools for AI-assisted iOS development workflows.