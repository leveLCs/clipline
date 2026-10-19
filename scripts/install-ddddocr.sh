#!/bin/bash
# Install a private Python and ddddocr runtime; never change system Python.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v uv >/dev/null || { echo 'Install uv first (https://docs.astral.sh/uv/).'; exit 1; }
umask 077
OCR_ROOT="${1:-$HOME/Library/Application Support/Clipline/OCR}"
export UV_PYTHON_INSTALL_DIR="$OCR_ROOT/python"
mkdir -p "$OCR_ROOT"
uv --no-config python install --no-bin 3.13
OCR_ENV="$OCR_ROOT/ddddocr-1.6.1"
if [ ! -x "$OCR_ENV/bin/python3" ]; then
  uv --no-config venv --managed-python --python 3.13 "$OCR_ENV"
fi
uv --no-config pip install --python "$OCR_ENV/bin/python3" --only-binary :all: \
  --default-index https://pypi.org/simple -r scripts/ddddocr-requirements.txt
"$OCR_ENV/bin/python3" -I -B - "$PWD/Sources/Clipline/Resources/ddddocr_worker.py" <<'PY'
import io, json, subprocess, sys
from PIL import Image, ImageDraw, ImageFont
image = Image.new("RGB", (180, 60), "white")
ImageDraw.Draw(image).text((8, 4), "1234", fill="black", font=ImageFont.load_default(size=44))
png = io.BytesIO()
image.save(png, format="PNG")
result = subprocess.run([sys.executable, "-I", "-B", sys.argv[1]], input=png.getvalue(),
                        capture_output=True, check=True, timeout=15)
assert json.loads(result.stdout)["text"] == "1234", "ddddocr smoke test failed"
print("ddddocr runtime ready: " + sys.executable)
PY
