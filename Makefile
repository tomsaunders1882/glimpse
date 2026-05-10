APP_NAME  := Glimpse
BUILD_DIR := .build/release
APP_DIR   := $(APP_NAME).app
IDENTITY  ?= Glimpse Dev

.PHONY: all build bundle run clean

all: bundle

build:
	swift build -c release

bundle: build
	@rm -rf $(APP_DIR)
	@mkdir -p $(APP_DIR)/Contents/MacOS
	@mkdir -p $(APP_DIR)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_DIR)/Contents/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(APP_DIR)/Contents/Info.plist
	@if security find-identity -v -p codesigning | grep -q "\"$(IDENTITY)\""; then \
		echo "Signing with '$(IDENTITY)'..."; \
		codesign --force --deep --sign "$(IDENTITY)" $(APP_DIR); \
	else \
		echo "WARN: '$(IDENTITY)' identity not found — using ad-hoc signing."; \
		echo "      You'll be re-prompted for your keychain password on each rebuild."; \
		echo "      Run scripts/setup-cert.sh to fix this."; \
		codesign --force --deep --sign - $(APP_DIR); \
	fi
	@echo "Built $(APP_DIR)"

run: bundle
	@open $(APP_DIR)

clean:
	rm -rf .build $(APP_DIR)
