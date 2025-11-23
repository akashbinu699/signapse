
output "endpoint_id" {
  description = "The deployed Vertex AI endpoint resource name"
  value       = google_vertex_ai_endpoint.endpoint.name
}

output "endpoint_display_name" {
  description = "Friendly endpoint name"
  value       = google_vertex_ai_endpoint.endpoint.display_name
}

output "region" {
  description = "Region where Vertex resources are deployed"
  value       = var.region
}
