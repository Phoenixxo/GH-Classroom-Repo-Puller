#!/usr/bin/env bash 
# Run in bash script
set -euo pipefail # used to ensure the script is safely ran, exiting on errors including undefined errors (-u), and one fail fails the whole pipeline.

# --- config ---
ORG=""     # Name of Org 
UNIT="unit"       # current unit
PARENT_DIR="path/to/parent_dir"      # where repos should be cloned to
USE_SSH=1           # use ssh or http (0)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDENTS_FILE="$SCRIPT_DIR/students.txt"

# --- checks ---
command -v gh >/dev/null || { echo "GitHub CLI (gh) not found. Install and run 'gh auth login'."; exit 1; } # safety command check
command -v git >/dev/null || { echo "git not found."; exit 1; } # safety command checks

cd "$PARENT_DIR" # switch to desired directory

if [[ -d "$UNIT" ]]; then
	cd "$UNIT"
else
	echo "==> Unit dir not found, creating $UNIT"
	mkdir "$UNIT"
  	cd "$UNIT"
fi

while read -r user || [[ -n "${user:-}" ]]; do # -r used to disable backslash escaping, tests for non-zero length on current line and safely substitutes an empty string if user is unset.
  # skip blanks and comments
  [[ -z "${user// }" || "$user" =~ ^# ]] && continue

  repo_name="${UNIT}-${user}" # constructs repo name
  slug="${ORG}/${repo_name}" # full name living in github
  local_dir="${repo_name}" # directory repo should live in

  if [[ -d "$local_dir/.git" ]]; then # checks to see if the directory already exists
    echo "==> Pulling $local_dir"
    git -C "$local_dir" pull --ff-only # pulls any updates to the repo
    continue
  fi

  if gh repo view "$slug" >/dev/null 2>&1; then # if the repo is null
    echo "==> Cloning $slug"
    if [[ "$USE_SSH" -eq 1 ]]; then # ssh
      gh repo clone "$slug" "$local_dir" # clone into the repo's designated directory
    else
      url=$(gh repo view "$slug" --json url --jq .url) # html
      git clone "$url" "$local_dir"
    fi
  else
    echo "!! Missing remote (skipping): $slug" # repo not found for student
  fi
done < "$STUDENTS_FILE"

