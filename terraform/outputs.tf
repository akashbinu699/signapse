output "model_name" {
  value = google_vertex_ai_model.sdxl_model.name
}

output "endpoint_name" {
  value = google_vertex_ai_endpoint.endpoint.name
}

output "deployment_id" {
  value = google_vertex_ai_endpoint_deployed_model.deployment.id
}
