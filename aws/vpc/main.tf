terraform {
  required_providers {
    aws        = "~> 3.70.0"
  }
}

provider "aws" {
  region  = "us-east-1"
}
#######################Create VPC with all needed network elements########################
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  single_nat_gateway = true
  name = "test_vpc_main"
  cidr = "10.0.0.0/16"
  secondary_cidr_blocks = ["10.1.0.0/16", "10.2.0.0/16"]
  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway = true
  enable_vpn_gateway = true
  create_igw = true
  tags = {
    Terraform = "true"
    Environment = "dev"
    Owner = "Stav"
  }
    enable_dns_hostnames = true
  enable_dns_support   = true
}