APP_NAME   = AirKwotes
APP_ID     = ai.airkwotes.app
BUILD_DIR  = build
DIST_DIR   = dist
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
SOURCES    = $(shell find Sources -name '*.swift')
SDK        = $(shell xcrun --show-sdk-path)
ARCH       = $(shell uname -m)
SIGN_IDENTITY ?= AirKwotes Local Code Signing
VERSION    := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
DMG        = $(DIST_DIR)/$(APP_NAME)-$(VERSION).dmg
PLIST_BUDDY = /usr/libexec/PlistBuddy

.PHONY: all clean run sign bundle cert dmg dist-sha release notarize help

all: $(APP_BUNDLE)

# 1) Compile all Swift sources into a single executable
$(BUILD_DIR)/$(APP_NAME): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc \
		-sdk $(SDK) \
		-target $(ARCH)-apple-macos14 \
		-parse-as-library \
		-O -whole-module-optimization \
		-framework SwiftUI -framework AppKit -framework Security -framework UserNotifications -framework ServiceManagement -framework EventKit -framework CryptoKit -framework Network \
		$(SOURCES) \
		-o $(BUILD_DIR)/$(APP_NAME)

# 2) Assemble .app bundle
$(APP_BUNDLE): $(BUILD_DIR)/$(APP_NAME)
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist      $(APP_BUNDLE)/Contents/Info.plist
	printf 'APPL????'             > $(APP_BUNDLE)/Contents/PkgInfo
	-cp Resources/AirKwotes.entitlements $(APP_BUNDLE)/Contents/Resources/

sign: $(APP_BUNDLE)
	@if security find-identity -p codesigning 2>/dev/null | grep -q "$(SIGN_IDENTITY)"; then \
		echo "  signing with '$(SIGN_IDENTITY)'"; \
		codesign --force --deep --sign "$(SIGN_IDENTITY)" $(APP_BUNDLE); \
	else \
		echo "  WARNING: '$(SIGN_IDENTITY)' not found — signing ad-hoc."; \
		echo "          Keychain may prompt on every launch. Run 'make cert' for a stable identity."; \
		codesign --force --deep --sign - $(APP_BUNDLE); \
	fi

bundle: $(APP_BUNDLE) sign

cert:
	@bash scripts/make-cert.sh

# --- Distribution ----------------------------------------------------------
# Builds a .dmg of the signed .app. Unsigned/ad-hoc unless SIGN_IDENTITY is a
# real Developer ID. Uses hdiutil (built-in, no external dependency).
dmg: bundle
	@mkdir -p $(DIST_DIR)
	@rm -rf $(DIST_DIR)/staging $(DMG)
	@mkdir -p $(DIST_DIR)/staging
	@cp -R $(APP_BUNDLE) $(DIST_DIR)/staging/
	@ln -s /Applications $(DIST_DIR)/staging/Applications
	hdiutil create -volname "$(APP_NAME) $(VERSION)" \
		-srcfolder "$(DIST_DIR)/staging" -ov -format UDZO \
		-imagekey zlib-level=9 "$(DMG)" >/dev/null
	@rm -rf $(DIST_DIR)/staging
	@echo "Built $(DMG)"

dist-sha:
	@test -f $(DMG) || $(MAKE) dmg
	@shasum -a 256 $(DMG) | tee $(DIST_DIR)/$(APP_NAME)-$(VERSION).dmg.sha256

# Build everything needed for a GitHub Release asset.
release: dmg dist-sha
	@echo "Release artifacts in $(DIST_DIR)/"

# Notarization — no-op until an Apple Developer ID + secrets are configured.
# Configure via env: SIGN_IDENTITY, AC_TEAM_ID, AC_KEYCHAIN_PROFILE (notarytool).
notarize:
	@if [ -z "$$AC_TEAM_ID" ] || [ -z "$$AC_KEYCHAIN_PROFILE" ]; then \
		echo "notarize: set AC_TEAM_ID and AC_KEYCHAIN_PROFILE (xcrun notarytool keychain-profile) first."; \
		echo "  example: make notarize SIGN_IDENTITY='Developer ID Application: funkchi'"; \
		exit 2; \
	fi
	codesign --force --deep --options runtime --sign "$(SIGN_IDENTITY)" $(APP_BUNDLE)
	xcrun notarytool submit $(DMG) --keychain-profile "$$AC_KEYCHAIN_PROFILE" --wait
	xcrun stapler staple $(DMG)

run: bundle
	@echo "Launching $(APP_BUNDLE)"
	@open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR)

# Convenience: regenerate an Xcode project if you have xcodegen installed
xcode:
	@command -v xcodegen >/dev/null 2>&1 || { echo "Install: brew install xcodegen"; exit 1; }
	xcodegen generate

help:
	@echo "make            build the .app bundle"
	@echo "make bundle     build + codesign (stable identity if present, else ad-hoc)"
	@echo "make cert       create the local self-signed signing identity (one-time)"
	@echo "make run        build, sign and launch"
	@echo "make dmg        build + package a .dmg in dist/"
	@echo "make dist-sha   compute the .dmg sha256"
	@echo "make release    dmg + sha256"
	@echo "make notarize   Developer ID sign + notarytool (needs Apple secrets)"
	@echo "make clean      remove build/ and dist/"
	@echo "make xcode      regenerate AirKwotes.xcodeproj (needs xcodegen)"
