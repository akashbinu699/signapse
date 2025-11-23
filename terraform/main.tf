terraform {
  backend "gcs" {
    bucket = "sdxl-terraform-state"
    prefix = "terraform/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.32.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Artifact registry (already exists but Terraform ensures state)
resource "google_artifact_registry_repository" "repo" {
  location       = var.region
  repository_id  = var.artifact_repo
  format         = "DOCKER"
}

# Vertex endpoint
resource "google_vertex_ai_endpoint" "endpoint" {
  display_name = var.endpoint_display_name
  location     = var.region
}

# Upload model via bootstrap script
resource "null_resource" "upload_model" {
  provisioner "local-exec" {
    command = <<EOF
gcloud ai models upload \
   --region=${var.region} \
   --display-name="${var.model_display_name}" \
   --container-image-uri="${var.image_uri}" \
   --format='value(name)' > model_id.txt
EOF
  }
}

# Deploy model to endpoint
resource "null_resource" "deploy_model" {
  depends_on = [
    google_vertex_ai_endpoint.endpoint,
    null_resource.upload_model
  ]

  provisioner "local-exec" {
    command = <<EOF
gcloud ai endpoints deploy-model ${google_vertex_ai_endpoint.endpoint.name} \
  --region=${var.region} \
  --model=$(cat model_id.txt) \
  --display-name="${var.model_display_name}-deployment" \
  --machine-type="${var.machine_type}" \
  --accelerator-type="${var.accelerator_type}" \
  --accelerator-count=${var.accelerator_count} \
  --min-replica-count=${var.min_replica_count} \
  --max-replica-count=${var.max_replica_count} \
  --traffic-split=0=100
EOF
  }
}
