#!/usr/bin/env bash

python3 -m uvicorn src.inference_handler:app --host 0.0.0.0 --port 8080
