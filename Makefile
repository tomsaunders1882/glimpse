APP_NAME  := Glimpse
BUILD_DIR := .build/release
APP_DIR   := $(APP_NAME).app
IDENTITY  ?= Glimpse Dev

ICON_SRC  := Resources/AppIcon.png
ICON_OUT  := Resources/AppIcon.icns
ICONSET   := Resources/AppIcon.iconset

.PHONY: all build bundle run clean icon

all: bundle

build:
	swift build -c release

icon: $(ICON_OUT)

$(ICON_OUT): $(ICON_SRC)
	@rm -rf $(ICONSET)
	@mkdir -p $(ICONSET)
	@for size in 16 32 64 128 256 512 1024; do \
		sips -z $$size $$size $(ICON_SRC) --out $(ICONSET)/_$$size.png >/dev/null; \
	done
	@cp $(ICONSET)/_16.png   $(ICONSET)/icon_16x16.png
	@cp $(ICONSET)/_32.png   $(ICONSET)/icon_16x16@2x.png
	@cp $(ICONSET)/_32.png   $(ICONSET)/icon_32x32.png
	@cp $(ICONSET)/_64.png   $(ICONSET)/icon_32x32@2x.png
	@cp $(ICONSET)/_128.png  $(ICONSET)/icon_128x128.png
	@cp $(ICONSET)/_256.png  $(ICONSET)/icon_128x128@2x.png
	@cp $(ICONSET)/_256.png  $(ICONSET)/icon_256x256.png
	@cp $(ICONSET)/_512.png  $(ICONSET)/icon_256x256@2x.png
	@cp $(ICONSET)/_512.png  $(ICONSET)/icon_512x512.png
	@cp $(ICONSET)/_1024.png $(ICONSET)/icon_512x512@2x.png
	@rm $(ICONSET)/_*.png
	iconutil -c icns -o $(ICON_OUT) $(ICONSET)
	@rm -rf $(ICONSET)
	@echo "Built $(ICON_OUT)"

bundle: build $(ICON_OUT)
	@rm -rf $(APP_DIR)
	@mkdir -p $(APP_DIR)/Contents/MacOS
	@mkdir -p $(APP_DIR)/Contents/Resources
	@cp $(BUILD_DIR)/$(APP_NAME) $(APP_DIR)/Contents/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(APP_DIR)/Contents/Info.plist
	@cp $(ICON_OUT) $(APP_DIR)/Contents/Resources/AppIcon.icns
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
	rm -rf .build $(APP_DIR) $(ICON_OUT) $(ICONSET)
