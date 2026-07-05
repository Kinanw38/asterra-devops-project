terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  # ה-Backend ריק מכיוון שהוא מוזרק דינמית דרך deploy.sh
  # בשביל לאפשר הרצה חלקה בכל Region ללא שינוי קוד קשיח
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}