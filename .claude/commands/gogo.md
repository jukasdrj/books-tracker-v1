---
description: Build and validate BooksTrack for App Store submission (MCP-powered)
---

🚀 **BooksTrack App Store Validation Pipeline** 🚀

Execute comprehensive build validation using XcodeBuildMCP for autonomous quality checks:

## Phase 1: Clean Build & Validation

1. **Clean Build Environment**
   - Use MCP to clean derived data
   - Verify workspace integrity
   - Clear any stale build artifacts

2. **Release Build (MCP Autonomous)**
   - Build Release configuration for BooksTracker.xcworkspace
   - Target: Generic iOS Device (App Store)
   - Automatically parse and report build errors
   - Verify zero warnings/errors

3. **Bundle Identifier Verification**
   - Main app: `Z67H8Y8DW.com.oooefam.booksV3`
   - Widget: `Z67H8Y8DW.com.oooefam.booksV3.BooksTrackerWidgets`
   - Live Activity: `Z67H8Y8DW.com.oooefam.booksV3.CSVImportLiveActivity`

4. **Version Synchronization Check**
   - Marketing Version: `3.0.0` (all targets)
   - Build Number: `44` (all targets)
   - Source: `Config/Shared.xcconfig`

## Phase 2: Swift Package Testing (MCP)

5. **BooksTrackerPackage Tests**
   - Run Swift Testing suite via MCP
   - Test coverage: CSV import, enrichment, search, SwiftData models
   - Report any test failures with code context

## Phase 3: Physical Device Validation (MCP)

6. **Connected Device Discovery**
   - List all connected iOS devices via MCP
   - Verify device eligibility for testing
   - Select target device for installation

7. **Device Build & Install**
   - Build for physical device (if connected)
   - Install on device via MCP
   - Capture installation logs
   - Verify app launches successfully

8. **Runtime Log Analysis**
   - Stream device logs via MCP
   - Monitor for crashes, warnings, or errors
   - Check Live Activity functionality
   - Verify CSV import progress tracking

## Phase 4: Git Workflow

9. **Commit & Push**
   - Stage all changes (code + docs)
   - Create comprehensive commit message
   - Push to both `main` and `ship` branches
   - Tag release if build is App Store ready

**Note:** Manual steps (Xcode Archive, App Store submission) handled outside automation

## Configuration

**Workspace:** `/Users/justingardner/Downloads/xcode/books-tracker-v1/BooksTracker.xcworkspace`
**Scheme:** `BooksTracker`
**Configuration:** `Release`
**Device:** Generic iOS Device (App Store) or connected iPhone

## Success Criteria

✅ Zero build warnings
✅ Zero build errors
✅ All Swift tests pass
✅ Bundle IDs match
✅ Versions synchronized
✅ Device installation successful (if device connected)
✅ No runtime crashes in logs
✅ Changes committed to git
