# 📚 BooksTracker - iOS App

A beautiful iOS application for tracking your personal book library with cultural diversity insights! Built with **Swift 6.1+**, **SwiftUI**, and forward-compatible **iOS 26 Liquid Glass** design system.

Uses a modern **workspace + SPM package** architecture for clean separation between app shell and feature code, plus some seriously slick automation! 🤖✨

## AI Assistant Rules Files

This template includes **opinionated rules files** for popular AI coding assistants. These files establish coding standards, architectural patterns, and best practices for modern iOS development using the latest APIs and Swift features.

### Included Rules Files
- **Claude Code**: `CLAUDE.md` - Claude Code rules
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