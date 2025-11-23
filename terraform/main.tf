provider "google" {
  project = var.project_id
  region  = var.region
}

# ==== Artifact Registry ====
resource "google_artifact_registry_repository" "repo" {
  location       = var.region
  repository_id  = var.artifact_repo
  description    = "Artifact Registry for SDXL inference images"
  format         = "DOCKER"
}

# ==== Service Account ====
resource "google_service_account" "deploy_sa" {
  account_id   = "vertex-deploy"
  display_name = "Vertex AI Deployment Service Account"
}

resource "google_project_iam_member" "artifact_reader" {
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.deploy_sa.email}"
  project = var.project_id
}

resource "google_project_iam_member" "storage_reader" {
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.deploy_sa.email}"
  project = var.project_id
}

# ==== Create Model ====
resource "google_vertex_ai_model" "sdxl_model" {
  display_name = var.model_display_name
  location     = var.region

  container_spec {
    image_uri     = var.image_uri

    ports {
      container_port = 8080
    }

    predict_route = "/predict"
    health_route  = "/health"
  }
}

# ==== Create Endpoint ====
resource "google_vertex_ai_endpoint" "endpoint" {
  location      = var.region
  display_name  = var.endpoint_display_name
}

# ==== Deploy Model to Endpoint ====
resource "google_vertex_ai_endpoint_deployed_model" "deployment" {
  location   = var.region
  endpoint   = google_vertex_ai_endpoint.endpoint.name
  model      = google_vertex_ai_model.sdxl_model.name

  display_name = "${var.model_display_name}-deployment"

  dedicated_resources {
    min_replica_count = var.min_replica_count
    max_replica_count = var.max_replica_count

    machine_spec {
      machine_type       = var.machine_type
      accelerator_type   = var.accelerator_type
      accelerator_count  = var.accelerator_count
    }
  }

  traffic_split = {
    "0" = 100
  }
}
