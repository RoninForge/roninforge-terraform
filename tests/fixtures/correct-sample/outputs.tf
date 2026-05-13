# Correct sample. Curated outputs, sensitive flag where needed.

output "web_instance_ids" {
  description = "Map of web instance names to EC2 instance IDs"
  value       = { for k, v in aws_instance.web : k => v.id }
}

output "web_security_group_id" {
  description = "ID of the web tier security group"
  value       = aws_security_group.web.id
}

output "db_endpoint" {
  description = "RDS endpoint hostname"
  value       = aws_db_instance.main.endpoint
}

# DB password is never output - consumers read from Secrets Manager directly.
