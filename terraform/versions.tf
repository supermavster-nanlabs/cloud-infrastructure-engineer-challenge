terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }

  # Bucket, key and region are supplied at init time (make init, or the deploy
  # workflow), so this code holds no account-specific value.
  backend "s3" {}
}
