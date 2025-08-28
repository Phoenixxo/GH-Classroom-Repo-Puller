#!/usr/bin/env bash 
# Run in bash script
set -euo pipefail # used to ensure the script is safely ran, exiting on errors including undefined errors (-u), and one fail fails the whole pipeline.

GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[0;33m"
RESET="\033[0m"

# --- config ---
ORG=""     # Name of Org 
UNIT=""       # current unit
PARENT_DIR=""      # where repos should be cloned to
USE_SSH=1           # use ssh or http (0)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDENTS_FILE="$SCRIPT_DIR/students.txt"
# Set the grading cutoff to the deadline, adjust accordingly
CUTOFF_ISO="2025-08-27 12:00:00 -0400" # uses ISO format 

# --- checks ---
command -v gh >/dev/null || { echo -e "${RED}GitHub CLI (gh) not found. Install and run 'gh auth login'."${RESET}; exit 1; } # safety command checks
command -v git >/dev/null || { echo -e "${RED}git not found."; exit 1; } # safety command checks

CUTOFF_SAFE="$CUTOFF_ISO" # name for dir, // replaces all ":" with "-"
CUTOFF_SAFE="${CUTOFF_SAFE/T/_}"
CUTOFF_SAFE="${CUTOFF_SAFE//:/-}"
CUTOFF_LABEL="due-$CUTOFF_SAFE"
BASE_OUT="$PARENT_DIR/$UNIT/$CUTOFF_LABEL" # output directory
mkdir -p "$BASE_OUT" # makes the output directory

while read -r user || [[ -n "${user:-}" ]]; do # -r used to disable backslash escaping, tests for non-zero length on current line and safely substitutes an empty string if user is unset.
  # skip blanks and comments
  [[ -z "${user// }" || "$user" =~ ^# ]] && continue

  repo_name="${UNIT}-${user}" # constructs repo name
  slug="${ORG}/${repo_name}" # full name living in github
  echo -e "${GREEN}=== $slug${RESET}"

  if ! gh repo view "$slug" >/dev/null 2>&1; then # checks if remote repo is missing (deletes output of error: /dev/null)
	  echo -e "${RED}!! Missing remote (skipping): $slug"
	  continue
  fi

  # Build remote URL
  if [[ "$USE_SSH" -eq 1 ]]; then
    remote="git@github.com:$slug.git" # using ssh
  else
    remote="https://github.com/$slug.git" # using https
  fi

  # Destination: <PARENT_DIR>/<UNIT>/<CUTOFF_ISO>/<repo_name>
  dest="$BASE_OUT/$repo_name"
  [[ -e "$dest" ]] && rm -rf "$dest" # checks if the directory exists and removes it, overriding it essentially
  mkdir -p "$dest"


# Ephemeral minimal clone, fetch only the needed commit, checkout into dest
  tmp_repo="$(mktemp -d)" # Creates a temp, empty working area
  git clone --no-checkout --filter=blob:none --depth=10000 "$remote" "$tmp_repo" # makes a clone wtih metadata only for checking

  default_branch_git="$(git -C "$tmp_repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)" # find the default branch using git, otherwise using 'main'
  if [[ -n "$default_branch_git" ]]; then
    # origin/MAIN -> MAIN
    default_branch="${default_branch_git#origin/}"
  else
    default_branch="${default_branch:-main}"
  fi

  git -C "$tmp_repo" fetch origin "$default_branch" --depth=10000 >/dev/null # Ensure we have the branch's history.

  deadline_sha="$(git -C "$tmp_repo" rev-list -n 1 --before="$CUTOFF_ISO" "origin/$default_branch" || true)" # Pick the last commit before cutoff

  if [[ -z "${deadline_sha:-}" ]]; then
    echo -e "${YELLOW}!! No commit on $default_branch at/before $CUTOFF_ISO (treat as no submission)"
    rm -rf "$tmp_repo"
    continue
  fi # Checking to see if any commits are found, prints message if no commit found.

  git -C "$tmp_repo" --work-tree="$dest" checkout --force "$deadline_sha" -- . >/dev/null # Add commit directly into $dest folder.
  # Minimal manifest for auditing
  {
    echo -e "Repository: $slug" # outputs repo
    echo -e "Unit: $UNIT" # outputs unit
    echo -e "Cutoff: $CUTOFF_ISO" # outputs cutoff time for current run
    echo -e "Default branch: $default_branch" # outputs the default branch
    echo -e "Selected commit: $deadline_sha" # outputs the selected commit hash
    echo -e "Snapshot created (UTC): $(date -u +'%Y-%m-%dT%H:%M:%SZ')" # time created, obviously
  } > "$dest/SUBMISSION_INFO.txt" # stores all of this in a txt file.

  rm -rf "$tmp_repo"

  echo -e "${GREEN}=> Snapshot: $dest" # links to destination.
done < "$STUDENTS_FILE" # Inputs students_file to be read.


