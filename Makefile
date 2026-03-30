APP_NAME  := zydock
BUILD_DIR := app/build
APP_PATH  := $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app

.PHONY: build run install clean

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
	rm -rf $(BUILD_DIR)
