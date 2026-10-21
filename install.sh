#!/usr/bin/env bash
#
# Install this repo's configuration into the live Claude Code profiles, check
# the live profiles against it, or pull live changes back into the repo.
#
#   ./install.sh            deploy repo -> ~/.claude*, ~/.local/bin, ~/.codex hooks, agy plugin
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
# with an empty CLAUDE.md and one of eight skills - so prefer this.
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
claude-work:$HOME/.claude-work:statusline.sh:no-nextjs"

# repo file : live file. Shared by every profile. The tab-status scripts each exit
# on the wrong terminal; the Prisma guard is inert without its local hosts file;
# wt-dev is a command you run yourself, never a hook. next-steps is one file
# under two names: the hooks call next-steps, $VISUAL/$EDITOR is next-steps-editor.
# The herdr hook is herdr's own file (it exits outside a herdr pane): a herdr
# update rewrites it live, so copy the new version back here when --check flags it.
SHARED_SCRIPTS="iterm-tab-status.sh:$HOME/.local/bin/claude-iterm-tab-status.sh
wt-tab-status.sh:$HOME/.local/bin/claude-wt-tab-status.sh
prisma-prod-guard.sh:$HOME/.local/bin/prisma-prod-guard
wt-dev.sh:$HOME/.local/bin/wt-dev
next-steps.mjs:$HOME/.local/bin/next-steps
next-steps.mjs:$HOME/.local/bin/next-steps-editor
claude/hooks/herdr-agent-state.sh:$HOME/.claude/hooks/herdr-agent-state.sh"

# Codex runs hooks from hooks.json only once each is trusted in /hooks, and
# records that in config.toml as [hooks.state."<abs path>:<event>:<group>:<n>"].
# The hash covers the hook definition, not the path, so the tracked list keeps
# only "<event>:<group>:<n> <hash>" and install.sh re-keys it for this machine.
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_HOOKS="$CODEX_DIR/hooks.json"
CODEX_CONFIG="$CODEX_DIR/config.toml"
CODEX_TRUST_PREFIX="[hooks.state.\"$CODEX_HOOKS:"
TRUST_FILE="codex/hooks-trust.txt"
TRUST_HEADER="# Trust hashes for codex/hooks.json, written by ./install.sh --pull from the
# live ~/.codex/config.toml. Format: <event>:<group>:<handler> <hash>.
# Edit hooks.json -> deploy -> trust the changes in codex /hooks -> --pull."

MODE="install"
case "${1:-}" in
  --check) MODE="check" ;;
  --pull) MODE="pull" ;;
  --help | -h) sed -n '2,22p' "$0" | sed 's/^#//;s/^ //'; exit 0 ;;
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
# holds client context, and skipDangerousModePermissionPrompt records consent to
# bypass-permissions mode, which each machine should ask for itself. --check
# ignores them, --pull strips them and a deploy keeps the live values.
LOCAL_KEYS='["autoMode","skipDangerousModePermissionPrompt"]'

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
    if [ "$MODE" = "install" ]; then
      cp CLAUDE.md "$live_dir/CLAUDE.md" || die "cannot write $live_dir/CLAUDE.md"
      note "CLAUDE.md"
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

    # --- plugins: check only, a deploy does not install them ---
    # Skipped without the claude CLI, which is also what keeps CI's scratch
    # HOME (no plugins installed) checking clean.
    if [ "$MODE" = "check" ]; then
      if ! command -v claude > /dev/null; then
        note "plugins  claude CLI not found, skipped"
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

# --- Codex tab-status hooks: hooks.json both ways, trust seeded on deploy ---
echo "codex  ->  ${CODEX_DIR/#$HOME/$TILDE}"
if [ ! -d "$CODEX_DIR" ]; then
  note "not installed, skipped"
else
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
      ;;
    pull)
      if [ ! -f "$CODEX_HOOKS" ]; then
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
      fi
      ;;
  esac
fi
echo

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

if [ "$MODE" = "check" ]; then
  if [ "$drift" -gt 0 ]; then
    echo "$drift item(s) differ. Deploy with ./install.sh, or --pull if live is the newer side."
    exit 1
  fi
  echo "live profiles match the repo."
fi
exit 0
