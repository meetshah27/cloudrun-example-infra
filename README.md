# cloudrun-example-infra

Terraform infrastructure for deploying a Flask API to Google Cloud Run. Related to [this blog post](https://fpgmaas.com/blog/deploying-a-flask-api-to-cloudrun-2) and the [Flask API repo](https://github.com/fpgmaas/cloudrun-example-api).

## 1. Prerequisites

A GCP project with a service account that has the following roles:

- Editor
- Service Usage Admin
- Artifact Registry Administrator
- Cloud Run Admin
- Project IAM Admin

## 2. Deploying a new version

- If this is the first time, complete section 3 first.
- Push a Docker image to Artifact Registry using the `docker-pusher` service account.
- Set `docker_image` in `main/variables.tf` to the image name (e.g. `my-api:1.0.0`).
- Open a Pull Request — a bot will comment the `terraform plan` output.
- Publish a GitHub release — this triggers `terraform apply`.

## 3. First-time setup

### 3.1 Terraform state bucket

```bash
cp .env.template .env
# Add the absolute path to your service account JSON in .env
source .env
terraform -chdir=backend init
terraform -chdir=backend apply
```

Copy the output bucket name into `main/backend.tf`.

### 3.2 Initial infrastructure

Leave `docker_image` empty in `main/variables.tf` (the default). This skips Cloud Run until you have an image.

Set `github_repository` in `main/variables.tf` to your repo in `owner/repo` format.

```bash
terraform -chdir=main init
terraform -chdir=main apply
```

### 3.3 Configure CI/CD with Workload Identity Federation

After the initial apply, get the WIF values from the Terraform outputs:

```bash
terraform -chdir=main output wif_provider
terraform -chdir=main output github_actions_sa_email
```

Add these as GitHub repository secrets:

| Secret | Value |
|--------|-------|
| `WIF_PROVIDER` | output of `wif_provider` |
| `WIF_SERVICE_ACCOUNT` | output of `github_actions_sa_email` |

The old `GOOGLE_CREDENTIALS` JSON key secret is no longer needed.

### 3.4 Deploy the first image

- Push a Docker image using the `docker-pusher` service account.
- Set `docker_image` in `main/variables.tf`.
- Create a PR, then publish a release to trigger deployment.

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | GCP project ID | `my-cloudrun-api` |
| `region` | Compute region | `europe-west4` |
| `zone` | Compute zone | `europe-west4-a` |
| `environment` | Deployment environment label | `prod` |
| `repository` | Artifact Registry repository name | `docker-repository` |
| `docker_image` | Docker image to deploy (empty = skip Cloud Run) | `""` |
| `min_instances` | Minimum Cloud Run instances | `1` |
| `max_instances` | Maximum Cloud Run instances | `3` |
| `github_repository` | GitHub repo in `owner/repo` format | *(required)* |
