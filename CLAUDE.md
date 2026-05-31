# Говорун — macOS

Native SwiftUI + AppKit speech-to-text app. Records mic, transcribes via GigaAM v3 ONNX (sherpa-onnx), optionally corrects via LLM, pastes at cursor.

## Repository

GitHub: https://github.com/amidexe/govorun-osx (приватный)
Local: /Users/tttt/projects/govorun-osx

## Build

```bash
make build          # Debug build → .build/Build/Products/Debug/Говорун.app
make install        # Kill running instance, copy to /Applications, launch
make run            # Launch already-built app from .build/
make clean          # Wipe .build/ and .xcodeproj
```

**ОБЯЗАТЕЛЬНО** перед каждым `make` делать `touch` всех изменённых Swift-файлов — xcodebuild агрессивно кэширует инкрементальную сборку и молча пропускает изменения:

```bash
touch Govorun/Path/ChangedFile.swift && make
```

Без `touch` бинарник может остаться старым несмотря на `BUILD SUCCEEDED`. Это не баг сборки — это штатное поведение xcodebuild.

After adding new Swift files: run `python3 patch_project.py` to register them in the .xcodeproj.

## Project structure

```
Govorun/
├── AppDelegate.swift          # NSApplicationDelegate, hotkey handlers, recording lifecycle + LLM call
├── GovorunApp.swift           # @main entry point
├── Engine/
│   ├── AudioEngine.swift      # Orchestrator: record → VAD → transcribe (accumulates phrases)
│   ├── CoreAudioRecorder.swift
│   ├── SileroVAD.swift        # Silero v4 VAD
│   ├── GigaAMEngine.swift     # GigaAM v3 RNNT speech-to-text (sherpa-onnx)
│   └── RecordingOptions.swift # System audio mute / media pause
├── LLM/
│   └── LLMCorrector.swift     # LLM text correction (Ollama / OpenAI / Gemini native API)
├── Settings/
│   └── SettingsView.swift     # Settings UI with stats hero section at top
├── Stats/
│   ├── SessionStats.swift     # Session + word counters (all-time + today, auto-resets by date)
│   └── MetricCard.swift       # Reusable stats card component (same style as VoiceInk)
├── Hotkey/                    # Global hotkey (CGEvent tap)
├── UI/                        # Floating recorder window
└── Paste/                     # CGEvent-based paste
```

## LLM pipeline

Flow: stop recording → full accumulated text sent ONCE to LLM → corrected text pasted.

Providers (each stores URL / API key / model separately in UserDefaults):
- **Ollama** — OpenAI-compat, local, no key
- **OpenAI** — OpenAI-compat, api.openai.com
- **Google Gemini** — native Gemini API, thinkingBudget=0 (disables thinking on 2.5 models)

Best model for this use case: `gemini-2.5-flash-lite` (~0.8s) or `gpt-5.4-nano` (~1s).
Recommended: `gpt-4.1-nano` ($0.05/1M input) for cheapest; `gpt-5.4-nano` for best quality.

System prompt stored in UserDefaults key `llmSystemPrompt`. Default in `LLMCorrector.defaultPrompt`.

## UserDefaults keys

| Key | Description |
|-----|-------------|
| `llmProvider` | `ollama` / `openai` / `gemini` |
| `llmServerURL_{provider}` | Per-provider API URL |
| `llmApiKey_{provider}` | Per-provider API key |
| `llmModel_{provider}` | Per-provider selected model |
| `llmSystemPrompt` | System prompt for correction |
| `llmMinLength` | Min chars to trigger LLM (default 80) |
| `llmEnabled` | Bool |
| `statsSessions` | All-time session count |
| `statsWords` | All-time word count |
| `statsSessionsToday` | Today's session count (resets by date) |
| `statsWordsToday` | Today's word count |
| `statsTodayDate` | ISO date string for today rollover |

## Stats

`SessionStats.record(text:)` called after each recording session. Increments all-time and today counters. Today counters reset automatically when date changes (no alarm needed — date compared on each read).
