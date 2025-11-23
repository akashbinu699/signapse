# 🚀 Scalable SDXL Inference Service on Google Cloud

This repository contains a fully optimized and production-grade deployment of **Stable Diffusion XL** for high-performance image generation on GPU infrastructure.  
Originally based on an intentionally slow codebase, this project improves model inference, containerization, infrastructure automation, and CI/CD.

---

## 📌 Features

| Capability | Status |
|-----------|--------|
| GPU-accelerated SDXL inference | ✅ |
| Mixed precision (`torch.autocast`) | ✅ |
| Model warmup & caching | ✅ |
| Batch inference support | ✅ |
| Optimized Docker container | ✅ |
| GitHub Actions CI/CD | ✅ |
| Deployment to Google Cloud Vertex AI | ✅ |
| Automated Terraform infrastructure | ✅ |
| Test script to validate deployment | ✅ |

---

## 🧠 Model Improvements

The original inference code suffered from:

- Model reloading on every request  
- No GPU memory optimization  
- Slow FP32 inference  
- No warmup  
- No batching or caching support  
- Inefficient output encoding  
- Blocking CPU operations  

### ✔ Key Optimizations Applied

| Improvement | Benefit |
|------------|---------|
| Model moved out of request path | Eliminates repeated loading overhead |
| `torch.inference_mode()` | Reduces unnecessary graph tracking |
| Automatic mixed precision (`torch.autocast`) | Faster inference, 50–70% memory savings |
| Attention slicing + VAE tiling | Enables large images on smaller GPUs |
| Cache for repeated prompts | Fast repeat results |
| Batch inference support | Efficient GPU utilization |
| JPEG conversion + streaming response | Faster I/O |

#### 🔧 Special Fix: Black Image Issue

Stable Diffusion XL produced **black images** when using FP16 VAE.  
Solution: load the corrected VAE:

```python
vae = AutoencoderKL.from_pretrained(
    "madebyollin/sdxl-vae-fp16-fix",
    torch_dtype=torch.float16
)
```
Architecture Overview
User → FastAPI → SDXL Pipeline → GPU → Output (PNG/JPEG/ZIP)
                   │
                   └── Cache (TTL + prompt hashing)


Run Locally Via Docker
```sh
docker build -t sdxl-inference .
docker run --gpus all \
    -p 8082:8080 \
    -v $(pwd):/app \
    -e HF_HOME=/app/.cache/huggingface \
    -e USE_AUTOCAST=1 \
    sdxl-inference
```

API Usage
Generate Single Image
```sh
curl -o output.jpg -X POST http://localhost:8082/predict \
  -H "Content-Type: application/json" \
  -d '{"prompt": "a futuristic floating city"}'
```

Batch Request
```sh
curl -o batch.zip \
  -H "Content-Type: application/json" \
  -H "Accept: application/zip" \
  -d '{"prompt": ["cat", "dog", "robot"], "num_inference_steps": 4}' \
  http://localhost:8082/predict
```

GitHub Actions CI/CD Workflow

Pipeline responsibilities:

✔ Build Docker image
✔ Push to Artifact Registry
✔ Terraform deploy
✔ Vertex AI model + endpoint creation
✔ Integration test against live endpoint

Workflow file: .github/workflows/deploy.yaml

Smoke Test (After Deployment)
```python
python tests/test_inference.py --endpoint $VERTEX_ENDPOINT
```
