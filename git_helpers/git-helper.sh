#!/usr/bin/env bash
set -euo pipefail

# Git Helper with menu-driven UI using whiptail/dialog fallback
# If neither is available, fall back to a text-based menu.

# Global state
UI_TOOL=""
TITLE="Git Helper"
HEIGHT=20
WIDTH=78
MENU_HEIGHT=12

# Detect UI tool
detect_ui() {
  if command -v whiptail >/dev/null 2>&1; then
    UI_TOOL="whiptail"
  elif command -v dialog >/dev/null 2>&1; then
    UI_TOOL="dialog"
  else
    UI_TOOL="text"
  fi
}

# UI primitives
ui_menu() {
  # args: title, prompt, pairs of key:label
  local title="$1"; shift
  local prompt="$1"; shift
  local args=("$@")
  local choice
  case "$UI_TOOL" in
    whiptail)
      # whiptail expects: key label key label ...
      choice=$(whiptail --title "$title" --menu "$prompt" "$HEIGHT" "$WIDTH" "$MENU_HEIGHT" "${args[@]}" 3>&1 1>&2 2>&3) || return 1
      ;;
    dialog)
      choice=$(dialog --title "$title" --menu "$prompt" "$HEIGHT" "$WIDTH" "$MENU_HEIGHT" "${args[@]}" 3>&1 1>&2 2>&3) || return 1
      ;;
    text)
      echo "$title" >&2
      echo "$prompt" >&2
      local i=0
      while [[ $i -lt ${#args[@]} ]]; do
        local key="${args[$i]}"; local label="${args[$((i+1))]}"
        printf "[%s] %s\n" "$key" "$label" >&2
        i=$((i+2))
      done
      read -r -p "Enter choice key: " choice || return 1
      ;;
  esac
  echo "$choice"
}

ui_checklist() {
  # args: title, prompt, pairs of key:label; returns space-separated selected keys
  local title="$1"; shift
  local prompt="$1"; shift
  local args=("$@")
  local selection
  case "$UI_TOOL" in
    whiptail)
      # Build checklist with OFF defaults
      local items=()
      local i=0
      while [[ $i -lt ${#args[@]} ]]; do
        items+=("${args[$i]}" "${args[$((i+1))]}" OFF)
        i=$((i+2))
      done
      selection=$(whiptail --title "$title" --checklist "$prompt" "$HEIGHT" "$WIDTH" "$MENU_HEIGHT" "${items[@]}" 3>&1 1>&2 2>&3) || return 1
      ;;
    dialog)
      local items=()
      local i=0
      while [[ $i -lt ${#args[@]} ]]; do
        items+=("${args[$i]}" "${args[$((i+1))]}" OFF)
        i=$((i+2))
      done
      selection=$(dialog --title "$title" --checklist "$prompt" "$HEIGHT" "$WIDTH" "$MENU_HEIGHT" "${items[@]}" 3>&1 1>&2 2>&3) || return 1
      ;;
    text)
      echo "$title" >&2
      echo "$prompt" >&2
      local i=0
      local all_keys=()
      while [[ $i -lt ${#args[@]} ]]; do
        local key="${args[$i]}"; local label="${args[$((i+1))]}"
        printf "[%s] %s\n" "$key" "$label" >&2
        all_keys+=("$key")
        i=$((i+2))
      done
      read -r -p "Enter keys (space-separated), or 'all': " selection || return 1
      if [[ "$selection" == "all" ]]; then
        selection="${all_keys[*]}"
      fi
      ;;
  esac
  echo "$selection"
}

ui_input() {
  # args: title, prompt, default
  local title="$1"; shift
  local prompt="$1"; shift
  local def="${1:-}"; shift || true
  local value
  case "$UI_TOOL" in
    whiptail)
      value=$(whiptail --title "$title" --inputbox "$prompt" "$HEIGHT" "$WIDTH" "$def" 3>&1 1>&2 2>&3) || return 1
      ;;
    dialog)
      value=$(dialog --title "$title" --inputbox "$prompt" "$HEIGHT" "$WIDTH" "$def" 3>&1 1>&2 2>&3) || return 1
      ;;
    text)
      if [[ -n "$def" ]]; then
        read -r -p "$prompt [$def]: " value || return 1
        [[ -z "$value" ]] && value="$def"
      else
        read -r -p "$prompt: " value || return 1
      fi
      ;;
  esac
  echo "$value"
}

ui_yesno() {
  # args: title, prompt; returns 0=yes, 1=no
  local title="$1"; shift
  local prompt="$1"; shift
  case "$UI_TOOL" in
    whiptail)
      whiptail --title "$title" --yesno "$prompt" "$HEIGHT" "$WIDTH"; return $?
      ;;
    dialog)
      dialog --title "$title" --yesno "$prompt" "$HEIGHT" "$WIDTH"; return $?
      ;;
    text)
      local ans
      read -r -p "$prompt [y/N]: " ans || return 1
      [[ "$ans" =~ ^[Yy]$ ]] && return 0 || return 1
      ;;
  esac
}

# Clear terminal on exit to remove UI remnants
cleanup_on_exit() {
  # Use clear; if not available, send ANSI clear
  if command -v clear >/dev/null 2>&1; then
    clear || true
  else
    printf "\033[H\033[2J" || true
  fi
}

# Show a simple message in a textbox
ui_message() {
  local title="$1"; shift
  local text="$1"; shift || true
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/git-helper.msg.XXXXXX")
  printf "%s\n" "$text" >"$tmp"
  ui_show_text_file "$title" "$tmp"
  rm -f "$tmp"
  prompt_exit_after_display
}

# Determine default branch name: origin/HEAD -> short name; fallback to existing local branches
default_branch_name() {
  local def
  if git rev-parse --verify --quiet refs/remotes/origin/HEAD >/dev/null; then
    def=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
    def=${def#origin/}
  fi
  if [[ -z "${def:-}" ]]; then
    def=$(git config --global init.defaultBranch || true)
  fi
  if [[ -n "${def:-}" ]] && git show-ref --verify --quiet "refs/heads/$def"; then
    echo "$def"; return 0
  fi
  # Heuristics: prefer main/master/dev
  for b in main master dev; do
    if git show-ref --verify --quiet "refs/heads/$b"; then echo "$b"; return 0; fi
  done
  # Fallback: current branch
  current_branch
}

# Get set of remote short branch names (without remote prefix), one per line
remote_short_names() {
  git for-each-ref --format='%(refname:short)' --exclude='refs/remotes/*/HEAD' refs/remotes | sed -E 's|^[^/]*/||' | sort -u
}

print_info() {
  # Print output; keep simple to avoid UI constraints
  echo
  echo "==== $1 ===="
  shift || true
  if [[ $# -gt 0 ]]; then
    echo "$@"
  fi
  echo
}

# Show the contents of a text file via UI (textbox) or stdout
ui_show_text_file() {
  local title="$1"; shift
  local file="$1"; shift
  case "$UI_TOOL" in
    whiptail)
      whiptail --title "$title" --textbox "$file" "$HEIGHT" "$WIDTH"
      ;;
    dialog)
      dialog --title "$title" --textbox "$file" "$HEIGHT" "$WIDTH"
      ;;
    text)
      echo "==== $title ===="
      cat "$file"
      echo
      read -r -p "Press Enter to return to menu..." _
      ;;
  esac
}

prompt_exit_after_display() {
  if ui_yesno "$TITLE" "Exit helper now?"; then
    exit 0
  fi
}

# Run a command, capture output, show it, then optionally exit
run_and_show() {
  local title="$1"; shift
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/git-helper.XXXXXX")
  {
    "$@"
  } &>"$tmp" || true
  ui_show_text_file "$title" "$tmp"
  rm -f "$tmp"
  prompt_exit_after_display
}

ensure_git_available() {
  if ! command -v git >/dev/null 2>&1; then
    echo "Error: git not found on PATH." >&2
    exit 1
  fi
}

ensure_repo() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi
  if ui_yesno "$TITLE" "No git repo here. Initialize a new repository?"; then
    git init
    print_info "Initialized new repository"
  else
    echo "Not inside a git repository. Exiting." >&2
    exit 1
  fi
}

# Config checks at startup
check_and_prompt_git_config() {
  local name email editor default_branch pull_rebase
  name=$(git config --global user.name || true)
  email=$(git config --global user.email || true)
  editor=$(git config --global core.editor || true)
  default_branch=$(git config --global init.defaultBranch || true)
  pull_rebase=$(git config --global pull.rebase || true)

  if [[ -z "$name" ]]; then
    if ui_yesno "$TITLE" "Global user.name is not set. Set it now?"; then
      local new_name
      new_name=$(ui_input "$TITLE" "Enter your name" "") || true
      if [[ -n "$new_name" ]]; then
        git config --global user.name "$new_name"
        print_info "Set user.name" "$new_name"
      fi
    fi
  fi

  if [[ -z "$email" ]]; then
    if ui_yesno "$TITLE" "Global user.email is not set. Set it now?"; then
      local new_email
      new_email=$(ui_input "$TITLE" "Enter your email" "") || true
      if [[ -n "$new_email" ]]; then
        git config --global user.email "$new_email"
        print_info "Set user.email" "$new_email"
      fi
    fi
  fi

  if [[ -z "$editor" ]]; then
    if ui_yesno "$TITLE" "Global core.editor not set. Set a preferred editor?"; then
      local new_editor
      new_editor=$(ui_input "$TITLE" "Enter editor (e.g., code --wait, nano, vim)" "") || true
      if [[ -n "$new_editor" ]]; then
        git config --global core.editor "$new_editor"
        print_info "Set core.editor" "$new_editor"
      fi
    fi
  fi

  if [[ -z "$default_branch" ]]; then
    if ui_yesno "$TITLE" "Set default initial branch name? (e.g., main)"; then
      local new_branch
      new_branch=$(ui_input "$TITLE" "Enter default branch name" "main") || true
      if [[ -n "$new_branch" ]]; then
        git config --global init.defaultBranch "$new_branch"
        print_info "Set init.defaultBranch" "$new_branch"
      fi
    fi
  fi

  if [[ -z "$pull_rebase" ]]; then
    if ui_yesno "$TITLE" "Prefer rebase on pull? (git pull --rebase)"; then
      git config --global pull.rebase true
      print_info "Set pull.rebase" "true"
    fi
  fi
}

# Helpers for git operations
current_branch() {
  git rev-parse --abbrev-ref HEAD
}

pick_remote() {
  local remotes
  remotes=$(git remote) || true
  if [[ -z "$remotes" ]]; then
    echo ""
    return 0
  fi
  local opts=()
  while read -r r; do
    [[ -z "$r" ]] && continue
    opts+=("$r" "Remote '$r'")
  done <<< "$remotes"
  local chosen
  chosen=$(ui_menu "$TITLE" "Choose remote" "${opts[@]}") || echo ""
  echo "$chosen"
}

pick_branch() {
  local branches_local branches_remote
  branches_local=$(git for-each-ref --format='%(refname:short)' refs/heads) || true
  branches_remote=$(git for-each-ref --format='%(refname:short)' --exclude='refs/remotes/*/HEAD' refs/remotes) || true
  local opts=()
  while read -r b; do
    [[ -z "$b" ]] && continue
    opts+=("$b" "Local '$b'")
  done <<< "$branches_local"
  while read -r rb; do
    [[ -z "$rb" ]] && continue
    opts+=("$rb" "Remote '$rb'")
  done <<< "$branches_remote"
  local chosen
  chosen=$(ui_menu "$TITLE" "Choose branch" "${opts[@]}") || echo ""
  echo "$chosen"
}

pick_files_to_add() {
  local changes
  changes=$(git status --porcelain) || true
  if [[ -z "$changes" ]]; then
    echo ""
    return 0
  fi
  local opts=()
  while read -r line; do
    [[ -z "$line" ]] && continue
    # format: XY path
    local path
    path=$(echo "$line" | sed -E 's/^..\s+//')
    [[ -z "$path" ]] && continue
    opts+=("$path" "$line")
  done <<< "$changes"
  local selected
  selected=$(ui_checklist "$TITLE" "Select files to add (space to toggle)" "${opts[@]}") || echo ""
  # whiptail/dialog returns quoted list; strip quotes
  selected=${selected//\"/}
  echo "$selected"
}

# Push current branch to a remote; set upstream if missing
push_current_branch() {
  local remote="$1"; shift || true
  local extra_args=("$@")
  local branch; branch=$(current_branch)

  # Determine if current branch has an upstream set
  if git rev-parse --symbolic-full-name --verify --quiet @{u} >/dev/null 2>&1; then
    git push "$remote" "$branch" "${extra_args[@]}"
  else
    # No upstream: set it while pushing
    git push -u "$remote" "$branch" "${extra_args[@]}" || git push "$remote" "$branch" "${extra_args[@]}"
  fi
}

# Expand default commit message prefix from env var GIT_HELPER_PREFIX
# Supported placeholders:
#  - {{branch}} -> current branch name
#  - {{ticket}} -> trailing number after last dash at end of branch (e.g., foo/bar-123 -> 123)
expand_commit_prefix() {
  local prefix="${GIT_HELPER_PREFIX:-}"
  [[ -z "$prefix" ]] && { echo ""; return 0; }
  local branch ticket
  branch=$(current_branch)
  # Extract digits after the last dash at end of branch name
  ticket=$(echo "$branch" | sed -n 's/.*-\([0-9][0-9]*\)$/\1/p')
  local expanded="$prefix"
  expanded=${expanded//\{\{branch\}\}/$branch}
  expanded=${expanded//\{\{ticket\}\}/$ticket}
  echo "$expanded"
}

# Combine prefix with a base default message
default_message_with_prefix() {
  local base="$1"; shift || true
  local pfx
  pfx=$(expand_commit_prefix)
  if [[ -n "$pfx" && -n "$base" ]]; then
    echo "$pfx $base"
  elif [[ -n "$pfx" ]]; then
    echo "$pfx"
  else
    echo "$base"
  fi
}

# Command implementations
cmd_status() {
  run_and_show "Git Status" git -c color.ui=false status
}

cmd_add() {
  if ui_yesno "$TITLE" "Add all changes (git add -A)?"; then
    git add -A
    print_info "Added all changes"
    return
  fi
  local files
  files=$(pick_files_to_add)
  if [[ -z "$files" ]]; then
    print_info "No files selected"
    return
  fi
  # split by spaces into array
  read -r -a arr <<< "$files"
  git add "${arr[@]}"
  print_info "Added selected files" "${arr[*]}"
}

cmd_add_commit_push() {
  # Add changes
  if ui_yesno "$TITLE" "Add all changes (git add -A)?"; then
    git add -A
    print_info "Added all changes"
  else
    local files
    files=$(pick_files_to_add)
    if [[ -n "$files" ]]; then
      read -r -a arr <<< "$files"
      git add "${arr[@]}"
      print_info "Added selected files" "${arr[*]}"
    else
      ui_message "$TITLE" "No files selected to add."
    fi
  fi

  # Ensure something staged
  if git diff --cached --quiet; then
    if ui_yesno "$TITLE" "No staged changes. Stage all and continue to commit?"; then
      git add -A
    else
      ui_message "$TITLE" "Nothing to commit. Flow ended."
      return
    fi
    if git diff --cached --quiet; then
      ui_message "$TITLE" "Still no staged changes. Flow ended."
      return
    fi
  fi

  # Commit
  local def_msg msg
  def_msg=$(expand_commit_prefix)
  msg=$(ui_input "$TITLE" "Commit message" "$def_msg") || return
  [[ -z "$msg" ]] && ui_message "$TITLE" "Commit message required. Flow ended." && return
  git commit -m "$msg"

  # Push
  if ui_yesno "$TITLE" "Push to remote now?"; then
    local remote branch
    remote=$(pick_remote)
    [[ -z "$remote" ]] && remote="origin"
    branch=$(current_branch)
    if push_current_branch "$remote"; then
      ui_message "$TITLE" "Committed and pushed to $remote/$branch."
    else
      ui_message "$TITLE" "Commit created, but push failed."
    fi
  else
    ui_message "$TITLE" "Commit created."
  fi
}

cmd_commit() {
  # Ensure something staged
  if ! git diff --cached --quiet; then
    :
  else
    if ui_yesno "$TITLE" "No staged changes. Stage all and commit?"; then
      git add -A
    else
      print_info "Nothing to commit"
      return
    fi
  fi
  local def_msg msg
  def_msg=$(expand_commit_prefix)
  msg=$(ui_input "$TITLE" "Commit message" "$def_msg") || return
  [[ -z "$msg" ]] && print_info "Commit message required" && return
  git commit -m "$msg"
  print_info "Committed" "$msg"
}

cmd_push() {
  local remote branch
  remote=$(pick_remote)
  [[ -z "$remote" ]] && remote="origin"
  branch=$(current_branch)
  if ui_yesno "$TITLE" "Push to $remote/$branch?"; then
    if push_current_branch "$remote"; then
      print_info "Pushed" "$remote/$branch"
    else
      print_info "Push failed" "$remote/$branch"
    fi
  fi
}

cmd_pull() {
  local remote branch
  remote=$(pick_remote)
  [[ -z "$remote" ]] && remote="origin"
  branch=$(current_branch)
  if ui_yesno "$TITLE" "Pull from $remote/$branch?"; then
    git pull "$remote" "$branch"
    print_info "Pulled" "$remote/$branch"
  fi
}

cmd_fetch() {
  local remote
  remote=$(pick_remote)
  [[ -z "$remote" ]] && remote="--all"
  if [[ "$remote" == "--all" ]]; then
    git fetch --all --prune
    print_info "Fetched all remotes"
  else
    git fetch "$remote" --prune
    print_info "Fetched" "$remote"
  fi
}

cmd_branch_create() {
  local name
  name=$(ui_input "$TITLE" "New branch name" "") || return
  [[ -z "$name" ]] && return
  git checkout -b "$name"
  print_info "Created and switched to" "$name"
}

cmd_branch_switch() {
  local b
  b=$(pick_branch)
  [[ -z "$b" ]] && return
  if [[ "$b" == */* ]]; then
    run_and_show "Switch to $b" git checkout --track "$b"
  else
    run_and_show "Switch to $b" git checkout "$b"
  fi
}

cmd_branch_delete() {
  local b
  b=$(pick_branch)
  [[ -z "$b" ]] && return
  if ui_yesno "$TITLE" "Delete local branch '$b'?"; then
    git branch -d "$b" || git branch -D "$b"
    print_info "Deleted branch" "$b"
  fi
}

cmd_branch_rename() {
  local b
  b=$(pick_branch)
  [[ -z "$b" ]] && return
  local new_name
  new_name=$(ui_input "$TITLE" "Rename branch '$b' to" "") || return
  [[ -z "$new_name" ]] && return
  if [[ "$b" == "$(current_branch)" ]]; then
    git branch -m "$new_name"
  else
    git branch -m "$b" "$new_name"
  fi
  print_info "Renamed branch" "$b → $new_name"
  
  # Check if branch existed on remote
  if git ls-remote --heads origin "$b" >/dev/null; then
    if ui_yesno "$TITLE" "Push rename to remote (delete old '$b' and push new '$new_name')?"; then
      git push origin -u "$new_name" 2>&1
      git push origin --delete "$b" 2>&1 || true
      print_info "Remote updated" "Old branch '$b' deleted, new branch '$new_name' pushed"
    fi
  fi
}

cmd_merge() {
  local b
  b=$(pick_branch)
  [[ -z "$b" ]] && return
  if ui_yesno "$TITLE" "Merge branch '$b' into current?"; then
    git merge "$b"
    print_info "Merged" "$b"
  fi
}

cmd_stash_save() {
  local msg
  msg=$(ui_input "$TITLE" "Stash message (optional)" "") || true
  if [[ -n "$msg" ]]; then
    git stash push -u -m "$msg"
  else
    git stash push -u
  fi
  print_info "Stashed changes"
}

cmd_stash_list() {
  run_and_show "Stash List" git stash list
}

cmd_stash_pop() {
  run_and_show "Stash Pop" git stash pop
}

cmd_log() {
  run_and_show "Log (last 20)" git --no-pager log --oneline --graph --decorate -20
}

cmd_diff() {
  run_and_show "Diff (unstaged)" git --no-pager diff
}

cmd_tag_create() {
  local name
  name=$(ui_input "$TITLE" "Tag name" "") || return
  [[ -z "$name" ]] && return
  local msg
  msg=$(ui_input "$TITLE" "Tag message (optional)" "") || true
  if [[ -n "$msg" ]]; then
    git tag -a "$name" -m "$msg"
  else
    git tag "$name"
  fi
  if ui_yesno "$TITLE" "Push tag '$name' to origin?"; then
    git push origin "$name"
  fi
  print_info "Created tag" "$name"
}

# History helpers
cmd_history_rewrite_to_single_commit() {
  # Check if there's already a rebase in progress
  if [[ -d "$(git rev-parse --git-dir)/rebase-merge" ]] || [[ -d "$(git rev-parse --git-dir)/rebase-apply" ]]; then
    if ui_yesno "$TITLE" "A rebase is already in progress. Abort it first?"; then
      git rebase --abort
      print_info "Aborted previous rebase"
    else
      ui_message "$TITLE" "Cannot start new rebase while one is in progress."
      return
    fi
  fi
  
  local offset=0
  local page_size=20
  
  while true; do
    # Get commits with offset for pagination
    local commits
    commits=$(git --no-pager log --pretty=format:'%h %s' -$((offset + page_size)) | tail -n +$((offset + 1))) || return
    
    if [[ -z "$commits" ]]; then
      [[ $offset -eq 0 ]] && ui_message "$TITLE" "No commits found." && return
      ui_message "$TITLE" "No more commits."
      offset=$((offset - page_size))
      continue
    fi
    
    # Build menu from commits: key is hash, label is "hash - message"
    local opts=()
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local hash msg
      hash=$(echo "$line" | cut -d' ' -f1)
      msg=$(echo "$line" | cut -d' ' -f2-)
      opts+=("$hash" "$hash - $msg")
    done <<< "$commits"
    
    # Add navigation options
    if [[ $offset -gt 0 ]]; then
      opts+=("_older" "← Load newer commits")
    fi
    opts+=("_newer" "Load older commits →")
    opts+=("_cancel" "Cancel")
    
    # Let user select a commit to squash back to
    local choice
    choice=$(ui_menu "$TITLE" "Select commit to squash since (offset: $offset)" "${opts[@]}") || return
    [[ -z "$choice" ]] && return
    
    case "$choice" in
      _newer)
        offset=$((offset + page_size))
        continue
        ;;
      _older)
        offset=$((offset - page_size))
        [[ $offset -lt 0 ]] && offset=0
        continue
        ;;
      _cancel)
        return
        ;;
      *)
        # User selected a commit hash
        local reset_to="$choice"
        ;;
    esac
    
    # Count commits to squash
    local commit_count
    commit_count=$(git rev-list --count "$reset_to..HEAD" 2>/dev/null || echo "0")
    if [[ "$commit_count" -le 0 ]]; then
      ui_message "$TITLE" "No commits to squash since $reset_to."
      continue
    fi
    
    if ! ui_yesno "$TITLE" "Squash $commit_count commits since $reset_to into one?"; then
      continue
    fi
    
    local msg
    local def_single
    def_single=$(expand_commit_prefix)
    msg=$(ui_input "$TITLE" "Single commit message" "$def_single") || { ui_message "$TITLE" "Message is required."; continue; }
    if [[ -z "$msg" ]]; then
      ui_message "$TITLE" "Message is required."
      continue
    fi
    
    # Create a temporary editor script that handles both todo and commit message
    local editor_script
    editor_script=$(mktemp "${TMPDIR:-/tmp}/git-helper.editor.XXXXXX")
    cat > "$editor_script" <<EDITOR_EOF
#!/bin/bash
# Handle both git-rebase-todo (squash transformation) and commit message editing
if [[ -f "\$1" ]]; then
  if grep -q "^pick " "\$1" 2>/dev/null; then
    # This is the rebase todo file - do the squash transformation
    sed -i '2,\$ s/^pick /squash /' "\$1"
  else
    # This is the commit message file - replace with our message
    echo "$msg" > "\$1"
  fi
else
  echo "Error: file not found" >&2
  exit 1
fi
EDITOR_EOF
    chmod +x "$editor_script"
    
    # Use git rebase -i with the editor script for both sequence and commit message
    local rebase_output
    rebase_output=$(mktemp "${TMPDIR:-/tmp}/git-helper.rebase.XXXXXX")
    if GIT_SEQUENCE_EDITOR="$editor_script" GIT_EDITOR="$editor_script" git rebase -i "$reset_to" --no-verify >"$rebase_output" 2>&1; then
      rm -f "$editor_script" "$rebase_output"
      local post_msg
      post_msg="Squashed $commit_count commits into one."

      # Optional: rebase onto default branch before pushing
      local def
      def=$(default_branch_name)
      if ui_yesno "$TITLE" "Rebase current branch onto '$def' before pushing?"; then
        local rb_out
        rb_out=$(mktemp "${TMPDIR:-/tmp}/git-helper.rebase.XXXXXX")
        if git fetch --all --prune &>>"$rb_out" && git rebase "origin/$def" &>>"$rb_out"; then
          post_msg+=$'\nRebased onto origin/'"$def"
        else
          local status_output
          status_output=$(git status --short)
          local full_error="Rebase onto $def failed.\n\nOutput:\n$(cat "$rb_out")\n\nGit status:\n$status_output"
          ui_message "$TITLE" "$full_error"
          rm -f "$rb_out"
          # Ask to abort
          if ui_yesno "$TITLE" "Abort this rebase?"; then
            git rebase --abort || true
            post_msg+=$'\nAborted failed rebase onto '"$def"
          else
            post_msg+=$'\nRebase onto '"$def"' incomplete; resolve manually.'
          fi
        fi
        rm -f "$rb_out"
      else
        # Offer rebase onto a chosen branch
        if ui_yesno "$TITLE" "Rebase onto a different branch?"; then
          local target
          target=$(pick_branch)
          if [[ -n "$target" ]]; then
            local rb_out2
            rb_out2=$(mktemp "${TMPDIR:-/tmp}/git-helper.rebase.XXXXXX")
            # Use origin/ prefix if not already a remote ref
            local rebase_ref="$target"
            if [[ "$target" != origin/* ]] && [[ "$target" != refs/* ]]; then
              rebase_ref="origin/$target"
            fi
            if git fetch --all --prune &>>"$rb_out2" && git rebase "$rebase_ref" &>>"$rb_out2"; then
              post_msg+=$'\nRebased onto '"$rebase_ref"
            else
              local status_output2
              status_output2=$(git status --short)
              local full_error2="Rebase onto $target failed.\n\nOutput:\n$(cat "$rb_out2")\n\nGit status:\n$status_output2"
              ui_message "$TITLE" "$full_error2"
              rm -f "$rb_out2"
              if ui_yesno "$TITLE" "Abort this rebase?"; then
                git rebase --abort || true
                post_msg+=$'\nAborted failed rebase onto '"$target"
              else
                post_msg+=$'\nRebase onto '"$target"' incomplete; resolve manually.'
              fi
            fi
            rm -f "$rb_out2"
          fi
        fi
      fi

      # Ask if user wants to push with force BEFORE exit prompt
      if ui_yesno "$TITLE" "Push with force (git push --force)?"; then
        local remote branch
        remote=$(pick_remote)
        [[ -z "$remote" ]] && remote="origin"
        branch=$(current_branch)
        # If no upstream, set it while force pushing
        if push_current_branch "$remote" --force; then
          post_msg+=$'\nPushed with force to '"$remote/$branch"
        else
          post_msg+=$'\nForce push failed.'
        fi
      fi
      ui_message "$TITLE" "$post_msg"
      return
    else
      # Show error output and git status
      local error_msg
      error_msg=$(cat "$rebase_output")
      local status_output
      status_output=$(git status --short)
      local full_error="Rebase failed.\n\nError output:\n$error_msg\n\nGit status:\n$status_output"
      ui_message "$TITLE" "$full_error"
      
      # Ask if user wants to abort the rebase
      if ui_yesno "$TITLE" "Abort this rebase?"; then
        git rebase --abort || true
        print_info "Rebase aborted"
      else
        print_info "Rebase left in progress. Resolve manually with 'git rebase --continue' or 'git rebase --abort'"
      fi
      rm -f "$editor_script" "$rebase_output"
      return
    fi
  done
}

# Rebase helpers
cmd_history_rebase_onto() {
  local def
  def=$(default_branch_name)
  # Choose target branch to rebase onto
  local choice
  choice=$(ui_menu "$TITLE" "Select rebase target" \
    "$def" "Default branch '$def'" \
    choose "Choose another branch" \
    cancel "Cancel") || return
  [[ -z "$choice" ]] && return

  local target
  case "$choice" in
    cancel) return ;;
    choose)
      target=$(pick_branch)
      [[ -z "$target" ]] && return
      ;;
    *)
      target="$choice"
      ;;
  esac

  # Perform rebase
  local rb_out
  rb_out=$(mktemp "${TMPDIR:-/tmp}/git-helper.rebase.XXXXXX")
  local current; current=$(current_branch)
  
  # Fetch all branches
  if ! git fetch --all --prune &>>"$rb_out"; then
    ui_message "$TITLE" "Failed to fetch from remote."
    rm -f "$rb_out"
    return
  fi
  
  # Pull current branch to ensure we're up to date
  if ! git pull origin "$current" &>>"$rb_out"; then
    echo "Warning: Could not pull current branch, continuing with local state" >>"$rb_out"
  fi
  
  if git rebase "origin/$target" &>>"$rb_out"; then
    rm -f "$rb_out"
    # Ask to force push
    local post_msg
    post_msg="Rebased onto origin/$target."
    if ui_yesno "$TITLE" "Push with force (git push --force)?"; then
      local remote branch
      remote=$(pick_remote)
      [[ -z "$remote" ]] && remote="origin"
      branch=$(current_branch)
      if push_current_branch "$remote" --force; then
        post_msg+=$'\nPushed with force to '"$remote/$branch"
      else
        post_msg+=$'\nForce push failed.'
      fi
    fi
    ui_message "$TITLE" "$post_msg"
  else
    local status_output
    status_output=$(git status --short)
    local full_error="Rebase onto $target failed.\n\nOutput:\n$(cat "$rb_out")\n\nGit status:\n$status_output"
    ui_message "$TITLE" "$full_error"
    if ui_yesno "$TITLE" "Abort this rebase?"; then
      git rebase --abort || true
      print_info "Rebase aborted"
    else
      print_info "Rebase left in progress. Resolve manually with 'git rebase --continue' or 'git rebase --abort'"
    fi
    rm -f "$rb_out"
  fi
}


cmd_history_squash_last_n() {
  local n
  n=$(ui_input "$TITLE" "Number of last commits to squash" "2") || return
  [[ -z "$n" ]] && return
  if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -le 0 ]]; then
    ui_message "$TITLE" "Invalid number: $n"
    return
  fi
  if ! ui_yesno "$TITLE" "Soft reset HEAD~$n and create one commit?"; then
    return
  fi
  git reset --soft HEAD~"$n" || { ui_message "$TITLE" "Soft reset failed."; return; }
  # Stage all changes to ensure a single commit of full diff
  git add -A
  if git diff --cached --quiet; then
    ui_message "$TITLE" "No changes to commit after reset."
    return
  fi
  local msg def_msg
  def_msg=$(expand_commit_prefix)
  msg=$(ui_input "$TITLE" "Commit message" "$def_msg") || { ui_message "$TITLE" "Message is required."; return; }
  [[ -z "$msg" ]] && { ui_message "$TITLE" "Message is required."; return; }
  git commit -m "$msg"
  ui_message "$TITLE" "Squashed last $n commits into one."
}

cmd_history_undo_last_keep_changes() {
  if ui_yesno "$TITLE" "Undo last commit but keep changes (soft reset)?"; then
    git reset --soft HEAD~1
    ui_message "$TITLE" "Undid last commit; changes preserved in index."
  fi
}

cmd_history_amend_message() {
  local msg def_msg
  def_msg=$(expand_commit_prefix)
  msg=$(ui_input "$TITLE" "New commit message for HEAD" "$def_msg") || return
  [[ -z "$msg" ]] && ui_message "$TITLE" "Message is required." && return
  git commit --amend -m "$msg"
  ui_message "$TITLE" "Amended last commit message."
}

menu_history() {
  local choice
  choice=$(ui_menu "$TITLE - History" "Select an action" \
    rewrite_single "Rewrite current branch to single commit" \
    rebase_onto "Rebase current branch onto another branch" \
    squash_n "Squash last N commits" \
    undo_last_soft "Undo last commit (keep changes)" \
    amend_msg "Amend last commit message" \
    back "Back" \
  ) || return 0
  case "$choice" in
    rewrite_single) cmd_history_rewrite_to_single_commit ;;
    rebase_onto) cmd_history_rebase_onto ;;
    squash_n) cmd_history_squash_last_n ;;
    undo_last_soft) cmd_history_undo_last_keep_changes ;;
    amend_msg) cmd_history_amend_message ;;
    back) : ;;
  esac
}

# Cleanup helpers
cmd_cleanup_prune_fetch() {
  run_and_show "Fetch + Prune All" bash -lc 'git fetch --all && git fetch -p'
}

cmd_cleanup_delete_orphan_branches() {
  local def
  def=$(default_branch_name)
  # Switch to default branch quietly to avoid exit prompts
  git checkout "$def" >/dev/null 2>&1 || true
  # Fetch and prune remotes quietly
  git fetch --all --prune >/dev/null 2>&1 || true
  # Compute remote short names
  local remotes
  remotes=$(remote_short_names)
  # Build deletion list: local branches not in remote names, excluding current
  local current; current=$(current_branch)
  local locals; locals=$(git for-each-ref --format='%(refname:short)' refs/heads)
  local to_delete=()
  while read -r lb; do
    [[ -z "$lb" ]] && continue
    [[ "$lb" == "$current" ]] && continue
    if ! grep -qx "$lb" <<< "$remotes"; then
      to_delete+=("$lb" "Local orphan '$lb'")
    fi
  done <<< "$locals"

  if [[ ${#to_delete[@]} -eq 0 ]]; then
    ui_message "$TITLE" "No orphan local branches found after prune."
    return
  fi
  local selected
  selected=$(ui_checklist "$TITLE" "Delete local branches not present on any remote" "${to_delete[@]}") || return
  selected=${selected//\"/}
  if [[ -z "$selected" ]]; then
    ui_message "$TITLE" "No branches selected for deletion."
    return
  fi
  if ui_yesno "$TITLE" "Confirm deletion of selected branches?"; then
    read -r -a arr <<< "$selected"
    local out
    out=$(mktemp "${TMPDIR:-/tmp}/git-helper.del.XXXXXX")
    for b in "${arr[@]}"; do
      git branch -D "$b" &>>"$out" || true
    done
    ui_show_text_file "Deleted branches" "$out"
    rm -f "$out"
    # Do not prompt for exit here; return to menu
  fi
}

cmd_cleanup_delete_merged_into_default() {
  local def
  def=$(default_branch_name)
  # Ensure we have latest default
  run_and_show "Fetch default" git fetch --all --prune
  # List branches fully merged into default
  local merged
  merged=$(git branch --merged "$def" | sed 's/^.. //')
  local current; current=$(current_branch)
  local opts=()
  while read -r b; do
    [[ -z "$b" ]] && continue
    [[ "$b" == "$def" ]] && continue
    [[ "$b" == "$current" ]] && continue
    opts+=("$b" "Merged into $def")
  done <<< "$merged"
  if [[ ${#opts[@]} -eq 0 ]]; then
    ui_message "$TITLE" "No local branches are fully merged into $def."
    return
  fi
  local selected
  selected=$(ui_checklist "$TITLE" "Delete branches merged into $def" "${opts[@]}") || return
  selected=${selected//\"/}
  if [[ -z "$selected" ]]; then
    ui_message "$TITLE" "No branches selected for deletion."
    return
  fi
  if ui_yesno "$TITLE" "Confirm deletion of selected merged branches?"; then
    read -r -a arr <<< "$selected"
    local out
    out=$(mktemp "${TMPDIR:-/tmp}/git-helper.mdel.XXXXXX")
    for b in "${arr[@]}"; do
      git branch -d "$b" &>>"$out" || git branch -D "$b" &>>"$out"
    done
    ui_show_text_file "Deleted merged branches" "$out"
    rm -f "$out"
    prompt_exit_after_display
  fi
}

menu_cleanup() {
  local choice
  choice=$(ui_menu "$TITLE - Cleanup" "Select an action" \
    prune_fetch "Fetch + Prune remotes" \
    delete_orphans "Delete local branches not on remote" \
    delete_merged "Delete branches merged into default" \
    back "Back" \
  ) || return 0
  case "$choice" in
    prune_fetch) cmd_cleanup_prune_fetch ;;
    delete_orphans) cmd_cleanup_delete_orphan_branches ;;
    delete_merged) cmd_cleanup_delete_merged_into_default ;;
    back) : ;;
  esac
}

menu_common() {
  local choice
  choice=$(ui_menu "$TITLE - Common" "Select an action" \
    status "Show status" \
    add "Add changes" \
    add_commit_push "Add → Commit → Push" \
    commit "Commit" \
    push "Push" \
    pull "Pull" \
    fetch "Fetch" \
    log "View log" \
    diff "View diff" \
    back "Back" \
  ) || return 0
  case "$choice" in
    status) cmd_status ;;
    add) cmd_add ;;
    add_commit_push) cmd_add_commit_push ;;
    commit) cmd_commit ;;
    push) cmd_push ;;
    pull) cmd_pull ;;
    fetch) cmd_fetch ;;
    log) cmd_log ;;
    diff) cmd_diff ;;
    back) : ;;
  esac
}

menu_branches() {
  local choice
  choice=$(ui_menu "$TITLE - Branches" "Select an action" \
    branch_create "Create branch" \
    branch_switch "Switch branch" \
    branch_rename "Rename branch" \
    branch_delete "Delete branch" \
    merge "Merge branch" \
    back "Back" \
  ) || return 0
  case "$choice" in
    branch_create) cmd_branch_create ;;
    branch_switch) cmd_branch_switch ;;
    branch_rename) cmd_branch_rename ;;
    branch_delete) cmd_branch_delete ;;
    merge) cmd_merge ;;
    back) : ;;
  esac
}

menu_stash() {
  local choice
  choice=$(ui_menu "$TITLE - Stash" "Select an action" \
    stash_save "Stash save" \
    stash_list "Stash list" \
    stash_pop "Stash pop" \
    back "Back" \
  ) || return 0
  case "$choice" in
    stash_save) cmd_stash_save ;;
    stash_list) cmd_stash_list ;;
    stash_pop) cmd_stash_pop ;;
    back) : ;;
  esac
}

menu_tags() {
  local choice
  choice=$(ui_menu "$TITLE - Tags" "Select an action" \
    tag_create "Create tag" \
    back "Back" \
  ) || return 0
  case "$choice" in
    tag_create) cmd_tag_create ;;
    back) : ;;
  esac
}
main_menu() {
  while true; do
    local choice
    choice=$(ui_menu "$TITLE" "Select a category" \
      common "Common Commands" \
      branches "Branch Management" \
      history "Commit History" \
      cleanup "Cleanup" \
      stash "Stash" \
      tags "Tags" \
      remotes "Remotes" \
      utils "Utilities" \
      quit "Quit" \
    ) || exit 0

    case "$choice" in
      common) menu_common ;;
      branches) menu_branches ;;
      history) menu_history ;;
      cleanup) menu_cleanup ;;
      stash) menu_stash ;;
      tags) menu_tags ;;
      remotes) menu_remotes ;;
      utils) menu_utils ;;
      quit) exit 0 ;;
      *) : ;;
    esac
  done
}

cmd_remotes_set_upstream_push() {
  local remote
  remote=$(pick_remote)
  [[ -z "$remote" ]] && remote="origin"
  local branch; branch=$(current_branch)
  if ui_yesno "$TITLE" "Push and set upstream to $remote/$branch?"; then
    run_and_show "Push -u $remote $branch" git push -u "$remote" "$branch"
  fi
}

menu_remotes() {
  local choice
  choice=$(ui_menu "$TITLE - Remotes" "Select an action" \
    set_upstream "Push and set upstream for current branch" \
    back "Back" \
  ) || return 0
  case "$choice" in
    set_upstream) cmd_remotes_set_upstream_push ;;
    back) : ;;
  esac
}

cmd_utils_restore_file() {
  local path
  path=$(ui_input "$TITLE" "Path to restore from HEAD" "") || return
  [[ -z "$path" ]] && return
  if ui_yesno "$TITLE" "Restore $path from HEAD (worktree only)?"; then
    run_and_show "Restore $path" git restore --source HEAD -- "$path"
  fi
}

cmd_utils_unstage_all() {
  if ui_yesno "$TITLE" "Unstage all changes (git reset)?"; then
    run_and_show "Unstaged all" git reset
  fi
}

cmd_utils_add_alias() {
  local script_path
  if command -v realpath >/dev/null 2>&1; then
    script_path=$(realpath "${BASH_SOURCE[0]}")
  else
    script_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/$(basename -- "${BASH_SOURCE[0]}")
  fi

  local profile_file
  profile_file="$HOME/.bash_profile"
  touch "$profile_file"

  local alias_name
  alias_name=$(ui_input "$TITLE" "Alias name to add to ~/.bash_profile" "git_helper") || return
  [[ -z "$alias_name" ]] && alias_name="git_helper"

  if grep -Eq "^alias[[:space:]]+$alias_name=" "$profile_file" 2>/dev/null; then
    if ui_yesno "$TITLE" "Alias '$alias_name' already exists in $profile_file. Replace it?"; then
      local tmp_alias
      tmp_alias=$(mktemp "${TMPDIR:-/tmp}/git-helper.alias.XXXXXX")
      grep -Ev "^alias[[:space:]]+$alias_name=" "$profile_file" >"$tmp_alias" || true
      mv "$tmp_alias" "$profile_file"
    else
      return
    fi
  fi

  local alias_line
  alias_line="alias $alias_name=\"bash $script_path\""
  echo "$alias_line" >>"$profile_file"
  eval "$alias_line" || true

  local msg
  msg="Added alias '$alias_name' pointing to:\nbash $script_path\nSaved to $profile_file.\nAlias activated in current session."

  if ui_yesno "$TITLE" "Add or update GIT_HELPER_PREFIX in $profile_file? (placeholders: {{branch}}, {{ticket}})"; then
    local prefix
    prefix=$(ui_input "$TITLE" "Enter GIT_HELPER_PREFIX (use {{branch}} and/or {{ticket}})" "${GIT_HELPER_PREFIX:-}") || prefix=""
    if [[ -n "$prefix" ]]; then
      local tmp_prefix
      tmp_prefix=$(mktemp "${TMPDIR:-/tmp}/git-helper.prefix.XXXXXX")
      grep -Ev '^(export[[:space:]]+)?GIT_HELPER_PREFIX=' "$profile_file" >"$tmp_prefix" || true
      mv "$tmp_prefix" "$profile_file"
      echo "export GIT_HELPER_PREFIX=\"$prefix\"" >>"$profile_file"
      export GIT_HELPER_PREFIX="$prefix"
      msg+=$'\nGIT_HELPER_PREFIX set for this session and saved to profile.'
    else
      msg+=$'\nGIT_HELPER_PREFIX not changed (empty input).'
    fi
  fi

  # Source the profile to apply changes immediately
  source "$profile_file" 2>/dev/null || true

  msg+=$'\nProfile sourced. Alias is ready to use!'
  ui_message "$TITLE" "$msg"
}

menu_utils() {
  local choice
  choice=$(ui_menu "$TITLE - Utilities" "Select an action" \
    restore_file "Restore file from HEAD" \
    unstage_all "Unstage all changes" \
    add_alias "Add alias to bash_profile" \
    back "Back" \
  ) || return 0
  case "$choice" in
    restore_file) cmd_utils_restore_file ;;
    unstage_all) cmd_utils_unstage_all ;;
    add_alias) cmd_utils_add_alias ;;
    back) : ;;
  esac
}

self_test() {
  echo "UI_TOOL=$(detect_ui; echo $UI_TOOL)"
  ensure_git_available
  echo "Git available"
  # Do not modify repo during self-test
  echo "Self-test complete"
}

usage() {
  cat <<EOF
$TITLE

Usage:
  git-helper.sh            Launch interactive UI (does config checks first)
  git-helper.sh --check    Run config checks then exit
  git-helper.sh --self-test  Print basic info and exit

Environment:
  Set FORCE_TEXT_UI=1 to force text UI fallback.
EOF
}

maybe_force_text_ui() {
  if [[ "${FORCE_TEXT_UI:-}" == "1" ]]; then
    UI_TOOL="text"
  fi
}

# Entry point
main() {
  detect_ui
  maybe_force_text_ui
  ensure_git_available
  # Clear terminal when the script exits (normal or via quit)
  trap cleanup_on_exit EXIT
  case "${1:-}" in
    --self-test)
      self_test
      return 0
      ;;
    --check)
      ensure_repo
      check_and_prompt_git_config
      echo "Config checks complete"
      return 0
      ;;
    -h|--help)
      usage
      return 0
      ;;
  esac
  ensure_repo
  check_and_prompt_git_config
  main_menu
}

main "$@"
