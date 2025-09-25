# BooksTracker Task Completion Checklist

## What to do when a development task is completed

### 1. Code Quality Checks
- **Build Verification**: Run build commands to ensure code compiles
- **Test Execution**: Run Swift Testing tests with `swift_package_test`
- **UI Testing**: Run simulator tests if UI changes were made

### 2. XcodeBuildMCP Commands for Verification
```javascript
// Clean and build to verify everything compiles
clean({ workspacePath: "/path/to/BooksTracker.xcworkspace" })
build_sim({ 
    workspacePath: "/path/to/BooksTracker.xcworkspace",
    scheme: "BooksTracker",
    simulatorName: "iPhone 16" 
})

// Run unit tests
swift_package_test({ packagePath: "/path/to/BooksTrackerPackage" })

// Run full test suite if needed
test_sim({
    workspacePath: "/path/to/BooksTracker.xcworkspace",
    scheme: "BooksTracker", 
    simulatorName: "iPhone 16"
})
```

### 3. Version Management (if completing features)
```bash
# Update version for new features
./Scripts/update_version.sh minor "Description of changes"

# Or for bug fixes
./Scripts/update_version.sh patch "Bug fix description"
```

### 4. Code Review Checklist
- **SwiftUI Patterns**: Ensure no ViewModels were introduced
- **Concurrency**: Verify @MainActor usage for UI updates
- **Public APIs**: Ensure exposed types have `public` access
- **Swift Testing**: Use @Test macros and #expect assertions
- **Theme Consistency**: Apply iOS26ThemeStore theming

### 5. Documentation Updates
- Update CLAUDE.md if architectural changes were made
- Add comments for complex business logic
- Update README.md for user-facing changes

### 6. Git Operations (when requested)
```bash
# Only commit when user explicitly asks
git add .
git commit -m "Descriptive message

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>"
```

## Important Notes
- **NEVER commit** unless explicitly requested by user
- **Always test** before considering a task complete
- **Verify builds** work on both simulator and device when possible
- **Check CloudKit sync** if data model changes were made