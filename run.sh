#!/usr/bin/env bash
#
# Launch Deep-Live-Cam on macOS + Apple Silicon using the CoreML
# (Apple Neural Engine) execution provider.
#
# Before launching, this verifies that every step performed by ./setup.sh has
# actually succeeded, and prints a clear message telling you what to run if
# something is missing.
#
# Any extra arguments are forwarded to run.py, e.g.:
#   ./run.sh --source face.jpg --target clip.mp4 --output out.mp4
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VENV_DIR="$SCRIPT_DIR/venv"
MODELS_DIR="$SCRIPT_DIR/models"
# The venv's versioned interpreter. The bare `python`/`python3` symlinks inside
# a venv can be repointed by tools like mise/pyenv, so we always invoke
# python3.11 explicitly to stay on the environment setup.sh created.
VENV_PY="$VENV_DIR/bin/python3.11"

# The two models setup.sh downloads (must match setup.sh).
REQUIRED_MODELS=(
  "GFPGANv1.4.onnx"
  "inswapper_128.onnx"
)

err() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }
hint() { printf '\033[1;33m   ->\033[0m %s\n' "$*" >&2; }

fail_needs_setup() {
  # $1 = what is wrong (one line)
  err "$1"
  hint "It looks like setup hasn't completed. From this folder, run:"
  hint "    ./setup.sh"
  hint "(see the CoreML / Apple Silicon section of README.md for details)"
  exit 1
}

# --- 1. Virtual environment exists and is Python 3.11 ----------------------
if [[ ! -d "$VENV_DIR" ]]; then
  fail_needs_setup "No virtual environment found at ./venv."
fi
if [[ ! -x "$VENV_PY" ]]; then
  fail_needs_setup "The ./venv exists but has no python3.11 interpreter ($VENV_PY)."
fi
if ! "$VENV_PY" -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 11) else 1)' 2>/dev/null; then
  actual="$("$VENV_PY" -V 2>&1 || true)"
  fail_needs_setup "The ./venv is not Python 3.11 (found: ${actual:-unknown})."
fi

# --- 2. Python dependencies are installed ----------------------------------
# Probe a representative set of the packages from requirements.txt. If any are
# missing, the environment wasn't fully installed.
missing_pkgs="$(
  "$VENV_PY" - <<'PY'
import importlib.util
# import name -> pip/display name
modules = {
    "cv2": "opencv-python",
    "onnx": "onnx",
    "onnxruntime": "onnxruntime",
    "insightface": "insightface",
    "numpy": "numpy",
    "PIL": "pillow",
    "PySide6": "PySide6",
    "tensorflow": "tensorflow",
    "tqdm": "tqdm",
}
missing = [name for mod, name in modules.items() if importlib.util.find_spec(mod) is None]
print(" ".join(missing))
PY
)"
if [[ -n "${missing_pkgs// /}" ]]; then
  fail_needs_setup "Python dependencies are missing from ./venv: ${missing_pkgs}."
fi

# --- 3. Required models are present ----------------------------------------
missing_models=()
for name in "${REQUIRED_MODELS[@]}"; do
  [[ -f "$MODELS_DIR/$name" ]] || missing_models+=("$name")
done
if (( ${#missing_models[@]} > 0 )); then
  fail_needs_setup "Missing model file(s) in ./models: ${missing_models[*]}."
fi

# --- 4. ffmpeg is available (required by modules/core.py pre_check) --------
if ! command -v ffmpeg >/dev/null 2>&1; then
  err "ffmpeg is not installed or not on your PATH."
  hint "Install it with Homebrew:"
  hint "    brew install ffmpeg"
  exit 1
fi

# --- All checks passed: launch --------------------------------------------
exec "$VENV_PY" run.py --execution-provider coreml "$@"
