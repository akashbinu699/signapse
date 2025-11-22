#########################
# STAGE 1 — BASE GPU
#########################
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/app/.cache/huggingface \
    MODEL_DIR=/opt/ml/model \
    PYTHONPATH=/app/src \
    TZ=Etc/UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv python3-distutils \
    curl ca-certificates git wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app


#########################
# STAGE 2 — DEPENDENCIES
#########################
FROM base AS builder

COPY requirements.txt /tmp/requirements.txt

RUN pip3 install --upgrade pip wheel setuptools \
    && pip3 wheel -r /tmp/requirements.txt -w /tmp/wheels


#########################
# STAGE 3 — FINAL RUNTIME
#########################
FROM base AS runtime

COPY --from=builder /tmp/wheels /tmp/wheels
RUN pip3 install /tmp/wheels/*.whl && rm -rf /tmp/wheels

RUN rm -rf /usr/share/man/* /usr/share/doc/* /usr/share/locale/* || true

COPY src/ /app/src

# --- Deployment entrypoint ---
COPY sagemaker/serve.sh /usr/local/bin/serve
RUN chmod +x /usr/local/bin/serve

# Cache directory
RUN mkdir -p /opt/ml/model /app/.cache/huggingface && chmod -R 777 /app

# Reduce image size
RUN find / -name "*.so" -exec strip -s {} + || true || echo "strip skipped"

EXPOSE 8080

CMD ["serve"]
