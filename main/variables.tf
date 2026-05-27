variable "project_id" {
  description = "The GCP project ID"
  type        = string
  default     = "my-cloudrun-api"
}

variable "region" {
  description = "The default compute region"
  type        = string
  default     = "europe-west4"
}

variable "zone" {
  description = "The default compute zone"
  type        = string
  default     = "europe-west4-a"
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging)"
  type        = string
  default     = "prod"
}

variable "repository" {
  description = "The name of the Artifact Registry repository"
  type        = string
  default     = "docker-repository"
}

variable "docker_image" {
  description = "Docker image name in Artifact Registry to deploy. Leave empty to skip Cloud Run deployment."
  type        = string
  default     = ""
}

variable "min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 3
}

variable "github_repository" {
  description = "GitHub repository in owner/repo format (e.g. fpgmaas/cloudrun-example-infra). Used to scope Workload Identity Federation."
  type        = string
}
