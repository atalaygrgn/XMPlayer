# Makefile for XMPlayer muOS build

BUILD_DIR = build
APP_NAME = XMPlayer
DIST_DIR = $(BUILD_DIR)/$(APP_NAME)

.PHONY: all clean build

all: build

build:
	@echo "Creating build structure..."
	@mkdir -p $(DIST_DIR)
	
	@echo "Copying .xmplayer directory..."
	@cp -R .xmplayer $(DIST_DIR)/
	
	@echo "Copying glyph folder..."
	@cp -R glyph $(DIST_DIR)/glyph
	
	@echo "Copying launch scripts and configs..."
	@cp mux_launch.sh $(DIST_DIR)/
	@cp mux_lang.ini $(DIST_DIR)/
	
	@echo "Build successful! Output located at $(DIST_DIR)"

clean:
	@echo "Cleaning up build directory..."
	@rm -rf $(BUILD_DIR)
