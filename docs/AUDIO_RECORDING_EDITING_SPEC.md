# Best-in-Class Audio Recording & Editing for iOS

## Context

The Hear Here iOS app currently has basic audio recording (record -> metadata -> upload) but **no editing capabilities**. Users cannot pause/resume, trim, cut, fade, or normalize their recordings before uploading. To deliver a best-in-class experience comparable to Voice Memos and podcast apps, we need enhanced recording controls and a full audio editing screen inserted into the flow.

**Target flow:** Record -> **Edit (new)** -> Metadata -> Upload

## Phase 1: Core Audio Engine & Waveform Data

Build the foundation: PCM waveform extraction and the audio processing engine.

### New Files

| File | Purpose |
|------|---------|
| `Core/Audio/WaveformDataProvider.swift` | Reads PCM samples from audio file via `AVAssetReader`, downsamples with Accelerate `vDSP` into displayable `WaveformData` (peak amplitudes per bin) |
| `Core/Audio/EditOperation.swift` | Value types: `.trim(start, end)`, `.cut(start, end)`, `.fadeIn(duration)`, `.fadeOut(duration)`, `.normalize(targetPeakDb)` |
| `Core/Audio/AudioEditSession.swift` | Non-destructive edit session: holds original file URL, ordered `[EditOperation]`, undo/redo stacks (memento pattern -- snapshot the full operations list on each apply) |
| `Core/Audio/AudioEngine.swift` | Processes & exports: reads PCM via `AVAssetReader` (Float32 mono), applies trim/cut/fade/normalize using Accelerate (`vDSP_vramp`, `vDSP_vsmul`, `vDSP_maxmgv`), writes AAC M4A via `AVAssetWriter`. Protocol-based (`AudioEngineProtocol`) for testability |

### Tests

| File | Purpose |
|------|---------|
| `Tests/WaveformDataProviderTests.swift` | Extraction from synthetic audio, downsampling accuracy, edge cases (short/empty files) |
| `Tests/AudioEditSessionTests.swift` | Apply, undo, redo, reset, canUndo/canRedo flags, effective duration calculation |
| `Tests/AudioEngineTests.swift` | Trim duration correctness, cut removes region, fade ramps amplitudes, normalize hits target peak, export produces valid M4A with ftyp atom, output stays under 10MB |

### Key Design Decisions

- **Accelerate framework** for all DSP (no third-party audio libs)
- **Memory**: 5-min mono Float32 @ 44.1kHz = ~53MB. Process in chunks for peak detection; load full buffer only for fade/normalize transforms
- **Export**: Use `AVAssetWriter` with AAC settings matching existing recorder (44.1kHz, 64kbps, mono). After export, read back actual duration via `AVAsset.load(.duration)` to avoid backend validation mismatches from AAC priming frames
- **Cut splice pops**: Auto-apply 5ms crossfade at cut boundaries

## Phase 2: Enhanced Recording

Add pause/resume, countdown, VU meter, and mic selection to the existing recorder.

### Modify Existing Files

**`Core/Audio/AudioRecorder.swift`**
- Add `pauseRecording()` and `resumeRecording()` to `AudioRecorderProtocol` and implementation (AVAudioRecorder natively supports `pause()`/`record()` to resume)
- Expose `currentPeakPower: Float` alongside existing average power for clipping detection (peak > -1 dB)
- Add `RecordingQuality` enum (`.standard` = 64kbps, `.high` = 128kbps) -- both stay under 10MB for 5 min

**`Core/Audio/AudioSession.swift`**
- Add `availableInputPorts() -> [AVAudioSessionPortDescription]`
- Add `selectInputPort(_:)` for external mic selection

**`Features/Recording/RecordingViewModel.swift`**
- Add `pauseRecording()` / `resumeRecording()` actions
- Add `countdownRemaining: Int?` state with 3-2-1 countdown before recording starts (1-second intervals via `Task.sleep`)
- Add `RecordingPhase.paused` case
- Haptic feedback via `UIImpactFeedbackGenerator` on start/stop/pause

**`Features/Recording/RecordingView.swift`**
- Add pause/resume toggle button alongside stop button
- Add countdown overlay (large centered "3", "2", "1" text)
- Add input level indicator (green -> yellow -> red gradient bar from normalized power)
- Add mic source picker when multiple inputs available

### New Files

| File | Purpose |
|------|---------|
| `Core/Audio/InputLevelMeter.swift` | Real-time input level monitoring view component with clipping indicator |
| `Tests/InputLevelMeterTests.swift` | dB normalization, clipping threshold detection |

## Phase 3: Editing UI

Build the full audio editing screen with interactive waveform.

### New Files

| File | Purpose |
|------|---------|
| `Shared/Components/PCMWaveformView.swift` | High-res waveform renderer using SwiftUI `Canvas` (not individual rectangles). Draws only visible samples based on scroll offset + zoom level. Supports: pinch-to-zoom (`MagnifyGesture`), pan/scroll (`DragGesture`), tap-to-seek, selection highlighting, playhead cursor |
| `Features/Editing/AudioEditingViewModel.swift` | Owns `AudioEditSession`, coordinates preview playback, manages state: `idle -> previewing -> processing -> completed(URL)`. Preview uses `AVMutableComposition` for trim/cut; temp export for fade/normalize preview |
| `Features/Editing/AudioEditingView.swift` | Main editing screen composing waveform, transport controls, edit toolbar |
| `Features/Editing/WaveformEditorView.swift` | Scrollable/zoomable waveform with trim handles and playhead, built on `PCMWaveformView` |
| `Features/Editing/TrimHandleView.swift` | Draggable left/right handles with haptic feedback on drag |
| `Features/Editing/EditToolbarView.swift` | Horizontal toolbar: Undo, Redo, Trim, Cut, Fade In, Fade Out, Normalize |
| `Features/Editing/TimeRulerView.swift` | Time markers that scroll with waveform |
| `Tests/AudioEditingViewModelTests.swift` | State transitions, undo/redo propagation, export produces URL, skip returns original |

### Layout

```
+------------------------------------------+
|  < Back       Edit Audio     Skip | Done |
+------------------------------------------+
|  [Time Ruler: 0:00  0:15  0:30  ...]     |
|  +--------------------------------------+|
|  |  Scrollable Canvas Waveform          ||
|  |  [left-handle ====|==== right-handle]||
|  |         | playhead                   ||
|  +--------------------------------------+|
|  Current: 0:23    Duration: 2:45         |
|  [<<]  [ Play / Pause ]  [>>]           |
+------------------------------------------+
| [Undo] [Redo] [Trim] [Cut]              |
| [Fade In] [Fade Out] [Normalize]         |
+------------------------------------------+
```

### Playhead Animation

Use `CADisplayLink` to interpolate playhead position at ~60fps between `AVPlayer` periodic time observer callbacks.

## Phase 4: Flow Integration

Wire the editing step into the existing recording -> metadata -> upload flow.

### Modify Existing Files

**`Features/Recording/RecordingCoordinator.swift`**
- Add `.editing` case to `Destination` enum
- Add `showEditing()` method

**`Features/Recording/RecordingViewModel.swift`**
- Add `.editing(URL)` case to `RecordingPhase`

**`Features/Recording/RecordingView.swift`**
- Change `.recorded` phase to navigate to `.editing` instead of `.metadata`
- Add `navigationDestination` for `.editing` -> `AudioEditingView`
- `AudioEditingView` completion callback stores edited URL in `viewModel.recordedFileURL` then calls `coordinator.showMetadata()`
- "Skip" button in editor passes original URL unchanged

**`Features/Recording/RecordingMetadataView.swift`**
- Replace `AudioWaveformView` with `PCMWaveformView` for richer audio preview

**`Shared/Styles/Theme.swift`**
- Add: `waveformForeground`, `waveformBackground`, `selectionHighlight`, `playheadColor`, `clippingIndicator`

**`App/AppEnvironment.swift`**
- Add `AudioEngineKey` environment key

## Phase 5: Polish

- **Performance**: Cache waveform data by file URL + resolution; only draw visible viewport samples in Canvas
- **Accessibility**: VoiceOver labels on all editing controls, custom rotor actions for waveform navigation
- **Edge cases**: Very short recordings (<5s), max-duration recordings, silent recordings
- **Memory**: Add memory warning observer, process in streaming chunks where possible
- **Error handling**: Graceful fallback if export fails (keep original file, show error, allow retry)

## Verification

1. **Unit tests**: Run all new test files -- waveform extraction, edit session undo/redo, audio engine trim/cut/fade/normalize/export, ViewModel state transitions
2. **Manual flow test**: Record -> pause -> resume -> stop -> edit (trim ends, cut middle, apply fade in + normalize) -> preview playback -> Done -> metadata -> upload -> verify backend accepts the file
3. **Skip path**: Record -> skip editing -> metadata -> upload (existing flow still works)
4. **Format validation**: Exported files pass backend's `IsValidAudioHeader` (ftyp atom check) and `TryParseMvhdDuration` (duration within 5s tolerance)
5. **Undo/redo**: Apply 3 edits -> undo all -> redo 2 -> verify waveform and preview reflect correct state
6. **External mic**: Connect AirPods/external mic -> verify source picker appears and recording uses selected input
7. **Memory**: Record 5-minute audio -> open editor -> zoom in/out aggressively -> verify no memory warnings or crashes

## Files Summary

### New Files (17)

All paths relative to `ios/HearHere/`:

- `Core/Audio/WaveformDataProvider.swift`
- `Core/Audio/EditOperation.swift`
- `Core/Audio/AudioEditSession.swift`
- `Core/Audio/AudioEngine.swift`
- `Core/Audio/InputLevelMeter.swift`
- `Shared/Components/PCMWaveformView.swift`
- `Features/Editing/AudioEditingView.swift`
- `Features/Editing/AudioEditingViewModel.swift`
- `Features/Editing/WaveformEditorView.swift`
- `Features/Editing/TrimHandleView.swift`
- `Features/Editing/EditToolbarView.swift`
- `Features/Editing/TimeRulerView.swift`
- `Tests/WaveformDataProviderTests.swift`
- `Tests/AudioEditSessionTests.swift`
- `Tests/AudioEngineTests.swift`
- `Tests/AudioEditingViewModelTests.swift`
- `Tests/InputLevelMeterTests.swift`

### Modified Files (8)

All paths relative to `ios/HearHere/`:

- `Core/Audio/AudioRecorder.swift` -- pause/resume, peak power, quality presets
- `Core/Audio/AudioSession.swift` -- input port enumeration/selection
- `Features/Recording/RecordingCoordinator.swift` -- `.editing` destination
- `Features/Recording/RecordingViewModel.swift` -- countdown, pause/resume, `.editing` phase
- `Features/Recording/RecordingView.swift` -- pause button, countdown, VU meter, route to editor
- `Features/Recording/RecordingMetadataView.swift` -- use PCMWaveformView
- `Shared/Styles/Theme.swift` -- waveform editor color tokens
- `App/AppEnvironment.swift` -- AudioEngine environment key
