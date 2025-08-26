# Classroom Repo Puller

Tiny script to clone or pull GitHub Classroom forks for a unit (repos like `$UNIT-<student>`).

## Requirements
- macOS/Linux (Bash)
- `git` and GitHub CLI `gh`
- Logged in: `gh auth login`
- SSH working (`ssh -T git@github.com`) **or** set HTTPS in the script

## Setup
1. Put `classpuller.sh` and `students.txt` in the **same folder**.
2. Edit the **config** in `classpuller.sh`:
   - `ORG="org"`
   - `UNIT="unit"`
   - `PARENT_DIR="/path/to/parent_dir"`
   - `USE_SSH=1` (set `0` to use HTTPS)

`students.txt` (one GitHub handle per line):
```text
alice
bob
charlie
```

## Run
```bash
chmod +x classpuller.sh
./classpuller.sh
```
### Per student pipeline:

- If PARENT_DIR/UNIT/UNIT-<user> exists → pulls (git pull --ff-only)

- If remote exists but local doesn’t → clones

- If remote doesn’t exist → skips with a message

## Changing Units
Change the "UNIT" variable to the name of your unit (i.e. "unit-02") and run again (reuse the same students.txt of course).

## Notes / Troubleshooting ( I had a few issues lol )
#### HTTPS Option (no SSH needed)

```bash
gh config set git_protocol https   # or set USE_SSH=0 in the script
gh auth login
# finish the steps necessary
```
#### SSH Quick Fixes / Troubleshooting
- Private key permissions (must be locked down):

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/<ssh_file_name>
chmod 644 ~/.ssh/<ssh_file_name>.pub
``` 
- macOS agent setup:

```bash
cat > ~/.ssh/config <<'EOF'
Host github.com
  AddKeysToAgent yes
  UseKeychain yes
  IdentitiesOnly yes
  IdentityFile ~/.ssh/<ssh_file_name>
EOF
```
Ensure you added your public key to GitHub: copy with pbcopy < ~/.ssh/<ssh_file_name>.pub, then GitHub → Settings → SSH and GPG keys → New SSH key → paste → Save.

Verify:

```bash
ssh -T git@github.com
# Expect: "Hi <username>! You've successfully authenticated, but GitHub does not provide shell access."
```
