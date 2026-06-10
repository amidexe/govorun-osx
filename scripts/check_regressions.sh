#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "regression check failed: $*" >&2
    exit 1
}

if [[ -e "$ROOT/Govorun/Dictionary/DictionaryEditorView.swift" ]]; then
    fail "DictionaryEditorView.swift should not exist; dictionary is embedded in SettingsView"
fi

if [[ -e "$ROOT/Govorun/Settings/AboutView.swift" ]]; then
    fail "AboutView.swift should not exist; About is embedded in SettingsView"
fi

forbidden_pattern="DictionaryEditorView|AboutView|showDictionary|showAbout|SettingsTabBar|stopRecordingFromMenu|cancelRecordingFromMenu|isRecordingActive"
if rg -n "$forbidden_pattern" "$ROOT/Govorun" "$ROOT/Govorun.xcodeproj" "$ROOT/project.yml"; then
    fail "old modal/settings or menu-recording symbols are still referenced"
fi

status_click_body="$(
    awk '
        /@objc private func handleStatusBarClick/ { inside=1 }
        inside { print }
        inside && /^    }/ { exit }
    ' "$ROOT/Govorun/AppDelegate.swift"
)"

if grep -Eq "startRecording|finishRecording|abortRecording" <<< "$status_click_body"; then
    fail "status bar click handler must not start, stop, or cancel recording"
fi

if ! grep -q "showStatsPopover" <<< "$status_click_body"; then
    fail "left click should keep opening stats popover"
fi

startup_forbidden_pattern="requestAccess\\(for: \\.audio|AXIsProcessTrustedWithOptions|migrateKeysToKeychain\\(\\)"
if rg -n "$startup_forbidden_pattern" "$ROOT/Govorun/AppDelegate.swift"; then
    fail "app launch must not trigger macOS permission or Keychain prompts"
fi

if rg -n "addPermissionsSection|Права:|Accessibility —|Микрофон —|Хоткей —" "$ROOT/Govorun/AppDelegate.swift"; then
    fail "status menu should not duplicate permission diagnostics; use Settings > Основные instead"
fi

if ! rg -q "SettingsSection\\(\"Разрешения\"\\)" "$ROOT/Govorun/Settings/SettingsView.swift"; then
    fail "settings General tab should show required permissions"
fi

if rg -n "SettingsSection\\(\"Словарь замен\"\\)" "$ROOT/Govorun/Settings/SettingsView.swift"; then
    fail "dictionary should not be duplicated in General settings; use the sidebar tab only"
fi

if ! rg -q "Использовать словарь замен|wordDictionaryEnabled|guard isEnabled else" "$ROOT/Govorun/Settings/SettingsView.swift" "$ROOT/Govorun/Dictionary/WordDictionary.swift"; then
    fail "dictionary tab should expose an enabled toggle without deleting rules"
fi

if ! rg -q "generalNeedsAttention" "$ROOT/Govorun/Settings/SettingsView.swift"; then
    fail "settings sidebar should mark Основные when required permissions are missing"
fi

if ! rg -q "birdStatus" "$ROOT/Govorun/AppDelegate.swift" "$ROOT/Govorun/UI/BirdLogoView.swift"; then
    fail "menu bar icon should show attention state when required permissions are missing"
fi

if rg -n "Права и хоткей|Горячая клавиша|hotkeyActive|isHotkeyActive|onRestartHotkey" "$ROOT/Govorun/Settings/SettingsView.swift"; then
    fail "hotkey state should not be presented as a required permission"
fi

if ! rg -q "HotkeyConfig\\.modifierOnly\\(UInt16\\(kVK_RightOption\\)" "$ROOT/Govorun/Hotkey/HotkeyConfig.swift"; then
    fail "default dictation hotkey should be the recommended right Option modifier"
fi

if ! rg -q "isReservedForPasteShortcut" "$ROOT/Govorun/Hotkey/HotkeyConfig.swift"; then
    fail "hotkey recorder should reject Cmd+V paste conflicts"
fi

if ! rg -q "modifierInterruptionWindowNanos|shouldAbortModifierShortcutForChord|onKeyAborted" "$ROOT/Govorun/Hotkey/HotkeyManager.swift"; then
    fail "modifier-only hotkeys should keep normal key chords usable, VoiceInk-style"
fi

if ! rg -q "sign_app.sh" "$ROOT/Makefile" "$ROOT/scripts/install_app.sh"; then
    fail "build and install should sign the app bundle so icons/resources and macOS permissions are stable"
fi

if ! rg -q "setup-local-signing" "$ROOT/Makefile"; then
    fail "Makefile should expose setup-local-signing for stable local TCC identity"
fi

if ! rg -q "Govorun Local Development|find_local_identity" "$ROOT/scripts/sign_app.sh"; then
    fail "sign_app.sh should use the stable local code-signing identity when available"
fi

if [[ ! -x "$ROOT/scripts/setup_local_signing.sh" ]]; then
    fail "setup_local_signing.sh should exist and be executable"
fi

if rg -n "@State private var llmKey:[^\n]+LLMSettings\\.apiKey" "$ROOT/Govorun/Settings/SettingsView.swift"; then
    fail "settings window must not read the LLM API key from Keychain during view initialization"
fi

if ! rg -q "apiKeyStorageState|staleReference|accessDenied" "$ROOT/Govorun/LLM" "$ROOT/Govorun/Settings/SettingsView.swift"; then
    fail "LLM key UI should distinguish missing, stale, and inaccessible Keychain states"
fi

if ! rg -q "ensureApiKeyReady|LLMConfigurationError|llmStatusDidUpdate|lastErrorMessage" "$ROOT/Govorun"; then
    fail "LLM styling should fail visibly and skip fast when a required API key is missing"
fi

if rg -n "SettingsRow\\(\"API ключ\"" "$ROOT/Govorun/Settings/SettingsView.swift"; then
    fail "LLM API key controls should not be squeezed into a right-side SettingsRow"
fi

if ! rg -q "Сохранить ключ|llmApiKeyRowVisible|llmKeySaveMessage" "$ROOT/Govorun/Settings/SettingsView.swift"; then
    fail "LLM API key UI should have an explicit full-width save flow and visible status"
fi

if ! rg -q "errSecDuplicateItem|deleteStatus\\(account\\)|updateQueries\\(for account\\)" "$ROOT/Govorun/LLM/KeychainHelper.swift"; then
    fail "Keychain writes should replace duplicate items instead of trapping users on errSecDuplicateItem"
fi

if ! rg -q "com\\.govorun\\.app\\.llm|legacyServices|readableServices|updateQueries|deleteQueries" "$ROOT/Govorun/LLM/KeychainHelper.swift"; then
    fail "Keychain should write LLM secrets into a dedicated namespace while retaining legacy cleanup/read paths"
fi

if ! rg -q "GOVORUN_KEYCHAIN_SELFTEST|KeychainSelfTest" "$ROOT/Govorun" "$ROOT/scripts/check_keychain_logic.sh"; then
    fail "Keychain save/read/delete behavior should be covered by the signed app self-test"
fi

if ! rg -q "KeychainHelper\\.getResult\\(account\\)" "$ROOT/Govorun/LLM/LLMCorrector.swift"; then
    fail "LLM key saves should verify that the Keychain item can be read after writing"
fi

if ! rg -q "apiKeyForRequest" "$ROOT/Govorun/LLM/LLMCorrector.swift"; then
    fail "LLM requests should read API keys through a throwing helper instead of silently omitting auth"
fi

if ! rg -q 'openaiEndpoint\("/responses"\)|OpenAIResponsesRequest|OpenAIResponsesResponse' "$ROOT/Govorun/LLM/LLMCorrector.swift"; then
    fail "OpenAI provider should use the Responses API for api.openai.com"
fi

if ! rg -q "validatedData|LLMHTTPError|decodeErrorMessage" "$ROOT/Govorun/LLM/LLMCorrector.swift"; then
    fail "LLM HTTP failures should surface provider status and server error messages"
fi

if ! rg -q "checkConnection|checkOpenAIResponsesConnection|checkLLMConnection" "$ROOT/Govorun/LLM/LLMCorrector.swift" "$ROOT/Govorun/Settings/SettingsView.swift"; then
    fail "LLM settings should include a real provider connectivity check, not only a Keychain read"
fi

if ! rg -q "LLMProxy\\.makeSession|connectionProxyDictionary" "$ROOT/Govorun/LLM"; then
    fail "LLM provider checks should use the shared proxy-aware URLSession builder"
fi

if ! rg -q "GOVORUN_OPENAI_PROXY_SELFTEST|OpenAIProxySelfTest" "$ROOT/Govorun" "$ROOT/scripts/check_openai_proxy_smoke.sh"; then
    fail "OpenAI/proxy connectivity should have an explicit smoke test path"
fi

if ! awk '
    /private func saveLLMKey\(\)/ { inside=1 }
    inside && /private var llmApiKeyRowVisible/ { exit }
    inside && /checkLLMConnection\(\)/ { ok=1 }
    END { exit ok ? 0 : 1 }
' "$ROOT/Govorun/Settings/SettingsView.swift"; then
    fail "saving an LLM API key should immediately verify provider connectivity"
fi

if rg -n "text\\(\\\\\\(text\\.count\\)\\):|NSLog\\([^\\n]*\\\\\\(text\\)" "$ROOT/Govorun/LLM/LLMCorrector.swift"; then
    fail "LLM logs must not include dictated text content"
fi

if ! rg -q "DiagnosticsLog|diagnosticsTab|textDump|sanitize" "$ROOT/Govorun"; then
    fail "settings should include lightweight diagnostics with sanitized export"
fi

if ! rg -q "maxStoredEvents|LazyVStack" "$ROOT/Govorun/Diagnostics/DiagnosticsLog.swift" "$ROOT/Govorun/Settings/SettingsView.swift"; then
    fail "diagnostics UI should stay bounded and render log rows lazily"
fi

if rg -n "DiagnosticsLog\\.record\\([^\\n]*(text|transcribedText)" "$ROOT/Govorun"; then
    fail "diagnostics must not record dictated text content"
fi

if rg -n "path = Assets\\.xcassets" "$ROOT/Govorun.xcodeproj/project.pbxproj"; then
    fail "asset catalog path should point to Govorun/Assets.xcassets so the app icon is bundled"
fi

if ! rg -q "path = Govorun/Assets\\.xcassets" "$ROOT/Govorun.xcodeproj/project.pbxproj"; then
    fail "asset catalog path is missing from the generated Xcode project"
fi

BUILT_APP="$ROOT/.build/Build/Products/Release/Говорун.app"
if [[ -d "$BUILT_APP" ]]; then
    if ! codesign --verify --deep --strict --verbose=2 "$BUILT_APP" >/dev/null 2>&1; then
        fail "built app bundle should have a valid resource seal"
    fi
    sign_info="$(codesign -dv "$BUILT_APP" 2>&1 || true)"
    if ! grep -q "Identifier=com.govorun.app" <<< "$sign_info"; then
        fail "built app signature should use com.govorun.app as the identifier"
    fi
    if ! grep -q "Sealed Resources" <<< "$sign_info"; then
        fail "built app signature should seal resources so AppIcon is visible to macOS"
    fi
fi

theme_surface_paths=(
    "$ROOT/Govorun/Settings"
    "$ROOT/Govorun/Stats"
    "$ROOT/Govorun/UI/StatsPopoverView.swift"
    "$ROOT/Govorun/UI/GovorunTheme.swift"
)
theme_forbidden_pattern="controlBackgroundColor|windowBackgroundColor|underPageBackgroundColor|\\.background\\(\\.background|Color\\(NSColor\\.(controlBackgroundColor|windowBackgroundColor|underPageBackgroundColor)"
if rg -n "$theme_forbidden_pattern" "${theme_surface_paths[@]}"; then
    fail "settings/statistics surfaces should use GovorunTheme roles instead of system gray backgrounds"
fi

stats_period_forbidden_pattern="lastDays\\(7\\)|7 дней|За 7 дней|Последние 7 дней|Месяц|месяц|currentMonth|case[[:space:]]+month|\\.month"
if rg -n "$stats_period_forbidden_pattern" \
    "$ROOT/Govorun/Stats/StatsView.swift" \
    "$ROOT/Govorun/Stats/SessionStats.swift" \
    "$ROOT/Govorun/UI/StatsPopoverView.swift"; then
    fail "statistics should show today/yesterday/week/all-time only; month and rolling 7 days are not part of the UI"
fi

text_forbidden_pattern="мягк.*зон|Зоны нагрузки|дневной нагрузкой|целиком на CPU"
if rg -n "$text_forbidden_pattern" \
    "$ROOT/Govorun" \
    "$ROOT/README.md"; then
    fail "outdated or unclear wording is still present"
fi

vad_allocation_forbidden_pattern="Array\\((self\\.)?windowBuf\\["
if rg -n "$vad_allocation_forbidden_pattern" "$ROOT/Govorun/Engine/AudioEngine.swift"; then
    fail "VAD window processing should avoid per-window Array allocations"
fi

if rg -n "vadPreRoll|vadPrimed|vadSilenceGate|feedSamplesToVadWithSilenceGate" "$ROOT/Govorun/Engine/AudioEngine.swift"; then
    fail "Silero should receive the normal 16 kHz stream; do not bypass it with a custom silence gate"
fi

if ! rg -q "silero\\.threshold[[:space:]]*=[[:space:]]*0\\.5" "$ROOT/Govorun/Engine/SileroVAD.swift"; then
    fail "Silero threshold should stay at the standard 0.5 baseline to avoid noise-triggered ASR"
fi

if ! rg -q "silero\\.window_size[[:space:]]*=[[:space:]]*Int32\\(SileroVAD\\.windowSize\\)" "$ROOT/Govorun/Engine/SileroVAD.swift"; then
    fail "Silero should be fed with its configured 512-sample window"
fi

if ! rg -q "cfg\\.sample_rate[[:space:]]*=[[:space:]]*16000" "$ROOT/Govorun/Engine/SileroVAD.swift"; then
    fail "Silero VAD should run at 16 kHz"
fi

if rg -n "model_config\\.num_threads[[:space:]]*=[[:space:]]*1" "$ROOT/Govorun/Engine/GigaAMEngine.swift"; then
    fail "GigaAM should not be pinned to one ASR thread; benchmark showed large recognition latency regressions"
fi

if ! rg -q "defaultThreadCount: Int32 = 2|GOVORUN_ASR_THREADS|recognitionThreads" "$ROOT/Govorun/Engine/GigaAMEngine.swift"; then
    fail "GigaAM thread count should default to the measured 2-thread profile and stay benchmarkable"
fi

if awk '
    /private func preloadRecognizerOnce\(\)/ { inside_allowed=1 }
    inside_allowed && /^    }/ { inside_allowed=0; next }
    /gigaAM\.preload\(\)/ && !inside_allowed { print; bad=1 }
    END { exit bad ? 0 : 1 }
' "$ROOT/Govorun/Engine/AudioEngine.swift"; then
    fail "GigaAM preload should only happen through the VAD-confirmed preload gate"
fi

if ! awk '
    /if vad\.isSpeechDetected\(\)/ { seen=1 }
    seen && /preloadRecognizerOnce\(\)/ { ok=1 }
    END { exit ok ? 0 : 1 }
' "$ROOT/Govorun/Engine/AudioEngine.swift"; then
    fail "GigaAM should preload only after Silero reports speech"
fi

if ! rg -q "runtimeBusyActive|runtimeRecordingActive" "$ROOT/scripts/install_app.sh"; then
    fail "install_app.sh should refuse to restart the app while dictation or processing is active"
fi

if ! rg -q "GOVORUN_INSTALL_ALLOW_BUSY_RESTART" "$ROOT/scripts/install_app.sh"; then
    fail "install_app.sh should require an explicit override for busy restarts"
fi

finish_body="$(
    awk '
        /private func finishRecording\(\) async/ { inside=1 }
        inside && /private func enqueueRecognition/ { exit }
        inside { print }
    ' "$ROOT/Govorun/AppDelegate.swift"
)"

if ! grep -q "stopRecordingForRecognition" <<< "$finish_body"; then
    fail "finishRecording should detach audio capture from recognition work"
fi

if ! grep -q "recordingState = \\.idle" <<< "$finish_body"; then
    fail "finishRecording should return to idle before recognition/LLM/paste completes"
fi

if ! rg -q "recognitionTail|enqueueRecognition|processRecognition" "$ROOT/Govorun/AppDelegate.swift"; then
    fail "recognition should be queued after capture stops so the next recording can start quickly"
fi

process_body="$(
    awk '
        /private func processRecognition/ { inside=1 }
        inside && /private func abortRecording/ { exit }
        inside { print }
    ' "$ROOT/Govorun/AppDelegate.swift"
)"

if grep -Eq "suspendForRecorder|resumeAfterRecorder" <<< "$process_body"; then
    fail "paste path must not disable the hotkey tap; it can swallow the next key-up"
fi

if ! rg -q "suppressSyntheticPasteEvents" "$ROOT/Govorun/AppDelegate.swift" "$ROOT/Govorun/Hotkey/HotkeyManager.swift"; then
    fail "paste path should suppress synthetic Cmd+V events without disabling the hotkey tap"
fi

bash "$ROOT/scripts/check_stats_logic.sh"
bash "$ROOT/scripts/check_keychain_logic.sh"

echo "regression checks: ok"
