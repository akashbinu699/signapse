# src/inference_handler.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from typing import List, Optional, Union
import base64
import time
import os

from .model import generate_from_prompts, DiffusionModel
from .logger import get_logger

from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response

logger = get_logger("inference")
app = FastAPI(title="SDXL-Turbo Inference")

# Prometheus metrics
INFER_REQ = Counter("inference_requests_total", "Total inference requests")
INFER_DUR = Histogram("inference_duration_seconds", "Inference latency in seconds")

class PredictRequest(BaseModel):
    prompt: Union[str, List[str]]
    num_inference_steps: Optional[int] = Field(8, ge=1, le=150)
    width: Optional[int] = Field(1024, ge=64, le=2048)
    height: Optional[int] = Field(1024, ge=64, le=2048)
    format: Optional[str] = Field("JPEG")

@app.on_event("startup")
async def startup_event():
    # Ensure model loaded at startup (not per-request)
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
        raise HTTPException(status_code=400, detail="`prompt` is required")

    if len(prompts) > int(os.environ.get("MAX_BATCH", "4")):
        raise HTTPException(status_code=400, detail=f"Batch size exceeds MAX_BATCH={os.environ.get('MAX_BATCH', '4')}")

    try:
        images = generate_from_prompts(prompts, steps=req.num_inference_steps, width=req.width, height=req.height, fmt=req.format)
    except Exception as e:
        logger.error("Generation failed: %s", e)
        raise HTTPException(status_code=500, detail=str(e))

    # encode
    encoded = [base64.b64encode(b).decode("utf-8") for b in images]
    elapsed = time.time() - start
    INFER_DUR.observe(elapsed)
    return {"images": encoded if len(encoded) > 1 else encoded[0], "elapsed_seconds": elapsed}
