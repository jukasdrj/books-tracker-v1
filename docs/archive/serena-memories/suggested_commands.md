# BooksTracker Development Commands

## XcodeBuildMCP Commands (Primary Development)

### Build & Run
```javascript
// List available simulators
list_sims({})

// Build for simulator
build_sim({
    workspacePath: "/path/to/BooksTracker.xcworkspace",
    scheme: "BooksTracker", 
    simulatorName: "iPhone 16"
})

// Build and run in one step
build_run_sim({
    workspacePath: "/path/to/BooksTracker.xcworkspace",
    scheme: "BooksTracker",
    simulatorName: "iPhone 16"
})

// Clean build
clean({
    workspacePath: "/path/to/BooksTracker.xcworkspace"
})
```

### Testing
```javascript
// Run Swift Package tests
swift_package_test({
    packagePath: "/path/to/BooksTrackerPackage"
})

// Run full test suite on simulator
test_sim({
    workspacePath: "/path/to/BooksTracker.xcworkspace", 
    scheme: "BooksTracker",
    simulatorName: "iPhone 16"
})
```

### Device Testing
```javascript
// List connected devices
list_devices()

// Build for device
build_device({
    workspacePath: "/path/to/BooksTracker.xcworkspace",
    scheme: "BooksTracker"
})
```

## Automation Scripts

### Version Management
```bash
# One-time setup (install git hooks)
./Scripts/setup_hooks.sh

# Version bumping
./Scripts/update_version.sh patch    # Bug fixes
./Scripts/update_version.sh minor    # New features  
./Scripts/update_version.sh major    # Breaking changes

# Complete release workflow
./Scripts/release.sh minor "Added awesome features!"
```

### Cloudflare Workers (Backend)
```bash
# Development
npm run dev

# Deploy workers
npm run deploy

# Test workers
npm run test
```

## macOS System Commands
- **ls**: List directory contents
- **cd**: Change directory
- **grep**: Search text (use ripgrep/rg when available)
- **find**: Find files
- **git**: Version control operations