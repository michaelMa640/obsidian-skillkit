#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIPPER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_DIR="${CLIPPER_DIR}/.venv-mac-local"
PYTHON_BIN="${VENV_DIR}/bin/python"
PIP_BIN="${VENV_DIR}/bin/pip"
PIP_INDEX_URL_DEFAULT="https://pypi.tuna.tsinghua.edu.cn/simple"
PIP_INDEX_URL="${PIP_INDEX_URL:-${PIP_INDEX_URL_DEFAULT}}"

echo "[setup] clipper dir: ${CLIPPER_DIR}"
echo "[setup] venv dir   : ${VENV_DIR}"
echo "[setup] pip index  : ${PIP_INDEX_URL}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[error] This script is only for macOS." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "[error] This script requires Apple Silicon (arm64)." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[error] python3 is required but was not found." >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "[error] Homebrew is required for ffmpeg installation." >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "[setup] ffmpeg not found, installing with Homebrew..."
  brew install ffmpeg
else
  echo "[setup] ffmpeg already present: $(command -v ffmpeg)"
fi

if [[ ! -d "${VENV_DIR}" ]]; then
  echo "[setup] creating venv..."
  python3 -m venv "${VENV_DIR}"
else
  echo "[setup] reusing existing venv."
fi

echo "[setup] upgrading pip toolchain..."
"${PYTHON_BIN}" -m pip install --index-url "${PIP_INDEX_URL}" --upgrade pip setuptools wheel

echo "[setup] installing Mac-local ASR dependencies..."
"${PIP_BIN}" install --index-url "${PIP_INDEX_URL}" \
  mlx-whisper \
  opencc-python-reimplemented

echo "[setup] installing Mac-local diarization dependencies..."
"${PIP_BIN}" install --index-url "${PIP_INDEX_URL}" \
  pyannote.audio \
  av \
  scikit-learn

echo "[setup] probing installed packages..."
"${PYTHON_BIN}" - <<'PY'
import importlib

modules = [
    "mlx",
    "mlx_whisper",
    "opencc",
    "torch",
    "pyannote.audio",
    "av",
    "sklearn",
]

for name in modules:
    try:
        importlib.import_module(name)
        print(f"[ok] {name}")
    except Exception as exc:
        print(f"[missing] {name}: {exc}")
PY

cat <<EOF
[setup] completed.

Next steps:
1. Activate the venv:
   source "${VENV_DIR}/bin/activate"
2. Export a Hugging Face token before diarization:
   export HF_TOKEN="your_token_here"
3. Accept the gated model terms:
   https://huggingface.co/pyannote/speaker-diarization-community-1
4. Optional model-download acceleration:
   export HF_ENDPOINT="https://hf-mirror.com"
EOF
