#!/usr/bin/env bash
# Required Notice: Copyright 2026 stop-loss-enjoyer
# Plainlines is source-available under the PolyForm Shield License 1.0.0.
#
# Linux under Wine only (on Windows compile in MetaEditor, see "Build from source" in MANUAL.md).
# Copies MetaEditor64.exe and MQL5/Include from a MetaTrader 5 installed under Wine
# into a local tool folder (default ~/.local/share/plainlines-build), so that ./build.sh
# compiles with the same build as that terminal. Point PLAINLINES_MT5_DIR at the
# "MetaTrader 5" folder of your own demo terminal; the default is the author's demo prefix.
# No real-account terminal prefix is ever read.
# These files belong to MetaQuotes and must never enter this repository.
# The source is only read (cp), nothing is ever written into it.
# Idempotent: existing files are kept unless --force is given.
set -euo pipefail

SRC="${PLAINLINES_MT5_DIR:-$HOME/.local/share/wineprefixes/plainlines-demo/drive_c/Program Files/MetaTrader 5}"
DEST="${PLAINLINES_BUILD_DIR:-$HOME/.local/share/plainlines-build}"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

case "$DEST" in *" "*) echo "error: destination path must not contain spaces: $DEST" >&2; exit 1;; esac
[[ -f "$SRC/MetaEditor64.exe" ]] || { echo "error: $SRC/MetaEditor64.exe not found, refusing to run" >&2; exit 1; }
[[ -d "$SRC/MQL5/Include" ]] || { echo "error: $SRC/MQL5/Include not found, refusing to run" >&2; exit 1; }

mkdir -p "$DEST/MQL5"
chmod -R u+w "$DEST" 2>/dev/null || true
if [[ ! -f "$DEST/MetaEditor64.exe" || $FORCE -eq 1 ]]; then
  cp -f "$SRC/MetaEditor64.exe" "$DEST/MetaEditor64.exe"
  echo "copied MetaEditor64.exe"
else
  echo "MetaEditor64.exe already present (use --force to refresh)"
fi
if [[ ! -d "$DEST/MQL5/Include" || $FORCE -eq 1 ]]; then
  rm -rf "$DEST/MQL5/Include"
  cp -r "$SRC/MQL5/Include" "$DEST/MQL5/Include"
  echo "copied MQL5/Include"
else
  echo "MQL5/Include already present (use --force to refresh)"
fi
# Read-only so a build can never alter the persistent copy by accident.
chmod -R a-w "$DEST/MetaEditor64.exe" "$DEST/MQL5/Include"
echo "ready: $DEST"
echo "MetaEditor FileVersion: $(strings -el "$DEST/MetaEditor64.exe" 2>/dev/null | grep -A1 '^FileVersion$' | tail -1)"
