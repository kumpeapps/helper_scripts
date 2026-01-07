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
- Utilities: restore a file from HEAD, unstage all changes, add alias to shell profile (bashrc or bash_profile)
- Config & UX: prompts to set user.name, user.email, core.editor, init.defaultBranch, and pull.rebase if missing; clears terminal on exit; shows command output in a scrollable viewer

### Commit message prefix
- `GIT_HELPER_PREFIX` can prefill commit prompts. The prefix is read from:
	1. `.GIT_HELPER_PREFIX` file in the repository root (first line only), or
	2. `GIT_HELPER_PREFIX` environment variable if file doesn't exist
- Supported placeholders:
	- `{{branch}}` → current branch name
	- `{{ticket}}` → trailing number after the last dash (e.g., `foo/bar-123` → `123`)

Examples:
- Create `.GIT_HELPER_PREFIX` file: `echo "[{{branch}}] (#{{ticket}})" > .GIT_HELPER_PREFIX`
- Or set environment variable: `export GIT_HELPER_PREFIX="{{ticket}}: "`
- Add `.GIT_HELPER_PREFIX` to `.gitignore` for personal preferences, or commit it for team standards

## Adding an Alias

Use the **Utilities → Add alias to shell profile** menu option to:
- Create a permanent shell alias pointing to the git-helper script
- Choose your own alias name (defaults to `git_helper`)
- Automatically adds the alias to both `~/.bashrc` and `~/.bash_profile`
- Optionally configure `GIT_HELPER_PREFIX` environment variable with placeholder support
- Activate the alias immediately in the current terminal session

The alias and prefix will be saved to both `~/.bashrc` and `~/.bash_profile` and available after restarting your terminal or running `source ~/.bashrc` (or `source ~/.bash_profile`).

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
