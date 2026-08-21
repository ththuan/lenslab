import os
import threading
import urllib.request
from pathlib import Path

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response


APP_NAME = "LensLab GFPGAN Retouch Service"
MODEL_URL = os.getenv(
    "LENS_AI_MODEL_URL",
    "https://github.com/TencentARC/GFPGAN/releases/download/v1.3.0/GFPGANv1.4.pth",
)
MODEL_DIR = Path(os.getenv("LENS_AI_MODEL_DIR", Path(__file__).parent / "models"))
MODEL_PATH = MODEL_DIR / "GFPGANv1.4.pth"
API_TOKEN = os.getenv("LENS_AI_TOKEN", "").strip()
MAX_UPLOAD_MB = int(os.getenv("LENS_AI_MAX_UPLOAD_MB", "40"))
ALLOWED_ORIGINS = [
    item.strip()
    for item in os.getenv("LENS_AI_ALLOWED_ORIGINS", "*").split(",")
    if item.strip()
]

app = FastAPI(title=APP_NAME, version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "X-LensLab-Token"],
    expose_headers=["X-LensLab-Model"],
)

_model = None
_model_lock = threading.Lock()
_inference_lock = threading.Lock()


def require_token(authorization: str | None, x_lenslab_token: str | None) -> None:
    if not API_TOKEN:
        return
    bearer = ""
    if authorization and authorization.lower().startswith("bearer "):
        bearer = authorization[7:].strip()
    if API_TOKEN not in (bearer, (x_lenslab_token or "").strip()):
        raise HTTPException(status_code=401, detail="Invalid AI service token")


def download_model() -> None:
    if MODEL_PATH.exists() and MODEL_PATH.stat().st_size > 1_000_000:
        return
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    temporary_path = MODEL_PATH.with_suffix(".download")
    try:
        urllib.request.urlretrieve(MODEL_URL, temporary_path)
        temporary_path.replace(MODEL_PATH)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def get_model():
    global _model
    if _model is not None:
        return _model
    with _model_lock:
        if _model is not None:
            return _model
        download_model()
        try:
            from gfpgan import GFPGANer
        except ImportError as exc:
            raise RuntimeError("GFPGAN is not installed; install requirements.txt") from exc
        _model = GFPGANer(
            model_path=str(MODEL_PATH),
            upscale=1,
            arch="clean",
            channel_multiplier=2,
            bg_upsampler=None,
        )
        return _model


def decode_image(payload: bytes) -> np.ndarray:
    encoded = np.frombuffer(payload, dtype=np.uint8)
    image = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
    if image is None or image.size == 0:
        raise HTTPException(status_code=400, detail="Uploaded file is not a supported image")
    return image


def encode_jpeg(image: np.ndarray) -> bytes:
    ok, encoded = cv2.imencode(".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, 96])
    if not ok:
        raise HTTPException(status_code=500, detail="Could not encode model output")
    return encoded.tobytes()


@app.get("/health")
def health(
    authorization: str | None = Header(default=None),
    x_lenslab_token: str | None = Header(default=None),
):
    require_token(authorization, x_lenslab_token)
    get_model()
    try:
        import torch

        device = "cuda" if torch.cuda.is_available() else "cpu"
    except ImportError:
        device = "unknown"
    return {
        "ok": True,
        "name": APP_NAME,
        "model": "GFPGANv1.4",
        "model_downloaded": MODEL_PATH.exists(),
        "device": device,
    }


@app.post("/v1/retouch")
def retouch(
    image: UploadFile = File(...),
    strength: float = Form(0.55),
    face_fidelity: float = Form(0.72),
    upscale: int = Form(1),
    authorization: str | None = Header(default=None),
    x_lenslab_token: str | None = Header(default=None),
):
    require_token(authorization, x_lenslab_token)
    payload = image.file.read(MAX_UPLOAD_MB * 1024 * 1024 + 1)
    if len(payload) > MAX_UPLOAD_MB * 1024 * 1024:
        raise HTTPException(status_code=413, detail=f"Image exceeds {MAX_UPLOAD_MB} MB")

    source = decode_image(payload)
    strength = float(np.clip(strength, 0.0, 1.0))
    face_fidelity = float(np.clip(face_fidelity, 0.0, 1.0))
    upscale = int(np.clip(upscale, 1, 4))
    model = get_model()

    with _inference_lock:
        model.upscale = upscale
        _, _, restored = model.enhance(
            source,
            has_aligned=False,
            only_center_face=False,
            paste_back=True,
            weight=face_fidelity,
        )

    if restored is None:
        restored = source
    if restored.shape[:2] != source.shape[:2]:
        source_for_blend = cv2.resize(source, (restored.shape[1], restored.shape[0]))
    else:
        source_for_blend = source
    output = cv2.addWeighted(restored, strength, source_for_blend, 1.0 - strength, 0.0)
    return Response(
        content=encode_jpeg(output),
        media_type="image/jpeg",
        headers={
            "X-LensLab-Model": "GFPGANv1.4",
            "Cache-Control": "no-store",
        },
    )
