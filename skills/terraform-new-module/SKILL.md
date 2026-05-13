---
name: terraform-new-module
description: "Scaffold a reusable Terraform / OpenTofu module: versions.tf with required_version + required_providers, variables.tf with typed + validated inputs, outputs.tf with curated outputs, main.tf with for_each + tagging, README + examples/ + tests/."
---

# Scaffold Terraform Module

## When to Use

When creating a new reusable module (e.g. VPC, RDS, ECS service) that will be consumed by multiple root modules.

## Instructions

1. Decide the module name and primary resource. Use a single-noun name: `vpc`, `rds`, `ecs-service`. Avoid `aws-vpc-network-module`.

2. Create the directory layout:

   ```
   modules/<name>/
   ├── README.md
   ├── versions.tf
   ├── variables.tf
   ├── main.tf
   ├── outputs.tf
   ├── examples/
   │   └── simple/
   │       ├── main.tf
   │       └── README.md
   └── tests/
       └── <name>.tftest.hcl
   ```

3. Write `versions.tf`:

   ```hcl
   terraform {
     required_version = ">= 1.5"
     required_providers {
       aws = {
         source  = "hashicorp/aws"
         version = ">= 5.0"
       }
     }
   }
   ```

4. Write `variables.tf` with `type`, `description`, and `validation` on every input:

   ```hcl
   variable "name" {
     description = "Logical name (used as a tag prefix and identifier)"
     type        = string
     validation {
       condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
       error_message = "name must be lowercase + hyphen, 2-31 chars"
     }
   }

   variable "tags" {
     description = "Tags merged onto every resource the module manages"
     type        = map(string)
     default     = {}
   }
   ```

5. Write `main.tf` with `for_each` over `count`, explicit tagging, no hardcoded values:

   ```hcl
   locals {
     module_tags = merge(
       var.tags,
       { Module = "<name>", ManagedBy = "Terraform" },
     )
   }

   resource "aws_<thing>" "this" {
     # ... per-resource args
     tags = merge(local.module_tags, { Name = var.name })
   }
   ```

6. Write `outputs.tf` with curated, named outputs:

   ```hcl
   output "id" {
     description = "ID of the created <thing>"
     value       = aws_<thing>.this.id
   }
   ```

   Mark anything secret-bearing `sensitive = true`. Better: do not output secrets at all.

7. Add a simple example under `examples/simple/`:

   ```hcl
   # examples/simple/main.tf
   provider "aws" { region = "eu-central-1" }

   module "thing" {
     source = "../../"
     name   = "demo"
   }
   ```

8. Add a `*.tftest.hcl` file under `tests/`:

   ```hcl
   run "rejects_invalid_name" {
     command = plan
     variables { name = "Invalid Name With Spaces" }
     expect_failures = [var.name]
   }

   run "plans_cleanly_with_valid_inputs" {
     command = plan
     variables { name = "test" }
     assert {
       condition     = aws_<thing>.this.tags["Name"] == "test"
       error_message = "Name tag did not propagate"
     }
   }
   ```

9. Generate the README with `terraform-docs`:

   ```bash
   terraform-docs markdown table --output-file README.md --output-mode inject .
   ```

10. Commit and tag a release:

    ```bash
    git tag v0.1.0
    git push origin v0.1.0
    ```

## Anti-patterns to avoid

- Never `count = length(var.things)` for stable collections - use `for_each = toset(var.things)`.
- Never embed `0.0.0.0/0` in module defaults (validate it out at the variable).
- Never declare `provider "aws"` inside the module - the caller configures the provider.
- Never output the raw resource object - curate the public surface.
- Never `~>` pin the engine inside a module - use `>=` and let root modules pin.
- Never accept `variable "extra" { type = any }` as an escape hatch - design real inputs.
