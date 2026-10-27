#!/usr/bin/env bash
# build.sh — Build Zebra without polluting the git working tree.
#
# How it works: rsync the source into a gitignored .build/ copy, then apply three
# kinds of mechanical substitutions in that copy:
#   A) @INSTALL_PREFIX @"..."   ->  jbroot(@"...")
#   B) INSTALL_PREFIX  "..."    ->  jbroot("...")     (plain C macro concat, incl. utils tools)
#   C) @"file://" @INSTALL_PREFIX @"..." -> [@"file://" stringByAppendingString:jbroot(@"...")]
#   Then auto-add #include to files that use jbroot but don't yet include
#   roothide.h, and finally build with theos.
#   The source tree stays untouched; these substitutions never show up in git status/diff.
#
# Usage:
#   ./build.sh [roothide|rootless|rootful]     # defaults to roothide
#   SKIP_BUILD=1 ./build.sh                    # only sync+substitute+audit, don't build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build}"
FLAVOR="${1:-roothide}"

case "$FLAVOR" in
  roothide) MAKE_ARGS="ROOTHIDE=1" ;;
  rootless) MAKE_ARGS="ROOTLESS=1" ;;
  *)        MAKE_ARGS="" ;;
esac

# Source file extensions to process.
SRC_EXT="-name '*.m' -o -name '*.mm' -o -name '*.c' -o -name '*.cpp' -o -name '*.h'"

echo "==> Syncing sources to $BUILD_DIR"
mkdir -p "$BUILD_DIR"
rsync -a --delete \
  --exclude='.git/' \
  --exclude='.theos/' \
  --exclude='.build/' \
  --exclude='packages/' \
  --exclude='Artwork/' \
  --exclude='docs/' \
  --exclude='.github/' \
  --exclude='.DS_Store' \
  --exclude='xcuserdata/' \
  "$ROOT/" "$BUILD_DIR/"

echo "==> Mechanically substituting INSTALL_PREFIX path concatenation"
# Only walk Zebra/ and utils/ (roothide.h, Makefile, etc. are build machinery and are skipped).
FILES=$(cd "$BUILD_DIR" && eval "find Zebra utils -type f \( $SRC_EXT \)")

CHANGED=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  fpath="$BUILD_DIR/$f"
  before=$(shasum "$fpath" | awk '{print $1}')

  # C) @"file://" @INSTALL_PREFIX @"..." -> [@"file://" stringByAppendingString:jbroot(@"...")]
  perl -pi -e 's/\@"file:\/\/"[ \t]*\@INSTALL_PREFIX[ \t]+\@("([^"]*)")/[\@"file:\/\/" stringByAppendingString:jbroot(\@$1)]/g' "$fpath"
  # A) @INSTALL_PREFIX @"..." -> jbroot(@"...")
  perl -pi -e 's/\@INSTALL_PREFIX[ \t]+\@("([^"]*)")/jbroot(\@$1)/g' "$fpath"
  # B) INSTALL_PREFIX "..." -> jbroot("...")   (negative lookbehind, to avoid touching the @ form above)
  perl -pi -e 's/(?<!\@)INSTALL_PREFIX[ \t]+("([^"]*)")/jbroot($1)/g' "$fpath"

  after=$(shasum "$fpath" | awk '{print $1}')
  if [ "$before" != "$after" ]; then
    CHANGED=$((CHANGED+1))
    printf '  substituted: %s\n' "$f"
    if ! grep -qE '#(include|import)[ \t]*[<"]roothide\.h' "$fpath"; then
      perl -0pi -e 'if(!m{#\s*(?:include|import)[ \t]*[<"]roothide\.h}){ s{(#\s*(?:include|import)[^\n]*\n)}{#include <roothide.h>\n$1} or s{\A}{#include <roothide.h>\n} }' "$fpath"
      printf '    added #include <roothide.h>\n'
    fi
  fi
done <<< "$FILES"

[ "$CHANGED" -eq 0 ] && echo "  (no INSTALL_PREFIX paths needed substitution)"

echo
echo "==> Remaining INSTALL_PREFIX after substitution (whole-copy sources)"
grep -rn 'INSTALL_PREFIX' \
  --include='*.m' --include='*.mm' --include='*.c' --include='*.cpp' --include='*.h' \
  "$BUILD_DIR" 2>/dev/null \
  | sed "s|$BUILD_DIR/||" || echo "  (none)"

if [ -n "${SKIP_BUILD:-}" ]; then
  echo
  echo "SKIP_BUILD=1, skipping build (copy is ready)."
  exit 0
fi

# ---- theos environment: prefer an existing env var, otherwise try common install paths ----
if [ -z "${THEOS:-}" ]; then
  for p in "$HOME/theos" /opt/theos /var/theos; do
    if [ -d "$p" ]; then
      export THEOS="$p"
      export PATH="$THEOS/bin:$PATH"
      break
    fi
  done
fi
if [ -z "${THEOS:-}" ]; then
  echo "Error: theos not found. Please set the THEOS environment variable." >&2
  exit 1
fi

echo
echo "==> Building ($FLAVOR): make package $MAKE_ARGS"
# Must compile inside the copy (xcodebuild's -project is a relative path).
cd "$BUILD_DIR"
# shellcheck disable=SC2086
make package $MAKE_ARGS

echo
echo "Done. Artifacts in: $BUILD_DIR/packages/"