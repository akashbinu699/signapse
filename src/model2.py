# src/model.py
import os
import io
from typing import List
from functools import wraps

import torch
from diffusers import StableDiffusionXLPipeline
from cachetools import TTLCache, cached
from PIL import Image
from .logger import get_logger

logger = get_logger("model")

# Configuration via env
MODEL_ID = os.environ.get("HF_MODEL_ID", "stabilityai/sdxl-turbo")
DEVICE = os.environ.get("MODEL_DEVICE", "cuda")
# model dtype: float16 recommended for GPU
MODEL_TORCH_DTYPE = os.environ.get("MODEL_TORCH_DTYPE", "float16")
DTYPE = torch.float16 if MODEL_TORCH_DTYPE == "float16" else torch.float32

WARMUP_PROMPT = os.environ.get("WARMUP_PROMPT", "warmup")
WARMUP_STEPS = int(os.environ.get("WARMUP_STEPS", "1"))
MAX_BATCH = int(os.environ.get("MAX_BATCH", "4"))

# Caching
CACHE_TTL_SECONDS = int(os.environ.get("CACHE_TTL_SECONDS", "3600"))
CACHE_MAXSIZE = int(os.environ.get("CACHE_MAXSIZE", "512"))
cache = TTLCache(maxsize=CACHE_MAXSIZE, ttl=CACHE_TTL_SECONDS)

# Autocast toggle (0/1)
USE_AUTOCAST = os.environ.get("USE_AUTOCAST", "0") == "1"
# Optional acceleration flags
ENABLE_XFORMERS = os.environ.get("ENABLE_XFORMERS", "0") == "1"
ENABLE_CPU_OFFLOAD = os.environ.get("ENABLE_CPU_OFFLOAD", "0") == "1"


class DiffusionModel:
    """
    Singleton wrapper around the StableDiffusionXLPipeline.
    """
    _pipe: StableDiffusionXLPipeline | None = None

    @classmethod
    def get_pipe(cls) -> StableDiffusionXLPipeline:
        if cls._pipe is None:
            logger.info("Loading model: %s", MODEL_ID)
            # Load pipeline
            pipe = StableDiffusionXLPipeline.from_pretrained(
                MODEL_ID,
                torch_dtype=DTYPE,
            )

            # move to device
            pipe.to(DEVICE)

            # Try to enable optional optimizations
            try:
                pipe.enable_attention_slicing()
                pipe.enable_vae_tiling()
                logger.info("Enabled attention slicing & VAE tiling")
            except Exception:
                logger.debug("Slicing/tiling not available")

            if ENABLE_XFORMERS:
                try:
                    pipe.enable_xformers_memory_efficient_attention()
                    logger.info("xFormers memory efficient attention enabled")
                except Exception as e:
                    logger.warning("xFormers not available: %s", e)

            if ENABLE_CPU_OFFLOAD:
                try:
                    pipe.enable_model_cpu_offload()
                    logger.info("Enabled model CPU offload")
                except Exception as e:
                    logger.warning("Model CPU offload not enabled: %s", e)

            cls._pipe = pipe

            # Warmup
            cls._warmup()

        return cls._pipe

    @classmethod
    def _warmup(cls):
        logger.info("Warming up model with prompt=%s steps=%d", WARMUP_PROMPT, WARMUP_STEPS)
        try:
            # Use the safe minimal call — SDXL Turbo supports simple signature
            cls._pipe(WARMUP_PROMPT, num_inference_steps=max(1, WARMUP_STEPS))
            logger.info("Warmup complete")
        except Exception as e:
            logger.warning("Warmup failed: %s", e)


def _make_cache_key(prompt: str, steps: int, width: int, height: int, fmt: str) -> str:
    # include key elements; small normalization of prompt
    return f"{prompt.strip()[:200]}|s{steps}|{width}x{height}|{fmt}"


def _cache_decorator(func):
    """
    Wrap generation function so caching uses cachetools TTLCache with
    a deterministic key derived from inputs.
    """
    @wraps(func)
    def wrapper(prompt: str, steps: int, width: int, height: int, fmt: str = "JPEG"):
        key = _make_cache_key(prompt, steps, width, height, fmt)
        if key in cache:
            logger.info("Cache hit for key (prefix): %s", key[:80])
            return cache[key]
        img = func(prompt, steps, width, height, fmt)
        cache[key] = img
        return img
    return wrapper


@_cache_decorator
def _generate_raw(prompt: str, steps: int, width: int, height: int, fmt: str = "JPEG") -> bytes:
    """
    Low-level generation call (no cache). Uses the singleton pipeline.
    Returns image bytes (JPEG/PNG) ready to write.
    """
    pipe = DiffusionModel.get_pipe()
    logger.info("Generating prompt (len=%d) with steps=%d", len(prompt), steps)

    try:
        device = "cuda" if torch.cuda.is_available() else "cpu"
        with torch.inference_mode():
            if USE_AUTOCAST and device == "cuda":
                # autocast may be useful in some envs. Default OFF to avoid fp16 decode issues.
                with torch.autocast(device):
                    result = pipe(prompt=prompt, num_inference_steps=steps, width=width, height=height)
            else:
                result = pipe(prompt=prompt, num_inference_steps=steps, width=width, height=height)

        image = result.images[0].convert("RGB")

    except Exception as e:
        logger.error("Generation failed: %s", e)
        raise

    buffer = io.BytesIO()
    image.save(buffer, format=fmt, quality=90, optimize=True)
    return buffer.getvalue()


def generate_from_prompts(prompts: List[str], steps: int = 8, width: int = 1024, height: int = 1024, fmt: str = "JPEG") -> List[bytes]:
    """
    Batch-friendly wrapper. Accepts a list of prompts up to MAX_BATCH.
    Uses single forward call when possible.
    """
    if not prompts:
        return []

    if len(prompts) > MAX_BATCH:
        raise ValueError(f"Batch size {len(prompts)} exceeds MAX_BATCH={MAX_BATCH}")

    pipe = DiffusionModel.get_pipe()
    logger.info("Batch generation (size=%d)", len(prompts))

    try:
        device = "cuda" if torch.cuda.is_available() else "cpu"
        with torch.inference_mode():
            if USE_AUTOCAST and device == "cuda":
                with torch.autocast(device):
                    result = pipe(prompts, num_inference_steps=steps, width=width, height=height)
            else:
                result = pipe(prompts, num_inference_steps=steps, width=width, height=height)

        images = [im.convert("RGB") for im in result.images]

    except Exception as e:
        logger.error("Batch generation failed: %s", e)
        raise

    # Encode each to bytes
    out_bytes = []
    for img in images:
        buf = io.BytesIO()
        img.save(buf, format=fmt, quality=90, optimize=True)
        out_bytes.append(buf.getvalue())

    # store individual items in cache for future single prompt hits
    for p, b in zip(prompts, out_bytes):
        key = _make_cache_key(p, steps, width, height, fmt)
        cache[key] = b

    return out_bytes
