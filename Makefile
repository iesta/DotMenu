SWIFT_SRCS = src/main.swift src/VersionGenerated.swift
INFO_PLIST = src/Info.plist
ICON = src/AppIcon.icns
VERSION_FILE = src/version.txt

PRODUCT = DotMenu
APP = $(PRODUCT).app
APPS_DIR = /Applications

swift_flags = -framework AppKit -framework SwiftUI -target arm64-apple-macosx14.0

.PHONY: build clean install run dmg generate_version

generate_version:
	@version=$$(cat $(VERSION_FILE)); \
	echo "let appVersion = \"$$version\"" > src/VersionGenerated.swift

build: $(APP)

$(APP): generate_version $(INFO_PLIST) $(ICON) src/main.swift
	rm -rf "$@"
	mkdir -p "$@/Contents/MacOS" "$@/Contents/Resources"
	swiftc -o "$@/Contents/MacOS/$(PRODUCT)" src/main.swift src/VersionGenerated.swift $(swift_flags)
	@version=$$(cat $(VERSION_FILE)); \
	new_version=$$(printf "%05d" $$((10#$$version + 1))); \
	echo "$$new_version" > $(VERSION_FILE)
	cp $(INFO_PLIST) "$@/Contents/"
	cp $(ICON) "$@/Contents/Resources/"
	codesign -f -s - --requirements '=designated => identifier "com.example.DotMenu"' "$@"

install: build
	-killall $(PRODUCT) 2>/dev/null
	sleep 2
	/bin/rm -rf "$(APPS_DIR)/$(APP)"
	cp -R "$(APP)" "$(APPS_DIR)/"
	open "$(APPS_DIR)/$(APP)"

run: build
	open "$(APP)"

dmg: build
	rm -f $(PRODUCT).dmg
	mkdir -p /tmp/dotmenu-dmg
	cp -R "$(APP)" /tmp/dotmenu-dmg/
	ln -s $(APPS_DIR) /tmp/dotmenu-dmg/Applications
	hdiutil create -volname "$(PRODUCT)" -srcfolder /tmp/dotmenu-dmg -ov -format UDZO "$(PRODUCT).dmg"
	rm -rf /tmp/dotmenu-dmg

clean:
	rm -rf "$(APP)" build/ src/VersionGenerated.swift