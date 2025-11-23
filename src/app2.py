import argparse
from pathlib import Path
from .model2 import generate_from_prompts
from .logger2 import get_logger

logger = get_logger("app")

OUTPUT_DIR = Path("/app/outputs")

def generate_image(prompt: str, output_path: str = None, steps: int = 8):
    logger.info("Generating image — prompt='%s' steps=%d", prompt, steps)

    images = generate_from_prompts([prompt], steps=steps)
    if not images:
        logger.error("No image returned")
        return

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    filename = output_path or f"{prompt[:30].replace(' ','_')}.jpg"
    out = OUTPUT_DIR / filename

    with open(out, "wb") as f:
        f.write(images[0])

    logger.info("Saved image to %s", out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt", type=str, required=True)
    parser.add_argument("--out", type=str, default=None)
    parser.add_argument("--steps", type=int, default=8)
    args = parser.parse_args()

    generate_image(args.prompt, args.out, args.steps)


if __name__ == "__main__":
    main()
