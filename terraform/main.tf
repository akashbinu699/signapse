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

# Artifact Registry (safe if exists)
resource "google_artifact_registry_repository" "repo" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_repo
  format        = "DOCKER"

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [format]
  }
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
    command = <<EOT
gcloud ai models upload \
  --region=${var.region} \
  --display-name="${var.model_display_name}" \
  --container-image-uri="${var.image_uri}" \
  --container-predict-route="/predict" \
  --container-health-route="/health" \
  --format="value(name)" > model_id.txt
EOT
  }
}

# Deploy Model to Endpoint
resource "null_resource" "deploy_model" {
  depends_on = [
    null_resource.register_model,
    null_resource.create_endpoint
  ]

  provisioner "local-exec" {
    command = <<EOT
gcloud ai endpoints deploy-model \
  $(cat endpoint_id.txt) \
  --region=${var.region} \
  --display-name="sdxl-deployment" \
  --model=$(cat model_id.txt) \
  --machine-type="${var.machine_type}" \
  --accelerator="type=${var.accelerator_type},count=${var.accelerator_count}" \
  --min-replica-count=${var.min_replica_count} \
  --max-replica-count=${var.max_replica_count} \
  --traffic-split=0=100
EOT
  }
}
