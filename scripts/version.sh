#!/bin/sh
# Print the version. The version's home is the git tag, not a file in the tree.
#
# A source tarball carries the tag: GitHub builds it with `git archive`, which expands
# the $Format: placeholder in .git_archival.txt to the tag name (see .gitattributes). A
# plain checkout leaves that placeholder literal and has no tag to speak of, so it builds
# as "0.0.0-dev" — MYNAH_VERSION overrides that, which is how the release workflow builds
# and verifies the artifacts before the tag it will derive from exists.
#
# scripts/stamp-version.sh generates cli/Sources/MynahCore/MynahVersion.swift from this
# script, and `make app` stamps the same value into Info.plist, so the CLI, the bundle and
# the formula can never disagree about which version is installed.
set -eu

cd "$(dirname "$0")/.."

if [ -n "${MYNAH_VERSION:-}" ]; then
    echo "$MYNAH_VERSION"
    exit 0
fi

# Unexpanded the line reads "describe-name: $Format:...$", which fails the v-prefix test
# below and falls through — the same as no file at all.
DESCRIBED=$(sed -n 's/^describe-name: *//p' .git_archival.txt 2>/dev/null || true)
case "$DESCRIBED" in
v[0-9]*)
    echo "${DESCRIBED#v}"
    exit 0
    ;;
esac

echo "0.0.0-dev"
