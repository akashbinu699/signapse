# terraform/outputs.tf
output "endpoint_name" {
  value = google_vertex_ai_endpoint.endpoint.name
}

output "endpoint_id" {
  value = google_vertex_ai_endpoint.main.id
}

output "model_name" {
  value = google_vertex_ai_model.sdxl_model.name
}
