# Correct sample. Demonstrates:
# - for_each over count for stable identity
# - admin_cidrs (validated to exclude 0.0.0.0/0)
# - ephemeral secret for DB password (Terraform 1.10+)
# - IMDSv2 required, encrypted root volume with CMK
# - private DB on its own security group, encrypted with CMK, deletion-protected
# - default_tags on provider for org-wide tagging

provider "aws" {
  region = var.region
  default_tags {
    tags = merge(
      {
        Environment = var.env
        ManagedBy   = "Terraform"
      },
      var.tags,
    )
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "web" {
  name        = "${var.env}-web"
  description = "Web tier; SSH from admin CIDRs only"
}

resource "aws_security_group_rule" "web_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.admin_cidrs
  security_group_id = aws_security_group.web.id
}

resource "aws_security_group_rule" "web_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

ephemeral "aws_secretsmanager_secret_version" "db" {
  secret_id = var.db_secret_arn
}

resource "aws_instance" "web" {
  for_each = var.web_names

  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web.id]

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted   = true
    kms_key_id  = aws_kms_key.ebs.arn
    volume_size = 20
    volume_type = "gp3"
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/cloud-init.yaml.tpl", {
    db_password = ephemeral.aws_secretsmanager_secret_version.db.secret_string
  })

  tags = { Name = "${var.env}-${each.key}" }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.env}-db"
  subnet_ids = ["subnet-aaa", "subnet-bbb"]   # placeholders
}

resource "aws_security_group" "db" {
  name        = "${var.env}-db"
  description = "RDS; ingress from web tier only"
}

resource "aws_security_group_rule" "db_ingress_from_web" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.web.id
  security_group_id        = aws_security_group.db.id
}

resource "aws_kms_key" "ebs" {
  description             = "${var.env} EBS encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_key" "rds" {
  description             = "${var.env} RDS encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_db_instance" "main" {
  identifier             = "${var.env}-main"
  engine                 = "postgres"
  engine_version         = "16.4"
  instance_class         = "db.t4g.small"
  allocated_storage      = 20

  publicly_accessible    = false
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.rds.arn

  backup_retention_period = 7
  deletion_protection     = true
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.env}-main-final"

  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db.id]

  username = "appuser"
  password = ephemeral.aws_secretsmanager_secret_version.db.secret_string
}
