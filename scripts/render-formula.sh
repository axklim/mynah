#!/bin/sh
# Render packaging/mynah.rb.tmpl to stdout as a Homebrew formula.
#
# The checksum is an argument rather than something this script computes, because it is
# the checksum of the release asset — which the release workflow builds, hashes and
# uploads. Rendering here rather than sed-patching a copy in the tap keeps the formula
# reviewable in the repository it describes.
set -eu

cd "$(dirname "$0")/.."

VERSION="${1:-}"
SHA256="${2:-}"

if [ -z "$VERSION" ] || [ -z "$SHA256" ]; then
    echo "usage: scripts/render-formula.sh <version> <sha256>" >&2
    exit 2
fi

echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
    echo "render-formula.sh: version must be X.Y.Z, got '$VERSION'" >&2
    exit 1
}
echo "$SHA256" | grep -Eq '^[0-9a-f]{64}$' || {
    echo "render-formula.sh: sha256 must be 64 hex characters, got '$SHA256'" >&2
    exit 1
}

OUT=$(sed -e "s|@VERSION@|$VERSION|g" -e "s|@SHA256@|$SHA256|g" packaging/mynah.rb.tmpl)

# A placeholder that survived substitution is a formula pointing at nothing. Better to
# fail here than to push it to the tap.
case "$OUT" in
*@VERSION@* | *@SHA256@*)
    echo "render-formula.sh: unresolved placeholder in the rendered formula" >&2
    exit 1
    ;;
esac

printf '%s\n' "$OUT"
