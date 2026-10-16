#!/usr/bin/env bash
# Instala os dotfiles num Mac (até um zerado): Homebrew, dependências, symlinks em ~ e
# statusLine do Claude Code. Pode rodar de novo quantas vezes quiser; o que já está certo fica.
#
# Remoto (clona em ~/dotfiles, ou DOTFILES_DIR, e roda a cópia local):
#   curl -fsSL https://raw.githubusercontent.com/danielfnfaria/dotfiles/main/install.sh | bash
set -euo pipefail

# Homebrew; o instalador oficial também instala as Command Line Tools (git)
ensure_brew() {
  local b
  if ! command -v brew &> /dev/null; then
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$b" ] && break
    done
    if [ ! -x "$b" ]; then
      echo ">> instalando Homebrew (pede a senha de administrador)"
      sudo -v < /dev/tty
      NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$b" ] && break
      done
    fi
    eval "$("$b" shellenv)"
  fi
}

# via curl | bash não existe arquivo do script: os symlinks precisam de um clone fixo para apontar
if [ -z "${BASH_SOURCE[0]:-}" ]; then
  ensure_brew
  repo="${DOTFILES_REPO:-https://github.com/danielfnfaria/dotfiles.git}"
  dir="${DOTFILES_DIR:-$HOME/dotfiles}"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only
  else
    git clone "$repo" "$dir"
  fi
  exec bash "$dir/install.sh" < /dev/null
fi

DOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP=$(date +%Y%m%d-%H%M%S)

# --- dependências ---------------------------------------------------------------------------
ensure_brew

# fórmulas: prompt, kubectl colorido, seletor do kctx, e jq/gh da status line
for f in git starship kubernetes-cli kubecolor fzf jq gh; do
  brew list --formula "$f" &> /dev/null || brew install "$f"
done

# casks: <cask> <o que indica que já está instalado fora do brew>
while read -r c app; do
  brew list --cask "$c" &> /dev/null && continue
  [ -e "$app" ] && continue
  brew install --cask "$c"
done <<EOF
ghostty                   /Applications/Ghostty.app
font-fira-code            $HOME/Library/Fonts/FiraCode-Regular.ttf
font-fira-code-nerd-font  $HOME/Library/Fonts/FiraCodeNerdFont-Regular.ttf
claude-code               $(command -v claude || echo "$HOME/.local/bin/claude")
EOF

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# --- symlinks -------------------------------------------------------------------------------
# link <origem no repo> <destino>: o que já existir (e não for este link) vira <destino>.bak-<data>
link() {
  local src="$DOT/$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    mv "$dst" "$dst.bak-$STAMP"
    echo "backup: $dst.bak-$STAMP"
  fi
  ln -s "$src" "$dst"
  echo "link:   $dst -> $src"
}

link zsh/.zshrc                     "$HOME/.zshrc"
link zsh/.zsh.d/100-aliases.sh      "$HOME/.zsh.d/100-aliases.sh"
link zsh/.zsh.d/101-functions.sh    "$HOME/.zsh.d/101-functions.sh"
link zsh/.zsh.d/110-env.sh          "$HOME/.zsh.d/110-env.sh"
link starship/starship.toml         "$HOME/.config/starship.toml"
link ghostty/config                 "$HOME/.config/ghostty/config"
link claude/statusline.sh           "$HOME/.claude/statusline.sh"

# credenciais: só o modelo, nunca sobrescreve o real
if [ ! -e "$HOME/.zsh.d/000-credentials.sh" ]; then
  cp "$DOT/zsh/.zsh.d/000-credentials.sh.example" "$HOME/.zsh.d/000-credentials.sh"
  chmod 700 "$HOME/.zsh.d/000-credentials.sh"
  echo "criado: ~/.zsh.d/000-credentials.sh (preencha seus tokens)"
fi

# --- statusLine do Claude Code --------------------------------------------------------------
settings="$HOME/.claude/settings.json"
[ -s "$settings" ] || echo '{}' > "$settings"
tmp=$(mktemp)
jq --slurpfile s "$DOT/claude/settings.statusline.json" '. * $s[0]' "$settings" > "$tmp"
mv "$tmp" "$settings"
echo "statusLine adicionada em $settings"

echo
echo "Pronto. Abra o Ghostty (ou um terminal novo) e rode: gh auth login && claude"
