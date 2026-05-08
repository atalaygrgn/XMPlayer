# Makefile for XMPlayer muOS build

BUILD_DIR = build
APP_NAME = XMPlayer
DIST_DIR = $(BUILD_DIR)/$(APP_NAME)
PACKAGE_FILE = $(BUILD_DIR)/$(APP_NAME).muxapp
POWERSHELL = powershell -NoProfile -Command

.PHONY: all clean build package

all: package

build:
	@echo "Resetting dist directory..."
	@$(POWERSHELL) "if (Test-Path '$(DIST_DIR)') { Remove-Item -Path '$(DIST_DIR)' -Recurse -Force }"

	@echo "Creating build structure..."
	@$(POWERSHELL) "New-Item -ItemType Directory -Force -Path '$(DIST_DIR)' | Out-Null"
	
	@echo "Copying .xmplayer directory..."
	@$(POWERSHELL) "Copy-Item -Path '.\.xmplayer' -Destination '$(DIST_DIR)\.xmplayer' -Recurse -Force"
	
	@echo "Copying glyph folder..."
	@$(POWERSHELL) "Copy-Item -Path '.\glyph' -Destination '$(DIST_DIR)\glyph' -Recurse -Force"
	
	@echo "Copying launch scripts and configs..."
	@$(POWERSHELL) "Copy-Item -Path '.\mux_launch.sh' -Destination '$(DIST_DIR)\' -Force"
	@$(POWERSHELL) "Copy-Item -Path '.\mux_lang.ini' -Destination '$(DIST_DIR)\' -Force"
	@$(POWERSHELL) "$$_content = [System.IO.File]::ReadAllText('$(DIST_DIR)/mux_launch.sh'); $$_content = $$_content -replace \"`r`n\", \"`n\"; [System.IO.File]::WriteAllText('$(DIST_DIR)/mux_launch.sh', $$_content, (New-Object System.Text.UTF8Encoding($$false)))"
	
	@echo "Build successful! Output located at $(DIST_DIR)"


package: build
	@echo "Creating $(PACKAGE_FILE)..."
	@$(POWERSHELL) "if (Test-Path '$(PACKAGE_FILE)') { Remove-Item -Path '$(PACKAGE_FILE)' -Force }"
	@$(POWERSHELL) "if (Test-Path '$(BUILD_DIR)/package_stage') { Remove-Item -Path '$(BUILD_DIR)/package_stage' -Recurse -Force }"
	@$(POWERSHELL) "New-Item -ItemType Directory -Force -Path '$(BUILD_DIR)/package_stage' | Out-Null"
	@$(POWERSHELL) "New-Item -ItemType Directory -Force -Path '$(BUILD_DIR)/package_stage/$(APP_NAME)' | Out-Null"
	@$(POWERSHELL) "Copy-Item -Path '$(DIST_DIR)/*' -Destination '$(BUILD_DIR)/package_stage/$(APP_NAME)' -Recurse -Force"
	@$(POWERSHELL) "$$zip = '$(BUILD_DIR)/$(APP_NAME).zip'; if (Test-Path $$zip) { Remove-Item -Path $$zip -Force }; Compress-Archive -Path '$(BUILD_DIR)/package_stage/*' -DestinationPath $$zip -Force"
	@$(POWERSHELL) "Move-Item -Path '$(BUILD_DIR)/$(APP_NAME).zip' -Destination '$(PACKAGE_FILE)' -Force"
	@$(POWERSHELL) "Remove-Item -Path '$(BUILD_DIR)/package_stage' -Recurse -Force"
	@echo "Package ready: $(PACKAGE_FILE)"

clean:
	@echo "Cleaning up build directory..."
	@$(POWERSHELL) "Remove-Item -Path '$(BUILD_DIR)' -Recurse -Force -ErrorAction SilentlyContinue"
