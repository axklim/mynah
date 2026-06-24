# Spell Checker — build & install the CLI (cli/ SwiftPM package)
PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
PKGDIR := cli
BIN    := spell-checker

.PHONY: help build install uninstall clean
.DEFAULT_GOAL := help

help:
	@echo "Targets:"
	@echo "  make install     build release and install spell-checker to $(BINDIR)"
	@echo "  make build       build the release binary (no install)"
	@echo "  make uninstall   remove the installed binary"
	@echo "  make clean       remove build artifacts"

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

clean:
	cd $(PKGDIR) && swift package clean
