# Remote state in S3. Locking uses an S3 lock file (no DynamoDB needed).
# Same key as the old Terraform\ec2 folder, so the migrated state continues here.
terraform {
  backend "s3" {
    bucket       = "shivakrishna-tf-state-dev"
    key          = "terraform-practice/ec2/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
