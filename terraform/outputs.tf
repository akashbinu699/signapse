output "endpoint_id" {
  value = google_vertex_ai_endpoint.endpoint.name
}

output "latest_model" {
  value = fileexists("model_id.txt") ? chomp(file("model_id.txt")) : ""
}

output "latest_deployment" {
  value = fileexists("deployed_model_id.txt") ? chomp(file("deployed_model_id.txt")) : ""
}
