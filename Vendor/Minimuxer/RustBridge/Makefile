TARGET=rust_bridge
RUST_DIR="."
SCHEME=Minimuxer
BUILD_DIR=lib
FRAMEWORK_NAME=Minimuxer

IPHONEOS_DEPLOYMENT_TARGET ?= 16.0
CFLAGS_aarch64_apple_ios ?= -miphoneos-version-min=$(IPHONEOS_DEPLOYMENT_TARGET)
CXXFLAGS_aarch64_apple_ios ?= -miphoneos-version-min=$(IPHONEOS_DEPLOYMENT_TARGET)
CFLAGS_aarch64_apple_ios_sim ?= -mios-simulator-version-min=$(IPHONEOS_DEPLOYMENT_TARGET)
CXXFLAGS_aarch64_apple_ios_sim ?= -mios-simulator-version-min=$(IPHONEOS_DEPLOYMENT_TARGET)
export IPHONEOS_DEPLOYMENT_TARGET
export CFLAGS_aarch64_apple_ios CXXFLAGS_aarch64_apple_ios
export CFLAGS_aarch64_apple_ios_sim CXXFLAGS_aarch64_apple_ios_sim

.PHONY: all build rust xcframework zip clean

# --- Core Build ---

all: build

build: rust

rust:
	@echo "--- Building Rust Bridge ---"

	@# iOS device (arm64)
	cd $(RUST_DIR) && cargo build --locked --target aarch64-apple-ios --release

	@# iOS Simulator (Apple Silicon)
	cd $(RUST_DIR) && cargo build --locked --target aarch64-apple-ios-sim --release


# --- XCFramework from static libs (no C headers needed — Swift uses @_silgen_name) ---

xcframework: rust
	@echo "--- Building RustBridge.xcframework ---"

	@# Empty headers dir required by xcodebuild -create-xcframework -library
	mkdir -p $(RUST_DIR)/lib/headers

	@# Remove stale xcframework
	rm -rf $(RUST_DIR)/lib/RustBridge.xcframework

	xcodebuild -create-xcframework \
		-library $(RUST_DIR)/target/aarch64-apple-ios/release/lib$(TARGET).a \
		-headers $(RUST_DIR)/lib/headers \
		-library $(RUST_DIR)/target/aarch64-apple-ios-sim/release/lib$(TARGET).a \
		-headers $(RUST_DIR)/lib/headers \
		-output $(RUST_DIR)/lib/RustBridge.xcframework

	@echo "--- Done: RustBridge/lib/RustBridge.xcframework ---"


# --- Cleanup ---

clean:
	@echo "--- Cleaning ---"
	cd $(RUST_DIR) && cargo clean
	rm -rf $(RUST_DIR)/lib
