# Unified White Surfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make FlashNote’s macOS and iOS page canvas, sidebar, cards and compact surfaces use one white visual foundation, with hierarchy expressed by subtle borders instead of contrasting background blocks.

**Architecture:** Keep all surface decisions in `AppTheme`, so existing feature views inherit the new visual system through semantic tokens. Update the macOS navigation list and the one direct system-background usage in the workbench to consume those tokens, preserving blue for primary actions and green only for status.

**Tech Stack:** Swift 5.10, SwiftUI, Swift Testing, XcodeGen, Xcode build tools.

---

### Task 1: Lock the white-surface contract with tests

**Files:**
- Modify: `Tests/DesignSystemTests.swift`

- [ ] **Step 1: Add a failing test for the three shared surfaces**

```swift
@Test func sharedSurfacesResolveToWhite() {
    for color in [AppTheme.pageBackground, AppTheme.cardBackground, AppTheme.elevatedSurface] {
        let components = resolvedComponents(for: color)
        #expect(abs(components.red - 1) < 0.001)
        #expect(abs(components.green - 1) < 0.001)
        #expect(abs(components.blue - 1) < 0.001)
        #expect(abs(components.alpha - 1) < 0.001)
    }
}

private func resolvedComponents(for color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
#if os(macOS)
    NSColor(color).usingColorSpace(.sRGB)!.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
#else
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
#endif
    return (red, green, blue, alpha)
}
```

- [ ] **Step 2: Run the test to verify it fails against the existing system-colour implementation**

Run:

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 test -only-testing:FlashNoteMacTests/DesignSystemTests/sharedSurfacesResolveToWhite
```

Expected: FAIL because the current page, card and elevated surfaces resolve from macOS system backgrounds rather than all-white values.

- [ ] **Step 3: Commit the test-only change**

```bash
git add Tests/DesignSystemTests.swift
git commit -m "test: define white surface palette"
```

### Task 2: Implement the unified white surface palette

**Files:**
- Modify: `DesignSystem/AppTheme.swift`

- [ ] **Step 1: Replace platform-specific surface colors with shared white tokens**

```swift
static let pageBackground = Color.white
static let cardBackground = Color.white
static let elevatedSurface = Color.white
static let background = Color.black.opacity(0.045)
static let border = Color.black.opacity(0.075)
static let cardShadow = Color.black.opacity(0.022)
```

Remove the `#if os(macOS)` branches for `pageBackground`, `cardBackground` and `elevatedSurface`. Keep `accent`, `accentMuted`, text colors, and status colors unchanged.

- [ ] **Step 2: Reduce the shared card shadow to preserve border-led hierarchy**

```swift
.shadow(color: AppTheme.cardShadow, radius: 8, y: 2)
```

Apply this in `Card` in `DesignSystem/Components.swift`; retain its one-point `AppTheme.border` overlay.

- [ ] **Step 3: Run the new surface test to verify it passes**

Run:

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 test -only-testing:FlashNoteMacTests/DesignSystemTests/sharedSurfacesResolveToWhite
```

Expected: PASS.

- [ ] **Step 4: Commit the palette implementation**

```bash
git add DesignSystem/AppTheme.swift DesignSystem/Components.swift
git commit -m "fix: unify white application surfaces"
```

### Task 3: Remove direct system-surface usage from navigation and workbench

**Files:**
- Modify: `App/RootView.swift`
- Modify: `Features/Workbench/WorkbenchView.swift`

- [ ] **Step 1: Make the macOS sidebar use the same page surface**

```swift
.listStyle(.sidebar)
.scrollContentBackground(.hidden)
.background(AppTheme.pageBackground)
```

Apply these modifiers to the `List` in the macOS branch of `RootView` after `.listStyle(.sidebar)`.

- [ ] **Step 2: Replace the workbench empty-state system background with the semantic card surface**

```swift
.background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
.overlay {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(AppTheme.border, lineWidth: 1)
}
```

Replace the direct `.background(.background, ...)` modifier in `recentSection` of `Features/Workbench/WorkbenchView.swift` with the code above.

- [ ] **Step 3: Verify no direct system surface references remain in UI source**

Run:

```bash
rg -n "underPageBackgroundColor|windowBackgroundColor|controlBackgroundColor|systemGroupedBackground|systemBackground|secondarySystemBackground|\\.background\\(\\.background" App Features DesignSystem --glob '*.swift'
```

Expected: no matches.

- [ ] **Step 4: Commit the token adoption**

```bash
git add App/RootView.swift Features/Workbench/WorkbenchView.swift
git commit -m "fix: apply unified white surfaces to navigation"
```

### Task 4: Validate and distribute the corrected app

**Files:**
- Create: `Release/FlashNoteMac-2026-08-23-white-surfaces.app` (untracked distribution artefact)
- Create: `Release/FlashNoteMac-2026-08-23-white-surfaces.zip` (untracked distribution artefact)

- [ ] **Step 1: Run the complete macOS test suite**

Run:

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 test
```

Expected: all tests pass.

- [ ] **Step 2: Verify the iOS target builds without signing**

Run:

```bash
xcodebuild -project FlashNote.xcodeproj -scheme FlashNote -sdk iphoneos CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Build a fresh signed-local macOS release and archive it**

Run:

```bash
xcodegen generate
package_build_dir=$(mktemp -d /tmp/flashnote-white-surfaces-XXXXXX)
xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -configuration Release -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 -derivedDataPath "$package_build_dir" build
cp -R "$package_build_dir/Build/Products/Release/FlashNoteMac.app" Release/FlashNoteMac-2026-08-23-white-surfaces.app
ditto -c -k --sequesterRsrc --keepParent Release/FlashNoteMac-2026-08-23-white-surfaces.app Release/FlashNoteMac-2026-08-23-white-surfaces.zip
codesign --verify --deep --strict --verbose=2 Release/FlashNoteMac-2026-08-23-white-surfaces.app
unzip -t Release/FlashNoteMac-2026-08-23-white-surfaces.zip
```

Expected: build succeeds, code-sign verification reports a valid app, and zip integrity validation completes without errors.

- [ ] **Step 4: Commit source changes only**

```bash
git status --short
```

Expected: the release artefacts remain untracked and are not added; only commits from Tasks 1–3 contain source changes.
