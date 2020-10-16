# Specify the provider and access details
provider "aws" {
  region = "us-west-2"
}
variable "db_password"{
  type = string
}
variable "db_admin"{
  type = string
}
# RDS (7min)
resource "aws_db_instance" "OctoDB" {
  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type         = "gp2"
  engine               = "sqlserver-ex"
  engine_version       = "15.00.4043.16.v1"
  instance_class       = "db.t3.small"
  identifier           = "octo"
  username             = var.db_admin
  password             = var.db_password
  parameter_group_name = "default.sqlserver-ex-15.0"
  vpc_security_group_ids = ["sg-0e47e07daae5a3c59"]
  publicly_accessible   = true
}
# EC2


output "db_endpoint" {
  value = aws_db_instance.OctoDB.endpoint
}
