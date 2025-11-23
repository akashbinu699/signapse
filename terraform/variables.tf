# terraform/variables.tf
variable "project_id" { type = string }
variable "region" { type = string, default = "us-central1" }
variable "artifact_repo" { type = string, default = "sdxl-repo" }
variable "image_name" { type = string, default = "sdxl-inference" }
variable "image_tag" { type = string, default = "latest" }
variable "model_display_name" { type = string, default = "sdxl-turbo-model" }
variable "endpoint_display_name" { type = string, default = "sdxl-endpoint" }

# deployment machine config
variable "machine_type" { type = string, default = "a2-highgpu-1" } # adjust
variable "accelerator_type" { type = string, default = "NVIDIA_A100" }
variable "accelerator_count" { type = number, default = 1 }
variable "min_replica_count" { type = number, default = 1 }
variable "max_replica_count" { type = number, default = 1 }
