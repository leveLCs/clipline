"""Read one PNG from stdin and emit one JSON result; no image files or network."""
import contextlib
import json
import sys

with contextlib.redirect_stdout(sys.stderr):
    import onnxruntime

    onnxruntime.disable_telemetry_events()
    import ddddocr

    image = sys.stdin.buffer.read()
    if not image:
        raise ValueError("Missing image")
    # Keep the default model used in the comparison; no language conversion.
    text = ddddocr.DdddOcr(show_ad=False, use_gpu=False).classification(image)

print(json.dumps({"text": text}, ensure_ascii=True))
