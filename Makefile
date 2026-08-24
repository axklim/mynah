# Mynah — build & install the CLI (cli/ SwiftPM package)
PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
PKGDIR := cli
BIN    := mynah
APP    := Mynah
APPBIN := mynah-bar
APPDIR := $(PKGDIR)/dist/$(APP).app
PLISTIN := $(PKGDIR)/packaging/Info.plist.in

# The version's home is the git tag, not a file in the tree — scripts/version.sh explains
# how it gets from there to here, and MYNAH_VERSION overrides it. Every build stamps that
# one value into both MynahVersion.swift and the bundle's Info.plist, so the binary and
# the bundle can never disagree. Nothing is bumped by hand. See Decision 0013.
VERSION = $(shell scripts/version.sh)

# Extra flags for `swift build`. Empty for normal development — SwiftPM's own sandbox
# around manifest compilation is worth keeping locally. The Homebrew formula passes
# `--disable-sandbox`, because a brew build already runs inside a sandbox and nesting
# sandbox-exec fails with "Invalid manifest".
SWIFT_FLAGS ?=

.PHONY: help build test install uninstall clean app run-app version stamp formula
.DEFAULT_GOAL := help

help:
	@echo "Targets:"
	@echo "  make install     build release and install mynah to $(BINDIR)"
	@echo "  make build       build the release binary (no install)"
	@echo "  make test        run the swift test suite"
	@echo "  make uninstall   remove the installed binary"
	@echo "  make clean       remove build artifacts"
	@echo "  make app         build the menu-bar app bundle (dist/Mynah.app)"
	@echo "  make run-app     build the app bundle and open it"
	@echo "  make version     print the version (single source: the git tag)"
	@echo "  make formula     render the Homebrew formula (needs VERSION= and SHA256=)"

version:
	@echo $(VERSION)

# Scoped to the CLI product on purpose. Building every target here would also compile
# MynahBar and its KeyboardShortcuts dependency, which needs full Xcode (see the vault
# Finding preview-macro-needs-xcode) — the CLI itself builds with the CLT alone.
build: stamp
	cd $(PKGDIR) && swift build -c release --product $(BIN) $(SWIFT_FLAGS)

test: stamp
	cd $(PKGDIR) && swift test

# Write the resolved version into MynahVersion.swift. A no-op when it already says that,
# so it costs no rebuild.
stamp:
	@scripts/stamp-version.sh

# Render the Homebrew formula. SHA256 is the checksum of the release asset, so only the
# release workflow has a real one to pass.
formula:
	@scripts/render-formula.sh $(VERSION) $(SHA256)

install: build
	mkdir -p $(BINDIR)
	install -m 0755 $(PKGDIR)/.build/release/$(BIN) $(BINDIR)/$(BIN)
	@echo ""
	@echo "✅ installed $(BIN) -> $(BINDIR)/$(BIN)"
	@echo ""
	@echo "Try it:"
	@echo "  $(BIN) check \"i has finished the task and it works good\""
	@echo "  pbpaste | $(BIN) check"
	@echo ""
	@echo "(make sure $(BINDIR) is on your PATH)"

uninstall:
	rm -f $(BINDIR)/$(BIN)
	@echo "removed $(BINDIR)/$(BIN)"

app: stamp ## build the menu-bar app bundle (dist/Mynah.app)
	@test -n "$(VERSION)" || { echo "error: scripts/version.sh printed nothing"; exit 1; }
	cd $(PKGDIR) && swift build -c release --product $(APPBIN) $(SWIFT_FLAGS)
	rm -rf $(APPDIR)
	mkdir -p $(APPDIR)/Contents/MacOS
	cp $(PKGDIR)/.build/release/$(APPBIN) $(APPDIR)/Contents/MacOS/$(APP)
	sed 's/__VERSION__/$(VERSION)/' $(PLISTIN) > $(APPDIR)/Contents/Info.plist
	codesign --force --sign - $(APPDIR)
	@echo ""
	@echo "✅ built $(APPDIR) (version $(VERSION))"
	@echo "   open it:  make run-app   (or double-click in Finder)"
	@echo "   hotkey:   ⌃⌥⌘C (Hyper+C) checks the clipboard"

run-app: app
	open $(APPDIR)

clean:
	cd $(PKGDIR) && swift package clean
	rm -rf $(APPDIR)
