# Device Reliability and Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver reliable CB08 download/transcription, stable navigation state, correct layout, and user-configurable appearance/API settings.

**Architecture:** Move device ownership from a transient screen view model into an app-scoped session. Treat a device completion frame as the only successful download terminal condition, with explicit retry/cancel paths. Keep navigation and settings separate from BLE protocol code.

**Tech Stack:** SwiftUI, Observation, CoreBluetooth, FlashNoteCore, libopus XCFramework, Swift Testing.

---

### Task 1: Make device downloads completion-frame safe

**Files:** `Services/Device/DeviceTranscriptionService.swift`, `Tests/DeviceTranscriptionServiceTests.swift`

- [ ] Add failing tests for a partial transfer that becomes an error after idle timeout and an OPUS decode error that requests the WAV candidate.
- [ ] Replace the idle-success continuation with `DeviceError.incompleteDownload`; retain data only after `cmd 2/5 code=0`.
- [ ] Catch OPUS decode failures in the candidate loop and retry a WAV candidate once; expose cancel by calling `CB08Device.abortImport()`.
- [ ] Run `xcodebuild -project FlashNote.xcodeproj -scheme FlashNoteMac -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES ARCHS=arm64 test -only-testing:FlashNoteMacTests/DeviceTranscriptionServiceTests`.

### Task 2: Persist the connection session across views

**Files:** `Services/Device/DeviceSession.swift`, `Features/Device/DevicePanelView.swift`, `App/FlashNoteApp.swift`, device tests

- [ ] Introduce one `@Observable DeviceSession` created at app startup; it restores current central state and owns `CB08Device`/transfer callbacks.
- [ ] Inject the session through SwiftUI environment and make `DevicePanelView` render it without constructing a new view model.
- [ ] Test that a new observing view receives the connected state, battery, firmware, and files.

### Task 3: Correct navigation and recording detail placement

**Files:** `App/RootView.swift`, `Features/Workbench/WorkbenchView.swift`

- [ ] Render one content region for non-library sections; show `RecordingDetailView` only for a selected library recording.
- [ ] Keep workbench actions and iOS tab routing functional.
- [ ] Validate macOS navigation manually and with the full macOS test suite.

### Task 4: Add appearance and API settings

**Files:** `Features/Settings/SettingsView.swift`, `Features/Settings/SettingsViewModel.swift`, `App/AppSettings.swift`, settings tests

- [ ] Persist `AppearanceMode.system/light/dark`, transcription endpoint, API key, model, language, and import preferences.
- [ ] Apply the selected color scheme at the app root and use semantic theme colors in all primary surfaces.
- [ ] Test defaults and persistence without exposing API keys in UI logs.

### Task 5: Complete audio and release validation

**Files:** `Vendor/Opus.xcframework`, `Services/Audio/OpusDecoder.swift`, OPUS fixture tests, vendor notice

- [ ] Build an iOS Simulator slice and add it to the XCFramework; make each selected platform use its own headers.
- [ ] Add a valid fixed-packet OPUS fixture test and an integration test proving WAV data reaches the file engine.
- [ ] Add source/version/license/build notes for libopus.
- [ ] Run macOS tests, core tests, iOS device build, and iOS Simulator build.
