XCODEBUILD := xcodebuild
PROJECT    := Govorun.xcodeproj
SCHEME     := Govorun
BUILD_DIR  := .build
MODEL_DST  := Govorun/Resources/Model

SHERPA_VER := v1.13.1
SHERPA_URL := https://github.com/k2-fsa/sherpa-onnx/releases/download/$(SHERPA_VER)/sherpa-onnx-$(SHERPA_VER)-macos-xcframework-static.tar.bz2
SHERPA_TMP := sherpa-onnx-$(SHERPA_VER)-macos-xcframework-static

GIGAAM_HF  := https://huggingface.co/istupakov/gigaam-v3-onnx/resolve/main
SILERO_URL := https://raw.githubusercontent.com/snakers4/silero-vad/master/src/silero_vad/data/silero_vad.onnx

.PHONY: all setup setup-sherpa setup-model generate build local run install smoke-settings clean dmg

all: setup generate build install

setup: setup-sherpa setup-model

setup-sherpa:
	@mkdir -p Frameworks
	@if [ ! -d "Frameworks/sherpa-onnx.xcframework" ]; then \
		echo "==> Скачиваю sherpa-onnx $(SHERPA_VER)..."; \
		curl -# -L -o /tmp/sherpa-onnx.tar.bz2 "$(SHERPA_URL)"; \
		tar -xjf /tmp/sherpa-onnx.tar.bz2 -C /tmp; \
		cp -R /tmp/$(SHERPA_TMP)/sherpa-onnx.xcframework Frameworks/; \
		rm -rf /tmp/sherpa-onnx.tar.bz2 /tmp/$(SHERPA_TMP); \
		echo "==> sherpa-onnx.xcframework готов"; \
	else \
		echo "==> sherpa-onnx.xcframework уже есть, пропускаю"; \
	fi

setup-model:
	@mkdir -p $(MODEL_DST)
	@if [ ! -f "$(MODEL_DST)/gigaam_v3_e2e_rnnt_encoder_int8.onnx" ]; then \
		echo "==> Скачиваю GigaAM v3 encoder (~300 МБ)..."; \
		curl -# -L -o "$(MODEL_DST)/gigaam_v3_e2e_rnnt_encoder_int8.onnx" "$(GIGAAM_HF)/v3_e2e_rnnt_encoder.int8.onnx"; \
	else \
		echo "==> GigaAM encoder уже есть"; \
	fi
	@if [ ! -f "$(MODEL_DST)/gigaam_v3_e2e_rnnt_decoder.onnx" ]; then \
		curl -# -L -o "$(MODEL_DST)/gigaam_v3_e2e_rnnt_decoder.onnx"       "$(GIGAAM_HF)/v3_e2e_rnnt_decoder.onnx"; \
	fi
	@if [ ! -f "$(MODEL_DST)/gigaam_v3_e2e_rnnt_joint.onnx" ]; then \
		curl -# -L -o "$(MODEL_DST)/gigaam_v3_e2e_rnnt_joint.onnx"          "$(GIGAAM_HF)/v3_e2e_rnnt_joint.onnx"; \
	fi
	@if [ ! -f "$(MODEL_DST)/gigaam_v3_e2e_rnnt_tokens.txt" ]; then \
		curl -# -L -o "$(MODEL_DST)/gigaam_v3_e2e_rnnt_tokens.txt"          "$(GIGAAM_HF)/v3_e2e_rnnt_vocab.txt"; \
	fi
	@if [ ! -f "$(MODEL_DST)/silero_vad.onnx" ]; then \
		echo "==> Скачиваю Silero VAD..."; \
		curl -# -L -o "$(MODEL_DST)/silero_vad.onnx" "$(SILERO_URL)"; \
	fi
	@echo "==> Модели готовы"

generate: setup
	@echo "==> Generating Xcode project..."
	xcodegen generate
	@echo "==> Patching pbxproj (sherpa-onnx + resources)..."
	python3 patch_project.py

build: generate
	@echo "==> Building Говорун (Debug)..."
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

local: generate
	@echo "==> Building Говорун (unsigned) → ~/Downloads..."
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		CONFIGURATION_BUILD_DIR=$(HOME)/Downloads
	@echo "==> Done: ~/Downloads/Говорун.app"

install:
	@echo "==> Устанавливаю в /Applications..."
	@pkill -x "Говорун" 2>/dev/null || true
	@sleep 0.5
	@cp -R $(BUILD_DIR)/Build/Products/Debug/Говорун.app /Applications/
	@echo "==> Запускаю..."
	@open /Applications/Говорун.app

smoke-settings: build
	@bash scripts/smoke_settings_cpu.sh

run:
	@open $(BUILD_DIR)/Build/Products/Debug/Говорун.app 2>/dev/null || \
	 open $(HOME)/Downloads/Говорун.app

dmg:
	@bash scripts/make_dmg.sh

clean:
	rm -rf $(BUILD_DIR) Govorun.xcodeproj
