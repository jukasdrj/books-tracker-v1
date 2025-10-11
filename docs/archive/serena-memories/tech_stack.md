# BooksTracker Tech Stack

## Core Technologies
- **Swift 6.1+** with strict concurrency mode
- **SwiftUI** for UI with native state management (@State, @Observable, @Environment)
- **SwiftData** for persistence with CloudKit sync enabled
- **Swift Concurrency** (async/await, @MainActor) - NO GCD usage
- **Swift Testing** framework (NOT XCTest) with @Test macros and #expect assertions
- **iOS 26 Liquid Glass** design system (forward-compatible with iOS 17+)

## Platform Support
- **Target**: iOS 26.0+ (deployment target in Config/Shared.xcconfig)
- **Compatibility**: Forward-compatible design gracefully degrades to iOS 17+
- **Devices**: iPhone and iPad (TARGETED_DEVICE_FAMILY = 1,2)

## Package Management
- **Swift Package Manager (SPM)** for dependencies
- **Package.swift** in BooksTrackerPackage/ for configuration
- **No external dependencies currently** - pure Swift/SwiftUI implementation

## Build System
- **Xcode 16+** with buildable folders
- **XCConfig files** for build settings management
- **Automated versioning** with git-based build numbers
- **Git hooks** for automatic version increments

## Additional Components
- **Cloudflare Workers** backend (in cloudflare-workers/ directory)
- **Node.js/npm** for worker deployment (package.json)
- **Wrangler** for Cloudflare deployments