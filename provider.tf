# ============================================================================
# provider.tf — Tells Terraform WHICH cloud to talk to and HOW.
# ----------------------------------------------------------------------------
# Every Terraform folder needs a provider config. This is read first, before
# any resources, so Terraform knows to download the AWS plugin and which
# region/credentials to use.
# ============================================================================

terraform {                       # Global settings block for this Terraform project
  required_version = ">= 1.10"    # S3 native locking (use_lockfile) in backend.tf needs Terraform 1.10 or newer

  required_providers {            # Declares which provider plugins are needed
    aws = {                       # We need the AWS provider
      source  = "hashicorp/aws"   # Where to download it from (the official HashiCorp registry)
      version = "5.84.0"          # Pin to this exact version for reproducible runs
    }
  }
}

provider "aws" {                  # Configuration for the AWS provider itself
  # Configuration options
  region = "us-east-1"            # All resources in this folder are created in the us-east-1 region
}
