# JamAI Setup Guide

This guide will walk you through setting up JamAI for development.

## Prerequisites

- **macOS 13.0+** (Ventura or later)
- **Xcode 15.0+**
- **Swift 5.9+**
- **Git**

## Step-by-Step Setup

### 1. Install Xcode

Download and install Xcode from the Mac App Store or Apple Developer website.

```bash
xcode-select --install
```

### 2. Clone the Repository

```bash
git clone https://github.com/yourusername/jamai.git
cd jamai
```

### 3. Open Project in Xcode

```bash
open JamAI.xcodeproj
```

### 4. Add GRDB Dependency

JamAI uses GRDB.swift for SQLite database management. Add it via Swift Package Manager:

1. In Xcode, go to **File → Add Package Dependencies**
2. Enter the URL: `https://github.com/groue/GRDB.swift`
3. Select version: **6.24.0** or later
4. Click **Add Package**
5. Select **GRDB** and add to **JamAI** target

### 5. Configure Project Settings

#### Update Bundle Identifier
1. Select **JamAI** project in navigator
2. Select **JamAI** target
3. Go to **Signing & Capabilities**
4. Update **Bundle Identifier** to your unique identifier (e.g., `com.yourname.jamai`)

#### Set Deployment Target
1. In **General** tab
2. Set **Minimum Deployments** to **macOS 13.0**

### 6. Build the Project

Press `Cmd+B` or select **Product → Build** from the menu.

### 7. Run the App

Press `Cmd+R` or select **Product → Run**.

## Configuration

### API Key Setup

1. Get a Gemini API key from: https://aistudio.google.com/app/apikey
2. Launch JamAI
3. Press `Cmd+,` to open Settings
4. Paste your API key
5. Click **Save API Key**

The key is stored securely in macOS Keychain.

## Project Structure

```
jamai/
├── JamAI/                      # Main app target
│   ├── Models/                 # Data models
│   ├── Services/               # Business logic
│   ├── Views/                  # SwiftUI views
│   ├── Storage/                # Database & persistence
│   ├── Utils/                  # Helpers & utilities
│   ├── Assets.xcassets/        # Images & colors
│   ├── Info.plist              # App configuration
│   └── JamAIApp.swift          # App entry point
├── JamAITests/                 # Unit tests
├── JamAIUITests/               # UI tests
├── JamAI.xcodeproj/            # Xcode project
├── README.md                   # Project documentation
├── SETUP.md                    # This file
└── .gitignore                  # Git ignore rules
```

## Development Workflow

### Building

```bash
# Debug build
xcodebuild -scheme JamAI -configuration Debug

# Release build
xcodebuild -scheme JamAI -configuration Release
```

### Testing

```bash
# Run all tests
xcodebuild test -scheme JamAI -destination 'platform=macOS'

# Run specific test
xcodebuild test -scheme JamAI -only-testing:JamAITests/TestClassName
```

### Debugging

1. Set breakpoints in Xcode
2. Press `Cmd+R` to run with debugger
3. Use `print()` or `debugPrint()` for console logging
4. Use **Debug View Hierarchy** to inspect UI

## Common Issues

### Issue: "No such module 'GRDB'"

**Solution:** Ensure GRDB package is added correctly:
1. Go to **File → Packages → Resolve Package Versions**
2. Clean build folder: `Cmd+Shift+K`
3. Rebuild: `Cmd+B`

### Issue: "Signing certificate not found"

**Solution:** 
1. Go to **Signing & Capabilities**
2. Select your development team
3. Or disable signing for local development

### Issue: API requests failing

**Solution:**
1. Check internet connection
2. Verify API key is correct
3. Check Gemini API quota: https://aistudio.google.com/

### Issue: Database errors

**Solution:**
1. Delete app data: `~/Library/Containers/com.jamai.JamAI`
2. Restart Xcode
3. Clean build: `Cmd+Shift+K`
4. Rebuild

## Performance Profiling

### Using Instruments

1. Select **Product → Profile** (`Cmd+I`)
2. Choose profiling template:
   - **Time Profiler** — CPU usage
   - **Allocations** — Memory usage
   - **Leaks** — Memory leaks
3. Record and analyze

### Canvas Performance

Monitor FPS in debug builds:
- Target: 60 FPS
- With 5,000 nodes: should maintain 60 FPS
- Enable Metal frame capture for GPU debugging

## File Locations

### Application Support
```
~/Library/Application Support/JamAI/
```

### User Projects
```
~/Documents/JamAI Projects/
```

### Logs
```
~/Library/Logs/JamAI/
```

### Preferences
```
~/Library/Preferences/com.jamai.JamAI.plist
```

## Environment Variables (Optional)

Create a `.env.local` file in project root:

```bash
# Development mode
DEBUG=true

# API endpoints (override defaults)
GEMINI_API_BASE_URL=https://generativelanguage.googleapis.com/v1beta

# Performance tuning
MAX_NODES=10000
TARGET_FPS=60
```

## Code Style

Follow Swift API Design Guidelines:
- Use camelCase for variables and functions
- Use PascalCase for types
- Add documentation comments for public APIs
- Keep functions under 50 lines
- Keep files under 400 lines

## Git Workflow

```bash
# Create feature branch
git checkout -b feature/my-feature

# Make changes and commit
git add .
git commit -m "Add: feature description"

# Push to remote
git push origin feature/my-feature

# Create pull request
```

## Release Process

### Creating a Release Build

1. Update version number in **JamAI** target settings
2. Update `CFBundleShortVersionString` in Info.plist
3. Archive: **Product → Archive**
4. Export for distribution
5. Notarize with Apple (required for distribution)

### Notarization

```bash
# Archive
xcodebuild archive -scheme JamAI -archivePath build/JamAI.xcarchive

# Export
xcodebuild -exportArchive -archivePath build/JamAI.xcarchive \
  -exportPath build -exportOptionsPlist ExportOptions.plist

# Notarize
xcrun notarytool submit build/JamAI.app \
  --apple-id "your@email.com" \
  --password "app-specific-password" \
  --team-id "TEAM_ID"
```

## Troubleshooting

### Reset Everything

```bash
# Delete derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/JamAI-*

# Delete app container
rm -rf ~/Library/Containers/com.jamai.JamAI

# Clean project
cd jamai
xcodebuild clean -scheme JamAI
```

### Enable Verbose Logging

Add to scheme environment variables:
- `OS_ACTIVITY_MODE` = `disable` (reduces noise)
- `JAMAI_DEBUG` = `1` (enable debug logs)

## Getting Help

- **Documentation:** See README.md
- **Issues:** GitHub Issues
- **Discord:** [Join our community]
- **Email:** support@jamai.dev

## Next Steps

Once setup is complete:
1. Read the [README.md](README.md) for usage guide
2. Explore the codebase
3. Run the example project
4. Start building!

---

**Happy coding! 🚀**
