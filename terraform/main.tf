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

# -------------------------
# Upload Model
# -------------------------
resource "null_resource" "register_model" {
  depends_on = [google_artifact_registry_repository.repo]

  triggers = {
    build_id = var.image_tag
  }

  provisioner "local-exec" {
    command = <<EOF
echo ">>> Uploading model: ${var.model_display_name}-${var.image_tag}"

MODEL_ID=$(gcloud ai models upload \
  --region="${var.region}" \
  --display-name="${var.model_display_name}-${var.image_tag}" \
  --container-image-uri="${var.image_uri}" \
  --container-predict-route="/predict" \
  --container-health-route="/health" \
  --format="value(name)")

if [ -z "$MODEL_ID" ]; then
  echo "ERROR: Model upload returned empty ID"
  exit 1
fi

echo "$MODEL_ID" > model_id.txt
echo "✔ Model uploaded: $MODEL_ID"
EOF
  }
}

# -------------------------
# Deploy New Model to Endpoint
# -------------------------
resource "null_resource" "deploy_model" {
  depends_on = [
    null_resource.register_model,
    google_vertex_ai_endpoint.endpoint
  ]

  triggers = {
    model_version = var.image_tag
  }

  provisioner "local-exec" {
    command = <<EOF
MODEL_ID=$(cat model_id.txt | tr -d '[:space:]')
ENDPOINT_ID=$(cat endpoint_id.txt | tr -d '[:space:]')

echo ">>> Deploying model '$MODEL_ID' to endpoint '$ENDPOINT_ID'...."

DEPLOYED_ID=$(gcloud ai endpoints deploy-model "$ENDPOINT_ID" \
  --region="${var.region}" \
  --model="$MODEL_ID" \
  --display-name="sdxl-deployment-${var.image_tag}" \
  --machine-type="${var.machine_type}" \
  --accelerator="type=${var.accelerator_type},count=${var.accelerator_count}" \
  --min-replica-count=${var.min_replica_count} \
  --max-replica-count=${var.max_replica_count} \
  --traffic-split=0=100 \
  --format="value(deployedModels.id)")

echo "$DEPLOYED_ID" > deployed_model_id.txt

echo "✔ Deployment complete. Deployed model ID: $DEPLOYED_ID"
EOF
  }
}
