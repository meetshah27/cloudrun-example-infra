terraform {
  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  common_labels = {
    managed_by  = "terraform"
    environment = var.environment
  }
}

#############################################
#               Enable APIs                 #
#############################################

resource "google_project_service" "iam" {
  provider           = google-beta
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

# Required for Workload Identity Federation
resource "google_project_service" "iamcredentials" {
  provider           = google-beta
  service            = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  provider           = google-beta
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudrun" {
  provider           = google-beta
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "resourcemanager" {
  provider           = google-beta
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

# GCP API activation can take time to propagate; 60s is more reliable than 30s
resource "time_sleep" "wait_60_seconds" {
  create_duration = "60s"
  depends_on = [
    google_project_service.iam,
    google_project_service.iamcredentials,
    google_project_service.artifactregistry,
    google_project_service.cloudrun,
    google_project_service.resourcemanager,
  ]
}

#############################################
#    Google Artifact Registry Repository    #
#############################################

resource "google_artifact_registry_repository" "my_docker_repo" {
  provider = google-beta

  location      = var.region
  repository_id = var.repository
  description   = "Docker repository"
  format        = "DOCKER"
  labels        = local.common_labels
  depends_on    = [time_sleep.wait_60_seconds]
}

resource "google_service_account" "docker_pusher" {
  provider = google-beta

  account_id   = "docker-pusher"
  display_name = "Docker Container Pusher"
  depends_on   = [time_sleep.wait_60_seconds]
}

resource "google_artifact_registry_repository_iam_member" "docker_pusher_iam" {
  provider = google-beta

  location   = google_artifact_registry_repository.my_docker_repo.location
  repository = google_artifact_registry_repository.my_docker_repo.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.docker_pusher.email}"
  depends_on = [
    google_artifact_registry_repository.my_docker_repo,
    google_service_account.docker_pusher,
  ]
}

#############################################
#       Workload Identity Federation        #
#############################################

resource "google_iam_workload_identity_pool" "github" {
  provider                  = google-beta
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions Pool"
  depends_on                = [time_sleep.wait_60_seconds]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  provider                           = google-beta
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  # Restrict to only your GitHub repository
  attribute_condition = "assertion.repository == \"${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "github_actions" {
  provider     = google-beta
  account_id   = "github-actions"
  display_name = "GitHub Actions CI/CD"
  depends_on   = [time_sleep.wait_60_seconds]
}

resource "google_service_account_iam_member" "github_actions_wif" {
  provider           = google-beta
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

resource "google_project_iam_member" "github_actions_roles" {
  provider = google-beta
  for_each = toset([
    "roles/editor",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/artifactregistry.admin",
    "roles/run.admin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

##############################################
#       Deploy API to Google Cloud Run       #
##############################################

resource "google_cloud_run_v2_service" "api" {
  provider = google-beta
  # Skipped until a docker image is provided
  count    = var.docker_image != "" ? 1 : 0
  name     = "api"
  location = var.region
  labels   = local.common_labels

  template {
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository}/${var.docker_image}"
      resources {
        limits = {
          memory = "1Gi"
          cpu    = "1"
        }
      }
    }
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  depends_on = [google_artifact_registry_repository_iam_member.docker_pusher_iam]
}

resource "google_cloud_run_v2_service_iam_member" "noauth" {
  provider = google-beta
  count    = var.docker_image != "" ? 1 : 0
  location = var.region
  project  = var.project_id
  name     = google_cloud_run_v2_service.api[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "cloud_run_instance_url" {
  value = var.docker_image != "" ? google_cloud_run_v2_service.api[0].uri : null
}

output "wif_provider" {
  description = "Workload Identity Provider resource name — use as WIF_PROVIDER secret in GitHub"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_actions_sa_email" {
  description = "GitHub Actions service account email — use as WIF_SERVICE_ACCOUNT secret in GitHub"
  value       = google_service_account.github_actions.email
}
