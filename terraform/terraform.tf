terraform {
  required_version = "~> 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.40.0"
    }
  }

  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "wanderlust/terraform.tfstate"
  #   region         = "us-east-2"
  #   dynamodb_table = "terraform-state-locking"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  # Speeds up authentication and initialization
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true

  default_tags {
    tags = {
      Project   = "Wanderlust-Mega-Project"
      ManagedBy = "Terraform"
    }
  }
}
