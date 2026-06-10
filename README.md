# roninforge-terraform

[![Validate Plugin](https://github.com/RoninForge/roninforge-terraform/actions/workflows/validate.yml/badge.svg)](https://github.com/RoninForge/roninforge-terraform/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/v/release/RoninForge/roninforge-terraform)](https://github.com/RoninForge/roninforge-terraform/releases)

Cursor plugin for Terraform 1.9+ and OpenTofu 1.8+. Teaches the AI to write production-grade HCL: `for_each` over `count`, remote backend with state locking, version pinning, `moved` / `removed` / `import` blocks for safe refactoring, ephemeral resources for secrets, `check` blocks for runtime invariants, OpenTofu state encryption, OIDC federation for CI auth. Catches 20 regressions LLMs trained on older HCL still produce.

## The Problem

LLMs trained on HCL from 2020-2023 produce code that ships drift-prone, insecure, or destroy-on-rename infrastructure. They write:

- `0.0.0.0/0` ingress on SSH / RDP / database ports (single most common shipped vulnerability)
- `count = length(var.things)` for stable collections (removing an item renumbers + destroys the rest)
- `backend "local" { }` or no backend block in shared modules (no state locking, no team workflow)
- No `required_version`, no `required_providers` version pin (next provider release silently breaks the plan)
- `lifecycle { ignore_changes = all }` to silence drift instead of fixing it
- `null_resource` + `local-exec` where a real provider resource exists
- Rename a resource without a `moved` block (destroys + recreates)
- `terraform import` CLI usage in scripts/docs instead of `import {}` blocks
- `terraform.workspace` interpolated into resource names (workspaces used as environments)
- Secrets in `variable` defaults, `*.tfvars` files, or HCL literals
- Static AWS access keys declared in provider blocks
- `actions = ["*"]` / `resources = ["*"]` in IAM policy documents
- Unmarked sensitive outputs (passwords appear in plan logs)
- `publicly_accessible = true` on RDS, missing encryption on EBS/RDS
- `http_tokens = "optional"` on EC2 metadata (IMDSv1 enabled)
- Module `source = "git::..."` without `?ref=v...` pin (upstream breaks consumers)
- Variables without `type`, `description`, or `validation`
- `terraform_remote_state` for everything instead of provider data sources
- `dynamic` blocks iterating over a single literal element
- Missing `terraform fmt` / `validate` / `tflint` / policy scan in CI

## Install

```bash
git clone https://github.com/RoninForge/roninforge-terraform.git ~/.cursor/plugins/local/roninforge-terraform
```

Or copy into your project:

```bash
git clone https://github.com/RoninForge/roninforge-terraform.git
cp -r roninforge-terraform/rules/* your-project/.cursor/rules/
cp -r roninforge-terraform/skills/* your-project/.cursor/skills/
cp -r roninforge-terraform/agents/* your-project/.cursor/agents/
```

## What's Included

### Rules (5 files)

| Rule | Scope | What it does |
|------|-------|-------------|
| `terraform-core` | Always active | Version pinning, remote backend + locking, `for_each` over `count`, `moved`/`removed`/`import` blocks, typed + validated variables, ephemeral secrets (1.10+), OIDC federation, repo layout, OpenTofu deltas |
| `terraform-anti-patterns` | Always active | 20 regressions: `0.0.0.0/0` on management ports, `count` misuse, local backend, unpinned providers, `ignore_changes=all`, `null_resource` overuse, `terraform_remote_state` for everything, workspace-as-env, plaintext secrets, static AWS keys, wildcard IAM, IMDSv1, public DBs |
| `terraform-modules` | `**/*.tf` | Module design: structure, inputs surface, output curation, semver discipline, examples directory, `*.tftest.hcl` |
| `terraform-aws-security` | `**/*.tf` | AWS-specific: S3 public-access blocks + encryption + versioning, IAM least-privilege, RDS hardening, IMDSv2, security groups by reference, VPC flow logs, GuardDuty, Security Hub, KMS rotation, tagging |
| `terraform-testing` | Agent-requested | `*.tftest.hcl` framework, `expect_failures`, mocked providers (OpenTofu 1.8+), apply tests, terratest, OPA policy tests |

### Skills (4 commands)

| Skill | Command | What it does |
|-------|---------|-------------|
| New module | `/terraform-new-module` | Scaffold a reusable module: versions.tf + variables.tf + main.tf + outputs.tf + examples + tests + README |
| Refactor with moved | `/terraform-refactor-with-moved` | Safely rename or restructure resources without destroy+create; covers cross-module moves and `count`->`for_each` migrations |
| Validate | `/terraform-validate` | Scan codebase for the 20 tracked anti-patterns, report by severity |
| Migrate secrets | `/terraform-migrate-secrets` | Move plaintext HCL secrets to Secrets Manager + ephemeral resources, rotate exposed credentials, mark sensitive outputs |

### Agent (1 subagent)

| Agent | What it does |
|-------|-------------|
| `terraform-reviewer` | Reviews HCL by severity: critical (security risk, data loss), warnings (regressions), suggestions (style + future-proofing) |

## What Makes This Different

Existing Terraform .cursorrules cover formatting and naming. None of them:

- Catch `0.0.0.0/0` on management ports (single most common shipped vulnerability)
- Force `for_each` over `count` with the destroy-on-renumber explanation
- Teach `moved` (1.1+) / `import` (1.5+) / `removed` (1.7+, OpenTofu 1.6+) blocks for safe refactoring
- Cover ephemeral resources (Terraform 1.10+) for secret handling
- Differentiate Terraform vs OpenTofu (BSL vs MPL licensing, state encryption, mock providers)
- Bundle a secrets-migration skill for projects that have already leaked

## Fixtures

`tests/fixtures/anti-pattern-sample/` is a deliberate trash fire: hardcoded region, `count`, `0.0.0.0/0` SSH, plaintext password in `terraform.tfvars`, `null_resource` + `local-exec`, public RDS, IMDSv1, `ignore_changes = all`, workspace-as-environment.

`tests/fixtures/correct-sample/` is the same shape rewritten with pinned versions, remote backend, `for_each`, validated admin CIDRs, ephemeral secrets, IMDSv2, encrypted private RDS, deletion-protected, curated outputs.

## License

MIT - see [LICENSE](LICENSE)

## Links

- [Terraform releases](https://github.com/hashicorp/terraform/releases)
- [Terraform 1.10: ephemeral values](https://www.hashicorp.com/en/blog/terraform-1-10-improves-handling-secrets-in-state-with-ephemeral-values)
- [Terraform 1.11: write-only arguments](https://www.hashicorp.com/en/blog/terraform-1-11-ephemeral-values-managed-resources-write-only-arguments)
- [OpenTofu state encryption](https://opentofu.org/docs/language/state/encryption/)
- [OpenTofu releases](https://github.com/opentofu/opentofu/releases)
- [pre-commit-terraform](https://github.com/antonbabenko/pre-commit-terraform)
- [Cursor Plugin Documentation](https://docs.cursor.com/plugins)
- [RoninForge](https://roninforge.org)


## More from RoninForge

[RoninForge](https://roninforge.org) builds free tools for developers working with AI coding assistants:

- [LLM API pricing comparison](https://roninforge.org/llm-pricing) - Claude, GPT, Gemini, DeepSeek, Mistral, and Grok token prices side by side, verified against official pricing pages
- [GitHub Copilot AI Credits calculator](https://roninforge.org/copilot-credits-calculator) - estimate your monthly credit burn under usage-based billing
- [All Cursor plugins](https://roninforge.org/#plugins)
