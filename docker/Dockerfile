FROM nvidia/cuda:12.3.0-devel-ubuntu22.04

RUN apt-get update && apt-get install -y python3 python3-pip git wget curl && apt-get clean

WORKDIR /app

COPY docker/requirements.txt .
RUN pip3 install --upgrade pip
RUN pip3 install -r requirements.txt

COPY src/ /app/src
COPY sagemaker/serve /usr/local/bin/serve
RUN chmod +x /usr/local/bin/serve

ENV PYTHONPATH=/app/src
ENV MODEL_DIR=/opt/ml/model

CMD ["serve"]
