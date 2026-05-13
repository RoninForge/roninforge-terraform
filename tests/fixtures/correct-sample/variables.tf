# Correct sample. Every variable typed, described, validated.

variable "region" {
  description = "AWS region for the deployment"
  type        = string
  default     = "eu-central-1"
}

variable "env" {
  description = "Environment name (used as a tag and prefix)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be one of: dev, staging, prod"
  }
}

variable "web_names" {
  description = "Logical names for the web instances (used as for_each keys)"
  type        = set(string)

  validation {
    condition     = length(var.web_names) >= 1
    error_message = "at least one web instance name required"
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^t3\\.", var.instance_type))
    error_message = "instance_type must be a t3 family size"
  }
}

variable "admin_cidrs" {
  description = "CIDR blocks allowed to SSH to web instances"
  type        = list(string)

  validation {
    condition     = !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs must not include 0.0.0.0/0"
  }
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the DB password"
  type        = string
}

variable "tags" {
  description = "Additional tags merged onto every resource"
  type        = map(string)
  default     = {}
}
