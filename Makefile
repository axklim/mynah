# Mynah — build & install the CLI (cli/ SwiftPM package)
PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
PKGDIR := cli
BIN    := mynah
APP    := Mynah
APPBIN := mynah-bar
APPDIR := $(PKGDIR)/dist/$(APP).app
PLIST  := $(PKGDIR)/packaging/Info.plist

# Extra flags for `swift build`. Empty for normal development — SwiftPM's own sandbox
# around manifest compilation is worth keeping locally. The Homebrew formula passes
# `--disable-sandbox`, because a brew build already runs inside a sandbox and nesting
# sandbox-exec fails with "Invalid manifest".
SWIFT_FLAGS ?=

.PHONY: help build test install uninstall clean app run-app
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

# Scoped to the CLI product on purpose. Building every target here would also compile
# MynahBar and its KeyboardShortcuts dependency, which needs full Xcode (see the vault
# Finding preview-macro-needs-xcode) — the CLI itself builds with the CLT alone.
build:
	cd $(PKGDIR) && swift build -c release --product $(BIN) $(SWIFT_FLAGS)

test:
	cd $(PKGDIR) && swift test

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

app: ## build the menu-bar app bundle (dist/Mynah.app)
	cd $(PKGDIR) && swift build -c release --product $(APPBIN) $(SWIFT_FLAGS)
	rm -rf $(APPDIR)
	mkdir -p $(APPDIR)/Contents/MacOS
	cp $(PKGDIR)/.build/release/$(APPBIN) $(APPDIR)/Contents/MacOS/$(APP)
	cp $(PLIST) $(APPDIR)/Contents/Info.plist
	codesign --force --sign - $(APPDIR)
	@echo ""
	@echo "✅ built $(APPDIR)"
	@echo "   open it:  make run-app   (or double-click in Finder)"
	@echo "   hotkey:   ⌃⌥⌘C (Hyper+C) checks the clipboard"

run-app: app
	open $(APPDIR)

clean:
	cd $(PKGDIR) && swift package clean
	rm -rf $(APPDIR)
