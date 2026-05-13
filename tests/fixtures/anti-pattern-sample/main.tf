# Anti-pattern sample. DO NOT use as a template.
#
# Violations:
# - hardcoded region
# - no required_version, no required_providers
# - count for stable resources
# - 0.0.0.0/0 ingress on SSH
# - plaintext password committed
# - null_resource + local-exec as a hammer
# - ignore_changes = all hides drift
# - workspace as environment
# - publicly_accessible RDS, no encryption
# - IMDSv1 enabled
# - user_data with embedded secret (not catchable by attribute-name grep)
# - variable without type or description (instance_count at the bottom)

provider "aws" {
  region = "us-east-1"
}

resource "aws_security_group" "web" {
  name = "${terraform.workspace}-web"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  count         = var.instance_count
  ami           = "ami-0abcd1234"
  instance_type = "t3.micro"

  metadata_options {
    http_tokens = "optional"
  }

  user_data = "DB_PASS=hunter2"

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_db_instance" "main" {
  identifier          = "${terraform.workspace}-db"
  engine              = "postgres"
  allocated_storage   = 20
  instance_class      = "db.t3.micro"
  username            = "admin"
  password            = "hunter2"
  publicly_accessible = true
  storage_encrypted   = false
  skip_final_snapshot = true
}

resource "null_resource" "deploy" {
  provisioner "local-exec" {
    command = "kubectl apply -f manifest.yaml"
  }
}

variable "instance_count" {
  default = 3
}
