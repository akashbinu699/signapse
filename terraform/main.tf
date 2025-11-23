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

resource "google_artifact_registry_repository" "repo" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_repo
  format        = "DOCKER"
  description   = "Stable Diffusion container repo"

  lifecycle {
    ignore_changes = [
      description,
      format
    ]
  }
}

resource "google_vertex_ai_endpoint" "endpoint" {
  name         = "vertex-${var.endpoint_display_name}-${var.project_id}"
  display_name = var.endpoint_display_name
  location     = var.region
}

# Upload model using gcloud CLI
resource "null_resource" "deploy_model" {
  depends_on = [
    google_artifact_registry_repository.repo,
    null_resource.register_model,
    google_service_account.deploy_sa,
    null_resource.create_endpoint
  ]

  provisioner "local-exec" {
    command = <<EOT
gcloud ai endpoints deploy-model \
  $(cat endpoint_id.txt) \
  --region=${var.region} \
  --model=$(cat model_id.txt) \
  --display-name="sdxl-model-deployment" \
  --machine-type="${var.machine_type}" \
  --accelerator="type=${var.accelerator_type},count=${var.accelerator_count}" \
  --min-replica-count=${var.min_replica_count} \
  --max-replica-count=${var.max_replica_count} \
  --traffic-split=0=100
EOT
  }
}
