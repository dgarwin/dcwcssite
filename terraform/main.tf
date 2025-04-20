variable "project_id" {
  description = "GCP project ID"
  type        = string
  default = "dcwcssite"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# 1. Create a public bucket
resource "google_storage_bucket" "dcwcssite" {
  name     = "dcwcssite"
  location = "US"
}

# Make bucket objects publicly readable
resource "google_storage_bucket_iam_member" "public_objects" {
  bucket = google_storage_bucket.dcwcssite.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# 3. Create a service account for GitHub
resource "google_service_account" "github" {
  account_id   = "github"
  display_name = "GitHub Workload Identity Service Account"
}

# 4. Grant Legacy Bucket Owner & Object Owner roles to the GitHub service account
resource "google_storage_bucket_iam_member" "github_bucket_owner" {
  bucket = google_storage_bucket.dcwcssite.name
  role   = "roles/storage.legacyBucketOwner"
  member = "serviceAccount:${google_service_account.github.email}"
}

resource "google_storage_bucket_iam_member" "github_object_owner" {
  bucket = google_storage_bucket.dcwcssite.name
  role   = "roles/storage.legacyObjectOwner"
  member = "serviceAccount:${google_service_account.github.email}"
}

# 5. Create a Workload Identity Pool for GitHub OIDC
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name = "GitHub OIDC Pool"
  description  = "OIDC pool for GitHub Actions"
}

# 6. Create a GitHub OIDC Provider in the pool
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name              = "GitHub OIDC Provider"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "attribute.repository==\"dgarwin/dcwcssite\""
}

# 7. Bind the GitHub workload identity to the service account for pushes on main
resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.github.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/repo:dgarwin/dcwcssite:ref:refs/heads/main"
}

# 8. Simplified Cloud Build trigger relying on cloudbuild.yaml

# Deploy to Cloud Run using the built image
resource "google_cloud_run_service" "dcwcssite" {
  name     = "dcwcssite"
  location = var.region

  metadata {
    annotations = {
      "run.googleapis.com/ingress" = "all"
    }
  }

  template {
    spec {
      containers {
        image = "gcr.io/${var.project_id}/dcwcssite:latest"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

# Allow only authenticated users to invoke Cloud Run
resource "google_cloud_run_service_iam_member" "invoker" {
  service  = google_cloud_run_service.dcwcssite.name
  location = google_cloud_run_service.dcwcssite.location
  role     = "roles/run.invoker"
  member   = "allAuthenticatedUsers"
}

