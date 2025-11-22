#!/usr/bin/env bash
set -euo pipefail
echo "Starting inference server..."
exec uvicorn src.inference_handler:app --host 0.0.0.0 --port 8080 --workers 1