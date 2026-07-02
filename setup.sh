#!/usr/bin/env bash
#
# Deep-Live-Cam setup for macOS + Apple Silicon (M1/M2/M3/M4).
#
# Installs Python 3.11, creates a virtual environment, installs the Python
# dependencies, and downloads the two model files from Hugging Face.
#
# Usage:
#   ./setup.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VENV_DIR="$SCRIPT_DIR/venv"
MODELS_DIR="$SCRIPT_DIR/models"
HF_BASE="https://huggingface.co/hacksider/deep-live-cam/resolve/main"

# The two models this project needs on Apple Silicon:
#   - GFPGANv1.4.onnx    : face enhancer
#   - inswapper_128.onnx : face swapper (fp32; the CoreML path uses fp32, not fp16)
MODELS=(
  "GFPGANv1.4.onnx"
  "inswapper_128.onnx"
)

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# --- 0. Sanity checks ------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  die "This script targets macOS. Detected: $(uname -s)."
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  warn "Expected Apple Silicon (arm64) but detected $(uname -m). Continuing anyway."
fi

# --- 1. Homebrew + Python 3.11 --------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew is required but not installed. Install it from https://brew.sh and re-run."
fi

log "Installing Python 3.11 and Tk (GUI) via Homebrew..."
brew install python@3.11 python-tk@3.11

# ffmpeg is required at runtime. Only install it if it's missing so we don't
# clash with an existing install from a different tap (e.g. homebrew-ffmpeg).
if command -v ffmpeg >/dev/null 2>&1; then
  log "ffmpeg already installed: $(command -v ffmpeg)"
else
  log "Installing ffmpeg via Homebrew..."
  brew install ffmpeg
fi

# Resolve the python3.11 executable (Homebrew keg path first, then PATH).
PY311=""
for candidate in \
  "$(brew --prefix 2>/dev/null)/opt/python@3.11/bin/python3.11" \
  "$(command -v python3.11 || true)"; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    PY311="$candidate"
    break
  fi
done
[[ -n "$PY311" ]] || die "Could not locate python3.11 after installation."
log "Using Python: $PY311 ($("$PY311" --version 2>&1))"

# --- 2. Virtual environment ------------------------------------------------
# The venv MUST be Python 3.11. Newer versions (e.g. 3.13) pull in a
# tensorflow that conflicts with the pinned protobuf. We always drive pip
# through the venv's own versioned interpreter ($VENV_PY) rather than the
# bare `python`/`python3` symlinks, which tools like mise/pyenv can silently
# repoint at a different Python.
VENV_PY="$VENV_DIR/bin/python3.11"

venv_is_valid() {
  [[ -x "$VENV_PY" ]] || return 1
  "$VENV_PY" -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 11) else 1)' 2>/dev/null
}

if [[ -d "$VENV_DIR" ]]; then
  if venv_is_valid; then
    log "Reusing existing Python 3.11 virtual environment at $VENV_DIR"
  else
    warn "Existing venv is not a valid Python 3.11 environment; recreating it."
    rm -rf "$VENV_DIR"
  fi
fi

if [[ ! -d "$VENV_DIR" ]]; then
  log "Creating virtual environment at $VENV_DIR"
  "$PY311" -m venv "$VENV_DIR"
fi

venv_is_valid || die "Virtual environment at $VENV_DIR is not Python 3.11 after setup."

# --- 3. Python dependencies ------------------------------------------------
log "Upgrading pip and installing requirements (Python $("$VENV_PY" -V 2>&1 | awk '{print $2}'))..."
"$VENV_PY" -m pip install --upgrade pip
"$VENV_PY" -m pip install -r "$SCRIPT_DIR/requirements.txt"

# --- 4. Model downloads ----------------------------------------------------
mkdir -p "$MODELS_DIR"
for name in "${MODELS[@]}"; do
  dest="$MODELS_DIR/$name"
  if [[ -f "$dest" ]]; then
    log "Model already present, skipping: $name"
    continue
  fi
  log "Downloading $name ..."
  # Download to a temp file first so an interrupted download never leaves a
  # truncated model in place.
  tmp="$dest.part"
  curl -L --fail --retry 3 --retry-delay 2 -o "$tmp" "$HF_BASE/$name"
  mv "$tmp" "$dest"
done

log "Setup complete."
cat <<EOF

Next steps:
  ./run.sh            # launches Deep-Live-Cam with the CoreML provider

EOF
