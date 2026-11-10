#!/usr/bin/env bash
#
# Install this repo's configuration into the live Claude Code profiles, check
# the live profiles against it, or pull live changes back into the repo.
#
#   ./install.sh            deploy repo -> ~/.claude*, ~/.local/bin, ~/.codex* hooks, agy plugin
#   ./install.sh --check    report where the live profiles differ (exit 1 on drift)
#   ./install.sh --pull     copy live settings and Codex hooks back (machine-local keys stripped)
#   ./install.sh --help
#
# Direction matters. Deploying a stale repo silently reverts real live state -
# plugins enabled since the last commit, an effort level raised in /config, a
# pinned model. Run --check first: if a difference is something you changed
# live, --pull it into the repo rather than deploying over it. Deploys back up
# the previous settings.json either way.
#
# The README's copy commands are the manual equivalent. They are easy to run
# partially - which is how the default ~/.claude profile ended up untracked,
# with an empty CLAUDE.md and one of eleven skills - so prefer this.
#
# The shared MCP servers in mcp-servers.json are merged into each profile's
# .claude.json by key, never written over it: that file also holds the
# profile's project history. Repo -> live only, so --pull leaves it alone.
#
# A deploy sets a brand-new profile up completely: settings, status line,
# skills, a CLAUDE.md symlinked to the one real file, and, when the profile has
# no plugins at all, the marketplaces and the enabled plugin set. That last
# step is the only one that touches the network; INSTALL_SKIP_PLUGINS=1 turns
# it off. It never changes plugin versions in a profile that already has them:
# that is claude-update-plugins' job.
#
# Requires bash 3.2 (macOS stock), jq and diff. macOS/Linux only: the Windows
# profile in windows/ is copied by hand, see the README.
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$REPO_ROOT" || exit 1

# repo dir : live dir : status line filename : skill set
PROFILES="claude:$HOME/.claude:statusline-command.sh:all
claude-dev:$HOME/.claude-dev:statusline.sh:all
claude-personal:$HOME/.claude-personal:statusline.sh:all
claude-work:$HOME/.claude-work:statusline.sh:no-nextjs
claude-yosh:$HOME/.claude-yosh:statusline.sh:all"

# The one real CLAUDE.md, and the profiles whose CLAUDE.md can link to it
# (README, Global config). Directory names under $HOME, space-separated.
CLAUDE_MD_REAL="$HOME/.claude-personal/CLAUDE.md"
CLAUDE_MD_LINKED=".claude .claude-work .claude-dev .claude-yosh"

# repo file : live file. Shared by every profile. The tab-status scripts each exit
# on the wrong terminal; the Prisma guard is inert without its local hosts file;
# wt-dev, claude-update-plugins and claude-handoff are commands you run yourself, never hooks. next-steps is one file
# under two names: the hooks call next-steps, $VISUAL/$EDITOR is next-steps-editor.
# The herdr hook is herdr's own file (it exits outside a herdr pane): a herdr
# update rewrites it live, so copy the new version back here when --check flags it.
SHARED_SCRIPTS="iterm-tab-status.sh:$HOME/.local/bin/claude-iterm-tab-status.sh
wt-tab-status.sh:$HOME/.local/bin/claude-wt-tab-status.sh
prisma-prod-guard.sh:$HOME/.local/bin/prisma-prod-guard
wt-dev.sh:$HOME/.local/bin/wt-dev
claude-handoff.sh:$HOME/.local/bin/claude-handoff
update-plugins.sh:$HOME/.local/bin/claude-update-plugins
next-steps.mjs:$HOME/.local/bin/next-steps
next-steps.mjs:$HOME/.local/bin/next-steps-editor
claude/hooks/herdr-agent-state.sh:$HOME/.claude/hooks/herdr-agent-state.sh"

# Codex runs hooks from hooks.json only once each is trusted in /hooks, and
# records that in config.toml as [hooks.state."<abs path>:<event>:<group>:<n>"].
# The hash covers the hook definition, not the path, so the tracked list keeps
# only "<event>:<group>:<n> <hash>" and install.sh re-keys it for this machine.
# One home per Codex account, in deploy order, the way .zshrc-codex sets them:
# bare `codex` uses ~/.codex, `codex-yosh` sets CODEX_HOME to ~/.codex-yosh.
# Each home keeps its own login, sessions and trust tables; the hooks and the
# shared config settings are the same in all of them. Homes that do not exist
# are skipped, so this list is safe on a machine with only the default account.
# CODEX_HOME set in the environment narrows the run to that one home.
CODEX_PROFILES="$HOME/.codex
$HOME/.codex-yosh"
[ -n "${CODEX_HOME:-}" ] && CODEX_PROFILES="$CODEX_HOME"

# Point the codex_* helpers below at one home.
codex_use_dir() {
  CODEX_DIR="$1"
  CODEX_HOOKS="$CODEX_DIR/hooks.json"
  CODEX_CONFIG="$CODEX_DIR/config.toml"
  CODEX_TRUST_PREFIX="[hooks.state.\"$CODEX_HOOKS:"
}
codex_use_dir "${CODEX_PROFILES%%$'\n'*}"
TRUST_FILE="codex/hooks-trust.txt"
TRUST_HEADER="# Trust hashes for codex/hooks.json, written by ./install.sh --pull from the
# live ~/.codex/config.toml. Format: <event>:<group>:<handler> <hash>.
# Edit hooks.json -> deploy -> trust the changes in codex /hooks -> --pull."

MODE="install"
case "${1:-}" in
  --check) MODE="check" ;;
  --pull) MODE="pull" ;;
  # Prints the header block, ending at the first line that is not a comment,
  # so adding a paragraph up there never truncates the help again.
  --help | -h) awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^#/, ""); sub(/^ /, ""); print }' "$0"; exit 0 ;;
  "") ;;
  *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

drift=0
STAMP=$(date +%Y%m%d-%H%M%S)
# Shown in place of $HOME in paths. Through a variable because bash 3.2 keeps
# the backslash of a literal \~ in a ${var/#$HOME/...} replacement.
TILDE='~'
die()    { printf '\n  FAILED: %s\n' "$1" >&2; exit 1; }
note()   { printf '  %s\n' "$1"; }
differ() { drift=$((drift + 1)); printf '  DRIFT  %s\n' "$1"; }
# A deploy must never overwrite a live file it could not back up first.
backup() {
  [ -f "$1" ] || return 0
  cp "$1" "$1.bak-$STAMP" || die "cannot back up $1 — refusing to overwrite it"
}

# Settings keys that belong to one machine and never go into the repo: autoMode
# holds client context, skipDangerousModePermissionPrompt records consent to
# bypass-permissions mode, and skipWorkflowUsageWarning records consent to the
# multi-agent workflow usage warning: each machine should ask for both itself.
# --check ignores them, --pull strips them and a deploy keeps the live values.
LOCAL_KEYS='["autoMode","skipDangerousModePermissionPrompt","skipWorkflowUsageWarning"]'

# Print a settings file without its machine-local keys; -S sorts the keys.
strip_local() { # file [-S]
  jq ${2:+"$2"} --argjson local "$LOCAL_KEYS" 'del(.[$local[]])' "$1"
}

# Compare tracked vs live settings, ignoring the machine-local keys. Keys are
# sorted so formatting differences never read as drift.
settings_differ() { # repo_file live_file
  [ -f "$2" ] || return 0
  ! diff -q <(strip_local "$2" -S) <(strip_local "$1" -S) > /dev/null
}

# Write tracked settings over live ones, keeping the live values of the
# machine-local keys. A live file jq cannot read is replaced as before.
deploy_settings() { # repo_file live_file
  local tmp="$2.deploy.$$" status
  if [ -f "$2" ] && jq -s --argjson local "$LOCAL_KEYS" \
      '.[0] + (.[1] | with_entries(select(.key | IN($local[]))))' "$1" "$2" > "$tmp"; then
    cp "$tmp" "$2"   # onto the existing file, so it keeps its mode
  else
    cp "$1" "$2"
  fi
  status=$?
  rm -f "$tmp"
  [ "$status" = 0 ] || die "cannot write $2"
}

# --- shared MCP servers ---
# Every profile gets the same MCP server block. These live in .claude.json, not
# settings.json, and that file also holds project history, prompt counts and
# onboarding state: megabytes of machine-local data that must never be replaced
# wholesale. A deploy therefore merges the tracked servers into .mcpServers one
# key at a time and leaves every other key alone. Servers a profile adds for
# itself (work's atlassian, dev's cloudflare) are kept, so this file is the
# shared floor, not the whole set.
#
# Flows repo -> live only, like the shared scripts. The tracked block is shared
# by all five profiles, so there is no single live file to --pull it back from:
# add a server by editing mcp-servers.json, then deploy.
#
# A running claude rewrites .claude.json from memory and can revert a deploy,
# the same way it does with .credentials.json. Deploy with that profile's
# sessions closed, or re-run once they are.
MCP_FILE="mcp-servers.json"

# The .claude.json a profile actually reads. The default profile keeps its one
# at $HOME, from before config directories existed; a CLAUDE_CONFIG_DIR profile
# keeps its own inside that directory. Writing $HOME/.claude/.claude.json
# instead would land in a stub nothing reads, and the deploy and --check would
# then agree with each other about a file the CLI never opens.
mcp_target() { # live_dir
  if [ "$1" = "$HOME/.claude" ]; then echo "$HOME/.claude.json"; else echo "$1/.claude.json"; fi
}

# 0 when the file holds exactly one JSON object. `jq empty` is not enough: it
# passes on an empty file, which holds zero JSON values, and the merge filter
# then runs zero times and writes a 0-byte file over the profile's history. A
# file holding two concatenated objects passes it just as happily and merges
# into both. -s slurps every value into one array, so the count and the type
# are checked together.
mcp_json_ok() { # file
  jq -e -s 'length == 1 and (.[0] | type == "object")' "$1" > /dev/null 2>&1
}

# The tracked server block; -S sorts the keys so formatting never reads as drift.
mcp_tracked() { jq -S '.mcpServers' "$MCP_FILE"; }

# The tracked servers as the live file holds them, narrowed to the tracked
# names so a profile's own extra servers are not drift. A tracked server that is
# missing live simply does not appear, which the diff then reports.
mcp_live() { # live_json
  jq -S --argjson want "$(mcp_tracked)" \
    '(.mcpServers // {}) | with_entries(select($want[.key] != null))' "$1"
}

# Merge the tracked servers into .claude.json, keeping every other key. Staged
# through a temp file: redirecting onto .claude.json would truncate it before jq
# ran, and a failure there would cost the profile's whole history.
deploy_mcp() { # live_json
  local tmp="$1.mcp.$$"
  if [ -f "$1" ] && ! mcp_json_ok "$1"; then
    die "$1 is not a single JSON object - left untouched"
  fi
  # umask: .claude.json is 0600, and mv keeps the temp file's mode.
  if (umask 077; { [ -f "$1" ] && cat "$1" || echo '{}'; } \
      | jq --argjson add "$(mcp_tracked)" '.mcpServers = ((.mcpServers // {}) + $add)' > "$tmp"); then
    backup "$1"
    if [ -f "$1" ]; then
      cp "$tmp" "$1" || die "cannot write $1"   # onto the existing file, so it keeps its mode
      rm -f "$tmp"
    else
      mv "$tmp" "$1" || die "cannot write $1"
    fi
  else
    rm -f "$tmp"
    die "cannot merge $MCP_FILE into $1"
  fi
}

skills_for() { # skill set -> prints source skill dirs
  for s in .claude/skills/*/; do
    [ "$1" = "no-nextjs" ] && [ "$(basename "$s")" = "nextjs-conventions" ] && continue
    printf '%s\n' "$s"
  done
}

# Plugins the live settings enable that have no user-scope install. Enabling a
# plugin in settings.json does not install it, so a deploy that adds one leaves
# it silently inactive until `claude plugin install` runs in that profile. A
# project-scope install only applies inside that project, so it does not count.
uninstalled_plugins() { # live_dir
  local installed='{}'
  if [ -f "$1/plugins/installed_plugins.json" ]; then
    installed=$(cat "$1/plugins/installed_plugins.json") || return 1
  fi
  jq -r --argjson inst "$installed" '
    [(.enabledPlugins // {}) | to_entries[] | select(.value == true) | .key
     | select(any($inst.plugins[.][]?; .scope == "user") | not)] | sort[]' "$1/settings.json"
}

# 0 when the profile has no user-scope plugin at all, i.e. it has never been
# bootstrapped. A profile with some of them installed is left alone: those are
# its own choices, and --check already lists whatever is still missing.
profile_has_no_plugins() { # live_dir
  local f="$1/plugins/installed_plugins.json"
  [ -f "$f" ] || return 0
  ! jq -e 'any(.plugins[]?[]?; .scope == "user")' "$f" > /dev/null 2>&1
}

# Every marketplace a profile needs, one per line. claude-plugins-official is
# not in the tracked extraKnownMarketplaces (it is a built-in, registered in
# plugins/known_marketplaces.json), yet nothing resolves a <name>@claude-plugins-official
# plugin until it is added, which is the step most easily missed by hand.
marketplace_repos() { # settings_file
  jq -r '["anthropics/claude-plugins-official"]
         + [(.extraKnownMarketplaces // {})[] | .source.repo // empty]
         | unique[]' "$1"
}

# `claude plugin marketplace add` writes the marketplace into the live
# settings.json. For claude-plugins-official that is a key the tracked file
# does not carry, so leaving it behind would make every later --check report
# drift on a profile this script had just set up correctly.
strip_official_marketplace() { # live_settings
  local tmp
  [ -f "$1" ] || return 0
  jq -e '.extraKnownMarketplaces["claude-plugins-official"]' "$1" > /dev/null 2>&1 || return 0
  tmp="$1.marketplace.$$"
  if jq 'del(.extraKnownMarketplaces["claude-plugins-official"])' "$1" > "$tmp"; then
    mv "$tmp" "$1" || return 1
  else
    rm -f "$tmp"; return 1
  fi
}

# Register the marketplaces, then install every enabled plugin. Output is
# swallowed: the deploy prints one line per profile, and CI fails the step on
# anything at all on stderr. A failure here is reported but never fatal, since
# it is usually the network; --check lists exactly what is still missing.
bootstrap_plugins() { # live_dir
  local repo p failed="" count=0
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    CLAUDE_CONFIG_DIR="$1" claude plugin marketplace add "$repo" > /dev/null 2>&1 \
      || failed="$failed $repo"
  done <<< "$(marketplace_repos "$1/settings.json")"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if CLAUDE_CONFIG_DIR="$1" claude plugin install "$p" > /dev/null 2>&1; then
      count=$((count + 1))
    else
      failed="$failed $p"
    fi
  done <<< "$(uninstalled_plugins "$1")"
  strip_official_marketplace "$1/settings.json" \
    || note "plugins  WARNING could not remove claude-plugins-official from settings.json"
  if [ -n "$failed" ]; then
    note "plugins  installed $count, failed:$failed"
  else
    note "plugins  installed $count, marketplaces registered"
  fi
}

# 0 when this profile's CLAUDE.md should be a symlink to the one real file.
claude_md_linked() { # live_dir
  local want="${1##*/}" a
  for a in $CLAUDE_MD_LINKED; do
    [ "$a" = "$want" ] && return 0
  done
  return 1
}

# Project templates whose skills get copied into real projects, and where those
# projects live. Space-separated, so no spaces in the paths.
TEMPLATES="nextjs-projects wp-projects"
PROJECT_DIRS="${PROJECT_DIRS:-$HOME/projects $HOME/Sites}"

# Every project's .claude directory, deep enough for a theme or plugin root
# (site/wp-content/themes/<theme>/.claude). WordPress core and dependency trees
# are pruned: walking them takes seconds on a Valet ~/Sites. This repo's own
# directories are left out.
project_claude_dirs() {
  local d
  for d in $PROJECT_DIRS; do
    [ -d "$d" ] || continue
    find "$d" -maxdepth 5 \( -name node_modules -o -name vendor -o -name uploads -o -name .git \
      -o -name .next -o -name wp-admin -o -name wp-includes \) -prune -o -type d -name .claude -print
  done | grep -vF "$REPO_ROOT/" | LC_ALL=C sort
}

# "<path> <blob hash>" for each file in a directory, as git hashes it.
dir_blobs() { # dir
  (cd "$1" && find . -type f ! -name .DS_Store | sed 's|^\./||' \
    | while IFS= read -r f; do printf '%s %s\n' "$f" "$(git hash-object "$f")"; done) | LC_ALL=C sort
}

# The same listing for a repo directory as committed in <commit>.
tree_blobs() { # commit dir
  git ls-tree -r "$1" -- "$2/" \
    | awk -F '\t' -v n=$((${#2} + 2)) '{ split($1, m, " "); print substr($2, n), m[3] }' | LC_ALL=C sort
}

# True when the project copy holds the same files as the template and every
# difference is lines the project added (a project override), none removed or
# changed. diff output is captured first: piping it into grep -q under
# pipefail can fail on SIGPIPE and flip the result.
only_added_lines() { # template skill dir, project copy
  local files f out
  files=$(cd "$1" && find . -type f ! -name .DS_Store | LC_ALL=C sort)
  [ "$files" = "$(cd "$2" && find . -type f ! -name .DS_Store | LC_ALL=C sort)" ] || return 1
  while IFS= read -r f; do
    out=$(diff -- "$1/$f" "$2/$f")
    # diff exits 0 (same) or 1 (different); 2 means it could not compare
    # (unreadable or vanished file), which must never pass as an override.
    [ $? -le 1 ] || return 1
    # Only "NaM" add headers, "> " lines and the no-final-newline marker may
    # remain; anything else is a removal, a change or a binary difference. The
    # marker can only refer to the project file here: the template's last line
    # would appear as a "<" line, which is already rejected.
    [ -z "$(printf '%s\n' "$out" | grep -vE '^(>( .*)?|[0-9]+a[0-9]+(,[0-9]+)?|\\ No newline at end of file)$')" ] || return 1
  done <<< "$files"
}

# Where a project's copy of a template skill stands: current, current with
# lines added by the project, a copy of an older committed template (newest
# match wins), or edited in the project.
template_status() { # template skill dir, project copy
  local copy commit since
  copy=$(dir_blobs "$2")
  if [ "$copy" = "$(dir_blobs "$1")" ]; then echo "current"; return; fi
  if only_added_lines "$1" "$2"; then echo "current + project override"; return; fi
  for commit in $(git rev-list HEAD -- "$1"); do
    if [ "$copy" = "$(tree_blobs "$commit" "$1")" ]; then
      since=$(git rev-list --count "$commit..HEAD" -- "$1")
      echo "behind: copy of $(git log -1 --format='%h, %ad' --date=short "$commit"), $since template change(s) since"
      return
    fi
  done
  echo "differs: edited in the project, or copied from an uncommitted template"
}

# Trust key suffix of every handler in a hooks.json, as Codex builds them:
# snake_case event, then the group and handler index within that event.
codex_hook_keys() { # hooks.json
  jq -r '.hooks | to_entries[]
    | (.key | gsub("(?<a>[a-z])(?<b>[A-Z])"; "\(.a)_\(.b)") | ascii_downcase) as $e
    | .value | to_entries[] | .key as $g
    | .value.hooks | keys[] | "\($e):\($g):\(.)"' "$1" | sort
}

# "<suffix> <hash>" for each hook in the live hooks.json that config.toml marks
# trusted. Stale entries left behind by removed hooks are filtered out.
codex_live_trust() {
  [ -f "$CODEX_CONFIG" ] && [ -f "$CODEX_HOOKS" ] || return 0
  # Multi-line lists go through ENVIRON: macOS awk rejects a newline in -v.
  keys="$(codex_hook_keys "$CODEX_HOOKS")" awk -v prefix="$CODEX_TRUST_PREFIX" '
    BEGIN { n = split(ENVIRON["keys"], k, "\n"); for (i = 1; i <= n; i++) valid[k[i]] = 1 }
    /^\[/ {
      key = ""
      if (index($0, prefix) == 1) { key = substr($0, length(prefix) + 1); sub(/"\][ \t]*$/, "", key) }
      next
    }
    key in valid && /^[ \t]*trusted_hash[ \t]*=/ {
      h = $0; sub(/^[^"]*"/, "", h); sub(/".*$/, "", h); print key, h
    }' "$CODEX_CONFIG" | sort
}

codex_tracked_trust() { grep -v -e '^#' -e '^[[:space:]]*$' "$TRUST_FILE" | sort; }

# Codex writes these itself (new-model announcement counters, a one-time
# screen reader probe), so they differ per machine and never read as drift.
# Space-separated: a whole "[table]", or "[table]key" for a single key.
CODEX_MANAGED="[tui.model_availability_nux] [tui]screen_reader_detection_done"

# Keys that belong to one Codex account rather than to the shared config:
# cli_auth_credentials_store = "file" keeps a second account's login in its own
# auth.json instead of the shared keyring, so only that home has it.
CODEX_ACCOUNT_KEYS="cli_auth_credentials_store"

# One sorted "[table] key = value" line per setting, so key order, comments
# and array layout (Codex writes arrays on one line, the repo spreads them over
# several) never read as drift. Machine-specific [projects*] and [hooks.state*]
# tables and the CODEX_MANAGED keys are left out. Full-line comments only:
# config.toml has no trailing ones.
codex_shared_config() { # config.toml
  awk -v managed=" $CODEX_MANAGED $CODEX_ACCOUNT_KEYS " '
    function emit() {
      gsub(/[ \t]+/, " ", val); gsub(/, *\]/, "]", val)
      gsub(/\[ /, "[", val); gsub(/ \]/, "]", val); gsub(/ *, */, ", ", val)
      if (index(managed, " " tbl key " ") == 0) print (tbl == "" ? "" : tbl " ") key " = " val
    }
    { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line) }
    line == "" || line ~ /^#/ { next }
    inarr { val = val " " line; if (line ~ /^\]/) { inarr = 0; emit() }; next }
    line ~ /^\[/ {
      tbl = line
      skip = line ~ /^\[(projects|hooks\.state)[].]/ || index(managed, " " tbl " ") > 0
      next
    }
    skip || index(line, "=") == 0 { next }
    {
      eq = index(line, "=")
      key = substr(line, 1, eq - 1); sub(/[ \t]+$/, "", key)
      val = substr(line, eq + 1); sub(/^[ \t]+/, "", val)
      if (val ~ /^\[/ && val !~ /\]$/) { inarr = 1; next }
      emit()
    }' "$1" | sort
}

# Give every tracked hook its tracked hash in config.toml. Other keys in those
# tables (an "enabled = false" set in /hooks) and all other tables are kept;
# hooks with no table yet get one appended.
codex_seed_trust() {
  local tmp="$CODEX_CONFIG.trust.$$"
  [ -f "$CODEX_CONFIG" ] || : > "$CODEX_CONFIG" || die "cannot create $CODEX_CONFIG"
  # umask: config.toml is 0600 and mv keeps the temp file's mode.
  if ! (umask 077; list="$(codex_tracked_trust)" awk -v prefix="$CODEX_TRUST_PREFIX" '
    BEGIN {
      n = split(ENVIRON["list"], line, "\n")
      for (i = 1; i <= n; i++) { split(line[i], f, " "); want[f[1]] = f[2]; order[i] = f[1] }
    }
    /^\[/ {
      cur = ""
      if (index($0, prefix) == 1) {
        k = substr($0, length(prefix) + 1); sub(/"\][ \t]*$/, "", k)
        if (k in want) { cur = k; print; printf "trusted_hash = \"%s\"\n", want[k]; done[k] = 1; next }
      }
    }
    cur != "" && /^[ \t]*trusted_hash[ \t]*=/ { next }
    { print }
    END {
      for (i = 1; i <= n; i++) if (!(order[i] in done))
        printf "\n%s%s\"]\ntrusted_hash = \"%s\"\n", prefix, order[i], want[order[i]]
    }' "$CODEX_CONFIG" > "$tmp"); then
    rm -f "$tmp"; die "could not update hook trust in $CODEX_CONFIG"
  fi
  backup "$CODEX_CONFIG"
  mv "$tmp" "$CODEX_CONFIG" || die "cannot write $CODEX_CONFIG"
}

echo "Claude Code config — ${MODE}"
echo

while IFS=: read -r repo_dir live_dir sl_name skillset; do
  [ -n "$repo_dir" ] || continue
  echo "$repo_dir  ->  ${live_dir/#$HOME/$TILDE}"

  if [ "$MODE" != "install" ] && [ ! -d "$live_dir" ]; then
    differ "profile directory missing"
    echo; continue
  fi

  # --- settings.json: the only artefact that flows in both directions ---
  case "$MODE" in
    install)
      mkdir -p "$live_dir" || die "cannot create $live_dir"
      backup "$live_dir/settings.json"
      deploy_settings "$repo_dir/settings.json" "$live_dir/settings.json"
      note "settings.json  (previous saved as settings.json.bak-$STAMP)"
      ;;
    pull)
      if [ -f "$live_dir/settings.json" ]; then
        # Redirection truncates its target before jq runs, so a malformed live
        # file (or a missing jq) would empty the tracked one and, with no
        # set -e, still report success. Stage it and only replace on success.
        tmp="$repo_dir/.settings.json.pull.$$"
        if strip_local "$live_dir/settings.json" > "$tmp"; then
          mv "$tmp" "$repo_dir/settings.json" || die "could not replace $repo_dir/settings.json"
          note "settings.json  <- live (machine-local keys stripped)"
        else
          rm -f "$tmp"
          die "$live_dir/settings.json is not valid JSON — tracked copy left untouched"
        fi
      else
        note "settings.json  live file missing, skipped"
      fi
      ;;
    check)
      if settings_differ "$repo_dir/settings.json" "$live_dir/settings.json"; then
        differ "settings.json"
        diff <(strip_local "$repo_dir/settings.json" -S) <(strip_local "$live_dir/settings.json" -S) \
          | grep -E '^[<>]' | head -6 | sed 's/^/           /'
      else
        note "settings.json  ok"
      fi
      ;;
  esac

  # Everything below flows repo -> live only, so --pull leaves it alone.
  if [ "$MODE" != "pull" ]; then

    # --- MCP servers in .claude.json ---
    # One target for both branches, so a deploy can never write somewhere
    # --check is not looking.
    mcp_json=$(mcp_target "$live_dir")
    if [ "$MODE" = "install" ]; then
      deploy_mcp "$mcp_json"
      note "${mcp_json/#$HOME/$TILDE} mcpServers  $(mcp_tracked | jq -r 'keys | join(", ")')"
    elif [ ! -f "$mcp_json" ]; then
      differ "${mcp_json/#$HOME/$TILDE} missing"
    elif ! mcp_json_ok "$mcp_json"; then
      differ "${mcp_json/#$HOME/$TILDE} is not a single JSON object"
    elif ! diff -q <(mcp_tracked) <(mcp_live "$mcp_json") > /dev/null; then
      differ "${mcp_json/#$HOME/$TILDE} mcpServers"
      diff <(mcp_tracked) <(mcp_live "$mcp_json") \
        | grep -E '^[<>]' | head -6 | sed 's/^/           /'
    else
      note "mcpServers  ok"
    fi

    # --- status line ---
    if [ "$MODE" = "install" ]; then
      cp "$repo_dir/$sl_name" "$live_dir/$sl_name" || die "cannot write $live_dir/$sl_name"
      chmod +x "$live_dir/$sl_name" || die "cannot chmod $live_dir/$sl_name"
      note "$sl_name"
    elif ! diff -q "$repo_dir/$sl_name" "$live_dir/$sl_name" > /dev/null; then
      differ "$sl_name"
    else
      note "$sl_name  ok"
    fi

    # --- CLAUDE.md ---
    # One real file, every other profile a symlink to it, so an edit reaches
    # all of them at once and a new profile needs no follow-up. A real copy
    # found where a link belongs is backed up first: it may hold a live edit
    # that was never copied back into the repo.
    if [ "$MODE" = "install" ]; then
      if claude_md_linked "$live_dir" && [ "$live_dir/CLAUDE.md" != "$CLAUDE_MD_REAL" ]; then
        if [ ! -f "$CLAUDE_MD_REAL" ]; then
          mkdir -p "${CLAUDE_MD_REAL%/*}" || die "cannot create ${CLAUDE_MD_REAL%/*}"
          cp CLAUDE.md "$CLAUDE_MD_REAL" || die "cannot write $CLAUDE_MD_REAL"
        fi
        if [ ! -L "$live_dir/CLAUDE.md" ]; then backup "$live_dir/CLAUDE.md"; fi
        ln -sfn "$CLAUDE_MD_REAL" "$live_dir/CLAUDE.md" \
          || die "cannot link $live_dir/CLAUDE.md"
        note "CLAUDE.md  -> ${CLAUDE_MD_REAL/#$HOME/$TILDE}"
      else
        cp CLAUDE.md "$live_dir/CLAUDE.md" || die "cannot write $live_dir/CLAUDE.md"
        note "CLAUDE.md"
      fi
    elif ! diff -q CLAUDE.md "$live_dir/CLAUDE.md" > /dev/null; then
      differ "CLAUDE.md"
    else
      note "CLAUDE.md  ok"
    fi

    # --- skills ---
    missing=""
    for s in $(skills_for "$skillset"); do
      name=$(basename "$s")
      if [ "$MODE" = "install" ]; then
        mkdir -p "$live_dir/skills" || die "cannot create $live_dir/skills"
        # cp -R overlays, so a file deleted from a tracked skill would survive
        # here and --check would report that skill as drifted forever.
        rm -rf "${live_dir:?}/skills/$name"
        # ${s%/} strips the glob's trailing slash: with it, BSD cp copies the
        # directory *contents* into skills/ instead of the directory itself.
        cp -R "${s%/}" "$live_dir/skills/" || die "cannot copy skill $name"
      elif ! diff -rq "$s" "$live_dir/skills/$name" > /dev/null; then
        missing="$missing $name"
      fi
    done
    if [ "$MODE" = "install" ]; then
      note "skills ($skillset)"
    elif [ -n "$missing" ]; then
      differ "skills:$missing"
    else
      note "skills  ok"
    fi

    # --- plugins ---
    # A deploy never touches plugin *versions*: those live in the profile, not
    # here, and `claude-update-plugins` owns them. It does bootstrap a profile
    # that has none, because registering the marketplaces and installing the
    # enabled set by hand is the step most easily missed when adding an account.
    # Skipped without the claude CLI, which is also what keeps CI's scratch
    # HOME (no plugins installed) from reaching the network or flagging every
    # enabled plugin as missing.
    if [ "$MODE" = "install" ]; then
      if ! command -v claude > /dev/null; then
        note "plugins  claude CLI not found, skipped"
      elif [ ! -f "$live_dir/settings.json" ]; then
        note "plugins  live settings.json missing, skipped"
      elif [ "${INSTALL_SKIP_PLUGINS:-0}" = 1 ]; then
        note "plugins  INSTALL_SKIP_PLUGINS=1, skipped"
      elif ! profile_has_no_plugins "$live_dir"; then
        note "plugins  already set up, versions left to claude-update-plugins"
      else
        note "plugins  none installed, bootstrapping (this hits the network)"
        bootstrap_plugins "$live_dir"
      fi
    elif [ "$MODE" = "check" ]; then
      if ! command -v claude > /dev/null; then
        note "plugins  claude CLI not found, skipped"
      elif [ "${INSTALL_SKIP_PLUGINS:-0}" = 1 ]; then
        # The flag means "plugins are not this run's business", so it has to
        # cover the check too: a deploy that skipped the bootstrap would
        # otherwise be followed by a --check reporting every enabled plugin as
        # missing, which is how CI would break the day a runner ships the CLI.
        note "plugins  INSTALL_SKIP_PLUGINS=1, skipped"
      elif [ ! -f "$live_dir/settings.json" ]; then
        note "plugins  live settings.json missing, skipped"
      elif ! unplugged=$(uninstalled_plugins "$live_dir"); then
        differ "plugins: cannot read settings.json or plugins/installed_plugins.json"
      elif [ -n "$unplugged" ]; then
        differ "plugins enabled but not installed:"
        printf '%s\n' "$unplugged" | sed 's/^/           /'
        note "  fix: CLAUDE_CONFIG_DIR=${live_dir/#$HOME/$TILDE} claude plugin install <plugin>"
      else
        note "plugins  ok"
      fi
    fi

  fi

  echo
done <<< "$PROFILES"

# --- CLAUDE.md links: check only, and never drift ---
# A deploy now creates these links, so an own copy here means the profile has
# not been deployed since. It is still listed rather than counted as drift: the
# content check above already flags a copy whose text differs from the repo,
# and a deliberately unlinked profile is not broken, only unusual. -ef compares
# the files the paths resolve to, so a relative link also reads as linked.
if [ "$MODE" = "check" ]; then
  echo "CLAUDE.md links  (info only, not drift)"
  if [ ! -f "$CLAUDE_MD_REAL" ]; then
    note "${CLAUDE_MD_REAL/#$HOME/$TILDE}  missing, nothing to link to"
  else
    for a in $CLAUDE_MD_LINKED; do
      f="$HOME/$a/CLAUDE.md"
      if [ -L "$f" ] && [ "$f" -ef "$CLAUDE_MD_REAL" ]; then
        note "$TILDE/$a/CLAUDE.md  -> ${CLAUDE_MD_REAL/#$HOME/$TILDE}"
      elif [ -L "$f" ]; then
        note "$TILDE/$a/CLAUDE.md  links elsewhere: $(readlink "$f")"
      elif [ -f "$f" ]; then
        note "$TILDE/$a/CLAUDE.md  own copy, not linked"
      else
        note "$TILDE/$a/CLAUDE.md  missing"
      fi
    done
  fi
  echo
fi

# --- shared scripts: repo -> live only ---
if [ "$MODE" != "pull" ]; then
  echo "shared"
  while IFS=: read -r src dst; do
    [ -n "$src" ] || continue
    if [ "$MODE" = "install" ]; then
      mkdir -p "$(dirname "$dst")" || die "cannot create $(dirname "$dst")"
      cp "$src" "$dst" || die "cannot write $dst"
      chmod +x "$dst" || die "cannot chmod $dst"
      note "${dst/#$HOME/$TILDE}"
    elif [ ! -f "$dst" ]; then
      differ "${dst/#$HOME/$TILDE} missing"
    elif ! diff -q "$src" "$dst" > /dev/null; then
      differ "${dst/#$HOME/$TILDE}"
    else
      note "${dst/#$HOME/$TILDE}  ok"
    fi
  done <<< "$SHARED_SCRIPTS"
  echo
fi

# --- Codex tab-status hooks: hooks.json both ways, trust seeded per account ---
# One pass per home in CODEX_PROFILES. The trust hash covers the hook
# definition, not the path, so every account gets the same tracked hashes,
# re-keyed to its own hooks.json path. --pull reads one home only: the tracked
# copies are shared, so the first account's home is the source.
codex_pulled=0
while IFS= read -r codex_dir; do
  [ -n "$codex_dir" ] || continue
  codex_use_dir "$codex_dir"
  echo "codex  ->  ${CODEX_DIR/#$HOME/$TILDE}"
  if [ ! -d "$CODEX_DIR" ]; then
    note "not installed, skipped"
    echo
    continue
  fi
  case "$MODE" in
    install)
      if diff -q codex/hooks.json "$CODEX_HOOKS" > /dev/null 2>&1; then
        note "hooks.json  ok"
      else
        backup "$CODEX_HOOKS"
        cp codex/hooks.json "$CODEX_HOOKS" || die "cannot write $CODEX_HOOKS"
        note "hooks.json"
      fi
      # Only rewrite config.toml when a tracked hook is actually untrusted, so
      # a no-op deploy leaves no backup behind.
      if [ -z "$(comm -23 <(codex_tracked_trust) <(codex_live_trust))" ]; then
        note "hook trust  ok"
      else
        codex_seed_trust
        note "hook trust  (previous config.toml saved as config.toml.bak-$STAMP)"
      fi
      ;;
    check)
      if [ ! -f "$CODEX_HOOKS" ]; then
        differ "codex hooks.json missing"
      elif ! diff -q codex/hooks.json "$CODEX_HOOKS" > /dev/null; then
        differ "codex hooks.json"
      else
        note "hooks.json  ok"
      fi
      untrusted=$(comm -23 <(codex_tracked_trust) <(codex_live_trust) | wc -l | tr -d ' ')
      if [ "$untrusted" -gt 0 ]; then
        differ "codex hook trust: $untrusted hook(s) not trusted in config.toml"
      else
        note "hook trust  ok"
      fi
      # Neither a deploy nor --pull copies config.toml (live holds the trust
      # tables), so drift here is merged by hand: see the README's Codex section.
      if [ ! -f "$CODEX_CONFIG" ]; then
        differ "codex config.toml missing"
      elif ! diff -q <(codex_shared_config codex/config.toml) <(codex_shared_config "$CODEX_CONFIG") > /dev/null; then
        differ "codex config.toml  (merge by hand, see README \"Codex config\")"
        diff <(codex_shared_config codex/config.toml) <(codex_shared_config "$CODEX_CONFIG") \
          | grep -E '^[<>]' | head -6 | sed 's/^/           /'
      else
        note "config.toml  ok"
      fi
      ;;
    pull)
      if [ "$codex_pulled" -eq 1 ]; then
        note "hooks.json, hook trust  pulled from the first account's home, skipped"
      elif [ ! -f "$CODEX_HOOKS" ]; then
        note "hooks.json  live file missing, skipped"
      else
        jq -e . "$CODEX_HOOKS" > /dev/null || die "$CODEX_HOOKS is not valid JSON - tracked copy left untouched"
        cp "$CODEX_HOOKS" codex/hooks.json || die "cannot write codex/hooks.json"
        tmp="$TRUST_FILE.pull.$$"
        if { printf '%s\n' "$TRUST_HEADER"; codex_live_trust; } > "$tmp"; then
          mv "$tmp" "$TRUST_FILE" || die "cannot write $TRUST_FILE"
        else
          rm -f "$tmp"; die "could not read hook trust from $CODEX_CONFIG"
        fi
        total=$(codex_hook_keys codex/hooks.json | wc -l | tr -d ' ')
        trusted=$(codex_tracked_trust | wc -l | tr -d ' ')
        note "hooks.json, hook trust  <- live ($trusted of $total hooks trusted)"
        if [ "$trusted" -lt "$total" ]; then
          note "  trust the rest in codex /hooks, then --pull again"
        fi
        codex_pulled=1
      fi
      ;;
  esac
  echo
done <<< "$CODEX_PROFILES"

# --- Antigravity (agy): the next-steps plugin, repo -> live only ---
# User plugins load from ~/.gemini/config/plugins/. The status line belongs to
# the person, so a deploy only fills it in when none is set.
AGY_ROOT="$HOME/.gemini"
AGY_PLUGINS="$AGY_ROOT/config/plugins"
AGY_SETTINGS="$AGY_ROOT/antigravity-cli/settings.json"
AGY_STATUSLINE='{"type":"command","command":"~/.local/bin/next-steps agy-statusline","stack_with_default":true}'
if [ "$MODE" != "pull" ]; then
  echo "agy  ->  ${AGY_ROOT/#$HOME/$TILDE}"
  if [ ! -d "$AGY_ROOT/antigravity-cli" ]; then
    note "not installed, skipped"
  elif [ "$MODE" = "install" ]; then
    # Validate first, so a broken settings.json stops the deploy before the
    # plugin is replaced rather than halfway through.
    if [ -f "$AGY_SETTINGS" ] && ! jq empty "$AGY_SETTINGS" > /dev/null; then
      die "$AGY_SETTINGS is not valid JSON - left untouched"
    fi
    mkdir -p "$AGY_PLUGINS" || die "cannot create $AGY_PLUGINS"
    rm -rf "${AGY_PLUGINS:?}/next-steps"
    cp -R agy/next-steps "$AGY_PLUGINS/" || die "cannot copy the next-steps agy plugin"
    note "plugins/next-steps"
    if [ -f "$AGY_SETTINGS" ] && jq -e 'has("statusLine")' "$AGY_SETTINGS" > /dev/null; then
      note "statusLine  already set, left alone"
    else
      tmp="$AGY_SETTINGS.next-steps.$$"
      # umask: settings.json is 0600 and mv keeps the temp file's mode.
      if (umask 077; { [ -f "$AGY_SETTINGS" ] && cat "$AGY_SETTINGS" || echo '{}'; } \
          | jq --argjson line "$AGY_STATUSLINE" '.statusLine = $line' > "$tmp"); then
        backup "$AGY_SETTINGS"
        mv "$tmp" "$AGY_SETTINGS" || die "cannot write $AGY_SETTINGS"
        note "statusLine  next-steps"
      else
        rm -f "$tmp"; die "$AGY_SETTINGS is not valid JSON - left untouched"
      fi
    fi
  else
    if diff -rq agy/next-steps "$AGY_PLUGINS/next-steps" > /dev/null 2>&1; then
      note "plugins/next-steps  ok"
    else
      differ "agy plugins/next-steps"
    fi
    if [ ! -f "$AGY_SETTINGS" ] || ! jq -e 'has("statusLine")' "$AGY_SETTINGS" > /dev/null; then
      differ "agy statusLine not set"
    elif jq -e --argjson line "$AGY_STATUSLINE" '.statusLine == $line' "$AGY_SETTINGS" > /dev/null; then
      note "statusLine  ok"
    else
      note "statusLine  your own (next-steps suggestions not shown there)"
    fi
  fi
  echo
fi

# --- project templates: check only, and never drift ---
# A project adapts the template to its own stack (auth, data layer), so an old
# or edited copy is listed for review rather than counted, and nothing is copied.
if [ "$MODE" = "check" ]; then
  echo "project templates  (info only, not drift)"
  found=0
  claude_dirs=$(project_claude_dirs)
  for t in $TEMPLATES; do
    for s in "$t"/.claude/skills/*/; do
      s=${s%/}
      while IFS= read -r c; do
        [ -d "$c/skills/$(basename "$s")" ] || continue
        found=1
        project=${c%/.claude}
        note "${project/#$HOME/$TILDE}  $(basename "$s")  $(template_status "$s" "$c/skills/$(basename "$s")")"
      done <<< "$claude_dirs"
    done
  done
  [ "$found" = 1 ] || note "no project copies in ${PROJECT_DIRS//$HOME/$TILDE}"
  echo
fi

if [ "$MODE" = "check" ]; then
  if [ "$drift" -gt 0 ]; then
    echo "$drift item(s) differ. Deploy with ./install.sh, or --pull if live is the newer side."
    exit 1
  fi
  echo "live profiles match the repo."
fi
exit 0
