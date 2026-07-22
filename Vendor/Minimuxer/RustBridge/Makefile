TARGET=rust_bridge
RUST_DIR=.
BUILD_DIR=lib
IOS_DEPLOYMENT_TARGET?=16.0
MACOS_DEPLOYMENT_TARGET?=11.0

.PHONY: all build test rust xcframework clean

all: test xcframework

build: rust

test:
	@echo "--- Testing Rust Bridge ---"
	cd $(RUST_DIR) && cargo test --lib

rust:
	@echo "--- Building Rust Bridge ---"

	@# iOS device (arm64)
	cd $(RUST_DIR) && IPHONEOS_DEPLOYMENT_TARGET=$(IOS_DEPLOYMENT_TARGET) \
		cargo build --target aarch64-apple-ios --release

	@# iOS Simulator (Apple Silicon)
	cd $(RUST_DIR) && IPHONEOS_DEPLOYMENT_TARGET=$(IOS_DEPLOYMENT_TARGET) \
		cargo build --target aarch64-apple-ios-sim --release

	@# macOS (arm64)
	cd $(RUST_DIR) && MACOSX_DEPLOYMENT_TARGET=$(MACOS_DEPLOYMENT_TARGET) \
		cargo build --target aarch64-apple-darwin --release

xcframework: rust
	@echo "--- Building RustBridge.xcframework ---"
	mkdir -p $(RUST_DIR)/lib/headers
	rm -rf $(RUST_DIR)/lib/RustBridge.xcframework
	xcodebuild -create-xcframework \
		-library $(RUST_DIR)/target/aarch64-apple-ios/release/lib$(TARGET).a \
		-headers $(RUST_DIR)/lib/headers \
		-library $(RUST_DIR)/target/aarch64-apple-ios-sim/release/lib$(TARGET).a \
		-headers $(RUST_DIR)/lib/headers \
		-library $(RUST_DIR)/target/aarch64-apple-darwin/release/lib$(TARGET).a \
		-headers $(RUST_DIR)/lib/headers \
		-output $(RUST_DIR)/lib/RustBridge.xcframework
	@echo "--- Done: RustBridge/lib/RustBridge.xcframework ---"

clean:
	@echo "--- Cleaning ---"
	cd $(RUST_DIR) && cargo clean
	rm -rf $(RUST_DIR)/lib
