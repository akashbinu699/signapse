import torch
from diffusers import StableDiffusionPipeline
from pathlib import Path
import time

def generate_image(prompt: str, output_path: str = "output.png"):
    print("Loading model… this may take a while…")

    pipe = StableDiffusionPipeline.from_pretrained(
        "stabilityai/sdxl-turbo",
        torch_dtype=torch.float16
    )
    pipe.to("cuda")

    torch.cuda.synchronize()

    print("Generating image...")
    result = pipe(prompt, num_inference_steps=8)

    image = result.images[0].convert("RGB")

    time.sleep(0.5)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path)
    print(f"Saved to {output_path}")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt", type=str, required=True)
    args = parser.parse_args()

    generate_image(args.prompt)
