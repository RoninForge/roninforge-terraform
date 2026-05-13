---
name: terraform-validate
description: "Scan a Terraform / OpenTofu codebase for anti-patterns: 0.0.0.0/0 ingress, count for stable resources, local backend in shared modules, unpinned providers, ignore_changes=all, null_resource overuse, plaintext secrets in HCL or tfvars, unmarked sensitive outputs, public DBs, unencrypted volumes, IMDSv1, wildcard IAM, unversioned modules."
---

# Validate Terraform / OpenTofu Codebase

## When to Use

When auditing AI-generated HCL, reviewing a PR, or preparing a Terraform repo for production handoff. Output is a list of locations and suggested fixes.

## Instructions

Run each grep against the repo root. Each hit is a candidate; review case by case.

### Security: open ingress

```bash
# 0.0.0.0/0 anywhere - audit each match
grep -rn '"0\.0\.0\.0/0"' --include='*.tf' .

# IPv6 wildcard
grep -rn '"::/0"' --include='*.tf' .
```

Pair these with the resource type. `0.0.0.0/0` on port 443 of a public ALB is acceptable; on SSH or a database port it is not.

### Resource identity

```bash
# count for resources that should be for_each
grep -rnE '^\s*count\s*=' --include='*.tf' .
```

Audit each: if it's `count = var.enabled ? 1 : 0` keep it; otherwise consider `for_each`.

### State management

```bash
# Local backend
grep -rn 'backend\s*"local"' --include='*.tf' .

# Find roots without a backend block
for d in live/*/*/*/; do
  test -f "$d/backend.tf" || echo "MISSING backend: $d"
done
```

### Drift suppression

```bash
grep -rn 'ignore_changes\s*=\s*all' --include='*.tf' .
```

Almost always a smell. Replace with a specific attribute list.

### Provider / engine pinning

```bash
# Roots without required_version
for f in $(grep -rl 'terraform\s*{' --include='*.tf' .); do
  grep -q 'required_version' "$f" || echo "MISSING required_version: $f"
done

# Providers without version pin
grep -rn 'required_providers' --include='*.tf' . -A 10 | grep -v 'version'
```

### Lifecycle / refactoring

```bash
# CLI imports in scripts/docs (should be import {} blocks)
grep -rn 'terraform\s\+import' --include='*.tf' --include='*.sh' --include='*.md' .

# null_resource - audit each
grep -rn 'null_resource' --include='*.tf' .
grep -rn 'local-exec' --include='*.tf' .

# Module sources without ref pin
grep -rnE 'source\s*=\s*"git::[^"]*"' --include='*.tf' . | grep -v '\?ref='
```

### Secrets

Note: secrets embedded inside `user_data` string content (e.g. `user_data = "DB_PASS=hunter2"`) are not caught by the grep below because the attribute name `user_data` does not contain "password" / "secret". Use `checkov` (CKV_AWS_88) or `trivy config` for user-data scanning.

```bash
# Plaintext secrets
grep -rnE '(password|secret|token|api[_-]?key)\s*=\s*"[^$\s{][^"]+"' --include='*.tf' --include='*.tfvars' .

# Common placeholder values
grep -rnE 'default\s*=\s*"(hunter2|changeme|password|admin123)"' --include='*.tf' .

# Static AWS credentials in HCL
grep -rnE 'access_key\s*=\s*"' --include='*.tf' .
```

### IAM

```bash
# Wildcard action / resource
grep -rnE 'Action"?\s*:\s*"\*"' --include='*.tf' .
grep -rnE 'Resource"?\s*:\s*"\*"' --include='*.tf' .

# actions = ["*"] in HCL policy documents
grep -rnE 'actions\s*=\s*\[\s*"\*"' --include='*.tf' .
```

### Storage / database

```bash
# Public DBs
grep -rn 'publicly_accessible\s*=\s*true' --include='*.tf' .

# Unencrypted volumes
grep -rnE '(storage_encrypted|encrypted)\s*=\s*false' --include='*.tf' .

# IMDSv1 enabled
grep -rn 'http_tokens\s*=\s*"optional"' --include='*.tf' .

# S3 buckets without public access block
for f in $(grep -rl 'aws_s3_bucket"' --include='*.tf' .); do
  grep -q 'aws_s3_bucket_public_access_block' "$f" || echo "MISSING public_access_block: $f"
done
```

### Outputs

```bash
# Outputs whose name suggests a secret, missing sensitive flag
grep -rnE 'output\s+"(password|token|secret|key)' --include='*.tf' . -A 3 | grep -v 'sensitive\s*=\s*true'
```

### Variables

`grep -L` does not work with piped stdin, so audit each variable block per file:

```bash
for f in $(grep -rl 'variable[[:space:]]*"' --include='*.tf' .); do
  python3 - "$f" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
for m in re.finditer(r'variable\s+"([^"]+)"\s*\{([^}]*)\}', text, re.DOTALL):
    name, body = m.group(1), m.group(2)
    if not re.search(r'\btype\s*=', body):
        print(f"{sys.argv[1]}: variable \"{name}\" missing type")
    if not re.search(r'\bdescription\s*=', body):
        print(f"{sys.argv[1]}: variable \"{name}\" missing description")
PY
done
```

### tfvars hygiene

```bash
# .tfvars files committed (audit each)
find . -name '*.tfvars' -not -path '*/.terraform/*'

# .tfvars not gitignored
git check-ignore -v $(find . -name '*.tfvars' -not -path '*/.terraform/*' 2>/dev/null) 2>&1 | grep -v gitignore
```

### Workspaces as environments

```bash
grep -rn 'terraform\.workspace' --include='*.tf' .
```

Audit each: legitimate use is in cheap parallel state (PR previews), not in resource names for production environments.

## Run automated tools alongside

The greps above are quick triage. For production audits also run:

```bash
terraform fmt -check -recursive
terraform validate
tflint
trivy config .
checkov -d .
```

Tflint / Trivy / Checkov ship pre-built rulesets that catch what greps miss.

## Output Format

```
=== Critical ===
live/prod/web/main.tf:34 - 0.0.0.0/0 on port 22 ingress
modules/vpc/main.tf:18 - count = length(var.azs) for stable collection
live/prod/web/backend.tf - missing required_version
shared.tfvars:5 - plaintext db_password value committed

=== Warnings ===
modules/iam/main.tf:78 - actions = ["*"] in policy document
live/staging/web/main.tf:12 - null_resource + local-exec (provider resource available?)

=== Suggestions ===
modules/rds/variables.tf:5 - missing description on variable "backup_retention"
```
