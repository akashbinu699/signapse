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
  depends_on = [google_artifact_registry_repository.repo]

  triggers = {
    build_id = timestamp()   # ← forces run every time
  }

  provisioner "local-exec" {
    command = <<EOT
MODEL_NAME="${var.model_display_name}-$(date +%s)"

gcloud ai models upload \
  --region=${var.region} \
  --display-name="$MODEL_NAME" \
  --container-image-uri="${var.image_uri}" \
  --container-predict-route="/predict" \
  --container-health-route="/health" \
  --format="value(name)" > model_id.txt

echo "Registered Model: $(cat model_id.txt)"
EOT
  }
}

# Deploy Model to Endpoint
resource "null_resource" "deploy_model" {
  depends_on = [
    google_vertex_ai_endpoint.endpoint,
    null_resource.register_model
  ]

  triggers = {
    new_model_id = timestamp()  # force redeploy each run
  }

  provisioner "local-exec" {
    command = <<EOT
MODEL_ID=$(cat model_id.txt)
ENDPOINT_ID="${google_vertex_ai_endpoint.endpoint.name}"

echo "Deploying Model $MODEL_ID to Endpoint $ENDPOINT_ID..."

gcloud ai endpoints deploy-model "$ENDPOINT_ID" \
  --region=${var.region} \
  --model="$MODEL_ID" \
  --display-name="sdxl-deployment-$(date +%s)" \
  --machine-type="${var.machine_type}" \
  --accelerator="type=${var.accelerator_type},count=${var.accelerator_count}" \
  --min-replica-count=${var.min_replica_count} \
  --max-replica-count=${var.max_replica_count} \
  --traffic-split=0=100 \
  --format="value(deployedModels.id)" > deployed_model_id.txt
EOT
  }
}
