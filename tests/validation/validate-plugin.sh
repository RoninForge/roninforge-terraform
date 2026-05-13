#!/bin/sh
# Validates the plugin structure and content.
# Run from the repository root: ./tests/validation/validate-plugin.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ERRORS=0
WARNINGS=0

red() { printf "\033[31m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
yellow() { printf "\033[33m%s\033[0m\n" "$1"; }

error() { red "ERROR: $1"; ERRORS=$((ERRORS + 1)); }
warn() { yellow "WARN: $1"; WARNINGS=$((WARNINGS + 1)); }
pass() { green "PASS: $1"; }

echo "=== Plugin Structure Validation ==="
echo ""

# 1. Check plugin.json exists and is valid JSON
if [ -f "$REPO_ROOT/.cursor-plugin/plugin.json" ]; then
    if python3 -c "import json; json.load(open('$REPO_ROOT/.cursor-plugin/plugin.json'))" 2>/dev/null; then
        pass "plugin.json is valid JSON"

        # Check required fields
        NAME=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.cursor-plugin/plugin.json')).get('name', ''))")
        if [ -n "$NAME" ]; then
            pass "plugin.json has 'name' field: $NAME"
        else
            error "plugin.json missing required 'name' field"
        fi

        # Check recommended fields
        for field in version description author license; do
            HAS=$(python3 -c "import json; d=json.load(open('$REPO_ROOT/.cursor-plugin/plugin.json')); print('yes' if '$field' in d else 'no')")
            if [ "$HAS" = "yes" ]; then
                pass "plugin.json has '$field' field"
            else
                warn "plugin.json missing recommended '$field' field"
            fi
        done
    else
        error "plugin.json is not valid JSON"
    fi
else
    error ".cursor-plugin/plugin.json not found"
fi

echo ""
echo "=== Rule Files ==="
echo ""

# 2. Check rule files
RULE_COUNT=0
for rule_file in "$REPO_ROOT"/rules/*.mdc; do
    [ -f "$rule_file" ] || continue
    RULE_COUNT=$((RULE_COUNT + 1))
    fname=$(basename "$rule_file")

    # Check for YAML frontmatter
    first_line=$(head -1 "$rule_file")
    if [ "$first_line" = "---" ]; then
        pass "$fname has YAML frontmatter"

        # Check for description in frontmatter
        if grep -q "^description:" "$rule_file"; then
            pass "$fname has description"
        else
            warn "$fname missing description in frontmatter"
        fi

        # Check for either alwaysApply or globs
        HAS_ALWAYS=$(grep -c "^alwaysApply:" "$rule_file" 2>/dev/null || true)
        HAS_GLOBS=$(grep -c "^globs:" "$rule_file" 2>/dev/null || true)
        if [ "$HAS_ALWAYS" -gt 0 ] || [ "$HAS_GLOBS" -gt 0 ]; then
            pass "$fname has application strategy (alwaysApply or globs)"
        else
            pass "$fname is agent-requested (no alwaysApply/globs - this is intentional)"
        fi
    else
        error "$fname missing YAML frontmatter (must start with ---)"
    fi

    # Check line count (recommended < 500)
    LINES=$(wc -l < "$rule_file" | tr -d ' ')
    if [ "$LINES" -lt 500 ]; then
        pass "$fname is $LINES lines (under 500 limit)"
    else
        warn "$fname is $LINES lines (recommended under 500)"
    fi
done

if [ "$RULE_COUNT" -gt 0 ]; then
    pass "Found $RULE_COUNT rule files"
else
    error "No .mdc rule files found in rules/"
fi

echo ""
echo "=== Skill Files ==="
echo ""

# 3. Check skill files
SKILL_COUNT=0
for skill_dir in "$REPO_ROOT"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")

    if [ -f "$skill_dir/SKILL.md" ]; then
        SKILL_COUNT=$((SKILL_COUNT + 1))
        pass "Skill '$skill_name' has SKILL.md"

        # Check for YAML frontmatter
        first_line=$(head -1 "$skill_dir/SKILL.md")
        if [ "$first_line" = "---" ]; then
            pass "Skill '$skill_name' has YAML frontmatter"

            # Check required frontmatter fields
            if grep -q "^name:" "$skill_dir/SKILL.md"; then
                # Verify name matches directory
                SKILL_NAME_VALUE=$(grep "^name:" "$skill_dir/SKILL.md" | head -1 | sed 's/name: *//' | tr -d '"')
                if [ "$SKILL_NAME_VALUE" = "$skill_name" ]; then
                    pass "Skill '$skill_name' name matches directory"
                else
                    error "Skill name '$SKILL_NAME_VALUE' does not match directory '$skill_name'"
                fi
            else
                error "Skill '$skill_name' missing 'name' in frontmatter"
            fi

            if grep -q "^description:" "$skill_dir/SKILL.md"; then
                pass "Skill '$skill_name' has description"
            else
                error "Skill '$skill_name' missing 'description' in frontmatter"
            fi
        else
            error "Skill '$skill_name' SKILL.md missing YAML frontmatter"
        fi
    else
        error "Skill directory '$skill_name' missing SKILL.md"
    fi
done

if [ "$SKILL_COUNT" -gt 0 ]; then
    pass "Found $SKILL_COUNT skills"
else
    warn "No skills found in skills/"
fi

echo ""
echo "=== Agent Files ==="
echo ""

# 4. Check agent files
AGENT_COUNT=0
for agent_file in "$REPO_ROOT"/agents/*.md; do
    [ -f "$agent_file" ] || continue
    AGENT_COUNT=$((AGENT_COUNT + 1))
    fname=$(basename "$agent_file")

    first_line=$(head -1 "$agent_file")
    if [ "$first_line" = "---" ]; then
        pass "Agent '$fname' has YAML frontmatter"

        if grep -q "^name:" "$agent_file"; then
            pass "Agent '$fname' has name"
        else
            error "Agent '$fname' missing 'name' in frontmatter"
        fi

        if grep -q "^description:" "$agent_file"; then
            pass "Agent '$fname' has description"
        else
            warn "Agent '$fname' missing description"
        fi
    else
        error "Agent '$fname' missing YAML frontmatter"
    fi
done

if [ "$AGENT_COUNT" -gt 0 ]; then
    pass "Found $AGENT_COUNT agent files"
else
    warn "No agent files found in agents/"
fi

echo ""
echo "=== Required Files ==="
echo ""

# 5. Check required repo files
for req_file in README.md LICENSE CHANGELOG.md; do
    if [ -f "$REPO_ROOT/$req_file" ]; then
        pass "$req_file exists"
    else
        error "$req_file not found"
    fi
done

echo ""
echo "=== Content Accuracy Checks ==="
echo ""

# 6. correct-sample fixture must be free of banned Terraform patterns.
#    Skip HCL comment lines (#). Egress 0.0.0.0/0 is legitimate; flag ingress
#    only by checking for type = "ingress" within 5 lines above a cidr_blocks
#    that contains 0.0.0.0/0.
CORRECT_HITS=$(grep -rnE '^[[:space:]]*(count[[:space:]]*=|ignore_changes[[:space:]]*=[[:space:]]*all|backend[[:space:]]*"local"|publicly_accessible[[:space:]]*=[[:space:]]*true|http_tokens[[:space:]]*=[[:space:]]*"optional"|password[[:space:]]*=[[:space:]]*"[^$])' "$REPO_ROOT/tests/fixtures/correct-sample/" 2>/dev/null | head -10 || true)
INGRESS_HITS=$(grep -rn -B 5 '"0\.0\.0\.0/0"' "$REPO_ROOT/tests/fixtures/correct-sample/" 2>/dev/null | grep -E 'type[[:space:]]*=[[:space:]]*"ingress"' | head -5 || true)
if [ -z "$CORRECT_HITS" ] && [ -z "$INGRESS_HITS" ]; then
    pass "correct-sample fixture is free of banned patterns"
else
    error "correct-sample contains banned Terraform patterns:"
    [ -n "$CORRECT_HITS" ] && echo "$CORRECT_HITS"
    [ -n "$INGRESS_HITS" ] && echo "ingress 0.0.0.0/0 detected:" && echo "$INGRESS_HITS"
fi

# 7. anti-pattern fixture should contain several tracked violations.
ANTI_HITS=$(grep -rcE '^[[:space:]]*(count[[:space:]]*=|"0\.0\.0\.0/0"|ignore_changes[[:space:]]*=[[:space:]]*all|null_resource|password[[:space:]]*=[[:space:]]*")' "$REPO_ROOT/tests/fixtures/anti-pattern-sample/" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
if [ "$ANTI_HITS" -ge 3 ]; then
    pass "anti-pattern-sample contains $ANTI_HITS tracked violations"
else
    warn "anti-pattern-sample has only $ANTI_HITS tracked violations (expected 3+)"
fi

echo ""
echo "=== Summary ==="
echo ""
echo "Errors:   $ERRORS"
echo "Warnings: $WARNINGS"
echo ""

if [ "$ERRORS" -gt 0 ]; then
    red "FAILED - fix $ERRORS error(s) before submission"
    exit 1
else
    if [ "$WARNINGS" -gt 0 ]; then
        yellow "PASSED with $WARNINGS warning(s)"
    else
        green "ALL CHECKS PASSED"
    fi
    exit 0
fi
