# BooksTracker Project Structure

## Directory Layout
```
BooksTracker/
├── BooksTracker.xcworkspace/              # ✅ Open this in Xcode
├── BooksTracker.xcodeproj/                # App shell project
├── BooksTracker/                          # App target (minimal entry point)
│   ├── BooksTrackerApp.swift              # @main app entry, SwiftData setup
│   └── Assets.xcassets/                   # App-level assets
├── BooksTrackerPackage/                   # 🚀 PRIMARY DEVELOPMENT AREA
│   ├── Package.swift                      # SPM configuration
│   ├── Sources/BooksTrackerFeature/       # All feature code goes here
│   └── Tests/BooksTrackerFeatureTests/    # Swift Testing tests
├── Config/                                # Build configuration
│   ├── Shared.xcconfig                    # Bundle ID, versions, deployment target
│   └── BooksTracker.entitlements          # App capabilities (CloudKit enabled)
├── Scripts/                               # 🛠️ Build & release automation
├── .githooks/                             # 🪝 Git automation hooks
├── cloudflare-workers/                    # Backend worker code
└── BooksTrackerUITests/                   # UI automation tests
```

## Key Development Areas

### Primary Development: BooksTrackerPackage/Sources/BooksTrackerFeature/
- **ModelTypes.swift**: Enums and type definitions
- **Work.swift**: Main Work model with relationships
- **Author.swift**: Author model with cultural metadata  
- **Edition.swift**: Edition model for specific publications
- **UserLibraryEntry.swift**: User's library tracking
- **ContentView.swift**: Main app view with TabView
- **iOS26*.swift**: iOS 26 Liquid Glass UI components
- **WorkDetailView.swift**: Book detail screens
- **EditionMetadataView.swift**: Edition metadata displays

### Configuration Files
- **Config/Shared.xcconfig**: Build settings, bundle ID, versions
- **Config/BooksTracker.entitlements**: App capabilities and permissions
- **BooksTrackerPackage/Package.swift**: SPM dependencies

### Automation & Scripts
- **Scripts/update_version.sh**: Smart version management
- **Scripts/release.sh**: One-click releases
- **Scripts/setup_hooks.sh**: Git hook installer
- **.githooks/pre-commit**: Auto-updates build numbers

## File Organization Patterns
- **Public APIs**: Types exposed to app need `public` access
- **Buildable Folders**: Files auto-appear in Xcode (no manual adding)
- **Resource Management**: App-level assets in BooksTracker/Assets.xcassets/
- **Test Structure**: Swift Testing in Tests/ directory