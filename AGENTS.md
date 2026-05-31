# Говорун — macOS dictation app

Native SwiftUI + AppKit speech-to-text app. Records mic, transcribes via GigaAM v3 ONNX (sherpa-onnx), pastes at cursor.

## Build

```bash
make setup          # Download sherpa-onnx xcframework and GigaAM model (~460 MB, one time)
make build          # Build Debug into .build/
make install        # Kill running instance, copy to /Applications, launch
make run            # Launch already-built app from .build/
make clean          # Wipe .build/ and .xcodeproj
```

## Project structure

```
Govorun/
├── AppDelegate.swift          # NSApplicationDelegate, hotkey handlers, recording lifecycle
├── GovorunApp.swift           # @main SwiftUI entry point
├── Engine/
│   ├── AudioEngine.swift      # Orchestrator: record → VAD → transcribe
│   ├── CoreAudioRecorder.swift # Low-level AUHAL recording
│   ├── SileroVAD.swift        # Voice Activity Detection (Silero v4)
│   ├── GigaAMEngine.swift     # GigaAM v3 RNNT speech-to-text
│   └── RecordingOptions.swift # Media pause / system mute controller
├── Dictionary/                # Word/phrase replacement dictionary
├── LLM/                       # Optional LLM post-processing
├── UI/                        # Floating recorder window
├── Hotkey/                    # Global keyboard shortcut (CGEvent tap)
├── Settings/                  # Settings UI + Licenses
└── Paste/                     # CGEvent-based paste
```

## Audio/media pause logic

`RecordingMediaController` in `Engine/RecordingOptions.swift`:
- `prepareForRecording()` — mutes system audio (CoreAudio) + pauses media (HID play/pause key via MediaRemote.framework)
- `restoreAfterRecording()` — unmutes + resumes media
- Before resuming, verifies: original app still running, media is still paused (not already resumed by user)
