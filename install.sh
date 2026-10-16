#!/usr/bin/env bash
# Instala os dotfiles: dependências via Homebrew, symlinks em ~ e statusLine do Claude Code.
# Pode rodar de novo quantas vezes quiser; o que já está certo fica como está.
#
# Remoto (clona em ~/dotfiles, ou DOTFILES_DIR, e roda a cópia local):
#   curl -fsSL https://raw.githubusercontent.com/danielfnfaria/dotfiles/main/install.sh | bash
set -euo pipefail

# via curl | bash não existe arquivo do script: os symlinks precisam de um clone fixo para apontar
if [ -z "${BASH_SOURCE[0]:-}" ]; then
  repo="${DOTFILES_REPO:-https://github.com/danielfnfaria/dotfiles.git}"
  dir="${DOTFILES_DIR:-$HOME/dotfiles}"
  if ! xcode-select -p &> /dev/null; then
    xcode-select --install || true
    echo "ERR: instale as Command Line Tools (git) na janela que abriu e rode de novo"
    exit 1
  fi
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
if ! command -v brew &> /dev/null; then
  echo "ERR: Homebrew não encontrado; instale em https://brew.sh e rode de novo"
  exit 1
fi

for f in starship kubecolor fzf jq gh; do
  brew list --formula "$f" &> /dev/null || brew install "$f"
done
for c in ghostty font-fira-code-nerd-font; do
  brew list --cask "$c" &> /dev/null || brew install --cask "$c"
done

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
echo "Pronto. Abra um terminal novo (ou rode: exec zsh)."
