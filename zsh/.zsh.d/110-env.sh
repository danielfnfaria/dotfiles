#!/usr/bin/env zsh
# Inicializacao de ferramentas e PATHs. Cada bloco só carrega se a ferramenta
# estiver instalada, para o mesmo arquivo servir em qualquer máquina.

# --- Starship prompt ---
command -v starship &> /dev/null && eval "$(starship init zsh)"

# --- Go ---
export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"

# --- NVM ---
export NVM_DIR="$HOME/.nvm"
[ -s "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm/nvm.sh" ] && \. "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm/nvm.sh"                                # This loads nvm
[ -s "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm/etc/bash_completion.d/nvm" ] && \. "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm/etc/bash_completion.d/nvm"  # nvm bash_completion

# --- Istio (istioctl baixado em ~/istio-<versão>; usa a mais recente) ---
for d in "$HOME"/istio-*/bin(Nn[-1]); do export PATH="$PATH:$d"; done

# --- curl / cargo / local bin / libpq (Homebrew) ---
export PATH="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/curl/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/libpq/bin:$PATH"

# --- Google Cloud SDK ---
if [ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/google-cloud-sdk/path.zsh.inc"; fi
if [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/google-cloud-sdk/completion.zsh.inc"; fi

# --- pyenv ---
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv &> /dev/null && eval "$(pyenv init - zsh)"

# --- opencode ---
[ -d "$HOME/.opencode/bin" ] && export PATH="$HOME/.opencode/bin:$PATH"
