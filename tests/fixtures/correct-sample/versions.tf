# Correct sample. Demonstrates:
# - required_version pinned (semver constraint)
# - required_providers pinned
# - remote backend with state locking
# - encryption at rest

terraform {
  required_version = "~> 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  backend "s3" {
    bucket         = "acme-tfstate"
    key            = "fixtures/correct/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "tfstate-locks"
    encrypt        = true
  }
}
