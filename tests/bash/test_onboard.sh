#!/usr/bin/env bash
# Tests for scripts/onboard.sh. Each test runs in a subshell with stubbed commands,
# so nothing is installed and no real startup file is touched.
# Stubs are functions and variables the sourced script reads, which shellcheck cannot see.
# shellcheck source-path=SCRIPTDIR disable=SC2317,SC2329,SC2034,SC2030,SC2031

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/scripts/onboard.sh"
PASSED=0
FAILED=0
FAILED_NAMES=""

t() {
  local name=$1
  shift
  if (
    # shellcheck source=../../scripts/onboard.sh
    . "$SCRIPT"
    TMP=$(mktemp -d)
    export HOME="$TMP/home"
    mkdir -p "$HOME"
    trap 'rm -rf "$TMP"' EXIT
    "$@"
  ) >"${TMPDIR:-/tmp}/onboard-test-out.$$" 2>&1; then
    PASSED=$((PASSED + 1))
    printf 'ok   %s\n' "$name"
  else
    FAILED=$((FAILED + 1))
    FAILED_NAMES="$FAILED_NAMES
  $name"
    printf 'FAIL %s\n' "$name"
    sed 's/^/     | /' "${TMPDIR:-/tmp}/onboard-test-out.$$"
  fi
  rm -f "${TMPDIR:-/tmp}/onboard-test-out.$$"
}

assert_eq() {
  if [ "$1" != "$2" ]; then
    printf 'expected: [%s]\n  actual: [%s]\n' "$2" "$1"
    return 1
  fi
}

assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  printf 'expected to contain: [%s]\nin: [%s]\n' "$2" "$1"
  return 1
}

assert_not_contains() {
  case "$1" in
    *"$2"*)
      printf 'expected not to contain: [%s]\nin: [%s]\n' "$2" "$1"
      return 1
      ;;
  esac
}

answers() {
  ANSWERS=("$@")
  ANSWER_I=0
  READS=0
  can_prompt() { return 0; }
  read_answer() {
    READS=$((READS + 1))
    if [ "$ANSWER_I" -ge "${#ANSWERS[@]}" ]; then
      REPLY=""
      return 1
    fi
    REPLY=${ANSWERS[$ANSWER_I]}
    ANSWER_I=$((ANSWER_I + 1))
  }
}

# A fake world of four steps: a, a_path (needs a), b, b_path (needs b).
fake_steps() {
  STEP_IDS="a a_path b b_path"
  APPLIED=""
  step_not_chosen() { :; }
  step_title() { printf 'Tool %s' "$1"; }
  step_dep() {
    case "$1" in
      a_path) printf 'a' ;;
      b_path) printf 'b' ;;
    esac
  }
  step_detect() {
    eval "D_STATUS=\${FS_$1:-change}"
    D_FOUND="state of $1"
    D_CHANGES="change $1"
  }
  step_apply() {
    APPLIED="$APPLIED $1"
    eval "STEP_RESULT=\${FR_$1:-done}"
  }
}

# ---------------------------------------------------------------------------
# Arguments and host
# ---------------------------------------------------------------------------

test_args_valid() {
  parse_args --agent CLAUDE || return 1
  assert_eq "$AGENT" claude || return 1
  parse_args --agent=both --dry-run --no-guide || return 1
  assert_eq "$AGENT/$DRY_RUN/$NO_GUIDE" both/1/1
}

test_args_invalid() {
  parse_args >/dev/null
  assert_eq $? 2 || return 1
  parse_args --agent gemini >/dev/null
  assert_eq $? 2 || return 1
  parse_args --agent >/dev/null
  assert_eq $? 2 || return 1
  parse_args --agent claude --force >/dev/null
  assert_eq $? 2 || return 1
  parse_args --help
  assert_eq $? 3
}

test_main_usage_error() {
  detect_host() { echo "must not detect"; return 1; }
  local out
  out=$(main --agent nope)
  assert_eq $? 2 || return 1
  assert_contains "$out" "Nothing was changed."
}

test_windows_shell_redirect() {
  uname() { printf 'MINGW64_NT-10.0'; }
  AGENT=both
  local out
  out=$(detect_host)
  assert_eq $? 1 || return 1
  assert_contains "$out" "onboard.ps1 -Agent both"
}

test_wsl_noted() {
  uname() { printf 'Linux'; }
  WSL_DISTRO_NAME=Ubuntu
  detect_host || return 1
  assert_eq "$HOST_OS" linux || return 1
  assert_contains "$HOST_DESC" "WSL"
}

# ---------------------------------------------------------------------------
# Backups and PATH lines
# ---------------------------------------------------------------------------

test_backup_names() {
  local f="$TMP/rc"
  printf 'one\n' >"$f"
  assert_eq "$(backup_path "$f")" "$f.bak" || return 1
  backup_file "$f" >/dev/null || return 1
  assert_eq "$(cat "$f.bak")" one || return 1
  printf 'two\n' >"$f"
  backup_file "$f" >/dev/null || return 1
  assert_eq "$(cat "$f.bak")" one || return 1
  local n
  n=$(find "$TMP" -name 'rc*.bak' | wc -l | tr -d ' ')
  assert_eq "$n" 2
}

on_windows() {
  case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) return 0 ;; esac
  return 1
}

test_backup_keeps_mode() {
  if on_windows; then echo "(file modes are not checked on Windows)"; return 0; fi
  local f="$TMP/private"
  printf 'secret-free\n' >"$f"
  chmod 600 "$f"
  backup_file "$f" >/dev/null || return 1
  assert_eq "$(find "$f.bak" -perm 600)" "$f.bak"
}

test_symlinked_rc_stays_a_link() {
  if on_windows; then echo "(symbolic links are not checked on Windows)"; return 0; fi
  HOST_OS=linux SHELL=/bin/bash
  mkdir -p "$TMP/dotfiles" "$HOME/.local/bin"
  printf 'old line\n' >"$TMP/dotfiles/bashrc"
  ln -s "$TMP/dotfiles/bashrc" "$HOME/.bashrc"
  printf '#!/bin/sh\necho 1\n' >"$HOME/.local/bin/claude"
  chmod +x "$HOME/.local/bin/claude"
  find_tool() { FOUND_PATH="$HOME/.local/bin/claude"; FOUND_DIR="$HOME/.local/bin"; }
  new_terminal_path() { printf '/usr/bin:/bin'; }
  tool_in_new_terminal() { return 0; }
  detect_path_for claude
  apply_path_for claude >/dev/null
  assert_eq "$STEP_RESULT" "done" || return 1
  [ -L "$HOME/.bashrc" ] || { echo "$HOME/.bashrc is no longer a link"; return 1; }
  [ -L "$HOME/.bashrc.bak" ] && { echo "the backup is a link"; return 1; }
  assert_eq "$(cat "$HOME/.bashrc.bak")" "old line" || return 1
  assert_contains "$(cat "$TMP/dotfiles/bashrc")" "added by onboard.sh"
}

test_unwritable_rc_fails_without_sudo() {
  if on_windows || [ "$(id -u)" = 0 ]; then echo "(not checked on Windows or as root)"; return 0; fi
  HOST_OS=linux SHELL=/bin/bash
  printf 'x\n' >"$HOME/.bashrc"
  chmod 444 "$HOME/.bashrc"
  sudo() { echo "SUDO RAN"; }
  PATH_DIR="$HOME/.local/bin" PATH_RC="$HOME/.bashrc"
  local out
  out=$(apply_path_for claude; printf 'result=%s' "$STEP_RESULT")
  assert_contains "$out" "result=failed" || return 1
  assert_not_contains "$out" "SUDO RAN"
}

test_backup_missing_file_is_ok() {
  backup_file "$TMP/none" || return 1
  assert_eq "$BACKUPS" ""
}

test_path_line_uses_home() {
  # shellcheck disable=SC2016
  assert_eq "$(path_line "$HOME/.local/bin")" 'export PATH="$PATH:$HOME/.local/bin"  # added by onboard.sh' || return 1
  # shellcheck disable=SC2016
  assert_eq "$(path_line /opt/x/bin)" 'export PATH="$PATH:/opt/x/bin"  # added by onboard.sh'
}

test_rc_file() {
  SHELL=/bin/zsh HOST_OS=linux
  assert_eq "$(rc_file)" "$HOME/.zshrc" || return 1
  SHELL=/bin/bash HOST_OS=macos
  assert_eq "$(rc_file)" "$HOME/.bash_profile" || return 1
  SHELL=/bin/bash HOST_OS=linux
  assert_eq "$(rc_file)" "$HOME/.bashrc" || return 1
  SHELL=/usr/bin/fish
  rc_file >/dev/null && return 1
  return 0
}

test_path_contains() {
  path_contains "/usr/bin:/home/u/.local/bin:/bin" /home/u/.local/bin || return 1
  path_contains "/usr/bin:/home/u/.local/bin/" /home/u/.local/bin || return 1
  path_contains "/usr/bin:/home/u/.local/binx" /home/u/.local/bin && return 1
  return 0
}

test_path_step_appends_after_backup() {
  HOST_OS=linux SHELL=/bin/bash
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\necho 1\n' >"$HOME/.local/bin/claude"
  chmod +x "$HOME/.local/bin/claude"
  printf 'alias ll="ls -l"\n' >"$HOME/.bashrc"
  command() { [ "$1" = -v ] && return 1; builtin command "$@"; }
  known_dirs() { printf '%s\n' "$HOME/.local/bin"; }
  new_terminal_path() { printf '/usr/bin:/bin'; }
  tool_in_new_terminal() { return 0; }
  detect_path_for claude
  assert_eq "$D_STATUS" change || return 1
  STEP_RESULT=""
  apply_path_for claude >/dev/null
  assert_eq "$STEP_RESULT" "done" || return 1
  assert_eq "$(cat "$HOME/.bashrc.bak")" 'alias ll="ls -l"' || return 1
  # shellcheck disable=SC2016
  assert_contains "$(cat "$HOME/.bashrc")" 'export PATH="$PATH:$HOME/.local/bin"  # added by onboard.sh' || return 1
  assert_contains "$(cat "$HOME/.bashrc")" 'alias ll="ls -l"' || return 1
  detect_path_for claude
  assert_eq "$D_STATUS" satisfied
}

test_path_step_satisfied_in_new_terminal() {
  HOST_OS=macos SHELL=/bin/zsh
  find_tool() { FOUND_PATH=/opt/homebrew/bin/git; FOUND_DIR=/opt/homebrew/bin; }
  new_terminal_path() { printf '/opt/homebrew/bin:/usr/bin'; }
  detect_path_for git
  assert_eq "$D_STATUS" satisfied || return 1
  [ ! -e "$HOME/.zshrc" ]
}

# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------

test_apple_git_stub_not_counted() {
  HOST_OS=macos
  xcode-select() { return 2; }
  is_apple_git_stub /usr/bin/git || return 1
  xcode-select() { printf '/Library/Developer/CommandLineTools\n'; }
  is_apple_git_stub /usr/bin/git && return 1
  HOST_OS=linux
  xcode-select() { return 2; }
  is_apple_git_stub /usr/bin/git && return 1
  return 0
}

test_git_mac_without_brew_fails_with_next_step() {
  HOST_OS=macos PKG="" BREW=""
  find_tool() { return 1; }
  detect_git
  assert_eq "$D_STATUS" fail || return 1
  assert_contains "$D_FOUND" "https://brew.sh"
}

test_git_apt_plan() {
  HOST_OS=linux PKG=apt
  find_tool() { return 1; }
  detect_git
  assert_eq "$D_STATUS" change || return 1
  assert_contains "$D_CHANGES" "sudo apt-get install -y git"
}

test_claude_pacman_points_to_docs() {
  HOST_OS=linux PKG=pacman
  find_tool() { return 1; }
  detect_claude
  assert_eq "$D_STATUS" fail || return 1
  assert_contains "$D_FOUND" "$CLAUDE_DOCS"
}

test_claude_apt_plan_checks_key() {
  HOST_OS=linux PKG=apt
  find_tool() { return 1; }
  claude_apt_ready() { return 1; }
  have() { return 0; }
  detect_claude
  assert_eq "$D_STATUS" change || return 1
  assert_contains "$D_CHANGES" "check its fingerprint" || return 1
  assert_contains "$D_CHANGES" "$CLAUDE_APT_LIST"
}

test_claude_repo_already_set_up_is_not_added_again() {
  HOST_OS=linux PKG=apt
  find_tool() { return 1; }
  claude_apt_ready() { return 0; }
  detect_claude
  assert_eq "$D_STATUS" change || return 1
  assert_not_contains "$D_CHANGES" "signing key" || return 1
  assert_not_contains "$D_CHANGES" "$CLAUDE_APT_LIST" || return 1
  CURL_RAN=0
  curl() { CURL_RAN=1; }
  sudo() { :; }
  answers YES YES
  apply_claude >/dev/null
  assert_eq "$CURL_RAN" 0
}

test_unsupported_host_stops() {
  uname() { printf 'FreeBSD'; }
  local out
  out=$(detect_host)
  assert_eq $? 1 || return 1
  assert_contains "$out" "does not support this system (FreeBSD)"
}

test_macos_host() {
  uname() { printf 'Darwin'; }
  sw_vers() { printf '15.1'; }
  detect_host || return 1
  assert_eq "$HOST_OS/$HOST_DESC" "macos/macOS 15.1"
}

test_key_fingerprint_single_key_only() {
  gpg() {
    printf 'pub:-:4096:1:AAAA:1:::-:::scESC::::::23::0:\n'
    printf 'fpr:::::::::%s:\n' "$CLAUDE_KEY_FPR"
    printf 'sub:-:4096:1:BBBB:1::::::e::::::23:\n'
    printf 'fpr:::::::::0000000000000000000000000000000000000000:\n'
  }
  assert_eq "$(key_fingerprint x)" "$CLAUDE_KEY_FPR" || return 1
  gpg() {
    printf 'pub:-:4096:1:AAAA:1:::-:::scESC::::::23::0:\n'
    printf 'fpr:::::::::%s:\n' "$CLAUDE_KEY_FPR"
    printf 'pub:-:4096:1:CCCC:1:::-:::scESC::::::23::0:\n'
    printf 'fpr:::::::::1111111111111111111111111111111111111111:\n'
  }
  assert_eq "$(key_fingerprint x)" ""
}

test_wrong_key_writes_nothing() {
  HOST_OS=linux PKG=apt
  curl() { printf 'fake key' >"$4"; }
  key_fingerprint() { printf '1111111111111111111111111111111111111111'; }
  SUDO_CALLS=""
  sudo() { SUDO_CALLS="$SUDO_CALLS|$*"; }
  claude_apt_ready() { return 1; }
  answers YES YES YES YES YES
  STEP_RESULT=""
  apply_claude >/dev/null
  assert_eq "$STEP_RESULT" failed || return 1
  assert_eq "$SUDO_CALLS" ""
}

test_codex_npm_needs_root_is_not_run() {
  HOST_OS=linux BREW=""
  find_tool() { return 1; }
  have() { [ "$1" = npm ]; }
  npm_prefix() { printf '/usr'; }
  npm_prefix_writable() { return 1; }
  detect_codex
  assert_eq "$D_STATUS" fail || return 1
  assert_contains "$D_FOUND" "never runs npm with sudo"
}

test_codex_without_brew_or_npm_prints_installer() {
  HOST_OS=linux BREW=""
  find_tool() { return 1; }
  have() { return 1; }
  detect_codex
  assert_eq "$D_STATUS" fail || return 1
  assert_contains "$D_FOUND" "$CODEX_INSTALLER_CMD" || return 1
  assert_contains "$D_FOUND" "does not run it"
}

test_codex_brew_plan() {
  HOST_OS=macos BREW=/opt/homebrew/bin/brew
  find_tool() { return 1; }
  detect_codex
  assert_eq "$D_STATUS" change || return 1
  assert_eq "$D_CHANGES" "/opt/homebrew/bin/brew install --cask codex"
}

# ---------------------------------------------------------------------------
# sudo
# ---------------------------------------------------------------------------

test_sudo_needs_exact_yes() {
  SUDO_CALLS=""
  sudo() { SUDO_CALLS="$SUDO_CALLS|$*"; }
  local a
  for a in yes Y "" "YES " ; do
    answers "$a"
    run_sudo apt-get update >/dev/null
    assert_eq $? 10 || return 1
  done
  assert_eq "$SUDO_CALLS" "" || return 1
  answers YES
  run_sudo apt-get update >/dev/null || return 1
  assert_eq "$SUDO_CALLS" "|apt-get update"
}

test_sudo_without_terminal_is_declined() {
  can_prompt() { return 1; }
  sudo() { echo "sudo ran"; return 0; }
  local out
  out=$(run_sudo apt-get update)
  assert_eq $? 10 || return 1
  assert_not_contains "$out" "sudo ran"
}

test_declined_sudo_marks_step_declined() {
  HOST_OS=linux PKG=apt
  sudo() { return 0; }
  find_tool() { return 1; }
  answers no
  STEP_RESULT=""
  apply_git >/dev/null
  assert_eq "$STEP_RESULT" declined
}

# ---------------------------------------------------------------------------
# Guided run
# ---------------------------------------------------------------------------

test_next_applies_every_step() {
  fake_steps
  GUIDED=1 DRY_RUN=0
  answers "" "" "" "" ""
  run_steps >/dev/null
  assert_eq "$APPLIED" " a a_path b b_path" || return 1
  exit_code
}

test_skip_skips_dependents_and_exits_0() {
  fake_steps
  GUIDED=1 DRY_RUN=0
  answers "" s "" ""
  run_steps >/dev/null
  assert_eq "$APPLIED" " b b_path" || return 1
  assert_eq "$(get_outcome a)/$(get_outcome a_path)" skipped/skipped || return 1
  exit_code
}

test_quit_skips_the_rest() {
  fake_steps
  GUIDED=1 DRY_RUN=0
  answers "" "" q
  run_steps >/dev/null
  assert_eq "$APPLIED" " a" || return 1
  assert_eq "$(get_outcome a_path)/$(get_outcome b)/$(get_outcome b_path)" skipped/skipped/skipped || return 1
  exit_code
}

test_quit_at_start() {
  fake_steps
  GUIDED=1 DRY_RUN=0
  answers Q
  run_steps >/dev/null
  assert_eq "$APPLIED" "" || return 1
  assert_eq "$(get_outcome a)" skipped
}

test_end_of_input_quits() {
  fake_steps
  GUIDED=1 DRY_RUN=0
  answers ""
  run_steps >/dev/null
  assert_eq "$APPLIED" "" || return 1
  assert_eq "$(get_outcome b_path)" skipped
}

test_unrecognized_answer_asks_again() {
  fake_steps
  FS_b=satisfied FS_b_path=satisfied
  GUIDED=1 DRY_RUN=0
  answers "" maybe "" ""
  local out
  run_steps >"$TMP/out"
  out=$(cat "$TMP/out")
  assert_eq "$APPLIED" " a a_path" || return 1
  assert_contains "$out" "Press Enter for Next, or type S to skip or Q to quit."
}

test_satisfied_steps_do_not_pause() {
  fake_steps
  FS_a=satisfied FS_a_path=satisfied FS_b=satisfied FS_b_path=na
  GUIDED=1 DRY_RUN=0
  answers ""
  run_steps >/dev/null
  assert_eq "$READS" 1 || return 1
  assert_eq "$(get_outcome b_path)" "not applicable" || return 1
  exit_code
}

test_not_guided_reads_nothing() {
  fake_steps
  GUIDED=0 DRY_RUN=0
  answers
  run_steps >/dev/null
  assert_eq "$READS" 0 || return 1
  assert_eq "$APPLIED" " a a_path b b_path"
}

test_failed_step_blocks_only_dependents() {
  fake_steps
  FR_a=failed
  GUIDED=0 DRY_RUN=0
  run_steps >/dev/null
  assert_eq "$(get_outcome a)/$(get_outcome a_path)/$(get_outcome b)/$(get_outcome b_path)" failed/skipped/done/done || return 1
  exit_code && return 1
  return 0
}

test_declined_step_exits_1() {
  fake_steps
  FR_b=declined
  GUIDED=0 DRY_RUN=0
  run_steps >/dev/null
  assert_eq "$(get_outcome b_path)" skipped || return 1
  exit_code && return 1
  return 0
}

test_preview_changes_nothing() {
  fake_steps
  GUIDED=0 DRY_RUN=1
  answers
  local out
  run_steps >"$TMP/out"
  out=$(cat "$TMP/out")
  assert_eq "$APPLIED" "" || return 1
  assert_eq "$READS" 0 || return 1
  assert_eq "$(get_outcome a)/$(get_outcome a_path)" "would change/checked after Tool a" || return 1
  assert_contains "$out" "Would do: change a"
}

test_steps_for_unchosen_agent_are_not_applicable() {
  AGENT=codex GUIDED=0 DRY_RUN=0
  STEP_IDS="claude claude_path codex"
  APPLIED=""
  step_detect() { D_STATUS=change; D_FOUND="missing"; D_CHANGES="install $1"; }
  step_apply() { APPLIED="$APPLIED $1"; STEP_RESULT="done"; }
  run_steps >/dev/null
  assert_eq "$APPLIED" " codex" || return 1
  assert_eq "$(get_outcome claude)/$(get_outcome claude_path)" "not applicable/not applicable" || return 1
  assert_contains "$(print_summary)" "not applicable (Claude Code was not chosen)"
}

test_windows_only_steps_are_not_applicable() {
  step_detect policy
  assert_eq "$D_STATUS" na || return 1
  step_detect git_bash
  assert_eq "$D_STATUS" na
}

test_wsl_is_named_in_summary() {
  IS_WSL=1 STEPS_RUN="" AGENT=claude DRY_RUN=0
  assert_contains "$(print_summary)" "set up inside this WSL distribution, not for native Windows"
}

test_preview_with_nothing_to_do_says_so() {
  fake_steps
  FS_a=satisfied FS_a_path=satisfied FS_b=satisfied FS_b_path=satisfied
  GUIDED=0 DRY_RUN=1
  run_steps >/dev/null
  assert_contains "$(print_summary)" "A real run would change nothing."
}

test_preview_end_to_end_on_bare_linux() {
  uname() { printf 'Linux'; }
  find_tool() { return 1; }
  find_brew() { return 1; }
  have() {
    case "$1" in apt-get | curl | gpg | npm) return 0 ;; esac
    return 1
  }
  npm_prefix() { printf '%s/.npm-global' "$HOME"; }
  npm_prefix_writable() { return 0; }
  claude_apt_ready() { return 1; }
  sudo() { echo "SUDO RAN"; }
  curl() { echo "CURL RAN"; }
  local out
  out=$(main --agent both --dry-run)
  assert_eq $? 0 || return 1
  assert_not_contains "$out" "SUDO RAN" || return 1
  assert_not_contains "$out" "CURL RAN" || return 1
  assert_contains "$out" "Would do: sudo apt-get update" || return 1
  assert_contains "$out" "Preview only: nothing was changed." || return 1
  assert_not_contains "$out" "A real run would change nothing." || return 1
  assert_contains "$out" "PowerShell execution policy" || return 1
  assert_contains "$out" "Git on PATH" || return 1
  assert_contains "$out" "checked after Git"
}

# ---------------------------------------------------------------------------
# Script safety
# ---------------------------------------------------------------------------

test_never_pipes_downloads_into_a_shell() {
  local hits
  hits=$(grep -nE '(curl|wget)[^|#]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z)?sh' "$SCRIPT" | grep -v '^[0-9]*:CODEX_INSTALLER_CMD=')
  assert_eq "$hits" ""
}

test_never_touches_git_config_claude_settings_or_codex_login() {
  assert_eq "$(grep -niE 'git[[:space:]]+config|\.gitconfig|settings\.json|codex[[:space:]]+login' "$SCRIPT")" ""
}

test_takes_no_secret_options() {
  assert_eq "$(grep -nE '^[[:space:]]*--?[a-z-]*(key|token|secret|password)' "$SCRIPT")" ""
}

test_never_runs_npm_with_sudo() {
  assert_eq "$(grep -nE 'sudo[^#]*npm|run_sudo[^#]*npm' "$SCRIPT" | grep -v 'never runs npm with sudo')" ""
}

for name in $(declare -F | awk '{print $3}' | grep '^test_'); do
  t "$name" "$name"
done

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
if [ "$FAILED" -gt 0 ]; then
  printf 'Failed:%s\n' "$FAILED_NAMES"
  exit 1
fi
