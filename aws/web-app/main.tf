provider "aws" {
  region     = "us-east-1"
  access_key = "placeholder"
  secret_key = "placeholder"
}

locals {
  romi = "romi"
  tomer = "tomer"

}

####################################################################
########                       VPC                   ###############
####################################################################
resource "aws_eip" "nat" {
  count = 1
  vpc = true
}
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name = local.romi
  cidr = "20.10.0.0/16" # 10.0.0.0/8 is reserved for EC2-Classic
  azs                 = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets     = ["20.10.1.0/24", "20.10.2.0/24", "20.10.3.0/24"]
  public_subnets      = ["20.10.11.0/24", "20.10.12.0/24", "20.10.13.0/24"]
  database_subnets    = ["20.10.21.0/24", "20.10.22.0/24", "20.10.23.0/24"]
  elasticache_subnets = ["20.10.31.0/24", "20.10.32.0/24", "20.10.33.0/24"]
  redshift_subnets    = ["20.10.41.0/24", "20.10.42.0/24", "20.10.43.0/24"]
  intra_subnets       = ["20.10.51.0/24", "20.10.52.0/24", "20.10.53.0/24"]
  create_database_subnet_group = true
  manage_default_route_table = true
  default_route_table_tags   = { DefaultRouteTable = true }
  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_classiclink             = false
  enable_classiclink_dns_support = false
//  enable_nat_gateway = true
//    single_nat_gateway = true
    enable_nat_gateway = false
  single_nat_gateway = false
  reuse_nat_ips       = true                    # <= Skip creation of EIPs for the NAT Gateways
//  external_nat_ip_ids = "${aws_eip.nat.*.id}"   # <= IPs specified here as input to the module
//  customer_gateways = {
//    IP1 = {
//      bgp_asn     = 65112
//      ip_address  = "1.2.3.4"
//      device_name = "some_name"
//    },
//    IP2 = {
//      bgp_asn    = 65112
//      ip_address = "5.6.7.8"
//    }
//  }
  enable_vpn_gateway = false
  enable_dhcp_options              = false
  dhcp_options_domain_name         = "service.consul"
  dhcp_options_domain_name_servers = ["127.0.0.1", "10.10.0.2"]
  # Default security group - ingress/egress rules cleared to deny all
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []
  # VPC Flow Logs (Cloudwatch log group and IAM role will be created)
  enable_flow_log                      = false
  create_flow_log_cloudwatch_log_group = false
  create_flow_log_cloudwatch_iam_role  = false
  flow_log_max_aggregation_interval    = 60
}
####################################################################
########                  ENDPOINTS                  ###############
####################################################################
module "endpoints" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.main_sg.security_group_id]
  endpoints = {
    s3 = {
      # interface endpoint
      service             = "s3"
      service_type    = "Gateway"
      tags                = { Name = "s3-vpc-endpoint" }
      route_table_ids = flatten([module.vpc.private_route_table_ids, module.vpc.public_route_table_ids, module.vpc.default_route_table_id])
    },
    dynamodb = {
      # gateway endpoint
      service         = "dynamodb"
      service_type    = "Gateway"
      route_table_ids = flatten([module.vpc.private_route_table_ids, module.vpc.public_route_table_ids, module.vpc.default_route_table_id])
      tags            = { Name = "dynamodb-vpc-endpoint" }
    }
  }
  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}
####################################################################
########                Security group               ###############
####################################################################
module "main_sg" {
  source = "terraform-aws-modules/security-group/aws"
  name        = "shirit-sg"
  description = "Security group which is used as an argument in complete-sg"
  vpc_id      = module.vpc.vpc_id
  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      description = "User-service ports"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      description = "Service name"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}
####################################################################
########                S3 Bucket                    ###############
####################################################################
module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"
  bucket = "shiritt-module-bucket"
  acl    = "private"
  versioning = {
    enabled = false
  }
}
####################################################################
########                EC2 Instance                 ###############
####################################################################
module "key_pair" {
  source = "terraform-aws-modules/key-pair/aws"
  key_name   = "deployer-one"
  public_key = tls_private_key.this.public_key_openssh
}
module "ec2_multiple" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  name = "single-instance"
  ami                    = "ami-0f06fc190dd71269e"
  instance_type          = "t2.micro"
  key_name               = module.key_pair.key_pair_name
  monitoring             = true
  vpc_security_group_ids = [module.main_sg.security_group_id]
//  vpc_security_group_ids = [module.vpc.default_security_group_id]
  subnet_id              = module.vpc.private_subnets[0]
  iam_instance_profile = module.iam_assumable_role.iam_instance_profile_id
  enable_volume_tags = false
}
resource "tls_private_key" "this" {
  algorithm = "RSA"
}

####################################################################
##########              Lambda                        ##############
####################################################################
module "lambda_function_existing_package_local" {
  source = "terraform-aws-modules/lambda/aws"
  function_name = "my-lambda-existing-package-local"
  description   = "My awesome lambda function"
  handler       = "index.lambda_handler"
  runtime       = "python3.8"
  create_package         = false
  local_existing_package = "lambda/lambda_function.zip"
}
####################################################################
##########              RDS                           ##############
####################################################################
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  identifier = "demodb"
  engine            = "mysql"
  engine_version    = "5.7.25"
  instance_class    = "db.t3a.micro"
  allocated_storage = 5
  db_name = "demodb"
  username = "user"
  password = "YourPwdShouldBeLongAndSecure!"
  port     = "3306"
  iam_database_authentication_enabled = true
//  create_db_option_group = false
  vpc_security_group_ids = [module.main_sg.security_group_id]
  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"
  # Enhanced Monitoring - see example for details on how to create the role
  # by yourself, in case you don't want to create it automatically
  monitoring_interval = "30"
  monitoring_role_name = "MyRDSMonitoringRole"
  create_monitoring_role = true
  tags = {
    Owner       = "user"
    Environment = "dev"
  }
  # DB subnet group
//  subnet_ids = module.vpc.database_subnets
  # DB parameter group
  major_engine_version = "mysql5.7"
  family = "mysql5.7"
  # DB option group
  # Database Deletion Protection
  deletion_protection = false
  parameters = [
    {
      name = "character_set_client"
      value = "utf8mb4"
    },
    {
      name = "character_set_server"
      value = "utf8mb4"
    }
  ]
}
####################################################################
##########            IAM Policy                      ##############
####################################################################
module "iam_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  name        = "mike-modules-policy"
  path        = "/"
  description = "My example policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*",
        "ec2:DescribeRegions",
        "kinesis:*",
        "sqs:*",
        "dynamodb:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}
####################################################################
##########            IAM role + profile              ##############
####################################################################
module "iam_assumable_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  trusted_role_services = [
    "ec2.amazonaws.com"
  ]
  create_role = true
  create_instance_profile = true
  role_name         = "mike-modules-role"
  role_requires_mfa = false
  custom_role_policy_arns = [
    module.iam_policy.arn
  ]
  number_of_custom_role_policy_arns = 1
}
####################################################################
##########                DynamoDB                    ##############
####################################################################
module "dynamodb_table" {
  source   = "terraform-aws-modules/dynamodb-table/aws"
  name     = "mike-module-table"
  hash_key = "id"
  attributes = [
    {
      name = "id"
      type = "N"
    }
  ]
  tags = {
    Terraform   = "true"
    Environment = "staging"
  }
}