# Git Helper (Menu UI)

A menu-driven Git helper script that provides a simple graphical (terminal UI) interface to perform common Git tasks with clear names and prompts. Works with `whiptail`, `dialog`, or a text fallback.

## Location

- Script: git-helper.sh

# Features

- Common: status, add, add → commit → push (guided), commit, push, pull, fetch, log, diff
- Branches: create, switch, delete, merge
	- Switch shows local and remote branches; selecting a remote sets up tracking
- Stash: save, list, pop
- Tags: create annotated or lightweight tags and optionally push
- Cleanup:
	- Fetch + prune all remotes
	- Delete local branches not present on any remote (guided checklist)
	- Delete branches merged into the default branch (guided checklist)
- History:
	- Rewrite current branch history into a single commit since a chosen commit (interactive rebase with auto-squash); optional rebase onto default/other branch and force-push prompt
	- Squash last N commits into one (requires explicit message)
	- Rebase current branch onto another branch (with force-push prompt)
	- Undo last commit but keep changes (soft reset)
	- Amend last commit message
- Remotes: push and set upstream for current branch
- Utilities: restore a file from HEAD, unstage all changes
- Utilities: restore a file from HEAD, unstage all changes
- Config & UX: prompts to set user.name, user.email, core.editor, init.defaultBranch, and pull.rebase if missing; clears terminal on exit; shows command output in a scrollable viewer

### Commit message prefix
- `GIT_HELPER_PREFIX` can prefill commit prompts. Supported placeholders:
	- `{{branch}}` → current branch name
	- `{{ticket}}` → trailing number after the last dash (e.g., `foo/bar-123` → `123`)

Examples:
- `export GIT_HELPER_PREFIX="[{{branch}}] (#{{ticket}})"`
- `export GIT_HELPER_PREFIX="{{ticket}}: "`

## Usage

Run from any Git repository directory:

```
bash git_helpers/git-helper.sh
```

Options:

- `--check`: run only the startup config checks and exit
- `--self-test`: run a lightweight self-test and exit
- `FORCE_TEXT_UI=1`: force text prompts if `whiptail`/`dialog` are unavailable

Examples:

```
# Launch with UI
bash git_helpers/git-helper.sh

# Only run config checks
bash git_helpers/git-helper.sh --check

# Force text UI
FORCE_TEXT_UI=1 bash git_helpers/git-helper.sh
```

## Notes

- The script prefers `whiptail` or `dialog` for a nicer menu UI, and will fall back to text prompts if neither is installed.
- It will prompt to initialize a repository if run outside of a Git repo.
- For commands that display results (status, log, diff, etc.), outputs are shown in a scrollable viewer and you’ll be prompted to exit or continue.
- On exit, the helper clears the terminal to remove UI remnants.
