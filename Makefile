# Spell Checker — build & install the CLI (cli/ SwiftPM package)
PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
PKGDIR := cli
BIN    := spell-checker
APP    := SpellChecker
APPBIN := spell-checker-bar
APPDIR := $(PKGDIR)/dist/$(APP).app
PLIST  := $(PKGDIR)/packaging/Info.plist

.PHONY: help build install uninstall clean app run-app
.DEFAULT_GOAL := help

help:
	@echo "Targets:"
	@echo "  make install     build release and install spell-checker to $(BINDIR)"
	@echo "  make build       build the release binary (no install)"
	@echo "  make uninstall   remove the installed binary"
	@echo "  make clean       remove build artifacts"
	@echo "  make app         build the menu-bar app bundle (dist/SpellChecker.app)"
	@echo "  make run-app     build the app bundle and open it"

build:
	cd $(PKGDIR) && swift build -c release

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

app: ## build the menu-bar app bundle (dist/SpellChecker.app)
	cd $(PKGDIR) && swift build -c release --product $(APPBIN)
	rm -rf $(APPDIR)
	mkdir -p $(APPDIR)/Contents/MacOS
	cp $(PKGDIR)/.build/release/$(APPBIN) $(APPDIR)/Contents/MacOS/$(APP)
	cp $(PLIST) $(APPDIR)/Contents/Info.plist
	codesign --force --sign - $(APPDIR)
	@echo ""
	@echo "✅ built $(APPDIR)"
	@echo "   open it:  make run-app   (or double-click in Finder)"
	@echo "   hotkey:   ⌃⌥C checks the clipboard"

run-app: app
	open $(APPDIR)

clean:
	cd $(PKGDIR) && swift package clean
	rm -rf $(APPDIR)
