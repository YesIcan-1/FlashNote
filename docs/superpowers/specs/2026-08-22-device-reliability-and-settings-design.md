# Device Reliability, Layout, and Settings Design

## Goal

Make device downloads reliable, keep device state alive across navigation, remove the unrelated persistent detail pane, and provide consistent appearance and API settings.

## Confirmed behavior

- Device downloads remain temporary until a valid completion frame arrives. An idle connection is a recoverable failure, never a successful recording.
- OPUS download/decoding failures retry the WAV candidate before surfacing an error.
- A single app-scoped device session owns the central connection, selected device, live status, file list, and active transfer. Views observe it rather than recreating a view model.
- macOS uses one primary content area for Workbench, Library, Files, or Device. A recording detail appears only after selecting a recording in Library.
- Appearance is configurable as System, Light, or Dark. Settings also retain transcription-provider endpoint, API key, model, and common behavior options.
- Real-time device audio is decoded and passed to the existing transcription boundary only when the device stream format is confirmed compatible; otherwise it shows a clear unavailable state rather than fabricated text.

## Safety and recovery

Incomplete transfers are deleted or never committed. Status messages expose download, decoding, retry, and transcription stages. The transfer can be cancelled, sends the device abort command, and returns the session to an actionable state.

## Validation

Tests cover completion-frame enforcement, OPUS-to-WAV fallback, state restoration after view recreation, WAV bytes passed to the transcription engine, and settings persistence. Build validation covers macOS, iOS device, and iOS Simulator libopus slices.
