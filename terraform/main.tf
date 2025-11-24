terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.32.0"
    }
  }

  required_version = ">= 1.3.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# First: Try to read repo (will fail gracefully if not found)
data "google_artifact_registry_repository" "existing_repo" {
  project  = var.project_id
  location = var.region
  repository_id = var.artifact_repo

  depends_on = []
}

# Create repo **only if it does not already exist**
resource "google_artifact_registry_repository" "repo" {
  count = length(data.google_artifact_registry_repository.existing_repo.repository_id) > 0 ? 0 : 1

  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_repo
  format        = "DOCKER"
  description   = "Stable Diffusion inference container repo"
}

# Unified reference to repo name — works for both new or existing
locals {
  artifact_repo_id = (
    length(data.google_artifact_registry_repository.existing_repo.repository_id) > 0 ?
    data.google_artifact_registry_repository.existing_repo.repository_id :
    google_artifact_registry_repository.repo[0].repository_id
  )
}

# Create Vertex AI Endpoint
resource "google_vertex_ai_endpoint" "endpoint" {
  name         = "vertex-${var.endpoint_display_name}-${var.project_id}"
  display_name = var.endpoint_display_name
  location     = var.region

  lifecycle {
    prevent_destroy = true
  }
}

# Upload Model
resource "null_resource" "register_model" {
  # force a new registration when CI pushes a new image
  triggers = { build_ts = timestamp() }

  provisioner "local-exec" {
    command = <<'EOT'
set -euo pipefail
# environment variables from Terraform: var.region, var.image_uri, var.model_display_name
echo "=== Model register: starting ==="
echo "Region: ${var.region}"
echo "Image URI: ${var.image_uri}"

# helper
retry_cmd() {
  local tries=0
  local max_tries=${1:-3}
  shift
  until "$@"; do
    tries=$((tries+1))
    if [ "$tries" -ge "$max_tries" ]; then
      return 1
    fi
    echo "Command failed, retrying ($tries/$max_tries) ..."
    sleep $((5 * tries))
  done
  return 0
}

MODEL_NAME="${var.model_display_name}-$(date +%s)"
UPLOAD_JSON="upload_response.json"
UPLOAD_ERR="upload_error.log"

echo "Uploading model with display name: $MODEL_NAME"

# try up to 3 times (adjust if needed)
if ! retry_cmd 3 gcloud ai models upload \
   --region="${var.region}" \
   --display-name="${MODEL_NAME}" \
   --container-image-uri="${var.image_uri}" \
   --container-predict-route="/predict" \
   --container-health-route="/health" \
   --format="json" > "${UPLOAD_JSON}" 2> "${UPLOAD_ERR}"; then
  echo "ERROR: gcloud upload failed after retries. Dumping logs:"
  echo "==== STDERR ===="
  sed -n '1,200p' "${UPLOAD_ERR}" || true
  echo "==== UPLOAD JSON (if any) ===="
  sed -n '1,200p' "${UPLOAD_JSON}" || true
  # show gcloud version and auth account to help debug
  echo "==== gcloud info ===="
  gcloud --version || true
  gcloud auth list || true
  exit 1
fi

# parse model name (resource name) from JSON
MODEL_ID=$(jq -r '.[0].name // .name // ""' "${UPLOAD_JSON}" 2>/dev/null || true)
# fallback: try parsing top-level name
if [ -z "$MODEL_ID" ] || [ "$MODEL_ID" = "null" ]; then
  MODEL_ID=$(jq -r '.name // ""' "${UPLOAD_JSON}" 2>/dev/null || true)
fi

if [ -z "$MODEL_ID" ] || [ "$MODEL_ID" = "null" ]; then
  echo "ERROR: upload returned no model id. Dumping logs:"
  echo "---- stderr ----"
  sed -n '1,200p' "${UPLOAD_ERR}" || true
  echo "---- upload json ----"
  sed -n '1,200p' "${UPLOAD_JSON}" || true
  echo "gcloud version:"
  gcloud --version || true
  exit 2
fi

echo "✔ Model registered: $MODEL_ID"
echo "$MODEL_ID" > model_id.txt
chmod 0644 model_id.txt
EOT
  }
}

# Deploy Model to Endpoint
resource "null_resource" "deploy_model" {
  depends_on = [
    null_resource.register_model,
    null_resource.create_endpoint
  ]

  triggers = { deploy_ts = timestamp() }

  provisioner "local-exec" {
    command = <<'EOT'
set -euo pipefail
echo "=== Deploy model: starting ==="

MODEL_ID_FILE="model_id.txt"
ENDPOINT_ID_FILE="endpoint_id.txt"
DEPLOY_RESP="deploy_response.json"
DEPLOY_ERR="deploy_error.log"

if [ ! -f "${MODEL_ID_FILE}" ]; then
  echo "ERROR: ${MODEL_ID_FILE} not found."
  exit 1
fi
if [ ! -f "${ENDPOINT_ID_FILE}" ]; then
  echo "ERROR: ${ENDPOINT_ID_FILE} not found."
  exit 1
fi

MODEL_ID=$(cat "${MODEL_ID_FILE}" | tr -d '[:space:]')
ENDPOINT_ID=$(cat "${ENDPOINT_ID_FILE}" | tr -d '[:space:]')

if [ -z "$MODEL_ID" ] || [ "$MODEL_ID" = "null" ]; then
  echo "ERROR: invalid MODEL_ID: '$MODEL_ID'"
  exit 2
fi
if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
  echo "ERROR: invalid ENDPOINT_ID: '$ENDPOINT_ID'"
  exit 2
fi

echo "Model: $MODEL_ID"
echo "Endpoint: $ENDPOINT_ID"

# ensure the model exists (describe)
if ! gcloud ai models describe "$MODEL_ID" --region="${var.region}" --format="value(name)" >/dev/null 2>&1; then
  echo "ERROR: model $MODEL_ID not found via gcloud. Aborting."
  gcloud ai models list --region="${var.region}" --filter="displayName:${var.model_display_name}" --format="table(name,displayName)" || true
  exit 3
fi

# deploy and capture response JSON (tries + check)
set +e
TRIES=0
MAX_TRIES=3
while [ $TRIES -lt $MAX_TRIES ]; do
  TRIES=$((TRIES+1))
  echo "Deployment attempt $TRIES/$MAX_TRIES..."
  # note: use --format=json and quiet to capture a structured response
  gcloud ai endpoints deploy-model "$ENDPOINT_ID" \
    --region="${var.region}" \
    --model="$MODEL_ID" \
    --display-name="sdxl-deployment-$(date +%s)" \
    --machine-type="${var.machine_type}" \
    --accelerator="type=${var.accelerator_type},count=${var.accelerator_count}" \
    --min-replica-count=${var.min_replica_count} \
    --max-replica-count=${var.max_replica_count} \
    --traffic-split=0=100 \
    --quiet \
    --format="json" > "${DEPLOY_RESP}" 2> "${DEPLOY_ERR}"
  RC=$?
  if [ $RC -eq 0 ]; then
    break
  fi
  echo "Deploy failed (rc=$RC). Dumping stderr (tail):"
  tail -n +1 "${DEPLOY_ERR}" || true
  sleep $((10 * TRIES))
done
set -e

# parse deployed model id
DEPLOYED_ID=$(jq -r '.[0].id // .deployedModels[0].id // .id // ""' "${DEPLOY_RESP}" 2>/dev/null || true)
if [ -z "$DEPLOYED_ID" ] || [ "$DEPLOYED_ID" = "null" ]; then
  echo "ERROR: Deployment response did not contain deployed model id. Dumping files:"
  echo "---- deploy stderr ----"
  sed -n '1,200p' "${DEPLOY_ERR}" || true
  echo "---- deploy json ----"
  sed -n '1,200p' "${DEPLOY_RESP}" || true
  exit 4
fi

echo "✔ Deployed model id: $DEPLOYED_ID"
echo "$DEPLOYED_ID" > deployed_model_id.txt
chmod 0644 deployed_model_id.txt
EOT
  }
}
