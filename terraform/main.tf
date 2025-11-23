# terraform/main.tf
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.80.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_artifact_registry_repository" "repo" {
  provider = google
  project  = var.project_id
  location = var.region
  repository_id = var.artifact_repo
  description = "Docker repo for SDXL inference images"
  format = "DOCKER"
}

resource "google_service_account" "deploy_sa" {
  account_id   = "${var.project_id}-vertex-deploy"
  display_name = "Vertex deploy SA"
}

# Grant roles to SA (simplified)
resource "google_project_iam_member" "sa_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.deploy_sa.email}"
}

resource "google_project_iam_member" "sa_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.deploy_sa.email}"
}

# Vertex AI Model (container model)
resource "google_vertex_ai_model" "sdxl_model" {
  provider = google
  project  = var.project_id
  region   = var.region
  display_name = var.model_display_name

  container_spec {
    image_uri = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}/${var.image_name}:${var.image_tag}"
    ports {
      container_port = 8080
    }
    # optional: health route
    predict_route = "/predict"
    health_route = "/health"
  }

  # optionally set machine type / accelerator when deploying
}

resource "google_vertex_ai_endpoint" "endpoint" {
  provider = google
  project  = var.project_id
  region   = var.region
  display_name = var.endpoint_display_name
}

# Deploy model to endpoint
resource "google_vertex_ai_endpoint_deployment" "deploy" {
  provider = google
  project  = var.project_id
  region   = var.region
  endpoint = google_vertex_ai_endpoint.endpoint.name
  deployed_model {
    model = google_vertex_ai_model.sdxl_model.name
    display_name = "${var.model_display_name}-deployment"

    dedicated_resources {
      machine_spec {
        machine_type = var.machine_type  # e.g. "a2-highgpu-1g" or "n1-standard-8"
        accelerator_type = var.accelerator_type # "NVIDIA_TESLA_T4" etc. OPTIONAL per machine
        accelerator_count = var.accelerator_count
      }
      min_replica_count = var.min_replica_count
      max_replica_count = var.max_replica_count
    }

    # autoscaling disabled by default; you can add autoscaling config as needed
  }
  traffic_split = {
    "0" = 100
  }
}
