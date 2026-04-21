# Copilot instructions for MyPhoto

## Build, test, and lint

- Build app (Debug):
  - `xcodebuild -project MyPhoto.xcodeproj -scheme MyPhoto -configuration Debug build`
- Build app (Release):
  - `xcodebuild -project MyPhoto.xcodeproj -scheme MyPhoto -configuration Release build`
- Tests:
  - There is currently no XCTest target in `MyPhoto.xcodeproj` (only the `MyPhoto` app target), so there is no runnable full-suite or single-test command yet.
  - After a test target is added, use:
    - Full suite: `xcodebuild test -project MyPhoto.xcodeproj -scheme <TestScheme> -destination 'platform=macOS'`
    - Single test: `xcodebuild test -project MyPhoto.xcodeproj -scheme <TestScheme> -destination 'platform=macOS' -only-testing:<TestTarget>/<TestClass>/<testMethod>`
- Lint:
  - No SwiftLint or other standalone linter config is present; rely on Xcode build diagnostics.

## High-level architecture

- `MyPhotoApp.swift` is a minimal app entry point that mounts `ContentView`.
- `ContentView.swift` owns UI state and interaction flow:
  - Split-pane layout (`HSplitView`) with thumbnail grid, optional live preview, and optional metadata panel.
  - Selection model is `selectedPhotoIDs + lastSelectedIndex` and drives keyboard navigation, multi-select behavior, flagging, and trashing.
  - Drag-and-drop to external apps (e.g., Lightroom) always uses `PhotoGroup.rawPreferredURL`.
- `PhotoManager.swift` is the domain/service layer:
  - `scanDirectory` clears current state and asynchronously rebuilds grouped photos.
  - `buildPhotoGroups` scans one folder level, groups files by base filename, and fills a `PhotoGroup` with linked formats (`arw/raf/heif/jpg/png`).
  - Thumbnail generation is concurrent (`withTaskGroup`) and prioritizes QuickLook (`QLThumbnailGenerator`) with ImageIO fallback.
  - High-res preview extraction and metadata extraction are centralized here.
  - Keep/reject/unflag/trash mutations are exposed as manager methods and called from UI.
- `PhotoGroup.swift` is the core model for “one photo entity across multiple file formats.”
  - `previewURL` chooses the fast display source.
  - `rawPreferredURL` chooses the RAW-first source for export/drag workflows.

## Key codebase conventions

- Grouping convention: files with the same base name are treated as one photo group; preserve this behavior when adding new formats or flows.
- URL priority convention is intentional and reused across features:
  - Preview/metadata priority: `jpg/heif` before RAW when possible.
  - Export/drag priority: RAW (`arw/raf`) before other formats.
- Concurrency convention: expensive IO/image work is kept out of the main actor (`nonisolated`, task groups, detached tasks), while observable state mutations happen on main actor-facing APIs.
- UX convention: culling actions (keyboard shortcuts, flags, trash, auto-selection updates) are implemented in `ContentView` and should stay consistent with the documented shortcuts in `README.md`.
- Settings convention: metadata panel preferences are in-memory `@State` toggles (not persisted), matching README’s memory-only settings note.
- Project capability convention: App Sandbox is intentionally disabled to allow broad file-system access (`ENABLE_APP_SANDBOX = NO` in project settings and README setup steps).
