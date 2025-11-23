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
resource "null_resource" "create_endpoint" {
  provisioner "local-exec" {
    command = <<EOT
gcloud ai endpoints create \
  --region=${var.region} \
  --display-name="${var.endpoint_display_name}" \
  --format="value(name)" > endpoint_id.txt
EOT
  }
}

# Upload Model
resource "null_resource" "register_model" {
  depends_on = [
    google_artifact_registry_repository.repo
  ]

  provisioner "local-exec" {
    command = <<-EOT
      MODEL_ID=$(gcloud ai models upload \
        --region=${var.region} \
        --display-name="${var.model_display_name}" \
        --container-image-uri="${var.image_uri}" \
        --container-predict-route="/predict" \
        --container-health-route="/health" \
        --format="value(name)")

      echo "$MODEL_ID" > model_id.txt
    EOT
  }
}

# Deploy Model to Endpoint
resource "null_resource" "deploy_model" {
  depends_on = [
    null_resource.register_model,
    google_vertex_ai_endpoint.endpoint
  ]

  provisioner "local-exec" {
    command = <<-EOT
      ENDPOINT_ID=$(gcloud ai endpoints deploy-model \
        ${google_vertex_ai_endpoint.endpoint.name} \
        --region=${var.region} \
        --model=$(cat model_id.txt) \
        --display-name="sdxl-model-deployment" \
        --machine-type="${var.machine_type}" \
        --accelerator="type=${var.accelerator_type},count=${var.accelerator_count}" \
        --min-replica-count=${var.min_replica_count} \
        --max-replica-count=${var.max_replica_count} \
        --traffic-split=0=100 \
        --format="value(name)")

      echo "$ENDPOINT_ID" > endpoint_id.txt
    EOT
  }
}
