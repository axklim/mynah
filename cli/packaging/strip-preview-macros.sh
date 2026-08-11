#!/bin/sh
#
# Remove the #Preview blocks from the KeyboardShortcuts checkout so that mynah-bar builds on a
# machine that has only the Command Line Tools.
#
# Why this exists: KeyboardShortcuts ends Recorder.swift with three `#Preview` blocks guarded
# only by `#if os(macOS)`, so they compile in every configuration, release included. The
# `Preview` macro is *declared* in SwiftUI (which the CLT SDK ships) but *implemented* by
# libPreviewsMacros.dylib, which exists only inside Xcode. Without this patch, building the app
# fails with "plugin for module 'PreviewsMacros' not found" and every user who wants the
# menu-bar app needs ~10 GB of Xcode. See mynah-vault/Findings/preview-macro-needs-xcode.md.
#
# We never use KeyboardShortcuts.Recorder, so the previews are dead code here and dropping them
# changes nothing about the app.
#
# Editing a dependency's source is only safe if we know exactly which source it is, so the
# version is pinned twice: Package.swift requires KeyboardShortcuts `exact: "1.17.0"`, and the
# checksum below is that release's Recorder.swift. Bump the dependency and this script fails
# loudly rather than mangling a file it does not recognise.

set -eu

CHECKOUTS="${1:?usage: strip-preview-macros.sh <path to .build/checkouts>}"
REC="$CHECKOUTS/KeyboardShortcuts/Sources/KeyboardShortcuts/Recorder.swift"
PRISTINE_SHA256=7cfc11e6613134dea303c1356af0107ecbabf819a855a169575b262daea6c9ae

if [ ! -f "$REC" ]; then
	echo "strip-preview-macros: no checkout at $REC — run 'swift package resolve' first" >&2
	exit 1
fi

# Idempotent on purpose: `make app` runs this on every build and the checkout persists between
# builds, so the second run finds nothing to do.
if ! grep -q '^#Preview' "$REC"; then
	exit 0
fi

actual=$(shasum -a 256 "$REC" | cut -d ' ' -f 1)
if [ "$actual" != "$PRISTINE_SHA256" ]; then
	cat >&2 <<EOF
strip-preview-macros: Recorder.swift is not the file this patch was written against.
  expected sha256: $PRISTINE_SHA256
  actual   sha256: $actual

KeyboardShortcuts was probably bumped past 1.17.0. Read the end of
  $REC
check that the #Preview blocks are still the only Xcode-only construct in it, then update
PRISTINE_SHA256 in this script.
EOF
	exit 1
fi

# The previews sit at the tail of the file, inside the `#if os(macOS)` that closes it. Print
# everything up to the first one, holding back `@available` lines because one decorates each
# preview, then close the conditional the previews were sitting inside.
awk '
	/^#Preview/   { exit }
	/^@available/ { held = held $0 "\n"; next }
	              { printf "%s", held; held = ""; print }
	END           { print "#endif" }
' "$REC" >"$REC.stripped"

# SwiftPM leaves its checkouts read-only.
chmod u+w "$REC"
mv "$REC.stripped" "$REC"

echo "strip-preview-macros: dropped the #Preview blocks from KeyboardShortcuts/Recorder.swift"
