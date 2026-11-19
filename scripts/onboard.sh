#!/usr/bin/env bash
# onboard.sh: set up Git and Claude Code, OpenAI Codex, or both on macOS and Linux.
#
#   bash onboard.sh --agent claude|codex|both [--dry-run] [--no-guide]
#
# Finds what is already installed, including tools that are installed but not on PATH,
# and installs only what is missing. Before each step that changes something it shows
# what it found and what it will change, and waits for Next, Skip, or Quit.
# It never runs a downloaded install script, never reads or stores API keys, never
# starts claude or codex, and asks you to type YES before each sudo command.

ONBOARD_VERSION="0.1.0"

CLAUDE_DOCS="https://code.claude.com/docs/en/setup"
CLAUDE_KEY_URL="https://downloads.claude.ai/keys/claude-code.asc"
CLAUDE_KEY_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE" # public fingerprint, not a secret. gitleaks:allow
CLAUDE_APT_KEYRING="/etc/apt/keyrings/claude-code.asc"
CLAUDE_APT_LIST="/etc/apt/sources.list.d/claude-code.list"
CLAUDE_APT_LINE="deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main"
CLAUDE_DNF_REPO="/etc/yum.repos.d/claude-code.repo"
CODEX_INSTALLER_CMD="curl -fsSL https://chatgpt.com/codex/install.sh | sh"

AGENT=""
DRY_RUN=0
NO_GUIDE=0
GUIDED=0
QUIT=0
HOST_OS=""
HOST_DESC=""
PKG=""
BREW=""
BACKUPS=""
PATH_ADDED=""
IS_WSL=0
STEP_IDS="policy git git_path git_bash claude claude_path codex codex_path"
STEPS_RUN=""

# ---------------------------------------------------------------------------
# Output and prompts
# ---------------------------------------------------------------------------

say() { printf '%s\n' "$*"; }

color() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    printf '\033[%sm%s\033[0m\n' "$1" "$2"
  else
    printf '%s\n' "$2"
  fi
}

heading() { color "1;36" "$*"; }
note() { color "2" "$*"; }
warn() { color "33" "$*"; }

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'; }

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage: bash onboard.sh --agent claude|codex|both [--dry-run] [--no-guide]

  --agent     Which coding agent to set up: claude, codex, or both (required)
  --dry-run   Preview: show what is installed and what would change, and change nothing
  --no-guide  Run every step without pausing for Next / Skip / Quit
  --help      Show this help
EOF
}

# Prompts come from the terminal, never from standard input, so a piped script
# cannot answer them.
can_prompt() {
  [ -z "${CI:-}" ] || return 1
  { : </dev/tty; } 2>/dev/null
}

read_answer() {
  REPLY=""
  IFS= read -r REPLY </dev/tty
}

ask_step() {
  while :; do
    color "36" "[Enter] Next   [S] Skip   [Q] Quit"
    if ! read_answer; then
      STEP_ANSWER=quit
      return
    fi
    case "$(lower "$REPLY")" in
      "") STEP_ANSWER=next; return ;;
      s | skip) STEP_ANSWER=skip; return ;;
      q | quit) STEP_ANSWER=quit; return ;;
      *) say "Press Enter for Next, or type S to skip or Q to quit." ;;
    esac
  done
}

confirm_yes() {
  if ! can_prompt; then
    say "  No terminal to ask on, so this counts as No."
    return 1
  fi
  color "33" "$1"
  color "33" "  Type YES to run it, or anything else to skip it:"
  read_answer || return 1
  [ "$REPLY" = "YES" ]
}

# run_sudo <command> [args...]: returns 10 when the user declines.
run_sudo() {
  say "  Needs administrator rights:"
  say "    sudo $*"
  if ! confirm_yes "  This command runs as root."; then
    say "  Not run."
    return 10
  fi
  sudo "$@"
}

# Sets STEP_RESULT to declined or failed when the sudo command does not succeed.
run_sudo_step() {
  run_sudo "$@"
  local rc=$?
  [ "$rc" -eq 0 ] && return 0
  if [ "$rc" -eq 10 ]; then
    STEP_RESULT=declined
  else
    say "  The command failed (exit code $rc)."
    STEP_RESULT=failed
  fi
  return 1
}

run_cmd() {
  say "  Running: $*"
  "$@"
}

# ---------------------------------------------------------------------------
# Arguments and host
# ---------------------------------------------------------------------------

# Returns 0 when valid, 2 for a usage error, 3 for --help.
parse_args() {
  AGENT=""
  DRY_RUN=0
  NO_GUIDE=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) shift; AGENT="${1:-}" ;;
      --agent=*) AGENT="${1#--agent=}" ;;
      --dry-run) DRY_RUN=1 ;;
      --no-guide) NO_GUIDE=1 ;;
      -h | --help) return 3 ;;
      *) say "onboard.sh: unknown option: $1"; return 2 ;;
    esac
    [ $# -gt 0 ] && shift
  done
  case "$(lower "$AGENT")" in
    claude | codex | both) AGENT="$(lower "$AGENT")"; return 0 ;;
    "") say "onboard.sh: choose which coding agent to set up with --agent."; return 2 ;;
    *) say "onboard.sh: '$AGENT' is not a valid --agent value."; return 2 ;;
  esac
}

agent_wants() { [ "$AGENT" = both ] || [ "$AGENT" = "$1" ]; }

detect_host() {
  local kernel
  kernel=$(uname -s 2>/dev/null)
  case "$kernel" in
    Darwin)
      HOST_OS=macos
      HOST_DESC="macOS $(sw_vers -productVersion 2>/dev/null)"
      ;;
    Linux)
      HOST_OS=linux
      HOST_DESC="Linux"
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        HOST_DESC=$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}")
      fi
      if [ -n "${WSL_DISTRO_NAME:-}" ] || [ -e /proc/sys/fs/binfmt_misc/WSLInterop ]; then
        IS_WSL=1
        HOST_DESC="$HOST_DESC on WSL (this sets up Linux inside WSL, not Windows)"
      fi
      ;;
    MINGW* | MSYS* | CYGWIN*)
      say "onboard.sh sets up macOS and Linux. On Windows, run the PowerShell script instead:"
      say "  powershell -NoProfile -ExecutionPolicy Bypass -File .\\onboard.ps1 -Agent ${AGENT:-both}"
      return 1
      ;;
    *)
      say "onboard.sh does not support this system (${kernel:-unknown})."
      return 1
      ;;
  esac
}

find_brew() {
  local b
  if have brew; then command -v brew; return 0; fi
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
    if [ -x "$b" ]; then printf '%s\n' "$b"; return 0; fi
  done
  return 1
}

detect_pkg() {
  BREW=$(find_brew) || BREW=""
  PKG=""
  if [ "$HOST_OS" = macos ]; then
    [ -n "$BREW" ] && PKG=brew
    return 0
  fi
  if have apt-get; then PKG=apt
  elif have dnf; then PKG=dnf
  elif have pacman; then PKG=pacman
  fi
}

# ---------------------------------------------------------------------------
# Finding tools and PATH
# ---------------------------------------------------------------------------

known_dirs() {
  case "$1" in
    git) printf '%s\n' /opt/homebrew/bin /usr/local/bin /usr/bin ;;
    claude) printf '%s\n' "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin /usr/bin ;;
    codex)
      printf '%s\n' "$HOME/.local/bin" "${CODEX_HOME:-$HOME/.codex}/packages/standalone/current/bin" \
        /opt/homebrew/bin /usr/local/bin /home/linuxbrew/.linuxbrew/bin
      if have npm; then printf '%s/bin\n' "$(npm prefix -g 2>/dev/null)"; fi
      ;;
  esac
}

# On a Mac without Apple's Command Line Tools, /usr/bin/git only opens an install dialog.
is_apple_git_stub() {
  [ "$HOST_OS" = macos ] && [ "$1" = /usr/bin/git ] && ! xcode-select -p >/dev/null 2>&1
}

tool_works() {
  [ -f "$1" ] && [ -x "$1" ] || return 1
  is_apple_git_stub "$1" && return 1
  "$1" --version >/dev/null 2>&1
}

# Sets FOUND_PATH and FOUND_DIR.
find_tool() {
  local tool=$1 candidate dir
  FOUND_PATH=""
  FOUND_DIR=""
  candidate=$(command -v "$tool" 2>/dev/null)
  case "$candidate" in
    /*)
      if tool_works "$candidate"; then
        FOUND_PATH=$candidate
        FOUND_DIR=$(dirname "$candidate")
        return 0
      fi
      ;;
  esac
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    if tool_works "$dir/$tool"; then
      FOUND_PATH="$dir/$tool"
      FOUND_DIR=$dir
      return 0
    fi
  done <<EOF
$(known_dirs "$tool")
EOF
  return 1
}

# Runs a command in the kind of shell a new terminal window opens: a login shell on
# macOS, an interactive shell on Linux.
in_new_shell() {
  local sh=${SHELL:-/bin/sh}
  if [ "$HOST_OS" = macos ]; then
    "$sh" -l -i -c "$1" </dev/null 2>/dev/null
  else
    "$sh" -i -c "$1" </dev/null 2>/dev/null
  fi
}

new_terminal_path() {
  local out
  # shellcheck disable=SC2016
  out=$(in_new_shell 'printf "__ONBOARD__%s__ONBOARD__" "$PATH"')
  case "$out" in
    *__ONBOARD__*__ONBOARD__*)
      out=${out#*__ONBOARD__}
      printf '%s' "${out%%__ONBOARD__*}"
      ;;
  esac
}

path_contains() {
  case ":$1:" in
    *":$2:"* | *":$2/:"*) return 0 ;;
  esac
  return 1
}

tool_in_new_terminal() {
  in_new_shell "command -v $1 >/dev/null 2>&1 && $1 --version" >/dev/null
}

rc_file() {
  case "$(basename "${SHELL:-}")" in
    zsh) printf '%s\n' "$HOME/.zshrc" ;;
    bash)
      if [ "$HOST_OS" = macos ]; then printf '%s\n' "$HOME/.bash_profile"; else printf '%s\n' "$HOME/.bashrc"; fi
      ;;
    *) return 1 ;;
  esac
}

home_form() {
  # shellcheck disable=SC2016
  case "$1" in
    "$HOME"/*) printf '$HOME/%s' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

path_line() {
  # shellcheck disable=SC2016
  printf 'export PATH="$PATH:%s"  # added by onboard.sh' "$(home_form "$1")"
}

rc_mentions() {
  [ -f "$1" ] || return 1
  grep -F -q -- "$2" "$1" && return 0
  grep -F -q -- "$(home_form "$2")" "$1"
}

# ---------------------------------------------------------------------------
# Backups
# ---------------------------------------------------------------------------

backup_path() {
  local f=$1 target stamp n
  target="$f.bak"
  if [ -e "$target" ] || [ -L "$target" ]; then
    stamp=$(date +%Y%m%d%H%M%S)
    target="$f.$stamp.bak"
    n=1
    while [ -e "$target" ] || [ -L "$target" ]; do
      target="$f.$stamp-$n.bak"
      n=$((n + 1))
    done
  fi
  printf '%s' "$target"
}

backup_file() {
  local f=$1 target
  [ -e "$f" ] || return 0
  target=$(backup_path "$f")
  if ! cp -pL "$f" "$target" 2>/dev/null || ! cmp -s "$f" "$target"; then
    say "  Could not back up $f, so it was not changed."
    return 1
  fi
  BACKUPS="${BACKUPS}${target}
"
  say "  Backed up $f to $target"
}

# ---------------------------------------------------------------------------
# Anthropic's signing key
# ---------------------------------------------------------------------------

# Prints the primary key fingerprint, or nothing unless the file holds exactly one key.
key_fingerprint() {
  gpg --batch --show-keys --with-colons "$1" 2>/dev/null | awk -F: '
    $1 == "pub" { pubs++; want = 1; next }
    $1 == "sub" { want = 0; next }
    $1 == "fpr" && want { fpr = $10; want = 0 }
    END { if (pubs == 1) print fpr }'
}

fetch_verified_key() {
  local dest=$1 fpr
  say "  Running: curl -fsSL $CLAUDE_KEY_URL -o $dest"
  if ! curl -fsSL "$CLAUDE_KEY_URL" -o "$dest"; then
    say "  Could not download Anthropic's signing key."
    return 1
  fi
  fpr=$(key_fingerprint "$dest")
  if [ "$fpr" != "$CLAUDE_KEY_FPR" ]; then
    say "  The downloaded key's fingerprint (${fpr:-none}) does not match Anthropic's published"
    say "  fingerprint $CLAUDE_KEY_FPR. Nothing was written."
    return 1
  fi
  say "  Key fingerprint matches Anthropic's published fingerprint."
}

claude_apt_ready() { [ -f "$CLAUDE_APT_LIST" ] && grep -q 'downloads.claude.ai/claude-code/apt' "$CLAUDE_APT_LIST" 2>/dev/null; }
claude_dnf_ready() { [ -f "$CLAUDE_DNF_REPO" ] && grep -q 'downloads.claude.ai/claude-code/rpm' "$CLAUDE_DNF_REPO" 2>/dev/null; }

# ---------------------------------------------------------------------------
# Steps: detect_* set D_STATUS (satisfied|change|na|fail), D_FOUND, D_CHANGES, D_PURPOSE;
# apply_* set STEP_RESULT (done|failed|declined).
# ---------------------------------------------------------------------------

no_pkg_message() {
  if [ "$HOST_OS" = macos ]; then
    printf '%s' "Homebrew was not found. Install it from https://brew.sh, then run this again"
  else
    printf '%s' "no supported package manager (apt, dnf, or pacman) was found"
  fi
}

detect_git() {
  D_PURPOSE="Installs Git."
  if find_tool git; then
    D_STATUS=satisfied
    D_FOUND="git at $FOUND_PATH"
    return
  fi
  D_FOUND="not installed"
  if [ "$HOST_OS" = macos ] && [ -x /usr/bin/git ]; then
    D_FOUND="only Apple's placeholder /usr/bin/git (Command Line Tools are not installed)"
  fi
  D_STATUS=change
  case "$PKG" in
    brew) D_CHANGES="$BREW install git" ;;
    apt) D_CHANGES="sudo apt-get update
sudo apt-get install -y git" ;;
    dnf) D_CHANGES="sudo dnf install -y git" ;;
    pacman) D_CHANGES="sudo pacman -S --noconfirm git" ;;
    *) D_STATUS=fail; D_FOUND="$D_FOUND, and $(no_pkg_message)" ;;
  esac
}

apply_git() {
  case "$PKG" in
    brew) run_cmd "$BREW" install git || { STEP_RESULT=failed; return; } ;;
    apt)
      run_sudo_step apt-get update || return
      run_sudo_step apt-get install -y git || return
      ;;
    dnf) run_sudo_step dnf install -y git || return ;;
    pacman) run_sudo_step pacman -S --noconfirm git || return ;;
  esac
  if find_tool git; then
    say "  Installed: $FOUND_PATH"
    STEP_RESULT="done"
  else
    STEP_RESULT=failed
  fi
}

detect_claude() {
  D_PURPOSE="Installs the Claude Code CLI."
  if find_tool claude; then
    D_STATUS=satisfied
    D_FOUND="claude at $FOUND_PATH"
    return
  fi
  D_FOUND="not installed"
  D_STATUS=change
  if [ "$HOST_OS" = macos ]; then
    if [ -n "$BREW" ]; then
      D_CHANGES="$BREW install --cask claude-code"
    else
      D_STATUS=fail
      D_FOUND="not installed, and $(no_pkg_message)"
    fi
    return
  fi
  case "$PKG" in
    apt)
      if claude_apt_ready; then
        D_PURPOSE="Installs Claude Code from Anthropic's apt repository, which is already set up."
        D_CHANGES="sudo apt-get update
sudo apt-get install -y claude-code"
        return
      fi
      D_PURPOSE="Installs Claude Code from Anthropic's signed apt repository."
      D_CHANGES="Download Anthropic's signing key and check its fingerprint
sudo install -d -m 0755 /etc/apt/keyrings
sudo install -m 0644 <checked key> $CLAUDE_APT_KEYRING
sudo install -m 0644 <list file> $CLAUDE_APT_LIST
    ($CLAUDE_APT_LINE)
sudo apt-get update
sudo apt-get install -y claude-code"
      ;;
    dnf)
      if claude_dnf_ready; then
        D_PURPOSE="Installs Claude Code from Anthropic's dnf repository, which is already set up."
        D_CHANGES="sudo dnf install -y claude-code"
        return
      fi
      D_PURPOSE="Installs Claude Code from Anthropic's signed dnf repository."
      D_CHANGES="Download Anthropic's signing key and check its fingerprint
sudo rpm --import <checked key>
sudo install -m 0644 <repo file> $CLAUDE_DNF_REPO
sudo dnf install -y claude-code"
      ;;
    pacman)
      D_STATUS=fail
      D_FOUND="not installed. Anthropic does not publish a pacman package; see $CLAUDE_DOCS"
      return
      ;;
    *)
      D_STATUS=fail
      D_FOUND="not installed, and $(no_pkg_message). See $CLAUDE_DOCS"
      return
      ;;
  esac
  if ! have curl || ! have gpg; then
    D_STATUS=fail
    D_FOUND="not installed. Checking Anthropic's signing key needs curl and gpg; install them first (for example: sudo $PKG install curl gnupg)"
  fi
}

apply_claude() {
  local tmp
  if [ "$HOST_OS" = macos ]; then
    run_cmd "$BREW" install --cask claude-code || { STEP_RESULT=failed; return; }
  elif [ "$PKG" = apt ]; then
    if ! claude_apt_ready; then
      tmp=$(mktemp -d) || { STEP_RESULT=failed; return; }
      if ! fetch_verified_key "$tmp/claude-code.asc"; then rm -rf "$tmp"; STEP_RESULT=failed; return; fi
      printf '%s\n' "$CLAUDE_APT_LINE" >"$tmp/claude-code.list"
      run_sudo_step install -d -m 0755 /etc/apt/keyrings &&
        run_sudo_step install -m 0644 "$tmp/claude-code.asc" "$CLAUDE_APT_KEYRING" &&
        run_sudo_step install -m 0644 "$tmp/claude-code.list" "$CLAUDE_APT_LIST"
      local rc=$?
      rm -rf "$tmp"
      [ "$rc" -eq 0 ] || return
    fi
    run_sudo_step apt-get update || return
    run_sudo_step apt-get install -y claude-code || return
  elif [ "$PKG" = dnf ]; then
    if ! claude_dnf_ready; then
      tmp=$(mktemp -d) || { STEP_RESULT=failed; return; }
      if ! fetch_verified_key "$tmp/claude-code.asc"; then rm -rf "$tmp"; STEP_RESULT=failed; return; fi
      cat >"$tmp/claude-code.repo" <<'EOF'
[claude-code]
name=Claude Code
baseurl=https://downloads.claude.ai/claude-code/rpm/stable
enabled=1
gpgcheck=1
gpgkey=https://downloads.claude.ai/keys/claude-code.asc
EOF
      run_sudo_step rpm --import "$tmp/claude-code.asc" &&
        run_sudo_step install -m 0644 "$tmp/claude-code.repo" "$CLAUDE_DNF_REPO"
      local rc=$?
      rm -rf "$tmp"
      [ "$rc" -eq 0 ] || return
    fi
    run_sudo_step dnf install -y claude-code || return
  fi
  if find_tool claude; then
    say "  Installed: $FOUND_PATH"
    STEP_RESULT="done"
  else
    STEP_RESULT=failed
  fi
}

npm_prefix() { npm prefix -g 2>/dev/null; }

npm_prefix_writable() {
  [ -n "$1" ] && [ -d "$1" ] && [ -w "$1" ] || return 1
  [ ! -e "$1/lib" ] || [ -w "$1/lib" ]
}

npm_usable() { have npm && npm_prefix_writable "$(npm_prefix)"; }

detect_codex() {
  D_PURPOSE="Installs the OpenAI Codex CLI."
  if find_tool codex; then
    D_STATUS=satisfied
    D_FOUND="codex at $FOUND_PATH"
    return
  fi
  D_FOUND="not installed"
  D_STATUS=change
  if [ -n "$BREW" ]; then
    D_CHANGES="$BREW install --cask codex"
    if [ "$HOST_OS" = linux ] && npm_usable; then
      D_CHANGES="$D_CHANGES
(if Homebrew cannot install it: npm install -g @openai/codex)"
    fi
    return
  fi
  if [ "$HOST_OS" = macos ]; then
    D_STATUS=fail
    D_FOUND="not installed, and $(no_pkg_message)"
    return
  fi
  if have npm; then
    if npm_prefix_writable "$(npm_prefix)"; then
      D_CHANGES="npm install -g @openai/codex"
      return
    fi
    D_STATUS=fail
    D_FOUND="not installed. npm's global folder ($(npm_prefix)) needs root, and onboard.sh never runs npm with sudo. Set a per-user folder first (npm config set prefix ~/.npm-global), then run this again"
    return
  fi
  D_STATUS=fail
  D_FOUND="not installed, and neither Homebrew nor npm was found. OpenAI's own installer is: $CODEX_INSTALLER_CMD (onboard.sh does not run it)"
}

apply_codex() {
  if [ -n "$BREW" ]; then
    if ! run_cmd "$BREW" install --cask codex; then
      if [ "$HOST_OS" = linux ] && npm_usable; then
        say "  Homebrew could not install Codex; trying npm."
        run_cmd npm install -g @openai/codex || { STEP_RESULT=failed; return; }
      else
        STEP_RESULT=failed
        return
      fi
    fi
  else
    run_cmd npm install -g @openai/codex || { STEP_RESULT=failed; return; }
  fi
  if find_tool codex; then
    say "  Installed: $FOUND_PATH"
    STEP_RESULT="done"
  else
    STEP_RESULT=failed
  fi
}

detect_path_for() {
  local tool=$1 rc ntp
  D_PURPOSE="Lets new terminals find $tool."
  if ! find_tool "$tool"; then
    D_STATUS=fail
    D_FOUND="$tool was not found"
    return
  fi
  ntp=$(new_terminal_path)
  if [ -n "$ntp" ] && path_contains "$ntp" "$FOUND_DIR"; then
    D_STATUS=satisfied
    D_FOUND="$FOUND_DIR is on PATH in a new terminal"
    return
  fi
  if ! rc=$(rc_file); then
    D_STATUS=fail
    D_FOUND="$FOUND_DIR is not on PATH, and onboard.sh does not know your shell's startup file. Add this line to it yourself: $(path_line "$FOUND_DIR")"
    return
  fi
  if rc_mentions "$rc" "$FOUND_DIR"; then
    D_STATUS=satisfied
    D_FOUND="$rc already adds $FOUND_DIR"
    return
  fi
  D_STATUS=change
  D_FOUND="$FOUND_DIR is not on PATH in a new $(basename "$SHELL") terminal"
  D_CHANGES=""
  [ -e "$rc" ] && D_CHANGES="Back up $rc
"
  D_CHANGES="${D_CHANGES}Append to $rc: $(path_line "$FOUND_DIR")"
  PATH_DIR=$FOUND_DIR
  PATH_RC=$rc
}

apply_path_for() {
  local tool=$1 line
  line=$(path_line "$PATH_DIR")
  backup_file "$PATH_RC" || { STEP_RESULT=failed; return; }
  say "  Running: append to $PATH_RC: $line"
  if ! printf '\n%s\n' "$line" >>"$PATH_RC"; then
    STEP_RESULT=failed
    return
  fi
  PATH_ADDED="${PATH_ADDED}${PATH_DIR} (${PATH_RC})
"
  if tool_in_new_terminal "$tool"; then
    say "  Checked in a new $(basename "$SHELL") shell: $tool --version works."
    STEP_RESULT="done"
  else
    say "  $tool still does not run in a new shell."
    STEP_RESULT=failed
  fi
}

# Prints why a step is not applicable for the chosen agents, or nothing.
step_not_chosen() {
  case "$1" in
    claude | claude_path) agent_wants claude || printf 'Claude Code was not chosen' ;;
    codex | codex_path) agent_wants codex || printf 'Codex was not chosen' ;;
  esac
}

step_title() {
  case "$1" in
    policy) printf 'PowerShell execution policy' ;;
    git) printf 'Git' ;;
    git_path) printf 'Git on PATH' ;;
    git_bash) printf 'Git Bash' ;;
    claude) printf 'Claude Code' ;;
    claude_path) printf 'Claude Code on PATH' ;;
    codex) printf 'Codex' ;;
    codex_path) printf 'Codex on PATH' ;;
    *) printf '%s' "$1" ;;
  esac
}

step_dep() {
  case "$1" in
    git_path) printf 'git' ;;
    claude_path) printf 'claude' ;;
    codex_path) printf 'codex' ;;
  esac
}

step_detect() {
  case "$1" in
    policy | git_bash) D_STATUS=na; D_FOUND="only needed on Windows" ;;
    git) detect_git ;;
    git_path) detect_path_for git ;;
    claude) detect_claude ;;
    claude_path) detect_path_for claude ;;
    codex) detect_codex ;;
    codex_path) detect_path_for codex ;;
  esac
}

step_apply() {
  case "$1" in
    git) apply_git ;;
    git_path) apply_path_for git ;;
    claude) apply_claude ;;
    claude_path) apply_path_for claude ;;
    codex) apply_codex ;;
    codex_path) apply_path_for codex ;;
  esac
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

set_outcome() { eval "OUTCOME_$1=\$2"; }
get_outcome() { eval "printf '%s' \"\${OUTCOME_$1:-}\""; }
set_plan() { eval "PLAN_$1=\$2"; }
get_plan() { eval "printf '%s' \"\${PLAN_$1:-}\""; }
set_detail() { eval "DETAIL_$1=\$2"; }
get_detail() { eval "printf '%s' \"\${DETAIL_$1:-}\""; }

reset_detection() {
  D_STATUS=""
  D_FOUND=""
  D_CHANGES=""
  D_PURPOSE=""
}

plan_text() {
  case "$D_STATUS" in
    satisfied) printf 'already set up' ;;
    change) printf 'will change' ;;
    na) printf 'not applicable' ;;
    *) printf 'cannot be done (details below)' ;;
  esac
}

title_width() {
  local id t width=0
  for id in $STEPS_RUN; do
    t=$(step_title "$id")
    [ ${#t} -gt "$width" ] && width=${#t}
  done
  printf '%s' $((width + 3))
}

print_changes() {
  local prefix first=1 line
  if [ "$DRY_RUN" -eq 1 ]; then prefix="Would do: "; else prefix="Will do:  "; fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$first" -eq 1 ]; then
      say "$prefix$line"
      first=0
    else
      say "          $line"
    fi
  done <<EOF
$D_CHANGES
EOF
}

run_steps() {
  local id n total=0 width dep depo t tag why
  STEPS_RUN=""
  for id in $STEP_IDS; do
    STEPS_RUN="$STEPS_RUN $id"
    total=$((total + 1))
  done
  width=$(title_width)

  heading "Plan"
  n=0
  for id in $STEPS_RUN; do
    n=$((n + 1))
    dep=$(step_dep "$id")
    if [ -n "$(step_not_chosen "$id")" ]; then
      set_plan "$id" na
      t="not applicable"
    elif [ -n "$dep" ] && [ "$(get_plan "$dep")" != satisfied ]; then
      set_plan "$id" pending
      t="checked after $(step_title "$dep")"
    else
      reset_detection
      step_detect "$id"
      set_plan "$id" "$D_STATUS"
      t=$(plan_text)
    fi
    printf '  %2d. %-*s%s\n' "$n" "$width" "$(step_title "$id")" "$t"
  done
  say ""

  QUIT=0
  if [ "$GUIDED" -eq 1 ]; then
    say "Nothing changes until you choose Next at a step."
    color "36" "Press Enter to start, or Q to quit."
    if ! read_answer; then
      QUIT=1
    else
      case "$(lower "$REPLY")" in q | quit) QUIT=1 ;; esac
    fi
  fi

  n=0
  for id in $STEPS_RUN; do
    n=$((n + 1))
    t=$(step_title "$id")
    tag="[$n/$total] $t"
    why=$(step_not_chosen "$id")
    if [ -n "$why" ]; then
      set_outcome "$id" "not applicable"
      set_detail "$id" "$why"
      note "$tag: not applicable. $why"
      continue
    fi
    if [ "$QUIT" -eq 1 ]; then
      set_outcome "$id" skipped
      continue
    fi
    dep=$(step_dep "$id")
    if [ -n "$dep" ]; then
      depo=$(get_outcome "$dep")
      if [ "$DRY_RUN" -eq 1 ] && [ "$depo" = "would change" ]; then
        set_outcome "$id" "checked after $(step_title "$dep")"
        note "$tag: checked after $(step_title "$dep")"
        continue
      fi
      case "$depo" in
        done | "already satisfied") ;;
        *)
          set_outcome "$id" skipped
          note "$tag: skipped, needs $(step_title "$dep")"
          continue
          ;;
      esac
    fi

    reset_detection
    step_detect "$id"
    case "$D_STATUS" in
      satisfied)
        set_outcome "$id" "already satisfied"
        note "$tag: already satisfied. $D_FOUND"
        continue
        ;;
      na)
        set_outcome "$id" "not applicable"
        set_detail "$id" "$D_FOUND"
        note "$tag: not applicable. $D_FOUND"
        continue
        ;;
      change) ;;
      *)
        set_outcome "$id" failed
        warn "$tag: failed. $D_FOUND"
        continue
        ;;
    esac

    say ""
    heading "Step $n of $total: $t"
    [ -n "$D_PURPOSE" ] && say "$D_PURPOSE"
    say "Found:    $D_FOUND"
    print_changes
    if [ "$DRY_RUN" -eq 1 ]; then
      set_outcome "$id" "would change"
      continue
    fi

    STEP_ANSWER=next
    [ "$GUIDED" -eq 1 ] && ask_step
    case "$STEP_ANSWER" in
      skip)
        set_outcome "$id" skipped
        say "$t: skipped."
        continue
        ;;
      quit)
        set_outcome "$id" skipped
        QUIT=1
        continue
        ;;
    esac

    STEP_RESULT=failed
    step_apply "$id"
    set_outcome "$id" "$STEP_RESULT"
    [ "$STEP_RESULT" = "done" ] || warn "$t: $STEP_RESULT."
  done
}

print_summary() {
  local id width o detail skipped=0 changes=0
  width=$(title_width)
  say ""
  heading "Summary"
  for id in $STEPS_RUN; do
    o=$(get_outcome "$id")
    detail=$(get_detail "$id")
    case "$o" in
      skipped | declined) skipped=1 ;;
      "would change" | failed) changes=1 ;;
      "not applicable") [ -n "$detail" ] && o="$o ($detail)" ;;
    esac
    printf '  %-*s%s\n' "$width" "$(step_title "$id")" "$o"
  done
  say ""
  if [ -n "$BACKUPS" ]; then
    say "Backups written:"
    printf '%s' "$BACKUPS" | sed 's/^/  /'
  fi
  if [ -n "$PATH_ADDED" ]; then
    say "Added to PATH:"
    printf '%s' "$PATH_ADDED" | sed 's/^/  /'
    say "Open a new terminal window so it picks up the new PATH."
  fi
  [ "$skipped" -eq 1 ] && say "Skipped or declined steps are offered again when you run the same command again."
  [ "$IS_WSL" -eq 1 ] && say "These tools were set up inside this WSL distribution, not for native Windows."
  if [ "$DRY_RUN" -eq 1 ]; then
    [ "$changes" -eq 0 ] && say "A real run would change nothing."
    say "Preview only: nothing was changed."
    return
  fi
  if [ "$AGENT" = both ]; then
    say "Next: open a new terminal window and run claude, then codex, to sign in."
  else
    say "Next: open a new terminal window and run $AGENT to sign in."
  fi
}

exit_code() {
  local id
  for id in $STEPS_RUN; do
    case "$(get_outcome "$id")" in failed | declined) return 1 ;; esac
  done
  return 0
}

main() {
  local rc code
  parse_args "$@"
  rc=$?
  if [ "$rc" -eq 3 ]; then
    usage
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    usage
    say "Nothing was changed."
    return 2
  fi
  detect_host || return 1
  detect_pkg

  GUIDED=0
  if [ "$DRY_RUN" -eq 0 ] && [ "$NO_GUIDE" -eq 0 ] && can_prompt; then GUIDED=1; fi

  say "onboard.sh $ONBOARD_VERSION | $HOST_DESC | $(basename "${SHELL:-sh}") | ${PKG:-no package manager} | agent: $AGENT"
  [ "$DRY_RUN" -eq 1 ] && say "Preview: nothing will be changed."
  if [ "$NO_GUIDE" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    say "Running every step without pausing. Each sudo command still needs YES."
  fi
  say ""

  run_steps
  print_summary
  code=0
  exit_code || code=1
  say "Exit code: $code"
  return "$code"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit $?
fi
