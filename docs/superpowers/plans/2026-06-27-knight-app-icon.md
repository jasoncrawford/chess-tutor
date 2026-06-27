# Knight App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a polished knight-based iPad app icon to ChessTutor.

**Architecture:** Generate static PNG icon assets from one high-resolution source and store them in a standard Xcode asset catalog. Configure the app target through XcodeGen so generated projects use the new app icon set.

**Tech Stack:** SwiftUI iOS app, XcodeGen `project.yml`, Xcode asset catalogs, PNG app icon assets.

---

## File Structure

- Create: `ChessTutor/Resources/Assets.xcassets/Contents.json` for the asset catalog root.
- Create: `ChessTutor/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` for iPad app icon metadata.
- Create: `ChessTutor/Resources/Assets.xcassets/AppIcon.appiconset/*.png` for generated icon files.
- Modify: `project.yml` to set `ASSETCATALOG_COMPILER_APPICON_NAME` to `AppIcon`.

### Task 1: Add App Icon Assets

**Files:**
- Create: `ChessTutor/Resources/Assets.xcassets/Contents.json`
- Create: `ChessTutor/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `ChessTutor/Resources/Assets.xcassets/AppIcon.appiconset/icon-*.png`

- [ ] **Step 1: Create the asset catalog directories**

Run:

```bash
mkdir -p ChessTutor/Resources/Assets.xcassets/AppIcon.appiconset
```

Expected: directory exists at `ChessTutor/Resources/Assets.xcassets/AppIcon.appiconset`.

- [ ] **Step 2: Generate PNG assets**

Use a deterministic drawing script to render the Knight Spark direction at the iPad app icon sizes: 20pt, 29pt, 40pt, 76pt, 83.5pt, and 1024px marketing.

Expected: PNG files are present in `AppIcon.appiconset` and share one visual design.

- [ ] **Step 3: Add asset catalog metadata**

Write `Contents.json` files for the catalog root and `AppIcon.appiconset`.

Expected: Xcode recognizes `AppIcon` as an iPad app icon set.

### Task 2: Configure XcodeGen

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Set the app icon name**

Add this setting under the `ChessTutor` target base settings:

```yaml
ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

Expected: regenerated project files include the app icon build setting.

- [ ] **Step 2: Regenerate the project**

Run:

```bash
xcodegen generate
```

Expected: `ChessTutor.xcodeproj/project.pbxproj` reflects the `AppIcon` build setting and includes the resource asset catalog.

### Task 3: Verify

**Files:**
- Inspect: `ChessTutor.xcodeproj/project.pbxproj`
- Inspect: `ChessTutor/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`

- [ ] **Step 1: Build the app**

Run:

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)'
```

Expected: build succeeds.

- [ ] **Step 2: Inspect git changes**

Run:

```bash
git status --short
```

Expected: only app icon, project configuration, and design/plan documents are new or modified by this work; pre-existing test-file changes remain unstaged unless explicitly requested.
