---
name: terraform-migrate-secrets
description: "Migrate secrets out of Terraform HCL: ephemeral resources for Terraform 1.10+, encrypted state for OpenTofu, sensitive data sources for older versions. Remove .tfvars secrets, rotate exposed credentials, document the rotation."
---

# Migrate Secrets Out of HCL

## When to Use

When auditing a Terraform codebase that contains:
- Hardcoded passwords / API keys in `variable "x" { default = "..." }`.
- Committed `*.tfvars` files with real values for secret-bearing variables.
- Secrets visible in `terraform plan` output (sensitive outputs not flagged).

## Instructions

### Step 1: Inventory the leaks

```bash
# Plaintext secrets in HCL
grep -rnE '(password|secret|token|api[_-]?key)\s*=\s*"[^$\s{][^"]+"' --include='*.tf' --include='*.tfvars' .

# Common placeholders
grep -rnE 'default\s*=\s*"(hunter2|changeme|password|admin)"' --include='*.tf' .

# Outputs that should be sensitive
grep -rnE 'output\s+"(password|token|secret|key)' --include='*.tf' . -A 3
```

Make a list of every file:line that needs change.

### Step 2: Rotate any exposed credentials first

If a real secret was committed to git, treat it as compromised. Rotate it (rotate the AWS key, change the DB password, regenerate the API token) before continuing. The git history retains the secret forever; rotating is the only mitigation.

```bash
# Optional: rewrite git history to scrub the secret (destructive, requires force-push)
git filter-repo --replace-text replacements.txt
```

Document the rotation in an incident note.

### Step 3: Move secrets to a secrets manager

For AWS:

```hcl
# in your secrets module or via the AWS console
resource "aws_secretsmanager_secret" "db" {
  name        = "${var.env}/db/password"
  description = "RDS password for ${var.env}"
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({ password = random_password.db.result })

  lifecycle {
    ignore_changes = [secret_string]   # subsequent rotations don't show as drift
  }
}

resource "random_password" "db" {
  length  = 32
  special = false
}
```

The password lives in Secrets Manager. State contains the resource references, not the password value (use `ephemeral` or read flag-tracked sensitive data sources).

### Step 4: Consume the secret

**Terraform 1.10+ (ephemeral resources):**

```hcl
ephemeral "aws_secretsmanager_secret_version" "db" {
  secret_id = "${var.env}/db/password"
}

resource "aws_db_instance" "main" {
  password = jsondecode(ephemeral.aws_secretsmanager_secret_version.db.secret_string).password
}
```

Ephemeral values are never written to state or plan output. This is the cleanest path.

**Terraform 1.6-1.9 / OpenTofu 1.6-1.7 (sensitive data source):**

```hcl
data "aws_secretsmanager_secret_version" "db" {
  secret_id = "${var.env}/db/password"
}

resource "aws_db_instance" "main" {
  password = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string).password
}
```

Plus encrypt the state (S3 backend with `encrypt = true` and KMS CMK, or OpenTofu native state encryption).

**OpenTofu state + plan encryption (1.7+):**

```hcl
terraform {
  encryption {
    key_provider "aws_kms" "k" {
      kms_key_id = "alias/tofu-state"
      region     = "eu-central-1"
    }
    method "aes_gcm" "m" { keys = key_provider.aws_kms.k }
    state { method = method.aes_gcm.m }
    plan  { method = method.aes_gcm.m }
  }
}
```

State and plan files are encrypted at rest by OpenTofu itself, even if the backend is not configured to encrypt.

### Step 5: Remove HCL secrets

```bash
# Remove default = "..." from variable blocks
# (manual edit, sed risky with multiline blocks)

# Delete *.tfvars files containing secrets
rm shared.tfvars
git rm shared.tfvars

# Update .gitignore
echo "*.tfvars" >> .gitignore
echo "!*.example.tfvars" >> .gitignore  # template versions OK
```

Keep `*.example.tfvars` with placeholder values as documentation:

```hcl
# shared.example.tfvars
db_secret_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:prod/db/password-XXXXXX"
admin_cidrs   = ["10.0.0.0/8"]
```

### Step 6: Mark sensitive outputs

```hcl
# Before
output "db_endpoint" {
  value = aws_db_instance.main.endpoint
}

# After (if endpoint is sensitive in your threat model)
output "db_endpoint" {
  value     = aws_db_instance.main.endpoint
  sensitive = true
}
```

For password outputs - do not output them at all. Consumers read from Secrets Manager directly.

### Step 7: Verify

```bash
# No plaintext secrets in tf or tfvars
grep -rnE '(password|secret|token|api[_-]?key)\s*=\s*"[^$\s{][^"]+"' --include='*.tf' --include='*.tfvars' .

# No tfvars committed
find . -name '*.tfvars' -not -path '*/.terraform/*' | grep -v example

# Plan output contains no secrets
terraform plan | grep -iE 'password|secret|api[_-]?key' || echo "plan clean"
```

The greps should return empty. If anything remains, fix it before continuing.

### Step 8: Document for future engineers

Add a section to the project README:

```markdown
## Secrets

This project does not store secrets in HCL. Secrets live in AWS Secrets Manager
under `<env>/<service>/<name>` paths. Terraform reads them via:

- **ephemeral** resources (1.10+) for runtime-only use.
- **aws_secretsmanager_secret_version** data sources for compile-time references.

Rotation is handled by Secrets Manager rotation lambdas; Terraform does not need
to be re-applied when a secret rotates (the `lifecycle.ignore_changes` on
`aws_secretsmanager_secret_version.secret_string` keeps it out of drift).
```

## Anti-patterns to avoid

- Do not check committed secrets into git history without rotating. The history is forever.
- Do not use `data` sources that put the secret value into state without encrypting the state.
- Do not pass secrets as Terraform variables on the command line - they appear in shell history and CI logs.
- Do not use `terraform output -raw db_password` in scripts. Read from Secrets Manager directly.
- Do not assume `sensitive = true` hides the value everywhere. It only suppresses plan/apply output; the value is in state.
