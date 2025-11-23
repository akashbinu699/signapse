data "local_file" "endpoint" {
  depends_on = [null_resource.create_endpoint]
  filename   = "${path.module}/endpoint_id.txt"
}

data "local_file" "model" {
  depends_on = [null_resource.register_model]
  filename   = "${path.module}/model_id.txt"
}

output "endpoint_id" {
  value = trimspace(data.local_file.endpoint.content)
}

output "model_id" {
  value = trimspace(data.local_file.model.content)
}
