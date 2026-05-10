APP_NAME      := zydock
BUILD_DIR     := app/build
APP_PATH      := $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app
DIST_DIR      := dist
RELEASE_APP   := $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app
DMG_PATH      := $(DIST_DIR)/$(APP_NAME).dmg

.PHONY: build run install clean dist

build:
	cd app && xcodegen generate
	xcodebuild -project app/$(APP_NAME).xcodeproj \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		build

run: build
	open "$(APP_PATH)"

install: build
	cp -R "$(APP_PATH)" /Applications/
	bash hooks/install.sh
	@echo "Installed to /Applications/$(APP_NAME).app"

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR)

# Build a Release .app, ad-hoc sign it, and package as a DMG for distribution.
# Requires: brew install create-dmg
dist:
	@command -v create-dmg >/dev/null || { echo "create-dmg not found. Run: brew install create-dmg"; exit 1; }
	cd app && xcodegen generate
	xcodebuild -project app/$(APP_NAME).xcodeproj \
		-scheme $(APP_NAME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		build
	codesign --deep --force --sign - "$(RELEASE_APP)"
	codesign --verify --verbose "$(RELEASE_APP)"
	mkdir -p $(DIST_DIR)
	rm -f "$(DMG_PATH)"
	create-dmg \
		--volname "$(APP_NAME)" \
		--window-size 500 300 \
		--icon-size 100 \
		--icon "$(APP_NAME).app" 130 130 \
		--app-drop-link 370 130 \
		"$(DMG_PATH)" \
		"$(RELEASE_APP)"
	@echo ""
	@echo "Built $(DMG_PATH)"
	@echo "Upload with: gh release create vX.Y.Z $(DMG_PATH)"
