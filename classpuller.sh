#!/usr/bin/env bash
# Run in bash script
set -euo pipefail

GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[0;33m"
RESET="\033[0m"

# --- config ---
ORG=""                 # Name of GitHub Classroom org
UNIT=""                # Current unit (used in repo naming and output path)
PARENT_DIR=""          # Where repos should be cloned to
USE_SSH=1              # 1=SSH, 0=https
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDENTS_FILE="$SCRIPT_DIR/students.txt"

# deadline stored in local timezone
CUTOFF_ISO="2025-08-30 11:00:00 -0400"

# empty UTC variable
CUTOFF_UTC="${CUTOFF_UTC:-}"

# How many pages to check (100 events per page.) Default is 3 unless otherwise provided.
EVENT_PAGES="${1:-3}"

# --- command checks ---
command -v gh >/dev/null || { echo -e "${RED}GitHub CLI (gh) not found. Install and run 'gh auth login'.${RESET}"; exit 1; }
command -v git >/dev/null || { echo -e "${RED}git not found.${RESET}"; exit 1; }
command -v jq  >/dev/null || { echo -e "${RED}jq not found. Install jq (e.g., brew install jq).${RESET}"; exit 1; }

# --- time conversion helpers ---
to_utc_from_iso() {
  # Try GNU date (gdate) first, then BSD date (macOS), else empty.
  local src="$1"
  if command -v gdate >/dev/null 2>&1; then
    gdate -u -d "$src" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true
  else
    # BSD date (macOS)
    date -u -j -f "%Y-%m-%d %H:%M:%S %z" "$src" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true
  fi
}

if [[ -z "$CUTOFF_UTC" ]]; then
  CUTOFF_UTC="$(to_utc_from_iso "$CUTOFF_ISO" || true)"
  if [[ -z "$CUTOFF_UTC" ]]; then
    echo -e "${RED}Could not convert UTC from CUTOFF_ISO. Follow the format when setting CUTOFF_ISO: "YYYY-MM-DDTHH:MM:SSZ" ${RESET}"
    exit 1
  fi
fi

# --- labels/paths ---
CUTOFF_SAFE="$CUTOFF_ISO"
CUTOFF_SAFE="${CUTOFF_SAFE/T/_}"
CUTOFF_SAFE="${CUTOFF_SAFE//:/-}"
CUTOFF_LABEL="due-$CUTOFF_SAFE"
BASE_OUT="$PARENT_DIR/$UNIT/$CUTOFF_LABEL"
mkdir -p "$BASE_OUT"

# --- functions ---

is_json_array() { jq -e 'type=="array"' >/dev/null 2>&1; } # returns 0 if array, otherwise sends it to brazil (1)

# quietly discards any error messages printed from jq
jq_quiet() { jq -r "$@" 2>/dev/null || true; }

get_default_branch() {
  # Try remote HEAD first (fast), then Gh API, else main
  local repo_dir="$1" slug="$2" # passed in args, repo_dir > temp dir until passed into dest, slug > link to remote repo
  local ref
  ref="$(git -C "$repo_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$ref" ]]; then
    echo "${ref#origin/}"
    return
  fi
  local api_branch
  api_branch="$(gh repo view "$slug" --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)" # pulls the default branch ref
  if [[ -n "$api_branch" && "$api_branch" != "null" ]]; then
      echo "$api_branch" # Should output "default branch: master (or different if set otherwise)"
  else
    echo "main"
  fi
}

# Find the last PushEvent at/before cutoff for the *default branch*; return its head SHA and event time.
find_deadline_sha_via_events() {
  local slug="$1" default_branch="$2" cutoff_utc="$3"
  local page=1
  local out head event_time

  while [[ $page -le ${EVENT_PAGES} ]]; do
    out="$(gh api -X GET "repos/$slug/events?per_page=100&page=$page" 2>/dev/null || true)"
    if ! is_json_array <<<"$out"; then
      ((page++))
      continue
    fi
    # Filter to PushEvent matching refs/heads/<default_branch>, with created_at <= cutoff
    head="$(jq_quiet -r --arg cutoff "$cutoff_utc" --arg ref "refs/heads/$default_branch" '
      map(select(.type=="PushEvent" and .payload.ref == $ref))
      | map(select(.created_at <= $cutoff))
      | sort_by(.created_at)
      | last
      | .payload.head // empty
      ' <<<"$out")" # Parses using JSON, filters by event type (Push) and matching refs (master unless changed), selects all commits based on time and compares it to cutoff time, sorts it in descending order and grabs the last commit made and pushes it to out.
    event_time="$(jq_quiet -r --arg cutoff "$cutoff_utc" --arg ref "refs/heads/$default_branch" '
      map(select(.type=="PushEvent" and .payload.ref == $ref))
      | map(select(.created_at <= $cutoff))
      | sort_by(.created_at)
      | last
      | .created_at // empty
      ' <<<"$out")" # Same logic as above, except it takes the time instead of the HEAD (default_branch)

    if [[ -n "$head" ]]; then
      echo "$head|$event_time" # Echos the two if non-empty string
      return 0
    fi
    ((page++))
  done
  echo "|"
  return 1
}

# --- main loop ---
while read -r user || [[ -n "${user:-}" ]]; do
  # skip blanks and comments
  [[ -z "${user// }" || "$user" =~ ^# ]] && continue

  repo_name="${UNIT}-${user}"
  slug="${ORG}/${repo_name}"
  echo -e "${GREEN}=== $slug${RESET}"

  if ! gh repo view "$slug" >/dev/null 2>&1; then
    echo -e "${RED}!! Missing remote (skipping): $slug${RESET}"
    continue
  fi

  # Build remote URL
  if [[ "$USE_SSH" -eq 1 ]]; then
    remote="git@github.com:$slug.git" # SSH
  else
    remote="https://github.com/$slug.git" # HTML
  fi

  # Destination: <PARENT_DIR>/<UNIT>/<CUTOFF_LABEL>/<repo_name>
  dest="$BASE_OUT/$repo_name"
  [[ -e "$dest" ]] && rm -rf "$dest"
  mkdir -p "$dest"

  # Temp dir to clone metadata to
  tmp_repo="$(mktemp -d)"
  git clone --no-checkout --filter=blob:none --depth=1 "$remote" "$tmp_repo" >/dev/null

  # Default branch
  default_branch="$(get_default_branch "$tmp_repo" "$slug")"
  echo "Default branch: $default_branch"

  # Pick server-timestamped on-time push head
  picked="$(find_deadline_sha_via_events "$slug" "$default_branch" "$CUTOFF_UTC" || true)"
  deadline_sha="${picked%%|*}"
  pushed_at="${picked#*|}"

  # Checks if the deadline_sha is empty, if so then displays the following warning.
  if [[ -z "${deadline_sha:-}" ]]; then
    echo -e "${YELLOW}!! No PushEvent on ${default_branch} at/before ${CUTOFF_UTC} (treat as no submission)${RESET}"
    rm -rf "$tmp_repo"
    continue
  fi

  # Ensure the commit is present, then extract tree into dest
  git -C "$tmp_repo" fetch origin "$deadline_sha" --depth=1 >/dev/null 2>&1 || true
  git -C "$tmp_repo" archive --format=tar "$deadline_sha" | tar -x -C "$dest" # archive repo data and extrat into the destination folder

  # Logging to help keep track of data and times for grading purposes.
  {
    echo "Repository: $slug"
    echo "Unit: $UNIT"
    echo "Cutoff (local): $CUTOFF_ISO"
    echo "Cutoff (UTC):   $CUTOFF_UTC"
    echo "Default branch: $default_branch"
    echo "Selected commit: $deadline_sha"
    [[ -n "$pushed_at" ]] && echo "Selected via PushEvent at: $pushed_at"
    echo "Snapshot created (UTC): $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  } > "$dest/SUBMISSION_INFO.txt"

  rm -rf "$tmp_repo"
  echo -e "${GREEN}=> Snapshot: $dest${RESET}"
done < "$STUDENTS_FILE"
