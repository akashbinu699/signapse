# src/app.py
import argparse
from pathlib import Path
from .model2 import generate_from_prompts
from .logger2 import get_logger

logger = get_logger("app")

def generate_image(prompt: str, output_path: str = "output.jpg", steps: int = 8):
    logger.info("Generating image — prompt='%s' steps=%d", prompt, steps)
    images = generate_from_prompts([prompt], steps=steps)
    if not images:
        logger.error("No image returned")
        return
    image_bytes = images[0]
    out = Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "wb") as f:
        f.write(image_bytes)
    logger.info("Saved image to %s", output_path)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt", type=str, required=True)
    parser.add_argument("--out", type=str, default="output.jpg")
    parser.add_argument("--steps", type=int, default=8)
    args = parser.parse_args()
    generate_image(args.prompt, args.out, args.steps)

if __name__ == "__main__":
    main()
