---
name: terraform-refactor-with-moved
description: "Safely refactor Terraform code (rename a resource, restructure a module, switch from count to for_each) using moved blocks. Avoids destroy+create cycles that would otherwise drop and recreate live infrastructure."
---

# Refactor with `moved` Blocks

## When to Use

When changing the address of an existing Terraform-managed resource - by renaming, moving between modules, or switching from `count` to `for_each`. Without a `moved` block, Terraform treats the new address as a new resource and destroys + recreates the old one.

## Instructions

### Step 1: Identify the affected addresses

Run `terraform state list` to see the current state addresses:

```
aws_iam_role.application
aws_iam_role_policy.application_s3
module.vpc.aws_subnet.private[0]
module.vpc.aws_subnet.private[1]
```

### Step 2: Write the `moved` block in HCL

For a simple rename:

```hcl
moved {
  from = aws_iam_role.application
  to   = aws_iam_role.app
}
```

For moving between modules:

```hcl
moved {
  from = aws_iam_role.app
  to   = module.iam.aws_iam_role.app
}
```

For switching from `count` to `for_each`:

```hcl
# Before (count-keyed)
resource "aws_subnet" "private" {
  count             = length(var.azs)
  availability_zone = var.azs[count.index]
  ...
}

# After (for_each-keyed)
resource "aws_subnet" "private" {
  for_each          = toset(var.azs)
  availability_zone = each.value
  ...
}

# moved block, one per element
moved {
  from = aws_subnet.private[0]
  to   = aws_subnet.private["eu-central-1a"]
}
moved {
  from = aws_subnet.private[1]
  to   = aws_subnet.private["eu-central-1b"]
}
```

### Step 3: Plan

```bash
terraform plan
```

You should see:

```
# aws_iam_role.app will be moved from aws_iam_role.application
```

Not a destroy + create. If the plan still shows destroy + create, the `moved` block does not match - check addresses carefully.

### Step 4: Apply

```bash
terraform apply
```

The state file is updated. No infrastructure changes.

### Step 5: Clean up

`moved` blocks live for one release cycle. After every consumer environment has applied the migrated configuration:

- Remove the `moved` blocks from HCL.
- Tag a new module version.

Leaving stale `moved` blocks indefinitely is harmless but adds noise.

## Cross-environment migration

If multiple environments use the same module:

1. Tag a new module version that includes both the resource rename and the `moved` block.
2. Bump each environment's `module "x" { source = "...?ref=vN" }` pin to the new version.
3. Plan + apply each environment. The state file gets migrated.
4. After every environment is on the new tag, you can delete the `moved` blocks and tag a follow-up version.

## When you cannot use `moved`

`moved` cannot migrate resources across:

- Different backends (different state files).
- Different cloud providers.
- Different resource types (`aws_instance` -> `aws_ec2_fleet`).

For these, use `removed { from = ... lifecycle { destroy = false } }` to drop the resource from state without destroying it, then re-adopt at the new address with an `import` block.

## Common mistakes

- **Forgetting the `moved` block**: rename without one and Terraform plans a destroy + create. Always plan before applying.
- **Wrong address syntax**: `moved { from = "aws_iam_role.x" to = "aws_iam_role.y" }` (strings) is wrong. The addresses are bare HCL identifiers, not quoted strings.
- **Mixing `moved` with other changes**: a single PR that both moves resources AND changes their arguments is hard to review. Split: PR 1 moves, PR 2 changes args.
- **Deleting `moved` blocks too early**: if you delete the block before all environments have applied, the un-applied environments will destroy + create on next apply.

## `removed` blocks for retiring resources without destroy

When you want to stop managing a resource but keep it alive (e.g., handing ownership to another team):

```hcl
removed {
  from = aws_iam_role.legacy
  lifecycle {
    destroy = false
  }
}
```

Terraform drops the resource from state on the next apply but does not destroy it. Useful when transferring ownership; rare otherwise.

## `import` blocks for adopting existing infrastructure

Pair with `removed` from the source codebase to do a clean handoff:

```hcl
# in the new codebase
import {
  to = aws_iam_role.app
  id = "my-iam-role-id"
}

resource "aws_iam_role" "app" {
  # ... config that matches the existing role
}
```

After apply: remove the `import` block in a follow-up PR.
