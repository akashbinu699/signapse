from fastapi import FastAPI
from pydantic import BaseModel
import torch
from diffusers import StableDiffusionPipeline
import base64
from io import BytesIO
import time

app = FastAPI()

class Prompt(BaseModel):
    prompt: str


@app.post("/predict")
async def predict(data: Prompt):
    print("Loading model (per request!) ...")
    pipe = StableDiffusionPipeline.from_pretrained(
        "stabilityai/sdxl-turbo",
        torch_dtype=torch.float16
    ).to("cuda")

    torch.cuda.synchronize()

    result = pipe(data.prompt, num_inference_steps=10)

    image = result.images[0]

    time.sleep(1)

    buffer = BytesIO()
    image.save(buffer, format="PNG")
    encoded = base64.b64encode(buffer.getvalue()).decode("utf-8")

    return {"image": encoded}
