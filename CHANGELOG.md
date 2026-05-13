# Changelog

## [1.0.0] - 2026-05-13

### Added

- 5 rule files: `terraform-core` (always-on, modern Terraform/OpenTofu fundamentals), `terraform-anti-patterns` (always-on, 20 regressions), `terraform-modules` (`.tf`), `terraform-aws-security` (`.tf`), `terraform-testing` (agent-requested)
- `/terraform-new-module` skill: scaffold a reusable module with versions, variables, main, outputs, examples, tests, README
- `/terraform-refactor-with-moved` skill: safely rename or restructure resources without destroy+create
- `/terraform-validate` skill: grep audit for the 20 tracked anti-patterns
- `/terraform-migrate-secrets` skill: move plaintext HCL secrets to Secrets Manager + ephemeral resources
- `terraform-reviewer` subagent: severity-grouped HCL review
- Test fixtures: insecure / drift-prone anti-pattern sample + production-grade correct sample with `for_each`, validated admin CIDRs, ephemeral secrets, IMDSv2, encrypted private RDS
- Plugin validation script and CI workflow
