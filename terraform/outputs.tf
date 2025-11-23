output "endpoint_id" {
  value = chomp(file("endpoint_id.txt"))
}

output "model_id" {
  value = chomp(file("model_id.txt"))
}
