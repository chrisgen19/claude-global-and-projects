# fzf + zoxide cheat sheet

Fuzzy search for shell history, files and folders ([fzf](https://github.com/junegunn/fzf)),
plus a `cd` that learns where you go ([zoxide](https://github.com/ajeetdsouza/zoxide)).
zoxide replaces the oh-my-zsh `z` plugin. Same setup on WSL and the Mac; only the way fzf
is loaded differs. Versions in use: fzf 0.75, zoxide 0.10, ripgrep 14 (WSL) / 15 (Mac).

- [Daily keys](#daily-keys)
- [zoxide](#zoxide)
- [`**` completion](#-completion)
- [Inside any fzf list](#inside-any-fzf-list)
- [Pipe recipes](#pipe-recipes)
- [Test it](#test-it)
- [Setup](#setup)
- [Troubleshooting](#troubleshooting)

## Daily keys

| Key | What it does |
|---|---|
| `Ctrl-R` | Search shell history. What's already on the prompt becomes the query; `Enter` puts the command back on the prompt. Inside the list: `Ctrl-R` again toggles ranked vs time order, `Alt-R` toggles raw view, `Tab` picks several lines. |
| `Ctrl-T` | Pick files and paste their paths at the cursor. Works mid-command (`code ` then `Ctrl-T`). Uses ripgrep: respects `.gitignore`, shows dotfiles, skips `.git`. Files only, no folders. `Tab` picks several. |
| `Alt-C` | Fuzzy `cd` into a subfolder of where you are. iTerm2 needs Profiles > Keys > Left Option key set to Esc+. |
| `z name` | Jump to the folder you use most that matches. `zi` opens a picker when you can't remember the name. |

## zoxide

Every `cd` is recorded and ranked by frecency (how often plus how recently). It only knows
folders you've actually visited, so `cd` into a new repo once by hand.

| Command | What it does |
|---|---|
| `z foo` | Best-ranked folder whose path matches `foo`. |
| `z foo bar` | Words match in order; the last one must match the last path segment. `z wp lamp` finds `~/wp/lampandpath`. |
| `z` | Home. |
| `z -` | Back to the previous folder. |
| `z ..`, `z ~/x`, `z /abs` | Real paths behave exactly like `cd`. |
| `zi`, `zi foo` | Interactive fzf picker, optionally pre-filtered. |
| `z foo` then `Space` `Tab` | Same picker, inline while typing. |
| `zoxide query -ls foo` | List matches with scores, without moving. |
| `zoxide remove <path>` | Forget one folder. |
| `zoxide edit` | fzf screen to bump, lower or delete entries (keys listed in its header). |

Home is excluded by default (`_ZO_EXCLUDE_DIRS`). Deleted folders are skipped, then aged
out. Set `_ZO_ECHO=1` to print where `z` took you.

## `**` completion

Type `**` then `Tab`.

| Example | Lists |
|---|---|
| `vim **` `Tab` | Files under the current folder. |
| `vim src/**` `Tab` | Files, starting from `src/`. |
| `cd **` `Tab` | Folders only. |
| `kill **` `Tab` | Running processes; `Tab` selects several. |
| `ssh **` `Tab` | Hosts from `~/.ssh/config` and `known_hosts`. |
| `export **` `Tab` | Env vars. Also `unset` and `unalias`. |

`**` uses fzf's own file walker, which ignores `.gitignore`. It's the way to reach ignored
files such as `.env.local` that `Ctrl-T` hides.

## Inside any fzf list

| Key | What it does |
|---|---|
| Arrows, `Ctrl-J`/`Ctrl-K`, `Ctrl-N`/`Ctrl-P` | Move. |
| `Tab` / `Shift-Tab` | Select / unselect, where multi-select is on (`Ctrl-R`, `Ctrl-T`, `**`). |
| `Enter` | Accept. |
| `Esc`, `Ctrl-C` | Cancel. |

Query syntax (space means AND):

| Query | Matches |
|---|---|
| `abc` | fuzzy |
| `'abc` | exact |
| `^abc` | starts with |
| `abc$` | ends with |
| `!abc` | excludes |
| `a \| b` | either |

Example: `^src .tsx$ !test` finds TSX files under `src` that aren't tests.

## Pipe recipes

```bash
vim "$(fzf)"                                                   # open a picked file
git switch "$(git branch --format='%(refname:short)' | fzf)"  # switch branch
git log --oneline | fzf                                        # find a commit
docker ps | fzf                                                # pick a container
fzf --preview 'head -50 {}'                                    # files with a preview pane
```

## Test it

In a new terminal tab:

1. `Ctrl-R`, type `git`: fuzzy list of past commands; `Enter` puts one on the prompt.
2. `cat ` then `Ctrl-T`: file list; `Enter` pastes the path. In a Next.js repo, nothing from `.next/` or `node_modules/`.
3. `Alt-C`: subfolder list; `Enter` changes into it.
4. `z projects`: lands in `~/projects` (from the imported history).
5. `zi`: fzf list of every folder zoxide knows.
6. `cd ~/projects/**` `Tab`: fzf folder picker.
7. `cd` into a repo, `cd ~`, then `z` + part of its name: back in the repo.

Scripted check:

```bash
zsh -i -c 'whence -w z zi zshz; bindkey "^R"; bindkey "^T"; bindkey "\ec"; echo "plugins: $plugins"; echo "ctrl-t: $FZF_CTRL_T_COMMAND"'
```

Expect `z` and `zi` as functions, `zshz` as `none`, the widgets `fzf-history-widget`,
`fzf-file-widget` and `fzf-cd-widget`, and the rg command after `ctrl-t:`. A
`can't change option: zle` warning here is harmless: it only appears without a real
terminal.

To confirm `Ctrl-T` hides gitignored files, both counts should match inside a repo:

```bash
rg --files --hidden -g '!.git' | wc -l
git ls-files --cached --others --exclude-standard | wc -l
```

## Setup

`~/.zshrc` is not tracked in this repo: these are manual edits on each machine. Back it up
first (`cp ~/.zshrc ~/.zshrc.bak-$(date +%Y%m%d)`).

### WSL (done 2026-11-11)

fzf from git in `~/.fzf`, zoxide in `~/.local/bin`, ripgrep from apt.

```bash
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install --key-bindings --completion --no-update-rc
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
sudo apt install -y ripgrep
```

`~/.zshrc`:

```zsh
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)   # "z" removed

source $ZSH/oh-my-zsh.sh

# fzf: Ctrl-R history, Ctrl-T files, Alt-C cd (installed from git in ~/.fzf)
# Ctrl-T lists files via ripgrep: respects .gitignore, includes dotfiles, skips .git
command -v rg >/dev/null && export FZF_CTRL_T_COMMAND='rg --files --hidden -g "!.git"'
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# ... end of file:
# zoxide: smarter cd (z <dir>, zi for fzf picker); keep last
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
```

Then import the old `z` history once: `zoxide import zsh-z --merge` (reads `~/.z`). To
update fzf later: `cd ~/.fzf && git pull && ./install --key-bindings --completion --no-update-rc`.

### Mac (done 2026-11-12, issue #116)

macOS 27 on Apple Silicon. Everything from Homebrew: fzf 0.75.0, zoxide 0.10.0, ripgrep
15.2.0 (all in `/opt/homebrew/bin`).

```bash
brew install fzf zoxide ripgrep
whence -p rg   # /opt/homebrew/bin/rg, a real binary rather than Claude Code's built-in one
```

`~/.zshrc`:

```zsh
plugins=(git extract sudo web-search zsh-autosuggestions zsh-syntax-highlighting zsh-completions)   # "z" removed

source $ZSH/oh-my-zsh.sh

# fzf: Ctrl-R history, Ctrl-T files, Alt-C cd (brew)
# Ctrl-T lists files via ripgrep: respects .gitignore, includes dotfiles, skips .git
command -v rg >/dev/null && export FZF_CTRL_T_COMMAND='rg --files --hidden -g "!.git"'
command -v fzf >/dev/null && source <(fzf --zsh)

# ... end of file, after Powerlevel10k:
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# zoxide: smarter cd (z <dir>, zi for fzf picker); keep last
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
```

The Mac `~/.zshrc` ends with the p10k source, whose comment says "must be sourced last".
zoxide still goes below it: `~/.p10k.zsh` only sets prompt options, while zoxide has to
come after anything that hooks `cd` or the prompt.

Then `zoxide import zsh-z --merge` (83/83 entries from `~/.z`).

iTerm2: `Alt-C` needs the Default profile's Left Option key set to Esc+ (Settings >
Profiles > Keys). Right Option stays Normal so it still types characters like `ç` and `€`.
To set it from a shell instead, quit iTerm2 first (a running iTerm2 can write its old
settings back), then:

```bash
P=~/Library/Preferences/com.googlecode.iterm2.plist
cp "$P" "$P.bak-$(date +%Y%m%d)"
/usr/libexec/PlistBuddy -c 'Set ":New Bookmarks:0:Option Key Sends" 2' "$P"   # 0 Normal, 1 Meta, 2 Esc+
killall cfprefsd
```

`New Bookmarks:0` is the first profile; check its `Guid` matches `defaults read
com.googlecode.iterm2 "Default Bookmark Guid"` if there are several.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `z` behaves like before | The oh-my-zsh `z` plugin is still in `plugins=(...)`, or the tab predates the change. Remove it and open a new tab. |
| `ctrl-t:` prints empty | `rg` isn't on zsh's PATH. Check with `whence -p rg` in a normal terminal; Claude Code's shell has its own `rg` that zsh can't see. |
| `Alt-C` types a character | The terminal isn't sending Alt as Esc. iTerm2: Left Option key to Esc+. |
| Can't find a `.env` file | `Ctrl-T` hides gitignored files on purpose. Use `vim .env**` `Tab`. |
| A folder won't show in `z` | Never visited, or it's your home folder. `cd` into it once. |
| `zoxide import --from=z` errors | zoxide 0.10 changed the syntax: `zoxide import zsh-z --merge`. |

## Revert

Restore `~/.zshrc.bak-*`, then remove the tools: `rm -rf ~/.fzf ~/.local/bin/zoxide
~/.local/share/zoxide` on WSL, or `brew uninstall fzf zoxide` and
`rm -rf ~/Library/Application\ Support/zoxide` on the Mac. Keep ripgrep if anything else
uses it. On the Mac, the iTerm2 Option key change can be undone in Settings > Profiles > Keys,
or by restoring `~/Library/Preferences/com.googlecode.iterm2.plist.bak-*` with iTerm2 closed.
