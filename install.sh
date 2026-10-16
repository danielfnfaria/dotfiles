#!/usr/bin/env bash
# Instala os dotfiles num Mac (até um zerado): Homebrew, dependências, symlinks em ~ e
# statusLine do Claude Code. Pode rodar de novo quantas vezes quiser; o que já está certo fica.
#
# Remoto (clona em ~/dotfiles, ou DOTFILES_DIR, e roda a cópia local):
#   curl -fsSL https://raw.githubusercontent.com/danielfnfaria/dotfiles/main/install.sh | bash
set -euo pipefail

USER_BREW="$HOME/.homebrew"   # Homebrew só deste usuário, quando o do sistema não serve

# candidatos na mesma ordem do ~/.zshrc, para o script e o shell usarem o mesmo brew
brew_candidates() {
  echo "$USER_BREW/bin/brew"
  echo /opt/homebrew/bin/brew
  echo /usr/local/bin/brew
  command -v brew 2> /dev/null || true
}

# o brew é deste usuário? (Intel: /usr/local é do root, mas o Cellar é de quem instalou)
brew_writable() {
  local p
  p=$(dirname "$(dirname "$1")")
  [ -w "$p/Cellar" ] || { [ ! -e "$p/Cellar" ] && [ -w "$p" ]; }
}

# primeiro brew que existe e em que este usuário pode instalar
find_brew() {
  local b
  while read -r b; do
    [ -x "$b" ] && brew_writable "$b" && { echo "$b"; return; }
  done < <(brew_candidates)
  return 0   # nada achado não é erro (o script roda com set -e)
}

# primeiro brew que existe mas é de outro usuário (só para explicar o que vai acontecer)
foreign_brew() {
  local b
  while read -r b; do
    [ -x "$b" ] && ! brew_writable "$b" && { echo "$b"; return; }
  done < <(brew_candidates)
  return 0
}

is_admin() { id -Gn | tr ' ' '\n' | grep -qx admin; }

# Homebrew, em ordem de preferência, sem nunca mexer no brew de outro usuário:
#   1. já existe um deste usuário: só usa (sem sudo)
#   2. não existe nenhum e o usuário é admin: instalador oficial em /opt/homebrew (pede a
#      senha uma vez: cria a pasta e instala as Command Line Tools, que trazem o git)
#   3. senão (sem admin, ou o brew do sistema é de outro usuário): clone em ~/.homebrew (sem sudo)
ensure_brew() {
  local b other
  b=$(find_brew)
  other=$(foreign_brew)
  if [ -n "$b" ]; then
    [ -n "${DOTFILES_BREW_OK:-}" ] || echo "==> Homebrew já instalado em ${b%/bin/brew}, pulando (sem sudo)"
  elif [ -z "$other" ] && is_admin; then
    echo "==> Homebrew não encontrado, instalando (pede a senha de administrador uma vez)"
    sudo -v
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    b=$(find_brew)
  else
    if [ -n "$other" ]; then
      echo "==> o Homebrew em ${other%/bin/brew} é de outro usuário; instalando um só seu em $USER_BREW (sem sudo)"
    else
      echo "==> usuário sem admin; instalando o Homebrew só para você em $USER_BREW (sem sudo)"
    fi
    if ! xcode-select -p &> /dev/null; then
      echo "ERR: faltam as Command Line Tools (git), e só um admin consegue instalá-las:"
      echo "     peça para rodarem 'xcode-select --install' nesta máquina e rode este script de novo"
      exit 1
    fi
    git clone -q https://github.com/Homebrew/brew "$USER_BREW"
    b="$USER_BREW/bin/brew"
  fi
  [ -n "$b" ] && [ -x "$b" ] || { echo "ERR: Homebrew não ficou instalado"; exit 1; }
  eval "$("$b" shellenv)"
  export DOTFILES_BREW_OK=1   # o install.sh relançado após o clone não repete a mensagem
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
# (git não: o das Command Line Tools basta, e o do brew compila do fonte fora do /opt/homebrew)
for f in starship kubernetes-cli kubecolor fzf jq gh; do
  brew list --formula "$f" &> /dev/null || brew install "$f"
done

# casks (nada vai para /Applications: fontes em ~/Library/Fonts, claude no prefixo do brew)
# <cask> <o que indica que já está instalado fora do brew>
while read -r c path; do
  brew list --cask "$c" &> /dev/null && continue
  [ -e "$path" ] && continue
  brew install --cask "$c"
done <<EOF
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
echo "Pronto. Abra um terminal novo e rode: gh auth login && claude"
