output "model_id" {
  value = fileexists("model_id.txt") ? chomp(file("model_id.txt")) : null
  description = "Uploaded model resource ID"
}

output "endpoint_id" {
  value = fileexists("endpoint_id.txt") ? chomp(file("endpoint_id.txt")) : null
  description = "Deployed endpoint ID"
}
