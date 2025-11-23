from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field, validator
from typing import List, Optional, Union
import base64
import time
import os
import traceback

from .model import generate_from_prompts, DiffusionModel
from .logger2 import get_logger

from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response

logger = get_logger("inference")
app = FastAPI(title="SDXL-Turbo Inference")

# Prometheus metrics
INFER_REQ = Counter("inference_requests_total", "Total inference requests")
INFER_DUR = Histogram("inference_duration_seconds", "Inference latency in seconds")


SUPPORTED_IMAGE_FORMATS = {"JPEG", "JPG", "PNG", "WEBP"}
SUPPORTED_RESPONSE_FORMATS = {"json", "binary"}


class PredictRequest(BaseModel):
    prompt: Union[str, List[str]]
    num_inference_steps: Optional[int] = Field(8, ge=1, le=150)
    width: Optional[int] = Field(1024, ge=64, le=2048)
    height: Optional[int] = Field(1024, ge=64, le=2048)

    image_format: Optional[str] = "JPEG"
    response_format: Optional[str] = "json"

    @validator("image_format")
    def validate_image_format(cls, v):
        if not v:
            return "JPEG"
        v = v.upper()
        if v not in SUPPORTED_IMAGE_FORMATS:
            raise ValueError(f"Invalid image_format. Supported: {SUPPORTED_IMAGE_FORMATS}")
        return "JPEG" if v == "JPG" else v  # Normalize JPG → JPEG

    @validator("response_format")
    def validate_output_format(cls, v):
        if not v:
            return "json"
        v = v.lower()
        if v not in SUPPORTED_RESPONSE_FORMATS:
            raise ValueError(f"Invalid response_format. Supported: {SUPPORTED_RESPONSE_FORMATS}")
        return v


@app.on_event("startup")
async def startup_event():
    DiffusionModel.get_pipe()
    logger.info("Model loaded on startup")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/predict")
def predict(req: PredictRequest):
    INFER_REQ.inc()
    start = time.time()

    prompts = [req.prompt] if isinstance(req.prompt, str) else req.prompt
    if not prompts:
        raise HTTPException(400, "`prompt` is required")

    if len(prompts) > int(os.environ.get("MAX_BATCH", "4")):
        raise HTTPException(400, f"Batch size exceeds MAX_BATCH={os.environ.get('MAX_BATCH', '4')}")

    try:
        images = generate_from_prompts(
            prompts,
            steps=req.num_inference_steps,
            width=req.width,
            height=req.height,
            fmt=req.image_format,
        )
    except Exception as e:
        logger.error("Generation failed: %s\n%s", e, traceback.format_exc())
        raise HTTPException(500, f"Generation failed: {e}")

    elapsed = time.time() - start
    INFER_DUR.observe(elapsed)

    # ---- Binary Return ----
    if req.response_format == "binary":
        if len(images) > 1:
            raise HTTPException(400, "Binary mode only supports a single image.")
    
        return Response(
            images[0],
            media_type=f"image/{req.image_format.lower()}",
            headers={"Content-Disposition": f'attachment; filename="generated.{req.image_format.lower()}"'}
        )

    # ---- Base64 JSON Response ----
    encoded = [base64.b64encode(b).decode("utf-8") for b in images]

    return {
        "images": encoded if len(encoded) > 1 else encoded[0],
        "elapsed_seconds": elapsed
    }
