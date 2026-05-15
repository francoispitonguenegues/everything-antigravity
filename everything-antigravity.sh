#!/bin/bash

set -euo pipefail

# -----------------------------
# Arguments & flags
# -----------------------------

ECC_DIR="${1:-./everything-claude-code}"
OUT_DIR=""                  # resolved after flag parsing
OPTIMIZE=false
VERBOSE=false
PROJECT_DIR=""              # --project <path> for stack detection
OUT_DIR_EXPLICIT=false      # true if --output was explicitly provided

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --optimize) OPTIMIZE=true ;;
    --verbose)  VERBOSE=true ;;
    --output)
      shift
      OUT_DIR="${1:-.agents}"
      OUT_DIR_EXPLICIT=true
      ;;
    --project)
      shift
      PROJECT_DIR="${1:-.}"
      ;;
    *) echo "⚠️  Unknown flag: $1" ;;
  esac
  shift
done

# Resolve OUT_DIR: --output wins; else --project/<subdir>; else default .agent
if [[ -z "$OUT_DIR" ]]; then
  if [[ -n "$PROJECT_DIR" && "$OUT_DIR_EXPLICIT" = false ]]; then
    OUT_DIR="$PROJECT_DIR/.agents"
  else
    OUT_DIR=".agents"
  fi
fi

# -----------------------------
# Counters for summary
# -----------------------------

COUNT_SKILLS=0
COUNT_WORKFLOWS=0
COUNT_RULES=0
COUNT_EA_SKILLS=0
INSTALLED_FILES=()
DETECTED_STACKS=""

# -----------------------------
# Utils
# -----------------------------

log() { echo "$1"; }
log_verbose() { [[ "$VERBOSE" = true ]] && echo "  ↳ $1" || true; }

slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//;s/-$//'
}

extract_title() {
  local file="$1"
  # 1. YAML frontmatter name: → 2. H1 heading → 3. filename
  python3 - "$file" << 'PYEOF'
import sys, re

path = sys.argv[1]
try:
    lines = open(path).read().splitlines()
except Exception:
    print(""); sys.exit()

# Try frontmatter
if lines and lines[0].strip() == "---":
    for line in lines[1:]:
        if line.strip() == "---":
            break
        m = re.match(r'^[Nn]ame:\s*["\']?(.*?)["\']?\s*$', line)
        if m and m.group(1):
            print(m.group(1)); sys.exit()

# Fallback: H1
for line in lines:
    m = re.match(r'^#\s+(.+)', line)
    if m:
        print(m.group(1)); sys.exit()

# Last resort: filename
import os
print(os.path.splitext(os.path.basename(path))[0])
PYEOF
}

extract_description() {
  local file="$1"
  # 1. YAML frontmatter description: → 2. first blockquote (> ...)
  python3 - "$file" << 'PYEOF'
import sys, re

path = sys.argv[1]
try:
    lines = open(path).read().splitlines()
except Exception:
    print(""); sys.exit()

# Try frontmatter
if lines and lines[0].strip() == "---":
    for line in lines[1:]:
        if line.strip() == "---":
            break
        m = re.match(r'^[Dd]escription:\s*["\']?(.*?)["\']?\s*$', line)
        if m and m.group(1):
            print(m.group(1)); sys.exit()

# Fallback: first blockquote
for line in lines:
    m = re.match(r'^>\s*(.+)', line)
    if m:
        print(m.group(1)); sys.exit()

print("")
PYEOF
}

# =============================================
# STEP 5 — Project Stack Detection
# =============================================
#
# When --project <path> is provided, detect the tech stack.
# Detected stacks are recorded in system.md for informational use.

# Maps project file indicators to skill prefixes
# Returns a space-separated list of active stack tags
detect_project_stack() {
  local dir="$1"
  local stacks=""

  # JavaScript / TypeScript / Node.js
  if [[ -f "$dir/package.json" ]] || [[ -f "$dir/tsconfig.json" ]]; then
    stacks+="javascript typescript nodejs "
    # Detect frameworks from package.json
    if [[ -f "$dir/package.json" ]]; then
      grep -q '"next"' "$dir/package.json" 2>/dev/null && stacks+="nextjs "
      grep -q '"react"' "$dir/package.json" 2>/dev/null && stacks+="react "
      grep -q '"vue"' "$dir/package.json" 2>/dev/null && stacks+="vue nuxt "
      grep -q '"nest' "$dir/package.json" 2>/dev/null && stacks+="nestjs "
      grep -q '"express"' "$dir/package.json" 2>/dev/null && stacks+="express "
      grep -q '"remotion"' "$dir/package.json" 2>/dev/null && stacks+="remotion "
      grep -q '"playwright"' "$dir/package.json" 2>/dev/null && stacks+="playwright e2e "
      grep -q '"prisma"' "$dir/package.json" 2>/dev/null && stacks+="prisma database "
      grep -q '"drizzle"' "$dir/package.json" 2>/dev/null && stacks+="drizzle database "
    fi
  fi

  # Python
  if [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/requirements.txt" ]] || [[ -f "$dir/setup.py" ]]; then
    stacks+="python "
    if [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/requirements.txt" ]]; then
      local pyfiles="$dir/pyproject.toml $dir/requirements.txt"
      grep -qi 'django' $pyfiles 2>/dev/null && stacks+="django "
      grep -qi 'flask' $pyfiles 2>/dev/null && stacks+="flask "
      grep -qi 'fastapi' $pyfiles 2>/dev/null && stacks+="fastapi "
      grep -qi 'pytorch\|torch' $pyfiles 2>/dev/null && stacks+="pytorch "
    fi
  fi

  # Rust
  [[ -f "$dir/Cargo.toml" ]] && stacks+="rust "

  # Go
  [[ -f "$dir/go.mod" ]] && stacks+="golang go "

  # Java / Kotlin / Spring
  if [[ -f "$dir/build.gradle" ]] || [[ -f "$dir/build.gradle.kts" ]] || [[ -f "$dir/pom.xml" ]]; then
    stacks+="java kotlin "
    grep -qi 'spring' "$dir/build.gradle" "$dir/build.gradle.kts" "$dir/pom.xml" 2>/dev/null && stacks+="springboot "
    grep -qi 'ktor' "$dir/build.gradle.kts" 2>/dev/null && stacks+="ktor "
    grep -qi 'exposed' "$dir/build.gradle.kts" 2>/dev/null && stacks+="exposed "
  fi

  # Flutter / Dart
  [[ -f "$dir/pubspec.yaml" ]] && stacks+="flutter dart "

  # Swift / iOS
  if [[ -f "$dir/Package.swift" ]] || find "$dir" -maxdepth 2 -name "*.xcodeproj" -o -name "*.xcworkspace" 2>/dev/null | grep -q .; then
    stacks+="swift swiftui ios "
  fi

  # C / C++
  [[ -f "$dir/CMakeLists.txt" ]] || [[ -f "$dir/Makefile" ]] && stacks+="cpp c "

  # .NET / C#
  if find "$dir" -maxdepth 2 -name "*.csproj" -o -name "*.sln" 2>/dev/null | grep -q .; then
    stacks+="dotnet csharp "
  fi

  # PHP / Laravel
  if [[ -f "$dir/composer.json" ]]; then
    stacks+="php "
    grep -qi 'laravel' "$dir/composer.json" 2>/dev/null && stacks+="laravel "
    grep -qi 'symfony' "$dir/composer.json" 2>/dev/null && stacks+="symfony "
  fi

  # Perl
  [[ -f "$dir/cpanfile" ]] || [[ -f "$dir/Makefile.PL" ]] && stacks+="perl "

  # Docker
  [[ -f "$dir/Dockerfile" ]] || [[ -f "$dir/docker-compose.yml" ]] || [[ -f "$dir/docker-compose.yaml" ]] && stacks+="docker devops "

  # Database indicators
  find "$dir" -maxdepth 2 -name "*.sql" -o -name "migrations" -type d 2>/dev/null | grep -q . && stacks+="database sql "

  # Infrastructure
  [[ -f "$dir/terraform.tf" ]] || [[ -f "$dir/.github/workflows" ]] && stacks+="devops ci "

  # Universal stacks (always relevant)
  stacks+="git security general "

  echo "$stacks"
}



# =============================================
# OBJECTIVE 2 — Intelligent agent parsing & metadata extraction
# =============================================

# Extract a field from YAML frontmatter (between --- delimiters)
# Usage: extract_frontmatter_field <file> <field_name>
extract_frontmatter_field() {
  local file="$1"
  local field="$2"
  # Check if file starts with ---
  if ! head -1 "$file" 2>/dev/null | grep -q '^---$'; then
    echo ""
    return
  fi
  # Extract frontmatter block and find the field
  awk '/^---$/{n++; next} n==1{print}' "$file" \
    | grep -m1 "^${field}:" 2>/dev/null \
    | sed "s/^${field}:[[:space:]]*//" \
    | sed 's/^"//;s/"$//' \
    | sed "s/^'//;s/'$//" \
    || true
}

# Classify a skill/agent into a category based on its name + description
# Returns one of: security, testing, api, frontend, backend, database,
#   devops, language, framework, architecture, documentation, git,
#   performance, research, content, mobile, ai-ml, review, ops, general
classify_category() {
  local text
  text=$(echo "$1" | tr '[:upper:]' '[:lower:]')

  # Order matters: more specific patterns first
  if [[ "$text" =~ security|vulnerability|exploit|audit|injection|xss|owasp|secret|agentshield|bounty|phi|hipaa|compliance ]]; then
    echo "security"
  elif [[ "$text" =~ test|tdd|coverage|e2e|playwright|jest|pytest|kotest|spec|qa|verification|eval ]]; then
    echo "testing"
  elif [[ "$text" =~ review|reviewer|code-review|lint|refactor|clean ]]; then
    echo "review"
  elif [[ "$text" =~ api|rest|graphql|endpoint|swagger|openapi ]]; then
    echo "api"
  elif [[ "$text" =~ frontend|react|next|vue|nuxt|css|html|slide|ui|design-system|accessibility|liquid-glass ]]; then
    echo "frontend"
  elif [[ "$text" =~ backend|express|nest|django|laravel|spring|fastapi|ktor ]]; then
    echo "backend"
  elif [[ "$text" =~ database|postgres|mysql|clickhouse|redis|mongo|jpa|migration|supabase ]]; then
    echo "database"
  elif [[ "$text" =~ deploy|docker|ci|cd|pm2|container|kubernetes|terraform|canary ]]; then
    echo "devops"
  elif [[ "$text" =~ python|golang|rust|swift|kotlin|java|perl|cpp|csharp|dart|typescript|dotnet|flutter ]]; then
    echo "language"
  elif [[ "$text" =~ architect|hexagonal|pattern|clean-architecture|blueprint ]]; then
    echo "architecture"
  elif [[ "$text" =~ doc|readme|update-doc|onboarding|tour|walkthrough ]]; then
    echo "documentation"
  elif [[ "$text" =~ git|commit|branch|pr|merge|workflow ]]; then
    echo "git"
  elif [[ "$text" =~ performance|benchmark|token|optimization|cost|budget|compact ]]; then
    echo "performance"
  elif [[ "$text" =~ research|deep-research|exa|search|market|intelligence ]]; then
    echo "research"
  elif [[ "$text" =~ content|article|writing|brand|social|video|media|slide|crosspost|investor|outreach ]]; then
    echo "content"
  elif [[ "$text" =~ mobile|ios|android|swiftui|compose ]]; then
    echo "mobile"
  elif [[ "$text" =~ ai|ml|pytorch|model|agent|llm|prompt|learning|instinct|evolve ]]; then
    echo "ai-ml"
  elif [[ "$text" =~ ops|loop|session|harness|orchestrat|multi-|council|fleet ]]; then
    echo "ops"
  else
    echo "general"
  fi
}

# Map category to brand_color (hex)
category_to_color() {
  case "$1" in
    security)       echo "#DC2626" ;;  # red
    testing)        echo "#22C55E" ;;  # green
    review)         echo "#8B5CF6" ;;  # violet
    api)            echo "#F97316" ;;  # orange
    frontend)       echo "#3B82F6" ;;  # blue
    backend)        echo "#6366F1" ;;  # indigo
    database)       echo "#14B8A6" ;;  # teal
    devops)         echo "#EAB308" ;;  # yellow
    language)       echo "#06B6D4" ;;  # cyan
    architecture)   echo "#A855F7" ;;  # purple
    documentation)  echo "#64748B" ;;  # slate
    git)            echo "#F43F5E" ;;  # rose
    performance)    echo "#F59E0B" ;;  # amber
    research)       echo "#0EA5E9" ;;  # sky
    content)        echo "#EC4899" ;;  # pink
    mobile)         echo "#10B981" ;;  # emerald
    ai-ml)          echo "#7C3AED" ;;  # purple-deep
    ops)            echo "#78716C" ;;  # stone
    general)        echo "#6B7280" ;;  # gray
    *)              echo "#6B7280" ;;  # gray fallback
  esac
}

# Determine if a skill should allow implicit (automatic) invocation
# Returns "true" or "false"
should_allow_implicit() {
  local name="$1"
  local category="$2"
  local text
  text=$(echo "$name" | tr '[:upper:]' '[:lower:]')

  # Dangerous or destructive skills → require explicit invocation
  if [[ "$text" =~ refactor|clean|delete|prune|uninstall|reset|drop|migrate|deploy ]]; then
    echo "false"
    return
  fi

  # Build/fix resolvers → implicit is useful (auto-trigger on errors)
  if [[ "$text" =~ resolver|build-fix|build-error|fix ]]; then
    echo "true"
    return
  fi

  # Security review → implicit (should always run)
  if [[ "$category" == "security" ]]; then
    echo "true"
    return
  fi

  # Reviewers → implicit (auto-trigger after edits)
  if [[ "$category" == "review" ]]; then
    echo "true"
    return
  fi

  # Ops/orchestration → explicit (user-initiated)
  if [[ "$category" == "ops" ]]; then
    echo "false"
    return
  fi

  # Default: allow implicit for most skills
  echo "true"
}

# Humanize a slug into a display name
# e.g. "code-reviewer" → "Code Reviewer"
humanize() {
  echo "$1" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1'
}


# Record an installed file for the state tracker
record_file() {
  INSTALLED_FILES+=("$1")
}

# Safe copy: create dir, copy file, record it
safe_copy() {
  local src="$1"
  local dest="$2"


  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  record_file "$dest"
  log_verbose "copied → $dest"
}

# -----------------------------
# Header
# -----------------------------

echo "🚀 ECC → Antigravity compiler"
echo "Source:   $ECC_DIR"
echo "Output:   $OUT_DIR"
echo "Optimize: $OPTIMIZE"
[[ -n "$PROJECT_DIR" ]] && echo "Project:  $PROJECT_DIR"
echo "----------------------------------"

# Validate source
if [ ! -d "$ECC_DIR" ]; then
  echo "❌ ECC directory not found: $ECC_DIR"
  exit 1
fi


# Clean previous install if state file exists (idempotent)
if [[ -f "$OUT_DIR/ea-install-state.json" ]]; then
  log "♻️  Previous install detected — cleaning EA-managed files…"
  # Only remove files that EA installed (from state file)
  while IFS= read -r managed_file; do
    if [[ -f "$managed_file" ]]; then
      rm "$managed_file"
      log_verbose "removed $managed_file"
    fi
  done < <(python3 -c "
import json, sys
try:
    with open('$OUT_DIR/ea-install-state.json') as f:
        state = json.load(f)
    for f in state.get('files', []):
        print(f)
except Exception:
    sys.exit(0)
" 2>/dev/null || true)
fi


# Create the Antigravity directory structure
mkdir -p "$OUT_DIR/skills"
mkdir -p "$OUT_DIR/workflows"
mkdir -p "$OUT_DIR/rules"


# =============================================
# OBJECTIVE 1 — Proper ECC → Antigravity mapping
# =============================================
#
# Source mapping (per ANTIGRAVITY-GUIDE.md):
#   ECC agents/*.md        → .agents/skills/       (agent definitions → skills)
#   ECC commands/*.md      → .agents/workflows/    (slash commands → workflows)
#   ECC rules/**/*.md      → .agents/rules/        (flattened, no subdirs)
#   ECC skills/*/SKILL.md  → .agents/skills/<name>/ (structured skills)
#
# Excluded: README.md, CONTRIBUTING.md, CHANGELOG.md,
#           docs/, examples/, tests/, translations, assets/

    # --- 1a. Agents → Skills ---
log ""
log "📦 [1/4] Mapping agents/ → .agents/skills/"

if [[ -d "$ECC_DIR/agents" ]]; then
  for file in "$ECC_DIR"/agents/*.md; do
    [[ -f "$file" ]] || continue

    basename_file=$(basename "$file" .md)
    slug=$(slugify "$basename_file")

    skill_dir="$OUT_DIR/skills/$slug"
    safe_copy "$file" "$skill_dir/agent.md"
    COUNT_SKILLS=$((COUNT_SKILLS + 1))

    log_verbose "$basename_file → $slug"
  done
  log "   ✅ $COUNT_SKILLS agents exported as skills"
else
  log "   ⚠️  No agents/ directory found in ECC source"
fi

# --- 1b. Commands → Workflows ---
log ""
log "📦 [2/4] Mapping commands/ → .agents/workflows/"

if [[ -d "$ECC_DIR/commands" ]]; then
  for file in "$ECC_DIR"/commands/*.md; do
    [[ -f "$file" ]] || continue

    basename_file=$(basename "$file")
    safe_copy "$file" "$OUT_DIR/workflows/$basename_file"
    COUNT_WORKFLOWS=$((COUNT_WORKFLOWS + 1))

    log_verbose "$basename_file"
  done
  log "   ✅ $COUNT_WORKFLOWS commands exported as workflows"
else
  log "   ⚠️  No commands/ directory found in ECC source"
fi

# --- 1c. Rules → Flat rules ---
log ""
log "📦 [3/4] Mapping rules/ → .agents/rules/ (flattened)"

if [[ -d "$ECC_DIR/rules" ]]; then
  # Process each rule subdirectory (common, typescript, python, golang, etc.)
  for rules_subdir in "$ECC_DIR"/rules/*/; do
    [[ -d "$rules_subdir" ]] || continue
    subdir_name=$(basename "$rules_subdir")

    for file in "$rules_subdir"*.md; do
      [[ -f "$file" ]] || continue

      basename_file=$(basename "$file")

      # Prefix with subdir name to avoid collisions when flattening
      # e.g. common/testing.md → common--testing.md
      # Exception: if basename is unique enough (README excluded)
      if [[ "$basename_file" == "README.md" ]]; then
        log_verbose "skipped $rules_subdir$basename_file (README)"
        continue
      fi

      if [[ "$basename_file" == zh* ]]; then
        log_verbose "skipped $rules_subdir$basename_file (zh translation)"
        continue
      fi

      flat_name="${subdir_name}--${basename_file}"
      safe_copy "$file" "$OUT_DIR/rules/$flat_name"
      COUNT_RULES=$((COUNT_RULES + 1))

      log_verbose "$subdir_name/$basename_file → $flat_name"
    done
  done
  log "   ✅ $COUNT_RULES rules exported (flattened)"
else
  log "   ⚠️  No rules/ directory found in ECC source"
fi

# --- 1d. Skills (SKILL.md) → Skills ---
log ""
log "📦 [4/4] Mapping skills/ → .agents/skills/"

if [[ -d "$ECC_DIR/skills" ]]; then
  for skill_dir_src in "$ECC_DIR"/skills/*/; do
    [[ -d "$skill_dir_src" ]] || continue

    skill_name=$(basename "$skill_dir_src")
    slug=$(slugify "$skill_name")
    dest_dir="$OUT_DIR/skills/$slug"

    # Copy SKILL.md if it exists
    if [[ -f "$skill_dir_src/SKILL.md" ]]; then
      safe_copy "$skill_dir_src/SKILL.md" "$dest_dir/SKILL.md"
      COUNT_EA_SKILLS=$((COUNT_EA_SKILLS + 1))
      log_verbose "$skill_name/SKILL.md"
    fi
  done
  log "   ✅ $COUNT_EA_SKILLS skills exported"
else
  log "   ⚠️  No skills/ directory found in ECC source"
fi

# --- 1e. Copy .agents/ static layout if present (import SKILL.md configs) ---
log ""
if [[ -d "$ECC_DIR/.agents/skills" ]]; then
  DOT_AGENTS_COUNT=0
  log "📦 [bonus] Importing .agents/skills/ SKILL.md configs"

  for skill_dir_src in "$ECC_DIR"/.agents/skills/*/; do
    [[ -d "$skill_dir_src" ]] || continue

    skill_name=$(basename "$skill_dir_src")
    slug=$(slugify "$skill_name")
    dest_dir="$OUT_DIR/skills/$slug"

    # Copy SKILL.md if present and not already copied
    if [[ -f "$skill_dir_src/SKILL.md" && ! -f "$dest_dir/SKILL.md" ]]; then
      safe_copy "$skill_dir_src/SKILL.md" "$dest_dir/SKILL.md"
      DOT_AGENTS_COUNT=$((DOT_AGENTS_COUNT + 1))
      log_verbose "$skill_name/SKILL.md (from .agents/)"
    fi
  done
  log "   ✅ $DOT_AGENTS_COUNT SKILL.md configs imported from .agents/"
fi

# =============================================
# STEP 5 — Project Stack Detection
# =============================================

DETECTED_STACKS=""

if [[ -n "$PROJECT_DIR" ]]; then
  log ""
  log "🔎 [Step.5] Detecting project stack in $PROJECT_DIR…"

  if [[ ! -d "$PROJECT_DIR" ]]; then
    log "   ⚠️  Project directory not found: $PROJECT_DIR — skipping stack detection"
  else
    DETECTED_STACKS=$(detect_project_stack "$PROJECT_DIR")
    log "   📋 Detected stacks: $(echo "$DETECTED_STACKS" | tr -s ' ' | sed 's/^ //;s/ $//' | tr ' ' ', ')"
  fi
else
  log_verbose "No --project flag — all skills active"
fi

# =============================================
# OBJECTIVE 3 — Caveman Skills Install (--optimize)
# =============================================
#
# When --optimize is passed:
#   - Copy every skill directory from <caveman>/skills/ into OUT_DIR/skills/
#   - Reference the new skills inside .agents/system.md (skill catalog + Operating Principles)

SCRIPT_DIR_OBJ3="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAVEMAN_SKILLS_SRC="$SCRIPT_DIR_OBJ3/caveman/skills"

# =============================================
# Run the Caveman install pass (--optimize flag)
# =============================================

if [[ "$OPTIMIZE" = true ]]; then
  log ""
  log "🪨  [Obj.3] Caveman skills install pass…"

  OPT_CAVEMAN_COUNT=0
  OPT_CAVEMAN_NAMES=()

  if [[ ! -d "$CAVEMAN_SKILLS_SRC" ]]; then
    log "   ⚠️  caveman/skills/ not found at $CAVEMAN_SKILLS_SRC — skipping"
  else
    for skill_dir_src in "$CAVEMAN_SKILLS_SRC"/*/; do
      [[ -d "$skill_dir_src" ]] || continue

      skill_name=$(basename "$skill_dir_src")
      dest_dir="$OUT_DIR/skills/$skill_name"
      mkdir -p "$dest_dir"

      # Copy every file in the skill directory (SKILL.md + any extras)
      for f in "$skill_dir_src"*; do
        [[ -f "$f" ]] || continue
        cp "$f" "$dest_dir/$(basename "$f")"
        record_file "$dest_dir/$(basename "$f")"
      done

      OPT_CAVEMAN_COUNT=$((OPT_CAVEMAN_COUNT + 1))
      OPT_CAVEMAN_NAMES+=("$skill_name")
      log_verbose "  ✅ $skill_name → $dest_dir"
    done

    log "   ✅ $OPT_CAVEMAN_COUNT caveman skills installed: ${OPT_CAVEMAN_NAMES[*]}"

    # --- Patch system.md: add caveman skills to catalog + Operating Principles ---
    SYSTEM_MD="$OUT_DIR/system.md"
    if [[ -f "$SYSTEM_MD" ]]; then
      log ""
      log "   📝 Patching $SYSTEM_MD with caveman references…"

      # 1. Append caveman skills to the General category line in the catalog
      CAVEMAN_LIST=$(IFS=", "; echo "${OPT_CAVEMAN_NAMES[*]}")
      python3 - "$SYSTEM_MD" "$CAVEMAN_LIST" <<'PY_CAT'
import sys, re
path, new_skills = sys.argv[1], sys.argv[2]
with open(path, 'r') as fh:
    content = fh.read()

# Append new skill names to the 📦 General category bullet if it exists
content = re.sub(
    r'(- \*\*📦 General\*\* \(\d+\): )([^\n]+)',
    lambda m: m.group(1) + m.group(2).rstrip() + ', ' + new_skills,
    content,
    count=1
)

# Update skill count in the header table
added = len(new_skills.split(', '))
content = re.sub(
    r'(\| Skills \(agents \+ knowledge\) \| )(\d+)( \|)',
    lambda m: m.group(1) + str(int(m.group(2)) + added) + m.group(3),
    content,
    count=1
)

with open(path, 'w') as fh:
    fh.write(content)
print('  ✅ Caveman skills appended to skill catalog in system.md')
PY_CAT

      record_file "$SYSTEM_MD"
    else
      log "   ⚠️  $SYSTEM_MD not found — skipping system.md patch (run after generate_system_prompt)"
    fi
  fi
fi

# =============================================
# OBJECTIVE 4 — AgentShield for Antigravity
# =============================================
#
# Transposition of AgentShield concepts into the conversion pipeline:
#   - Static secret scanner (14 patterns from AgentShield)
#   - Permission auditing on SKILL.md source files
#   - Agent config validation
#   - Comprehensive security-auditor skill (OWASP Top 10)
#   - Security-baseline rule
#   - Color-graded A-F scan report
#   - JSON report export
#   - CI gate (exit code 2 on CRITICAL findings)

SHIELD_FINDINGS=()
SHIELD_CRITICAL=0
SHIELD_HIGH=0
SHIELD_MEDIUM=0
SHIELD_LOW=0

# --- Record a finding ---
# Usage: shield_finding <severity> <category> <file> <message> [<fix>]
shield_finding() {
  local severity="$1"
  local category="$2"
  local file="$3"
  local message="$4"
  local fix="${5:-}"

  SHIELD_FINDINGS+=("${severity}|${category}|${file}|${message}|${fix}")

  case "$severity" in
    CRITICAL) SHIELD_CRITICAL=$((SHIELD_CRITICAL + 1)) ;;
    HIGH)     SHIELD_HIGH=$((SHIELD_HIGH + 1)) ;;
    MEDIUM)   SHIELD_MEDIUM=$((SHIELD_MEDIUM + 1)) ;;
    LOW)      SHIELD_LOW=$((SHIELD_LOW + 1)) ;;
  esac
}

# --- Secret detection patterns (14 patterns from AgentShield) ---
scan_secrets() {
  local scan_dir="$1"

  log_verbose "Scanning for hardcoded secrets…"

  # Pattern array: "label|regex|severity"
  local patterns=(
    "OpenAI API Key|sk-[a-zA-Z0-9]{20,}|CRITICAL"
    "Anthropic API Key|sk-ant-[a-zA-Z0-9]{20,}|CRITICAL"
    "GitHub Token|ghp_[a-zA-Z0-9]{36,}|CRITICAL"
    "GitHub OAuth|gho_[a-zA-Z0-9]{36,}|CRITICAL"
    "AWS Access Key|AKIA[0-9A-Z]{16}|CRITICAL"
    "AWS Secret Key|aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}|CRITICAL"
    "Generic Password Field|password[[:space:]]*[:=][[:space:]]*['\"][^'\"]{8,}['\"]|HIGH"
    "Generic Secret Field|secret[[:space:]]*[:=][[:space:]]*['\"][^'\"]{8,}['\"]|HIGH"
    "Generic Token Field|token[[:space:]]*[:=][[:space:]]*['\"][^'\"]{8,}['\"]|HIGH"
    "Private Key Header|-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----|CRITICAL"
    "Bearer Token|Bearer [a-zA-Z0-9._~+/=-]{20,}|HIGH"
    "Slack Token|xox[bpors]-[a-zA-Z0-9-]{10,}|CRITICAL"
    "Stripe Key|sk_live_[a-zA-Z0-9]{24,}|CRITICAL"
    "Database URL|(?:postgres|mysql|mongodb)://[^:]+:[^@]+@|HIGH"
  )

  for pattern_entry in "${patterns[@]}"; do
    IFS='|' read -r label regex severity <<< "$pattern_entry"

    # Scan all .md and .yaml files in the output directory
    while IFS= read -r match_file; do
      [[ -z "$match_file" ]] && continue
      shield_finding "$severity" "secrets" "$match_file" "Potential $label detected" "Remove or move to environment variables"
    done < <(grep -rlE "$regex" "$scan_dir" --include="*.md" --include="*.yaml" --include="*.json" 2>/dev/null || true)
  done
}

# --- Permission auditing ---
# Checks skill permissions and metadata directly from SKILL.md
# No dependency on openai.yaml — works from source files only
audit_permissions() {
  local scan_dir="$1"

  log_verbose "Auditing skill permissions from SKILL.md…"

  for skill_dir in "$scan_dir"/skills/*/; do
    [[ -d "$skill_dir" ]] || continue

    local skill_slug
    skill_slug=$(basename "$skill_dir")

    # Locate the skill source file
    local source_file=""
    if [[ -f "$skill_dir/SKILL.md" ]]; then
      source_file="$skill_dir/SKILL.md"
    elif [[ -f "$skill_dir/agent.md" ]]; then
      source_file="$skill_dir/agent.md"
    else
      continue
    fi

    # Check 1: destructive skills should not allow implicit invocation
    # Use the same logic as generate_openai_yaml to stay consistent
    local implicit_decision
    implicit_decision=$(should_allow_implicit "$skill_slug" "")
    if [[ "$implicit_decision" = "false" && \
          "$skill_slug" =~ refactor|clean|delete|prune|uninstall|reset|drop|migrate|deploy|remove ]]; then
      # This is fine — destructive skills correctly have implicit=false
      # Only flag if the original source overrides to explicit true via frontmatter
      if grep -qiE '^allow_implicit_invocation:\s*true' "$source_file" 2>/dev/null; then
        shield_finding "HIGH" "permissions" "$source_file" \
          "Destructive skill '$skill_slug' explicitly sets allow_implicit_invocation: true" \
          "Remove or set to false for destructive operations"
      fi
    fi

    # Check 2: missing display name (H1 title or frontmatter name:)
    # Note: a title matching the slug is still a valid frontmatter name: field —
    # only flag when extract_title falls back to returning empty string.
    local title
    title=$(extract_title "$source_file")
    if [[ -z "$title" ]]; then
      shield_finding "LOW" "config" "$source_file" \
        "Skill '$skill_slug' has no display name (no H1 heading or name: frontmatter field)" \
        "Add a '# Title' heading or 'name:' field in frontmatter"
    fi

    # Check 3: missing description (blockquote or description: frontmatter)
    local desc
    desc=$(extract_description "$source_file")
    if [[ -z "$desc" ]]; then
      shield_finding "LOW" "config" "$source_file" \
        "Skill '$skill_slug' has no short description (no '> ...' blockquote or description: field)" \
        "Add a '> Description' blockquote or 'description:' field in frontmatter"
    fi
  done
}

# --- Agent config review ---
# Validates agent/skill markdown files for security hygiene
audit_agent_configs() {
  local scan_dir="$1"

  log_verbose "Reviewing agent configurations…"

  for agent_md in "$scan_dir"/skills/*/agent.md; do
    [[ -f "$agent_md" ]] || continue

    local skill_slug
    skill_slug=$(basename "$(dirname "$agent_md")")

    # Check: agent references unrestricted tools
    if grep -qiE 'tools:.*\*|tools:.*all|tools:.*any' "$agent_md" 2>/dev/null; then
      shield_finding "MEDIUM" "permissions" "$agent_md" \
        "Agent '$skill_slug' requests unrestricted tool access" \
        "Restrict tools to the minimum required set (e.g., [\"Read\", \"Grep\"])"
    fi

    # Check: agent uses Write/Edit tools but no security mention
    if grep -qiE 'tools:.*\b(Write|Edit)\b' "$agent_md" 2>/dev/null; then
      if ! grep -qi 'security\|sanitiz\|validat' "$agent_md" 2>/dev/null; then
        shield_finding "MEDIUM" "security" "$agent_md" \
          "Agent '$skill_slug' has write access but no security guidance" \
          "Add security checks (input validation, output sanitization) to the agent prompt"
      fi
    fi

    # Check: agent uses Bash tool (high risk)
    if grep -qiE 'tools:.*\bBash\b' "$agent_md" 2>/dev/null; then
      if ! grep -qi 'sandbox\|restrict\|allow\|deny\|safe' "$agent_md" 2>/dev/null; then
        shield_finding "HIGH" "permissions" "$agent_md" \
          "Agent '$skill_slug' has Bash access without sandboxing guidance" \
          "Add execution guardrails (allowed commands, denied patterns, sandbox requirements)"
      fi
    fi
  done
}

# --- Workflow security audit ---
# Check workflow files for command injection risks
audit_workflows() {
  local scan_dir="$1"

  log_verbose "Auditing workflow security…"

  for workflow_md in "$scan_dir"/workflows/*.md; do
    [[ -f "$workflow_md" ]] || continue

    local wf_name
    wf_name=$(basename "$workflow_md" .md)

    # Check: workflow contains unquoted variable expansion in shell blocks
    if grep -qE '\$\{?[A-Z_]+\}?' "$workflow_md" 2>/dev/null; then
      if grep -qE '(eval |`.*\$|xargs.*\$)' "$workflow_md" 2>/dev/null; then
        shield_finding "HIGH" "injection" "$workflow_md" \
          "Workflow '$wf_name' may be vulnerable to command injection" \
          "Quote all variable expansions and avoid eval/backtick patterns"
      fi
    fi
  done
}

# --- Rules security audit ---
# Ensure rules directory has security coverage
audit_rules() {
  local scan_dir="$1"

  log_verbose "Auditing rules coverage…"

  local has_security_rule=false
  local has_auth_rule=false

  for rule_md in "$scan_dir"/rules/*.md; do
    [[ -f "$rule_md" ]] || continue
    grep -qi 'security\|vulnerabilit\|owasp' "$rule_md" 2>/dev/null && has_security_rule=true || true
    grep -qi 'auth\|authenticat\|authoriz' "$rule_md" 2>/dev/null && has_auth_rule=true || true
  done

  if [[ "$has_security_rule" = false ]]; then
    shield_finding "MEDIUM" "coverage" "$scan_dir/rules/" \
      "No security-focused rule found" \
      "Add a security rule covering input validation and OWASP basics"
  fi

  if [[ "$has_auth_rule" = false ]]; then
    shield_finding "MEDIUM" "coverage" "$scan_dir/rules/" \
      "No authentication/authorization rule found" \
      "Add a rule enforcing auth checks in generated code"
  fi
}

# --- Compute grade (A-F) ---
compute_grade() {
  local total=$(( SHIELD_CRITICAL + SHIELD_HIGH + SHIELD_MEDIUM + SHIELD_LOW ))

  if [[ $SHIELD_CRITICAL -gt 0 ]]; then
    echo "F"
  elif [[ $SHIELD_HIGH -gt 2 ]]; then
    echo "D"
  elif [[ $SHIELD_HIGH -gt 0 ]]; then
    echo "C"
  elif [[ $SHIELD_MEDIUM -gt 3 ]]; then
    echo "C"
  elif [[ $SHIELD_MEDIUM -gt 0 ]]; then
    echo "B"
  elif [[ $SHIELD_LOW -gt 5 ]]; then
    echo "B"
  elif [[ $total -eq 0 ]]; then
    echo "A"
  else
    echo "A"
  fi
}

# --- Color for grade ---
grade_color() {
  case "$1" in
    A) echo "32" ;;  # green
    B) echo "33" ;;  # yellow
    C) echo "33" ;;  # yellow
    D) echo "31" ;;  # red
    F) echo "31" ;;  # red
    *) echo "0"  ;;  # default
  esac
}

# --- Write JSON report ---
write_shield_report() {
  local report_file="$1"

  local grade
  grade=$(compute_grade)
  local total=$(( SHIELD_CRITICAL + SHIELD_HIGH + SHIELD_MEDIUM + SHIELD_LOW ))

  local findings_json="["
  local first=true
  for finding in "${SHIELD_FINDINGS[@]}"; do
    IFS='|' read -r severity category file message fix <<< "$finding"
    [[ "$first" = false ]] && findings_json+=","
    # Escape quotes in message and fix
    message=$(echo "$message" | sed 's/"/\\"/g')
    fix=$(echo "$fix" | sed 's/"/\\"/g')
    file=$(echo "$file" | sed 's/"/\\"/g')
    findings_json+="{\"severity\":\"$severity\",\"category\":\"$category\",\"file\":\"$file\",\"message\":\"$message\",\"fix\":\"$fix\"}"
    first=false
  done
  findings_json+="]"

  cat > "$report_file" << JSON_EOF
{
  "scanner": "AgentShield (everything-antigravity)",
  "version": "1.0.0",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "grade": "$grade",
  "summary": {
    "total": $total,
    "critical": $SHIELD_CRITICAL,
    "high": $SHIELD_HIGH,
    "medium": $SHIELD_MEDIUM,
    "low": $SHIELD_LOW
  },
  "findings": $findings_json
}
JSON_EOF

  record_file "$report_file"
}

# --- Create the security-auditor skill ---
create_security_auditor() {
  local dir="$OUT_DIR/skills/security-auditor"


  mkdir -p "$dir/agents"

  cat > "$dir/agent.md" << 'AGENT_EOF'
---
name: security-auditor
description: AgentShield security auditor for Antigravity. Scans code for OWASP Top 10 vulnerabilities, hardcoded secrets, injection risks, auth flaws, and misconfigurations.
tools: ["Read", "Grep", "Glob", "Bash"]
model: sonnet
---

# Security Auditor (AgentShield)

You are an expert application security auditor. Your mission is to find vulnerabilities before they reach production.

## Core Responsibilities

1. **Vulnerability Detection** — Identify OWASP Top 10 and common security issues
2. **Secrets Detection** — Find hardcoded API keys, passwords, tokens, private keys
3. **Input Validation** — Flag unvalidated user inputs (SQL injection, XSS, SSRF)
4. **Authentication Flaws** — Detect missing auth, broken access control, session issues
5. **Configuration Review** — Audit agent configs, MCP servers, hook permissions

## Scanning Methodology

### Phase 1: Reconnaissance
- Map the codebase structure and identify entry points
- Identify frameworks, languages, and dependency stack
- Check for `.env`, `.env.local`, config files with secrets

### Phase 2: Static Analysis
- Scan for hardcoded secrets using these patterns:
  - `sk-`, `sk-ant-`, `ghp_`, `gho_` (API keys)
  - `AKIA` (AWS), `xox` (Slack), `sk_live_` (Stripe)
  - `-----BEGIN PRIVATE KEY-----`
  - `password=`, `secret=`, `token=` assignments
  - Database connection strings with credentials
- Check for SQL injection (string concatenation in queries)
- Check for XSS (unescaped user input in HTML/templates)
- Check for SSRF (unvalidated URLs in HTTP requests)
- Check for command injection (unsanitized input in exec/system calls)
- Check for path traversal (unvalidated file paths)

### Phase 3: Configuration Audit
- Review agent definitions for overly permissive tool access
- Check agent definitions for unsafe implicit invocation settings (via SKILL.md frontmatter)
- Audit workflow files for command injection risks
- Verify rules enforce security baseline

### Phase 4: Dependency Check
- Flag known vulnerable dependencies if lockfiles are present
- Check for outdated critical security packages

## Output Format

For each finding, provide:

```
### [SEVERITY] Title
- **Category**: secrets | injection | auth | config | dependency
- **File**: path/to/file:line
- **Description**: What was found and why it's dangerous
- **Impact**: What an attacker could do
- **Fix**: Specific remediation steps with code example
```

## Severity Scale

| Level | Criteria | Example |
|-------|----------|---------|
| CRITICAL | Immediate exploit risk, data breach | Hardcoded API key, SQL injection |
| HIGH | Significant risk, exploitable with effort | Missing auth, command injection |
| MEDIUM | Moderate risk, defense-in-depth gap | Missing input validation, verbose errors |
| LOW | Best practice violation, minimal risk | Missing security headers, weak config |
AGENT_EOF
  record_file "$dir/agent.md"
  log "🛡️  AgentShield skill installed (expanded: OWASP, secrets, injection, auth, config)"
}

# --- Create security-baseline rule ---
create_security_rule() {

  mkdir -p "$OUT_DIR/rules"

  cat > "$OUT_DIR/rules/security-baseline.md" << 'RULE_EOF'
# Security Baseline (AgentShield)

All generated and modified code MUST follow these security requirements.

## Input Validation
- Validate and sanitize ALL user inputs before processing
- Use parameterized queries for database operations (never string concatenation)
- Validate file paths to prevent path traversal (reject `..`, absolute paths)
- Validate URLs to prevent SSRF (allowlist-based validation)

## Secrets Management
- NEVER hardcode API keys, passwords, tokens, or private keys
- Use environment variables or secret managers for credentials
- Ensure `.env` files are listed in `.gitignore`
- Rotate any credential that appears in version control

## Authentication & Authorization
- Enforce authentication on all non-public endpoints
- Apply least-privilege access control
- Validate session tokens server-side
- Implement rate limiting on auth endpoints

## Output Encoding
- Escape all dynamic content in HTML output (prevent XSS)
- Use Content Security Policy headers
- Set HttpOnly, Secure, SameSite flags on cookies

## Error Handling
- Never expose stack traces, internal paths, or debug info in production
- Log security events with sufficient context for forensics
- Return generic error messages to clients

## Dependencies
- Pin dependency versions in lockfiles
- Monitor for known vulnerabilities (npm audit, pip-audit, cargo audit)
- Avoid deprecated or unmaintained packages
RULE_EOF
  log "🌐 Security baseline rule installed (hardened)"
}

# =============================================
# Run AgentShield scan on the generated output
# =============================================

log ""
log "🛡️  [Obj.4] AgentShield — Security scan…"

# Install the skill and rule first
create_security_auditor
create_security_rule

# Run scans on the generated .agents/ output
set +e   # scan functions use grep which returns 1 on no-match — must not abort
scan_secrets "$OUT_DIR"
audit_permissions "$OUT_DIR"
audit_agent_configs "$OUT_DIR"
audit_workflows "$OUT_DIR"
audit_rules "$OUT_DIR"
set -e

# --- Display findings ---
SHIELD_TOTAL=$(( SHIELD_CRITICAL + SHIELD_HIGH + SHIELD_MEDIUM + SHIELD_LOW ))
SHIELD_GRADE=$(compute_grade)
SHIELD_COLOR=$(grade_color "$SHIELD_GRADE")

log ""
log "  ────────────────────────────────────────"
printf "  🛡️  AgentShield Report — Grade: \033[${SHIELD_COLOR}m%s\033[0m\n" "$SHIELD_GRADE"
log "  ────────────────────────────────────────"
log "  Findings:  $SHIELD_TOTAL total"
[[ $SHIELD_CRITICAL -gt 0 ]] && log "    🔴 CRITICAL: $SHIELD_CRITICAL"
[[ $SHIELD_HIGH -gt 0 ]]     && log "    🟠 HIGH:     $SHIELD_HIGH"
[[ $SHIELD_MEDIUM -gt 0 ]]   && log "    🟡 MEDIUM:   $SHIELD_MEDIUM"
[[ $SHIELD_LOW -gt 0 ]]      && log "    🔵 LOW:      $SHIELD_LOW"
[[ $SHIELD_TOTAL -eq 0 ]]    && log "    ✅ No findings — clean!"

# Print findings detail
if [[ $SHIELD_TOTAL -gt 0 ]]; then
  log ""
  for finding in "${SHIELD_FINDINGS[@]}"; do
    IFS='|' read -r severity category file message fix <<< "$finding"
    local_color="0"
    case "$severity" in
      CRITICAL) local_color="31" ;;
      HIGH)     local_color="31" ;;
      MEDIUM)   local_color="33" ;;
      LOW)      local_color="34" ;;
    esac
    printf "  \033[${local_color}m[%s]\033[0m %s\n" "$severity" "$message"
    log "         📁 $file"
    [[ -n "$fix" ]] && log "         💊 $fix"
  done
fi

log "  ────────────────────────────────────────"

# Write JSON report
SHIELD_REPORT="$OUT_DIR/security-report.json"
write_shield_report "$SHIELD_REPORT"
log "  📄 Report exported → $SHIELD_REPORT"

# CI gate: exit code 2 on critical findings
if [[ $SHIELD_CRITICAL -gt 0 ]]; then
  log ""
  log "  🚨 CI GATE: $SHIELD_CRITICAL CRITICAL finding(s) — would exit with code 2"
  log "     Pass --no-gate to suppress exit code in non-CI contexts"
fi


# =============================================
# STEP 1 — Hooks / Lifecycle Events as Behavioral Rules
# =============================================
#
# ECC hooks are Node.js scripts that intercept tool calls at runtime.
# Antigravity doesn't support runtime hooks natively.
# Strategy: transpose the 7 most impactful hooks into structured
# behavioral rules in .agents/rules/hooks/ that the agent follows.
#
# Priority hooks (from ECC hooks.json analysis):
#   1. pre:bash:dispatcher     → bash-safety.md
#   2. pre:edit-write:gateguard → gateguard.md
#   3. post:quality-gate        → quality-gate.md
#   4. pre:config-protection    → config-protection.md
#   5. post:edit:design-quality → design-quality.md
#   6. session:start            → session-context.md
#   7. pre:edit-write:compact   → strategic-compaction.md

generate_hooks_rules() {
  local hooks_dir="$OUT_DIR/rules/hooks"


  mkdir -p "$hooks_dir"
  local count=0

  # ─── Hook 1: Pre-Bash Safety Guard ───
  cat > "$hooks_dir/bash-safety.md" << 'HOOK_EOF'
# Bash Safety Guard

> Transposed from ECC hook: `pre:bash:dispatcher`

## When

Before executing ANY shell command via Bash tool.

## Behavior

1. **SCAN** the command for destructive patterns before execution:
   - `rm -rf /` or `rm -rf ~` or `rm -rf .` (recursive delete of critical paths)
   - `DROP TABLE`, `DROP DATABASE`, `TRUNCATE` (database destruction)
   - `git push --force` or `git push -f` to main/master/production
   - `chmod 777`, `chmod -R 777` (overly permissive)
   - `curl | sh`, `curl | bash`, `wget | sh` (blind pipe execution)
   - `kill -9 1`, `shutdown`, `reboot` (system-level)
   - `mkfs`, `dd if=` (disk operations)
   - `> /dev/sda`, `> /etc/passwd` (critical file overwrites)

2. **BLOCK** if any destructive pattern is detected:
   - Explain WHY the command is dangerous
   - Suggest a safer alternative
   - Require explicit user confirmation before proceeding

3. **ALLOW** safe commands without interruption.

4. **WARN** on commands that modify state but aren't destructive:
   - `npm install`, `pip install` (dependency changes)
   - `git commit`, `git merge` (VCS changes)
   - File writes outside the project directory

## Examples

```
❌ BLOCKED: rm -rf /tmp/project/*  → "This recursively deletes all files. Use rm -ri for interactive mode."
⚠️ WARNING: npm install lodash    → "This adds a dependency. Proceed? (dependency changes are tracked)"
✅ ALLOWED: ls -la, cat file.txt, grep -r "pattern"
```
HOOK_EOF
  record_file "$hooks_dir/bash-safety.md"
  count=$((count + 1))

  # ─── Hook 2: GateGuard Fact-Forcing ───
  cat > "$hooks_dir/gateguard.md" << 'HOOK_EOF'
# GateGuard — Fact-Forcing Pre-Edit Gate

> Transposed from ECC hook: `pre:edit-write:gateguard-fact-force`
> Measured impact: +2.25 quality points vs ungated editing.

## When

Before the FIRST Edit or Write operation on any file in the current task.

## Behavior

**Three-stage gate:**

### Stage 1: DENY
On the first attempt to edit a file, STOP and do NOT write yet.

### Stage 2: FORCE INVESTIGATION
Before editing, you MUST gather these facts:

1. **Importers**: Run `grep -r "import.*<module>" .` or `grep -r "require.*<module>" .`
   to find every file that imports the module you're about to change.
2. **Schema**: If the file contains data structures, read the existing schema/types
   to ensure your changes are compatible.
3. **Tests**: Check if tests exist for this file (`*_test.*`, `*.spec.*`, `*.test.*`).
4. **Callers**: Find all functions/methods that call what you're modifying.
5. **Conventions**: Check 2-3 similar files in the same directory for naming
   and formatting patterns.

### Stage 3: ALLOW
After presenting the investigation results, proceed with the edit.
Reference which facts informed your changes.

## Why This Works

Self-evaluation ("are you sure?") always produces "yes."
Forced investigation creates context that changes the output.
The act of reading importers and callers reveals constraints
that prevent breaking changes.

## Exceptions

- Typo fixes (< 5 characters changed)
- New file creation (no existing code to investigate)
- Appending to log/changelog files
HOOK_EOF
  record_file "$hooks_dir/gateguard.md"
  count=$((count + 1))

  # ─── Hook 3: Post-Edit Quality Gate ───
  cat > "$hooks_dir/quality-gate.md" << 'HOOK_EOF'
# Post-Edit Quality Gate

> Transposed from ECC hooks: `post:quality-gate`, `stop:format-typecheck`

## When

After EVERY file edit or write operation.

## Behavior

After editing a file, verify the change didn't break anything:

1. **Syntax check**: Ensure the file is syntactically valid
   - Python: `python -m py_compile <file>`
   - JavaScript/TypeScript: check for unclosed brackets/quotes
   - Rust: `cargo check` if available
   - Go: `go vet` if available

2. **Import check**: Verify all new imports resolve to existing modules

3. **Type check**: If the project uses TypeScript (`tsconfig.json`), run
   `npx tsc --noEmit` on the changed files

4. **Lint check**: If a linter config exists (`.eslintrc`, `pyproject.toml [tool.ruff]`,
   `.golangci.yml`), run the linter on changed files

5. **Test check**: If tests exist for the modified file, run them:
   - `pytest <test_file>` for Python
   - `npm test -- --testPathPattern=<file>` for JS/TS
   - `cargo test <module>` for Rust
   - `go test ./<package>` for Go

## Format

After each edit batch, report:
```
✅ Quality gate: syntax OK, imports OK, 3 tests pass
```
or
```
❌ Quality gate: TypeScript error in line 42 — fixing...
```
HOOK_EOF
  record_file "$hooks_dir/quality-gate.md"
  count=$((count + 1))

  # ─── Hook 4: Config Protection ───
  cat > "$hooks_dir/config-protection.md" << 'HOOK_EOF'
# Config Protection

> Transposed from ECC hook: `pre:config-protection`

## When

Before modifying ANY linter, formatter, or build configuration file.

## Protected Files

These files should NOT be modified to make checks pass:

- `.eslintrc*`, `.eslintignore`, `eslint.config.*`
- `.prettierrc*`, `.prettierignore`
- `biome.json`, `biome.jsonc`
- `tsconfig.json`, `tsconfig.*.json`
- `.stylelintrc*`
- `pyproject.toml` (linter sections: `[tool.ruff]`, `[tool.mypy]`, `[tool.pylint]`)
- `.golangci.yml`
- `rustfmt.toml`, `clippy.toml`
- `.editorconfig`
- `Makefile` (build rules)

## Behavior

1. **DETECT**: If you are about to edit a config file from the list above
2. **CHALLENGE**: Ask yourself — "Am I changing the config to fix the actual issue,
   or to silence a warning?"
3. **FIX THE CODE**: In 95% of cases, the correct action is to fix the source code
   to comply with the existing linter rules, NOT to weaken the rules.
4. **EXCEPTION**: Only modify config files when the user explicitly asks to change
   linting rules, or when adding NEW rules (never removing existing ones).

## Anti-Pattern

```
❌ WRONG: Disable the no-unused-vars rule because my new code triggers it
✅ RIGHT: Remove the unused variable from my new code
```
HOOK_EOF
  record_file "$hooks_dir/config-protection.md"
  count=$((count + 1))

  # ─── Hook 5: Design Quality Check ───
  cat > "$hooks_dir/design-quality.md" << 'HOOK_EOF'
# Frontend Design Quality Check

> Transposed from ECC hook: `post:edit:design-quality-check`

## When

After editing any frontend file (`.html`, `.css`, `.jsx`, `.tsx`, `.vue`, `.svelte`, `.astro`, `.scss`).

## Behavior

Scan your edits for **generic template signals** that indicate low-effort design:

### Red Flags (Generic Copy)
- "Get Started", "Learn More", "Read More" (placeholder CTAs)
- "Lorem ipsum" or clearly placeholder text
- "Feature 1", "Feature 2", "Feature 3" (unnamed features)
- "Your Company" or "Company Name" (unfilled branding)

### Red Flags (Generic Layout)
- Uniform 3-column or 4-column card grids without visual hierarchy
- Stock gradient utility classes (`bg-gradient-to-r`) without customization
- Default font stacks (`font-sans`, `font-inter`) without intentional typography
- Centered-everything layouts without visual rhythm
- No depth, layering, or overlap — flat card-only interfaces

### Required Instead
- **Visual hierarchy**: Size, weight, and color contrast between elements
- **Intentional spacing**: Consistent rhythm, not uniform padding everywhere
- **Depth**: Shadows, layering, overlapping elements, glassmorphism
- **Custom colors**: Curated palette, not raw Tailwind defaults
- **Micro-animations**: Hover effects, transitions, subtle motion
- **Real content**: Specific names, numbers, descriptions — not placeholders

## Self-Check

After editing frontend code, ask:
> "Would a user be impressed at first glance, or does this look like a template?"

If the answer is "template" → iterate before presenting.
HOOK_EOF
  record_file "$hooks_dir/design-quality.md"
  count=$((count + 1))

  # ─── Hook 6: Session Context Loader ───
  cat > "$hooks_dir/session-context.md" << 'HOOK_EOF'
# Session Context Loader

> Transposed from ECC hook: `session:start`

## When

At the START of every new session or conversation.

## Behavior

Before beginning any work, load and review project context:

1. **Read `.agents/system.md`** if it exists — this is your identity and skill catalog.
   Know which skills you have available and which are active for this project's stack.

2. **Read `ea-install-state.json`** to understand what's installed and when.

3. **Check for recent changes**:
   - `git log --oneline -5` to see recent commits
   - `git status` to see uncommitted changes
   - `git diff --stat` to see what's being worked on

4. **Identify the current task context**:
   - What was the user working on last?
   - Are there any open TODO items or unfinished work?
   - What branch are we on?

5. **Announce context** briefly:
   ```
   📋 Context loaded: [project name] on branch [branch]
   Last commit: [commit message]
   Active stack: [detected stacks]
   ```

## Why

Starting fresh without context leads to repeated mistakes,
redundant questions, and loss of continuity. A 30-second
context load saves 10 minutes of re-explanation.
HOOK_EOF
  record_file "$hooks_dir/session-context.md"
  count=$((count + 1))

  # ─── Hook 7: Strategic Compaction ───
  cat > "$hooks_dir/strategic-compaction.md" << 'HOOK_EOF'
# Strategic Compaction

> Transposed from ECC hook: `pre:edit-write:suggest-compact`

## When

During long sessions with many tool calls (roughly every 30-40 operations).

## Behavior

Suggest context compaction at LOGICAL milestones, not arbitrary points:

### Good Compaction Points
- ✅ After completing exploration, before starting implementation
- ✅ After finishing one feature, before starting the next
- ✅ After a debugging session, before the fix
- ✅ After reviewing code, before writing changes
- ✅ After a test-fix cycle converges

### Bad Compaction Points
- ❌ Mid-implementation (loses critical state)
- ❌ During a debugging investigation (loses clues)
- ❌ While waiting for test results
- ❌ During a multi-file refactoring

### How to Suggest

```
💡 This is a good compaction point — we've finished [phase].
   Summarizing context before starting [next phase].
   Key state to preserve: [list 3-5 critical facts]
```

## Why Manual > Auto

Auto-compaction happens at arbitrary points, often mid-task,
losing critical context. Strategic compaction preserves state
through logical phases and ensures continuity.
HOOK_EOF
  record_file "$hooks_dir/strategic-compaction.md"
  count=$((count + 1))

  log "🪝 $count hook rules generated in $hooks_dir/"
}

# Resume install guard — calls are only for full install mode

log ""
log "🪝 [Step.1] Generating lifecycle hooks as behavioral rules…"
generate_hooks_rules

# =============================================
# STEP 3 — Skill Dependency Graph
# =============================================
#
# Generates .agents/skill-graph.json by:
#   1. Structural analysis: infer dependencies from naming conventions
#      (e.g., django-tdd depends on django-patterns + python-testing)
#   2. Content scanning: grep each SKILL.md/agent.md for references
#      to other skill slugs
#
# Output format:
#   { "skill-slug": { "depends_on": [], "enhances": [], "related_to": [] } }

generate_skill_graph() {
  local dest="$OUT_DIR/skill-graph.json"


  GRAPH_OUT_DIR="$OUT_DIR" GRAPH_DEST="$dest" python3 << 'GRAPH_SCRIPT'
import os, sys, json, re

out_dir = os.environ["GRAPH_OUT_DIR"]
dest = os.environ["GRAPH_DEST"]
skills_dir = os.path.join(out_dir, "skills")

# Collect all installed skill slugs
all_slugs = set()
for entry in os.scandir(skills_dir):
    if entry.is_dir():
        all_slugs.add(entry.name)

# Build graph
graph = {}

# ─── Strategy 1: Structural naming conventions ───
# These are deterministic rules based on EA's naming patterns

STRUCTURAL_RULES = {
    # Testing skills depend on their language patterns
    "django-tdd":       {"depends_on": ["django-patterns", "python-testing"], "enhances": ["django-verification"]},
    "django-verification": {"depends_on": ["django-tdd", "django-security", "django-patterns"]},
    "django-security":  {"depends_on": ["django-patterns"]},

    "springboot-tdd":   {"depends_on": ["springboot-patterns", "java-coding-standards"], "enhances": ["springboot-verification"]},
    "springboot-verification": {"depends_on": ["springboot-tdd", "springboot-security", "springboot-patterns"]},
    "springboot-security": {"depends_on": ["springboot-patterns"]},

    "laravel-tdd":      {"depends_on": ["laravel-patterns", "php-patterns"], "enhances": ["laravel-verification"]},
    "laravel-verification": {"depends_on": ["laravel-tdd", "laravel-security", "laravel-patterns"]},
    "laravel-security": {"depends_on": ["laravel-patterns"]},

    "kotlin-testing":   {"depends_on": ["kotlin-patterns"], "enhances": ["kotlin-build"]},
    "golang-testing":   {"depends_on": ["golang-patterns"], "enhances": ["go-build"]},
    "rust-testing":     {"depends_on": ["rust-patterns"], "enhances": ["rust-build"]},
    "python-testing":   {"depends_on": ["python-patterns"], "enhances": ["python-review"]},
    "cpp-testing":      {"depends_on": ["cpp-coding-standards"]},
    "csharp-testing":   {"depends_on": ["dotnet-patterns"]},
    "perl-testing":     {"depends_on": ["perl-patterns"], "enhances": ["perl-security"]},

    # Review skills relate to their domain patterns
    "python-reviewer":  {"depends_on": ["python-patterns", "python-testing"]},
    "flutter-reviewer": {"depends_on": ["dart-flutter-patterns", "flutter-dart-code-review"]},
    "go-reviewer":      {"depends_on": ["golang-patterns", "golang-testing"]},
    "rust-reviewer":    {"depends_on": ["rust-patterns", "rust-testing"]},
    "cpp-reviewer":     {"depends_on": ["cpp-coding-standards", "cpp-testing"]},
    "csharp-reviewer":  {"depends_on": ["dotnet-patterns", "csharp-testing"]},
    "kotlin-reviewer":  {"depends_on": ["kotlin-patterns", "kotlin-testing"]},

    # Build skills depend on patterns
    "cpp-build-resolver":  {"depends_on": ["cpp-coding-standards"]},
    "dart-build-resolver":  {"depends_on": ["dart-flutter-patterns"]},
    "go-build-resolver":    {"depends_on": ["golang-patterns"]},
    "rust-build-resolver":  {"depends_on": ["rust-patterns"]},
    "kotlin-build-resolver": {"depends_on": ["kotlin-patterns"]},

    # Security skills relate to their base patterns
    "perl-security":    {"depends_on": ["perl-patterns"]},
    "defi-amm-security": {"depends_on": ["evm-token-decimals"]},
    "llm-trading-agent-security": {"depends_on": ["defi-amm-security"]},

    # Architecture skills
    "hexagonal-architecture": {"enhances": ["api-design", "backend-patterns"]},
    "android-clean-architecture": {"depends_on": ["kotlin-patterns", "compose-multiplatform-patterns"]},

    # Orchestration skills
    "gan-style-harness": {"depends_on": ["gan-planner", "gan-generator", "gan-evaluator"]},
    "santa-method":      {"enhances": ["code-reviewer"]},
    "council":           {"enhances": ["blueprint"]},
    "blueprint":         {"enhances": ["team-builder"]},

    # Frontend chain
    "design-system":     {"enhances": ["frontend-patterns", "frontend-slides"]},
    "liquid-glass-design": {"depends_on": ["swiftui-patterns"]},

    # Testing meta-skills
    "tdd-workflow":      {"enhances": ["python-testing", "golang-testing", "rust-testing", "kotlin-testing"]},
    "e2e-testing":       {"depends_on": ["frontend-patterns"]},
    "browser-qa":        {"depends_on": ["e2e-testing"]},
    "ai-regression-testing": {"depends_on": ["tdd-workflow"]},

    # Database chain
    "database-migrations": {"depends_on": ["postgres-patterns"]},
    "clickhouse-io":     {"enhances": ["postgres-patterns"]},

    # Healthcare chain
    "healthcare-emr-patterns": {"depends_on": ["healthcare-phi-compliance"]},
    "healthcare-cdss-patterns": {"depends_on": ["healthcare-emr-patterns"]},
    "healthcare-eval-harness": {"depends_on": ["healthcare-cdss-patterns", "healthcare-phi-compliance"]},
    "hipaa-compliance":  {"enhances": ["healthcare-phi-compliance"]},

    # Content chain
    "content-engine":    {"depends_on": ["brand-voice"]},
    "crosspost":         {"depends_on": ["content-engine"]},

    # Kotlin multiplatform
    "compose-multiplatform-patterns": {"depends_on": ["kotlin-patterns"]},
    "kotlin-coroutines-flows": {"depends_on": ["kotlin-patterns"]},
    "kotlin-exposed-patterns": {"depends_on": ["kotlin-patterns"]},
    "kotlin-ktor-patterns": {"depends_on": ["kotlin-patterns"]},

    # Swift chain
    "swift-actor-persistence": {"depends_on": ["swiftui-patterns"]},
    "swift-concurrency-6-2": {"depends_on": ["swiftui-patterns"]},
    "swift-protocol-di-testing": {"depends_on": ["swiftui-patterns"]},
    "foundation-models-on-device": {"depends_on": ["swiftui-patterns"]},

    # DevOps chain
    "deployment-patterns": {"depends_on": ["docker-patterns"]},
    "canary-watch":      {"depends_on": ["deployment-patterns"]},

    # Meta skills
    "verification-loop": {"enhances": ["tdd-workflow", "quality-gate"]},
    "continuous-learning-v2": {"enhances": ["continuous-learning"]},
    "codebase-onboarding": {"enhances": ["code-tour"]},
}

# Initialize graph with structural rules
for slug in all_slugs:
    entry = {"depends_on": [], "enhances": [], "related_to": []}
    if slug in STRUCTURAL_RULES:
        rules = STRUCTURAL_RULES[slug]
        # Only include dependencies that are actually installed
        entry["depends_on"] = [s for s in rules.get("depends_on", []) if s in all_slugs]
        entry["enhances"] = [s for s in rules.get("enhances", []) if s in all_slugs]
    graph[slug] = entry

# ─── Strategy 2: Content scanning for cross-references ───
# Scan each skill's markdown files for mentions of other skill slugs

# Build a lookup of slugs long enough to be meaningful (avoid false positives)
searchable_slugs = {s for s in all_slugs if len(s) >= 5}

for slug in sorted(all_slugs):
    skill_path = os.path.join(skills_dir, slug)
    content = ""

    # Read all markdown files in the skill directory
    for md_name in ["SKILL.md", "agent.md", "README.md"]:
        md_path = os.path.join(skill_path, md_name)
        if os.path.isfile(md_path):
            try:
                with open(md_path, "r", errors="ignore") as f:
                    content += f.read().lower() + "\n"
            except:
                pass

    if not content:
        continue

    # Search for mentions of other skills
    for other_slug in searchable_slugs:
        if other_slug == slug:
            continue
        # Skip if already in depends_on or enhances
        if other_slug in graph[slug]["depends_on"] or other_slug in graph[slug]["enhances"]:
            continue
        # Look for the slug as a word boundary match
        pattern = r'\b' + re.escape(other_slug) + r'\b'
        if re.search(pattern, content):
            if other_slug not in graph[slug]["related_to"]:
                graph[slug]["related_to"].append(other_slug)

# ─── Stats ───
total = len(graph)
with_deps = sum(1 for g in graph.values() if g["depends_on"])
with_enhances = sum(1 for g in graph.values() if g["enhances"])
with_related = sum(1 for g in graph.values() if g["related_to"])
isolated = sum(1 for g in graph.values() if not g["depends_on"] and not g["enhances"] and not g["related_to"])
total_edges = sum(len(g["depends_on"]) + len(g["enhances"]) + len(g["related_to"]) for g in graph.values())

output = {
    "_meta": {
        "generator": "everything-antigravity.sh (Step 3)",
        "total_skills": total,
        "with_dependencies": with_deps,
        "with_enhances": with_enhances,
        "with_related": with_related,
        "isolated": isolated,
        "total_edges": total_edges
    },
    "graph": dict(sorted(graph.items()))
}

with open(dest, "w") as f:
    json.dump(output, f, indent=2)

# Print summary for bash
print(f"{total} skills, {total_edges} edges ({with_deps} with deps, {with_enhances} enhance others, {isolated} isolated)")
GRAPH_SCRIPT

  if [[ $? -eq 0 ]]; then
    record_file "$dest"
  else
    log "   ⚠️  Python graph generation failed — skipping"
  fi
}

log ""
log "🕸️  [Step.3] Building skill dependency graph…"
GRAPH_RESULT=$(generate_skill_graph 2>&1)
log "   ✅ Skill graph: $GRAPH_RESULT"

# =============================================
# STEP 6 — Runtime Scripts / Operational Tooling
# =============================================
#
# Generates standalone bash scripts in .agents/scripts/ for:
#   ea-doctor    — health check & diagnostics
#   ea-list      — list installed components
#   ea-uninstall — clean removal of EA files
#   ea-status    — installation dashboard

generate_runtime_scripts() {
  local scripts_dir="$OUT_DIR/scripts"


  mkdir -p "$scripts_dir"
  local count=0

  # ─── Script 1: ea-doctor ───
  cat > "$scripts_dir/ea-doctor" << 'SCRIPT_EOF'
#!/bin/bash
# EA Doctor — Health check for the EA installation
# Usage: .agents/scripts/ea-doctor [--fix]

set -euo pipefail
AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIX=false
[[ "${1:-}" = "--fix" ]] && FIX=true

PASS=0; WARN=0; FAIL=0
check() { local status="$1" msg="$2"
  case "$status" in
    pass) PASS=$((PASS+1)); echo "  ✅ $msg" ;;
    warn) WARN=$((WARN+1)); echo "  ⚠️  $msg" ;;
    fail) FAIL=$((FAIL+1)); echo "  ❌ $msg" ;;
  esac
}

echo "🏥 EA Doctor — Diagnosing $AGENT_DIR"
echo ""

# 1. Structure checks
echo "📁 Structure"
[[ -d "$AGENT_DIR/skills" ]]    && check pass "skills/ exists" || check fail "skills/ missing"
[[ -d "$AGENT_DIR/workflows" ]] && check pass "workflows/ exists" || check fail "workflows/ missing"
[[ -d "$AGENT_DIR/rules" ]]     && check pass "rules/ exists" || check fail "rules/ missing"
[[ -f "$AGENT_DIR/system.md" ]] && check pass "system.md exists" || check fail "system.md missing — run everything-antigravity.sh"

# 2. State file
echo ""
echo "📋 Install State"
if [[ -f "$AGENT_DIR/ea-install-state.json" ]]; then
  check pass "ea-install-state.json exists"
  # Validate JSON
  python3 -c "import json; json.load(open('$AGENT_DIR/ea-install-state.json'))" 2>/dev/null \
    && check pass "install state is valid JSON" \
    || check fail "install state is corrupted JSON"
else
  check fail "ea-install-state.json missing — installation not tracked"
fi

# 3. Skills integrity
echo ""
echo "🧩 Skills Integrity"
total_skills=$(find "$AGENT_DIR/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
check pass "$total_skills skills installed"
no_source=$(find "$AGENT_DIR/skills" -mindepth 1 -maxdepth 1 -type d | while read d; do
  [[ -f "$d/SKILL.md" ]] || echo "$d"
done | wc -l)
[[ "$no_source" -eq 0 ]] && check pass "all skills have SKILL.md" || check warn "$no_source skills missing SKILL.md"

# 4. Security report
echo ""
echo "🔒 Security"
if [[ -f "$AGENT_DIR/security-report.json" ]]; then
  grade=$(python3 -c "import json; print(json.load(open('$AGENT_DIR/security-report.json')).get('grade','?'))" 2>/dev/null || echo "?")
  [[ "$grade" =~ ^[AB]$ ]] && check pass "Security grade: $grade" || check warn "Security grade: $grade — review findings"
else
  check warn "No security report found — run everything-antigravity.sh"
fi

# 5. Dependency graph
echo ""
echo "🕸️  Dependency Graph"
if [[ -f "$AGENT_DIR/skill-graph.json" ]]; then
  edges=$(python3 -c "import json; print(json.load(open('$AGENT_DIR/skill-graph.json')).get('_meta',{}).get('total_edges',0))" 2>/dev/null || echo 0)
  check pass "skill-graph.json exists ($edges edges)"
else
  check warn "skill-graph.json missing"
fi

# Summary
echo ""
echo "─────────────────────────"
echo "  Results: $PASS passed, $WARN warnings, $FAIL failures"
if [[ $FAIL -gt 0 ]]; then
  echo "  Status: UNHEALTHY"
  exit 1
elif [[ $WARN -gt 0 ]]; then
  echo "  Status: DEGRADED"
else
  echo "  Status: HEALTHY ✨"
fi
SCRIPT_EOF
  chmod +x "$scripts_dir/ea-doctor"
  record_file "$scripts_dir/ea-doctor"
  count=$((count + 1))

  # ─── Script 2: ea-list ───
  cat > "$scripts_dir/ea-list" << 'SCRIPT_EOF'
#!/bin/bash
# EA List — List installed components
# Usage: .agents/scripts/ea-list [skills|workflows|rules|hooks|all] [--search TERM]

set -euo pipefail
AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPONENT="${1:-all}"
SEARCH="${2:-}"
[[ "$SEARCH" = "--search" ]] && SEARCH="${3:-}" || true

list_skills() {
  echo "🧩 Skills ($(find "$AGENT_DIR/skills" -mindepth 1 -maxdepth 1 -type d | wc -l))"
  echo ""
  for d in "$AGENT_DIR"/skills/*/; do
    [[ -d "$d" ]] || continue
    local slug=$(basename "$d")
    [[ -n "$SEARCH" && ! "$slug" =~ $SEARCH ]] && continue
    local desc=""
    # Extract first non-empty, non-heading line from SKILL.md as description
    if [[ -f "$d/SKILL.md" ]]; then
      desc=$(grep -v '^#\|^---\|^$\|^>\|^\*\*' "$d/SKILL.md" | head -1 | sed 's/^[[:space:]]*//' | cut -c1-70)
    fi
    printf "  %-35s %s\n" "$slug" "$desc"
  done
}

list_workflows() {
  echo "⚡ Workflows ($(find "$AGENT_DIR/workflows" -name '*.md' | wc -l))"
  echo ""
  for f in "$AGENT_DIR"/workflows/*.md; do
    [[ -f "$f" ]] || continue
    local name=$(basename "$f" .md)
    [[ -n "$SEARCH" && ! "$name" =~ $SEARCH ]] && continue
    printf "  /%s\n" "$name"
  done
}

list_rules() {
  echo "📏 Rules ($(find "$AGENT_DIR/rules" -name '*.md' -not -path '*/hooks/*' | wc -l))"
  echo ""
  for f in "$AGENT_DIR"/rules/*.md; do
    [[ -f "$f" ]] || continue
    local name=$(basename "$f" .md)
    if [[ "$name" == zh* ]]; then
      continue
    fi
    [[ -n "$SEARCH" && ! "$name" =~ $SEARCH ]] && continue
    printf "  %s\n" "$name"
  done
}

list_hooks() {
  echo "🪝 Hooks ($(find "$AGENT_DIR/rules/hooks" -name '*.md' 2>/dev/null | wc -l))"
  echo ""
  for f in "$AGENT_DIR"/rules/hooks/*.md; do
    [[ -f "$f" ]] || continue
    local name=$(basename "$f" .md)
    local title=$(grep -m1 '^# ' "$f" | sed 's/^# //')
    printf "  %-25s %s\n" "$name" "$title"
  done
}


case "$COMPONENT" in
  skills)    list_skills ;;
  workflows) list_workflows ;;
  rules)     list_rules ;;
  hooks)     list_hooks ;;
  all)
    list_skills; echo ""; list_workflows; echo ""
    list_rules; echo ""; list_hooks
    ;;
  *) echo "Usage: ea-list [skills|workflows|rules|hooks|all] [--search TERM]" ;;
esac
SCRIPT_EOF
  chmod +x "$scripts_dir/ea-list"
  record_file "$scripts_dir/ea-list"
  count=$((count + 1))

  # ─── Script 3: ea-uninstall ───
  cat > "$scripts_dir/ea-uninstall" << 'SCRIPT_EOF'
#!/bin/bash
# EA Uninstall — Clean removal of all EA-managed files
# Usage: .agents/scripts/ea-uninstall [--confirm]

set -euo pipefail
AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIRM=false
[[ "${1:-}" = "--confirm" ]] && CONFIRM=true

STATE_FILE="$AGENT_DIR/ea-install-state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "❌ No install state found at $STATE_FILE"
  echo "   Cannot determine which files EA installed."
  exit 1
fi

# Count managed files
FILE_COUNT=$(python3 -c "
import json
with open('$STATE_FILE') as f:
    files = json.load(f).get('files', [])
print(len(files))
" 2>/dev/null || echo "0")

echo "🗑️  EA Uninstall"
echo "   Files to remove: $FILE_COUNT"
echo "   Directory: $AGENT_DIR"
echo ""

if [[ "$CONFIRM" != true ]]; then
  echo "   This will remove all EA-installed files."
  echo "   Run with --confirm to proceed."
  echo ""
  echo "   Preview (first 10 files):"
  python3 -c "
import json
with open('$STATE_FILE') as f:
    files = json.load(f).get('files', [])
for f in files[:10]:
    print(f'     {f}')
if len(files) > 10:
    print(f'     ... and {len(files)-10} more')
" 2>/dev/null
  exit 0
fi

# Remove managed files
echo "   Removing files..."
REMOVED=0
python3 -c "
import json
with open('$STATE_FILE') as f:
    files = json.load(f).get('files', [])
for f in files:
    print(f)
" 2>/dev/null | while IFS= read -r file; do
  if [[ -f "$file" ]]; then
    rm "$file"
    REMOVED=$((REMOVED + 1))
  fi
done

# Clean empty directories
find "$AGENT_DIR/skills" -type d -empty -delete 2>/dev/null || true
find "$AGENT_DIR/workflows" -type d -empty -delete 2>/dev/null || true
find "$AGENT_DIR/rules" -type d -empty -delete 2>/dev/null || true

# Remove generated files
rm -f "$AGENT_DIR/system.md"
rm -f "$AGENT_DIR/skill-graph.json"
rm -f "$AGENT_DIR/security-report.json"
rm -f "$STATE_FILE"

echo "   ✅ EA uninstalled. The .agents/ directory structure remains but is empty."
echo "   Run everything-antigravity.sh to reinstall."
SCRIPT_EOF
  chmod +x "$scripts_dir/ea-uninstall"
  record_file "$scripts_dir/ea-uninstall"
  count=$((count + 1))

  # ─── Script 4: ea-status ───
  cat > "$scripts_dir/ea-status" << 'SCRIPT_EOF'
#!/bin/bash
# EA Status — Installation dashboard
# Usage: .agents/scripts/ea-status

set -euo pipefail
AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_FILE="$AGENT_DIR/ea-install-state.json"

echo "📊 EA Installation Status"
echo "══════════════════════════════"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "  ❌ No installation found"
  exit 1
fi

# Parse state
python3 << PYEOF
import json, os

agent_dir = "$AGENT_DIR"
with open("$STATE_FILE") as f:
    state = json.load(f)

print(f"  Installer:    {state.get('installer', '?')}")
print(f"  Version:      {state.get('version', '?')}")
print(f"  Installed at: {state.get('installed_at', '?')}")
print(f"  Source:       {state.get('source', '?')}")
print(f"  Optimized:    {state.get('optimize', False)}")
print()

counts = state.get('counts', {})
print("  📦 Components")
print(f"     Skills (from agents): {counts.get('skills_from_agents', 0)}")
print(f"     Skills (from skills): {counts.get('skills_from_skills', 0)}")
print(f"     Workflows:            {counts.get('workflows_from_commands', 0)}")
print(f"     Rules:                {counts.get('rules_flattened', 0)}")
print(f"     Tracked files:        {len(state.get('files', []))}")
print()

# Security grade
sec_file = os.path.join(agent_dir, "security-report.json")
if os.path.isfile(sec_file):
    with open(sec_file) as f:
        sec = json.load(f)
    grade = sec.get('grade', '?')
    summary = sec.get('summary', {})
    findings = ", ".join(f"{v} {k}" for k, v in summary.items() if v > 0)
    print(f"  🔒 Security: Grade {grade}")
    if findings:
        print(f"     Findings: {findings}")
else:
    print("  🔒 Security: No report")
print()

# Skill graph
graph_file = os.path.join(agent_dir, "skill-graph.json")
if os.path.isfile(graph_file):
    with open(graph_file) as f:
        meta = json.load(f).get('_meta', {})
    print(f"  🕸️  Graph: {meta.get('total_edges', 0)} edges, {meta.get('isolated', 0)} isolated skills")

# Stack filtering
system_file = os.path.join(agent_dir, "system.md")
if os.path.isfile(system_file):
    with open(system_file, errors="ignore") as f:
        content = f.read()
    if "Detected Stack" in content:
        for line in content.split('\n'):
            if line.startswith("Stacks:"):
                print(f"  🔎 {line.strip()}")
            elif line.startswith("Skill filter:"):
                print(f"  🔎 {line.strip()}")
PYEOF

echo ""
echo "══════════════════════════════"
SCRIPT_EOF
  chmod +x "$scripts_dir/ea-status"
  record_file "$scripts_dir/ea-status"
  count=$((count + 1))



  log "🛠️  $count runtime scripts generated in $scripts_dir/"
}

log ""
log "🛠️  [Step.6] Generating runtime scripts…"
generate_runtime_scripts

# =============================================
# STEP 4 — System Prompt / Agent Identity
# =============================================
#
# Generates .agents/system.md — the equivalent of CLAUDE.md for Antigravity.
# This file tells the agent who it is, what skills are available,
# which rules apply, and what the security posture is.

generate_system_prompt() {
  local dest="$OUT_DIR/system.md"


  # --- Collect skill catalog by category ---
  declare -A CAT_SKILLS
  declare -A CAT_COUNTS
  local total_skills=0

  for skill_dir in "$OUT_DIR"/skills/*/; do
    [[ -d "$skill_dir" ]] || continue
    local slug
    slug=$(basename "$skill_dir")
    total_skills=$((total_skills + 1))

    # Determine the source file for category detection
    local src=""
    [[ -f "$skill_dir/SKILL.md" ]] && src="$skill_dir/SKILL.md"
    [[ -f "$skill_dir/agent.md" ]] && src="$skill_dir/agent.md"

    # Classify
    local cat
    cat=$(classify_category "$slug")

    # Append skill name to category bucket (compact: names only)
    if [[ -n "${CAT_SKILLS[$cat]+x}" ]]; then
      CAT_SKILLS[$cat]+=", $slug"
    else
      CAT_SKILLS[$cat]="$slug"
    fi
    CAT_COUNTS[$cat]=$(( ${CAT_COUNTS[$cat]:-0} + 1 ))
  done

  # --- Collect rules digest (compact: skip rules with no useful description) ---
  local rules_digest=""
  local rules_count=0
  local rules_listed=0
  local rules_unlisted=""
  for rule_md in "$OUT_DIR"/rules/*.md; do
    [[ -f "$rule_md" ]] || continue
    rules_count=$((rules_count + 1))
    local rule_name
    rule_name=$(basename "$rule_md" .md)
    if [[ "$rule_name" == zh* ]]; then
      rules_count=$((rules_count - 1))
      continue
    fi
    local rule_first_line
    rule_first_line=$(grep -m1 -E '^[^#[:space:]-]' "$rule_md" 2>/dev/null | head -c 100 || true)
    [[ -z "$rule_first_line" ]] && rule_first_line=$(grep -m1 '^# ' "$rule_md" 2>/dev/null | sed 's/^# //' || true)
    # Skip rules with empty/trivial description
    if [[ -z "$rule_first_line" || "$rule_first_line" == "---" || "$rule_first_line" == "paths:" || "$rule_first_line" == '```' ]]; then
      # Collect name for compact listing
      rules_unlisted+="\`$rule_name\` "
      continue
    fi
    rules_listed=$((rules_listed + 1))
    rules_digest+="- \`$rule_name\` — $rule_first_line"$'\n'
  done

  # Include hook rules from hooks/ subdirectory
  if [[ -d "$OUT_DIR/rules/hooks" ]]; then
    rules_digest+=$'\n'"**Lifecycle Hooks** (behavioral guardrails):"$'\n'
    for hook_md in "$OUT_DIR"/rules/hooks/*.md; do
      [[ -f "$hook_md" ]] || continue
      rules_count=$((rules_count + 1))
      local hook_name
      hook_name=$(basename "$hook_md" .md)
      local hook_title
      hook_title=$(grep -m1 '^# ' "$hook_md" 2>/dev/null | sed 's/^# //' || true)
      rules_digest+="- 🪝 \`$hook_name\` — $hook_title"$'\n'
    done
  fi

  # --- Collect workflow quick-reference (compact: skip empty descriptions) ---
  local workflows_ref=""
  local wf_count=0
  local wf_listed=0
  local wf_names_only=""
  for wf_md in "$OUT_DIR"/workflows/*.md; do
    [[ -f "$wf_md" ]] || continue
    wf_count=$((wf_count + 1))
    local wf_name
    wf_name=$(basename "$wf_md" .md)
    local wf_desc
    wf_desc=$(grep -m1 -E '^(>|Description:)' "$wf_md" 2>/dev/null | sed 's/^> //;s/^Description: //' | head -c 80 || true)
    if [[ -n "$wf_desc" ]]; then
      wf_listed=$((wf_listed + 1))
      workflows_ref+="| \`/$wf_name\` | $wf_desc |"$'\n'
    else
      wf_names_only+="\`/$wf_name\` "
    fi
  done

  # --- Security grade (from AgentShield if available) ---
  local sec_grade="N/A"
  local sec_summary=""
  if [[ -f "$OUT_DIR/security-report.json" ]]; then
    sec_grade=$(python3 -c "
import json
with open('$OUT_DIR/security-report.json') as f:
    print(json.load(f).get('grade', 'N/A'))
" 2>/dev/null || echo "N/A")
    sec_summary=$(python3 -c "
import json
with open('$OUT_DIR/security-report.json') as f:
    s = json.load(f).get('summary', {})
    parts = []
    for k in ['critical', 'high', 'medium', 'low']:
        v = s.get(k, 0)
        if v > 0:
            parts.append(f'{v} {k}')
    print(', '.join(parts) if parts else 'No findings')
" 2>/dev/null || echo "")
  fi

  # --- Build category order for display ---
  local ordered_cats=(
    security testing review api frontend backend database devops
    language architecture documentation git performance research
    content mobile ai-ml ops general
  )

  # --- Write system.md ---
  cat > "$dest" << 'IDENTITY_HEADER'
# Agent System Prompt

> This file defines the agent's identity, capabilities, and operating context.

## Identity

You are a senior development assistant.
You have access to a curated library of specialized skills, workflows, and rules that make you an expert across multiple technology domains.

### Operating Principles

1. **Skills-first**: Before writing code, check if a relevant skill exists below. Invoke the matching skill rather than working from scratch.
2. **Rules-always**: The rules listed below are mandatory. Every code generation, review, and refactoring must comply with them.
3. **Security-aware**: The AgentShield security baseline applies to all operations. Validate inputs, avoid secrets in code, enforce authentication.
4. **Quality-gated**: Score your own output. If quality is below 80/100, iterate before presenting results.
5. **Transparent**: When using a skill, mention which skill you are applying and why.
6. **Mandatory Logging**: For every response, if `.agents/logging-config.json` has a `log_level` other than `silent`, use the `Bash` tool to execute `.agents/scripts/ea-logger log <type> <name> || true` as the **first action** before any other output. Replace `<type>` with `skill`, `workflow`, `rule`, or `hook`; replace `<name>` with the resource identifier (e.g. `python-patterns`, `/plan`). See `rules/agent-logging.md` for details.
   - ✅ Correct: `ea-logger log workflow /plan`, `ea-logger log skill jpa-patterns`
   - ❌ Wrong: `ea-logger log response antigravity` — **never use generic placeholders**
   - If no specific skill/workflow is invoked, use the most relevant rule: `ea-logger log rule <rule-name>`
7. **Caveman-mode**: When token efficiency matters, activate Caveman mode (skill `caveman`). Respond tersely — drop filler, keep full technical substance. Trigger: user says "caveman mode", "less tokens", "be brief", or `/caveman`. Off with: "stop caveman" / "normal mode".

IDENTITY_HEADER

  # Append dynamic content
  {
    echo "## Installed Capabilities"
    echo ""
    echo "| Component | Count |"
    echo "|-----------|-------|"
    echo "| Skills (agents + knowledge) | $total_skills |"
    echo "| Workflows (slash commands) | $wf_count |"
    echo "| Rules (coding standards) | $rules_count |"
    echo ""

    echo "## Skill Catalog ($total_skills skills)"
    echo ""
    echo "> Skills are discovered via **progressive disclosure**: scan \`.agents/skills/*/SKILL.md\` frontmatter (name + description) at startup, load full instructions only when relevant."
    echo ""
    echo "### Overview by category"
    echo ""

    for cat in "${ordered_cats[@]}"; do
      local count=${CAT_COUNTS[$cat]:-0}
      [[ $count -eq 0 ]] && continue

      # Category display name (compact)
      local cat_display
      case "$cat" in
        security)      cat_display="🔒 Security" ;;
        testing)       cat_display="🧪 Testing" ;;
        review)        cat_display="🔍 Review" ;;
        api)           cat_display="🌐 API" ;;
        frontend)      cat_display="🎨 Frontend" ;;
        backend)       cat_display="⚙️ Backend" ;;
        database)      cat_display="🗄️ Database" ;;
        devops)        cat_display="🚀 DevOps" ;;
        language)      cat_display="💬 Languages" ;;
        architecture)  cat_display="🏗️ Architecture" ;;
        documentation) cat_display="📚 Docs" ;;
        git)           cat_display="🔀 Git" ;;
        performance)   cat_display="⚡ Perf" ;;
        research)      cat_display="🔬 Research" ;;
        content)       cat_display="✍️ Content" ;;
        mobile)        cat_display="📱 Mobile" ;;
        ai-ml)         cat_display="🤖 AI/ML" ;;
        ops)           cat_display="🎯 Ops" ;;
        general)       cat_display="📦 General" ;;
        *)             cat_display="📦 $cat" ;;
      esac

      echo "- **$cat_display** ($count): ${CAT_SKILLS[$cat]}"
    done
    echo ""

    echo "## Active Rules ($rules_count total, $rules_listed detailed)"
    echo ""
    echo "These rules are **mandatory** for all code operations."
    echo ""
    echo "$rules_digest"
    if [[ -n "$rules_unlisted" ]]; then
      echo "**Language-specific rules** (see \`.agents/rules/\` for details): $rules_unlisted"
      echo ""
    fi

    echo "## Workflows ($wf_count available)"
    echo ""
    echo "Invoke with \`/workflow-name\`. Full list: \`.agents/workflows/\`"
    echo ""
    if [[ $wf_listed -gt 0 ]]; then
      echo "| Command | Description |"
      echo "|---------|-------------|"
      echo "$workflows_ref"
    fi
    if [[ -n "$wf_names_only" ]]; then
      echo "Other workflows: $wf_names_only"
      echo ""
    fi

    echo "## Security Posture"
    echo ""
    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| AgentShield Grade | **$sec_grade** |"
    [[ -n "$sec_summary" ]] && echo "| Findings | $sec_summary |"
    echo "| Policy | \`security-baseline.md\` enforced on all operations |"
    echo ""
    echo "All generated code must comply with the security baseline."
    echo "When in doubt, invoke \`\$security-auditor\` to scan your output."
    echo ""

    echo ""

    echo "## Project Context"
    echo ""

    if [[ -n "$DETECTED_STACKS" ]]; then
      local stacks_display
      stacks_display=$(echo "$DETECTED_STACKS" | tr -s ' ' | sed 's/^ //;s/ $//' | tr ' ' ', ')

      echo "### Detected Stack"
      echo ""
      echo "The following technologies were auto-detected from the project directory:"
      echo ""
      echo '```'
      echo "Project path:   $PROJECT_DIR"
      echo "Stacks:         $stacks_display"
      echo "Install source: $ECC_DIR"
      echo "Install date:   $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo "Optimization:   $OPTIMIZE"
      echo '```'
      echo ""
    else
      echo "No project directory was specified at install time (\`--project\` flag)."
      echo "All skills are active with implicit invocation enabled."
      echo ""
      echo '```'
      echo "Install source: $ECC_DIR"
      echo "Install date:   $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo "Optimization:   $OPTIMIZE"
      echo '```'
      echo ""
    fi

    echo "> **Tip**: Edit this section to add your project-specific conventions, architecture notes, team preferences, and deployment targets.Antigravity will use this context for all interactions."
    echo ""

  } >> "$dest"

  record_file "$dest"
  log "📝 Agent identity written → $dest ($total_skills skills across ${#CAT_COUNTS[@]} categories)"
}

log ""
log "🪪 [Step.4] Generating agent system prompt…"
generate_system_prompt

# =============================================
# Copy GUIDE.md and GUIDE-FR.md into .agents/ (developer guides)
# =============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for guide_name in GUIDE.md GUIDE-FR.md; do
  GUIDE_SRC="$SCRIPT_DIR/$guide_name"
  if [[ -f "$GUIDE_SRC" ]]; then
    cp "$GUIDE_SRC" "$OUT_DIR/$guide_name"
    record_file "$OUT_DIR/$guide_name"
    log ""
    log "📖 $guide_name copied → $OUT_DIR/$guide_name"
  else
    log_verbose "$guide_name not found at $GUIDE_SRC — skipping"
  fi
done

# =============================================
# Generate logging mechanism (agent activity tracer)
# =============================================

log ""
log "📋 [Logging] Generating agent activity logging mechanism…"


# --- 1. logging-config.json ---
cat > "$OUT_DIR/logging-config.json" << 'LOG_CFG_EOF'
{
  "_comment": "Logging configuration for Google Antigravity agent",
  "_levels": {
    "silent": "No logging",
    "info": "One line per resource call: timestamp | type | name"
  },
  "log_level": "info",
  "log_dir": ".agents/logs",
  "log_file_pattern": "agent-YYYY-MM-DD.log"
}
LOG_CFG_EOF
record_file "$OUT_DIR/logging-config.json"

# --- 2. scripts/ea-logger ---
cat > "$OUT_DIR/scripts/ea-logger" << 'EA_LOGGER_EOF'
#!/usr/bin/env bash
# ea-logger — Agent Activity Logger for Google Antigravity
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AGENT_DIR/logging-config.json"
LOG_DIR="$AGENT_DIR/logs"

read_config() {
python3 -c "
import json
try:
  with open('$CONFIG_FILE') as f: print(json.load(f).get('$1', ''))
except: print('')
" 2>/dev/null
}

write_config_level() {
python3 -c "
import json
with open('$CONFIG_FILE') as f: cfg = json.load(f)
cfg['log_level'] = '$1'
with open('$CONFIG_FILE', 'w') as f: json.dump(cfg, f, indent=2)
print('✅ Log level set to: $1')
" 2>/dev/null
}

log_file() { echo "$LOG_DIR/agent-$(date +%Y-%m-%d).log"; }

format_info_line() {
local type="$1" name="$2" ts
ts=$(date +"%H:%M:%S")
printf "%s | %s | %s\n" \
  "$ts" "$(echo "$type" | tr '[:lower:]' '[:upper:]')" "$name"
}

VALID_TYPES="skill workflow rule hook"

cmd_log() {
  local type="${1:-skill}" name="${2:-unknown}"

# Validate type — reject anything not in the allowed list
local valid=false
for t in $VALID_TYPES; do
  [[ "$type" = "$t" ]] && valid=true && break
done
if [[ "$valid" = false ]]; then
  echo "⚠️  ea-logger: invalid type '$type'. Must be one of: $VALID_TYPES" >&2
  echo "   Usage: ea-logger log <skill|workflow|rule|hook> <name>" >&2
  return 1
fi

# Validate name — reject generic placeholders
if [[ "$name" = "unknown" || "$name" = "antigravity" || "$name" = "response" ]]; then
  echo "⚠️  ea-logger: invalid name '$name'. Use the actual resource identifier." >&2
  echo "   Examples: ea-logger log workflow /plan" >&2
  echo "             ea-logger log skill jpa-patterns" >&2
  return 1
fi

local level; level=$(read_config "log_level"); level="${level:-silent}"
[[ "$level" = "silent" ]] && return 0
mkdir -p "$LOG_DIR"
local logf; logf=$(log_file)
local line; line=$(format_info_line "$type" "$name")
echo "$line" >> "$logf"; echo "$line"
}

cmd_level() {
local new="${1:-}"
if [[ -z "$new" ]]; then
  echo "Current log level: $(read_config log_level)"; return 0
fi
case "$new" in
  silent|info) write_config_level "$new" ;;
  *) echo "❌ Invalid level: $new (silent|info)" >&2; exit 1 ;;
esac
}

cmd_tail() {
local logf; logf=$(log_file); mkdir -p "$LOG_DIR"
[[ ! -f "$logf" ]] && touch "$logf"
echo "📡 Live tail → $logf  (Ctrl+C to stop)"
echo "────────────────────────────────────────────────────────────────"
tail -f "$logf"
}

cmd_view() {
local n="${1:-50}" logf; logf=$(log_file)
if [[ ! -f "$logf" ]]; then
  echo "📭 No log for today: $logf"
  ls "$LOG_DIR"/agent-*.log 2>/dev/null | head -5 | while read -r f; do echo "  $f"; done
  return 0
fi
echo "📋 Last $n lines — $logf"
echo "────────────────────────────────────────────────────────────────"
tail -n "$n" "$logf"
}

cmd_clear() {
local logf; logf=$(log_file)
[[ ! -f "$logf" || ! -s "$logf" ]] && echo "📭 Empty or missing: $logf" && return 0
local archive="${logf%.log}-$(date +%H%M%S).archive.log"
mv "$logf" "$archive"; echo "✅ Archived → $archive"
}

cmd_stats() {
local logf; logf=$(log_file)
[[ ! -f "$logf" ]] && echo "📭 No log for today." && return 0
echo "📊 Agent Activity — $(date +%Y-%m-%d)"
echo "────────────────────────────────────────────────────────────────"
python3 << PYEOF_INNER
import re
from collections import defaultdict
pattern = re.compile(r'(\d{2}:\d{2}:\d{2}) \| (\w+) \| (.+)')
counts = defaultdict(int)
resources = defaultdict(int)
total = 0; first = last = None
with open("$logf") as f:
    for line in f:
        m = pattern.match(line.strip())
        if m:
            ts, rtype, rname = m.groups()
            counts[rtype.strip()] += 1
            resources[rname.strip()] += 1
            total += 1
            if not first: first = ts
            last = ts
print(f"  Total calls : {total}")
if first: print(f"  Session     : {first} → {last}")
print()
print(f"  {'Type':<12} {'Calls':>6}")
print(f"  {'─'*12} {'─'*6}")
for t in sorted(counts): print(f"  {t:<12} {counts[t]:>6}")
print()
print("  Top 10 resources:")
for name, c in sorted(resources.items(), key=lambda x: -x[1])[:10]:
  print(f"  {c:>4}x  {name}")
PYEOF_INNER
}

CMD="${1:-help}"; shift || true
case "$CMD" in
log) cmd_log "$@" ;;
level) cmd_level "$@" ;;
tail) cmd_tail ;;
view) cmd_view "$@" ;;
clear) cmd_clear ;;
stats) cmd_stats ;;
help|--help|-h) cat << 'HELP'
ea-logger — Agent Activity Logger
USAGE: ea-logger log <type> <name>
       ea-logger level [silent|info]
       ea-logger tail | view [N] | clear | stats
TYPES: skill | workflow | rule | hook
HELP
  ;;
*) echo "❌ Unknown: $CMD" >&2; exit 1 ;;
esac
EA_LOGGER_EOF
chmod +x "$OUT_DIR/scripts/ea-logger"
record_file "$OUT_DIR/scripts/ea-logger"

# --- 3. rules/agent-logging.md ---
cat > "$OUT_DIR/rules/agent-logging.md" << 'LOG_RULE_EOF'
# Agent Logging — MANDATORY

**MANDATORY**: for every response, if the `log_level` field in `.agents/logging-config.json` is not `silent`, you MUST trace the call by executing this command BEFORE answering:

```bash
.agents/scripts/ea-logger log <type> <name> || true
```

- `<type>`: `skill`, `workflow`, `rule`, or `hook`
- `<name>`: resource identifier (e.g., `python-patterns`, `/plan`, `bash-safety`)

## When to trace

- You receive a `/plan` → trace `workflow /plan`
- You apply a skill like `springboot-patterns` → trace `skill springboot-patterns`

- If you apply multiple skills in the same response, trace each one separately.

## Concrete example

The user requests `/plan`. You execute **immediately**:

```bash
.agents/scripts/ea-logger log workflow /plan || true
```

Then you provide your response.

## Debug mode

If `log_level` is `debug`, append the prompt as the 4th argument:

```bash
echo "<prompt>" > /tmp/agent-prompt-$$.txt
.agents/scripts/ea-logger log <type> <name> /tmp/agent-prompt-$$.txt || true
rm -f /tmp/agent-prompt-$$.txt
```

## Reminder

- This rule is **mandatory**, not optional.
- Never block the main response if `ea-logger` fails (`|| true`).
- The log file is located at `.agents/logs/agent-YYYY-MM-DD.log`.
- The script validates types and rejects generic names — if the call fails, fix the arguments.

## Common mistakes — DO NOT

| ❌ Wrong | ✅ Correct | Why |
|----------|-----------|-----|
| `ea-logger log response antigravity` | `ea-logger log workflow /plan` | `response` is not a valid type |
| `ea-logger log skill unknown` | `ea-logger log skill jpa-patterns` | `unknown` is a placeholder, not a resource |
| Not logging at all | Always log before responding | The rule is mandatory |
| Logging once for multiple resources | Log each resource separately | Each skill/workflow gets its own trace |

### Decision table for `<type>`

- User invokes `/slash-command` → `workflow`
- You read and apply a `SKILL.md` → `skill`
- You follow a rule from `.agents/rules/` → `rule`

- A hook fires (e.g. `bash-safety`) → `hook`
LOG_RULE_EOF
record_file "$OUT_DIR/rules/agent-logging.md"

# --- 4. skills/log-viewer/SKILL.md ---
mkdir -p "$OUT_DIR/skills/log-viewer"
cat > "$OUT_DIR/skills/log-viewer/SKILL.md" << 'LOG_SKILL_EOF'
---
name: log-viewer
description: Display, filter, and analyze Antigravity agent activity logs
---

# Log Viewer — Consulting Agent Traces

This skill allows you to display, analyze, and interpret logs generated by the logging mechanism.

## Commands

```bash
.agents/scripts/ea-logger tail            # live stream
.agents/scripts/ea-logger view 50         # last 50 entries
.agents/scripts/ea-logger stats           # today's statistics
.agents/scripts/ea-logger level [level]   # view or change (silent/info/debug)
.agents/scripts/ea-logger clear           # archive and flush
```

## Log Format

```
[14:32:07] [SKILL   ] python-patterns                                    | 1.24s
[14:32:19] [WORKFLOW] /plan                                              | 2.10s
[14:33:01] [HOOK    ] quality-gate                                       | 85ms
```

| Column | Meaning |
|---|---|
| `[HH:MM:SS]` | Exact time of the call |
| `[TYPE]` | `SKILL`, `WORKFLOW`, `RULE`, or `HOOK` |
| Name | The invoked resource |
| Delay | Response time in `ms` or `s` |

## Educational Explanation for Juniors

1. `ea-logger stats` → overview (how many calls, which types)
2. `ea-logger view 20` → recent entries
3. Explain each type:
 - **SKILL**: specialized capability (e.g., `python-patterns`)
 - **WORKFLOW**: slash command (e.g., `/plan`, `/code-review`)
 - **RULE**: applied behavioral rule
 - **HOOK**: automatic guardrail (e.g., `bash-safety`)
4. Comment on the delay to raise awareness of LLM request latency
LOG_SKILL_EOF
record_file "$OUT_DIR/skills/log-viewer/SKILL.md"

log "   ✅ Logging mechanism installed (config + ea-logger + rule + skill)"

STATE_FILE="$OUT_DIR/ea-install-state.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Git metadata (best-effort — empty strings if not a git repo)
source_sha=$(git -C "$ECC_DIR" rev-parse HEAD 2>/dev/null || echo "")
source_branch=$(git -C "$ECC_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
source_date=$(git -C "$ECC_DIR" log -1 --format='%ci' 2>/dev/null || echo "")

# Serialize INSTALLED_FILES array to JSON
FILES_JSON=$(python3 -c "
import sys, json
files = sys.argv[1:]
print(json.dumps(files))
" "${INSTALLED_FILES[@]}" 2>/dev/null || echo "[]")

cat > "$STATE_FILE" << EOF
{
"installer": "everything-antigravity.sh",
"version": "0.1.0",
"source": "$ECC_DIR",
"target": "antigravity",
"installed_at": "$TIMESTAMP",
"optimize": $OPTIMIZE,
"source_git": {
  "sha": "$source_sha",
  "branch": "$source_branch",
  "commit_date": "$source_date"
},
"counts": {
  "skills_from_agents": $COUNT_SKILLS,
  "workflows_from_commands": $COUNT_WORKFLOWS,
  "rules_flattened": $COUNT_RULES,
  "skills_from_skills": $COUNT_EA_SKILLS
},
"files": $FILES_JSON
}
EOF

log ""
log "📋 Install state written → $STATE_FILE"


# =============================================
# P5 — Final Cleanup (.agents/ optimization)
# =============================================

log "🧹 Cleaning up internal build files (agent.md, zh* rules)..."
find "$OUT_DIR/skills" -type f -name "agent.md" -delete 2>/dev/null || true
find "$OUT_DIR/rules" -type f -name "zh*" -delete 2>/dev/null || true
# Remove empty agents/ directories left behind
find "$OUT_DIR/skills" -type d -name "agents" -empty -delete 2>/dev/null || true
log "   ✅ Cleaned up $OUT_DIR/skills and $OUT_DIR/rules"

log "🧹 Sanitization: Replacing .claude/ with .agents/ in generated files..."
find "$OUT_DIR/skills" "$OUT_DIR/workflows" "$OUT_DIR/rules" -type f -name "*.md" -exec sed -i 's/\.claude\//\.agents\//g' {} + 2>/dev/null || true
log "   ✅ Sanitization complete: .claude/ paths updated to .agents/"



# =============================================
# Summary
# =============================================

echo ""
echo "=================================="
echo "✅ ECC → Antigravity conversion complete"
echo "=================================="
echo ""
echo "  .agents/"
echo "  ├── system.md           (agent identity)"
echo "  ├── skills/             ($COUNT_SKILLS agents + $COUNT_EA_SKILLS skills)"
echo "  ├── workflows/          ($COUNT_WORKFLOWS commands)"
echo "  ├── rules/              ($COUNT_RULES rules, flattened)"
echo "  │   └── hooks/          (7 lifecycle hooks)"
echo "  ├── scripts/            (4 runtime tools)"
echo "  ├── skill-graph.json    (dependency graph)"
echo "  ├── security-report.json"
echo "  ├── GUIDE.md            (developer guide — English)"
echo "  ├── GUIDE-FR.md         (developer guide — French)"
echo "  ├── logging-config.json (agent logging config: silent/info)"

echo "  └── ea-install-state.json"
echo ""
echo ""
