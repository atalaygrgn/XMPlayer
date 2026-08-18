# Makefile for XMPlayer muOS build

BUILD_DIR = build
APP_NAME = XMPlayer
DIST_DIR = $(BUILD_DIR)/$(APP_NAME)
PACKAGE_FILE = $(BUILD_DIR)/$(APP_NAME).muxapp
POWERSHELL = powershell -NoProfile -Command

.PHONY: all clean build package portmaster

all: package portmaster

build:
	@echo "Resetting dist directory..."
	@$(POWERSHELL) "if (Test-Path '$(DIST_DIR)') { Remove-Item -Path '$(DIST_DIR)' -Recurse -Force }"

	@echo "Creating build structure..."
	@$(POWERSHELL) "New-Item -ItemType Directory -Force -Path '$(DIST_DIR)' | Out-Null"
	
	@echo "Copying .xmplayer directory..."
	@$(POWERSHELL) "Copy-Item -Path '.\.xmplayer' -Destination '$(DIST_DIR)\.xmplayer' -Recurse -Force"
	@echo "Excluding ffplay binary from muOS build..."
	@$(POWERSHELL) "if (Test-Path '$(DIST_DIR)\.xmplayer\bin\ffplay') { Remove-Item -Path '$(DIST_DIR)\.xmplayer\bin\ffplay' -Force }"
	
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
	@$(POWERSHELL) "tar -c --format zip -f '$(PACKAGE_FILE)' -C '$(BUILD_DIR)/package_stage' *"
	@$(POWERSHELL) "Remove-Item -Path '$(BUILD_DIR)/package_stage' -Recurse -Force"
	@echo "Package ready: $(PACKAGE_FILE)"

portmaster:
	@echo "Creating Portmaster build structure..."
	@$(POWERSHELL) "if (Test-Path '$(BUILD_DIR)/portmaster') { Remove-Item -Path '$(BUILD_DIR)/portmaster' -Recurse -Force }"
	@$(POWERSHELL) "New-Item -ItemType Directory -Force -Path '$(BUILD_DIR)/portmaster/xmplayer/gamedata' | Out-Null"
	
	@echo "Copying Love2D application files..."
	@$(POWERSHELL) "Copy-Item -Path '.\.xmplayer\*' -Destination '$(BUILD_DIR)\portmaster\xmplayer\gamedata' -Recurse -Force"
	
	@echo "Copying Portmaster-specific packaging files..."
	@$(POWERSHELL) "Copy-Item -Path '.\portmaster\XMPlayer.sh' -Destination '$(BUILD_DIR)\portmaster\' -Force"
	@$(POWERSHELL) "$$_content = [System.IO.File]::ReadAllText('$(BUILD_DIR)/portmaster/XMPlayer.sh'); $$_content = $$_content -replace \"`r`n\", \"`n\"; [System.IO.File]::WriteAllText('$(BUILD_DIR)/portmaster/XMPlayer.sh', $$_content, (New-Object System.Text.UTF8Encoding($$false)))"
	@$(POWERSHELL) "Copy-Item -Path '.\portmaster\port.json' -Destination '$(BUILD_DIR)\portmaster\xmplayer\' -Force"
	@$(POWERSHELL) "Copy-Item -Path '.\portmaster\gameinfo.xml' -Destination '$(BUILD_DIR)\portmaster\xmplayer\' -Force"
	@$(POWERSHELL) "Copy-Item -Path '.\portmaster\README.md' -Destination '$(BUILD_DIR)\portmaster\xmplayer\' -Force"
	@$(POWERSHELL) "Copy-Item -Path '.\portmaster\screenshot.png' -Destination '$(BUILD_DIR)\portmaster\xmplayer\' -Force"
	@$(POWERSHELL) "Copy-Item -Path '.\.xmplayer\config\xmplayer.gptk' -Destination '$(BUILD_DIR)\portmaster\xmplayer\xmplayer.gptk' -Force"
	@$(POWERSHELL) "Copy-Item -Path '.\portmaster\license' -Destination '$(BUILD_DIR)\portmaster\xmplayer\license' -Recurse -Force"
	
	@echo "Creating Portmaster package..."
	@$(POWERSHELL) "tar -a -c -f '$(BUILD_DIR)/XMPlayer-PortMaster.zip' -C '$(BUILD_DIR)/portmaster' *"
	@$(POWERSHELL) "Remove-Item -Path '$(BUILD_DIR)/portmaster' -Recurse -Force"
	@echo "PortMaster package ready: $(BUILD_DIR)/XMPlayer-PortMaster.zip"

clean:
	@echo "Cleaning up build directory..."
	@$(POWERSHELL) "Remove-Item -Path '$(BUILD_DIR)' -Recurse -Force -ErrorAction SilentlyContinue"
