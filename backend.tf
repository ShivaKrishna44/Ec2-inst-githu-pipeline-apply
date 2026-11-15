# ============================================================================
# backend.tf - Where Terraform keeps its state file (remote, in S3).
# ----------------------------------------------------------------------------
# The pipeline and your laptop must use the same state, so it lives in S3.
# The key must be unique per project. Do not reuse a key from another folder.
# use_lockfile (S3 native locking) needs Terraform 1.10 or newer.
# No DynamoDB table is needed.
# ============================================================================

terraform {
  backend "s3" {
    bucket       = "shivakrishna-tf-state-dev"
    key          = "terraform-practice/ec2/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
