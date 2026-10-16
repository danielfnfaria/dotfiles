# dotfiles

Meu setup de terminal no macOS: zsh (oh-my-zsh + `~/.zsh.d`), Starship, Ghostty
e a status line do Claude Code. Tema Catppuccin Macchiato em tudo.

## Instalação

    curl -fsSL https://raw.githubusercontent.com/danielfnfaria/dotfiles/main/install.sh | bash

Isso clona o repo em `~/dotfiles` (outro lugar: `... | DOTFILES_DIR=~/src/dotfiles bash`) e roda o `install.sh` de lá.
Se preferir clonar à mão:

    git clone https://github.com/danielfnfaria/dotfiles ~/dotfiles
    ~/dotfiles/install.sh

Funciona num Mac zerado. O `install.sh`:
- instala o Homebrew, se faltar (pede a senha de administrador; ele traz as Command Line Tools e o git);
- instala via Homebrew o que faltar: git, starship, kubectl, kubecolor, fzf, jq, gh, Ghostty,
  Fira Code, FiraCode Nerd Font e Claude Code, além do oh-my-zsh;
- cria symlinks em `~` (o que já existir vira `<arquivo>.bak-<data>`);
- adiciona o `statusLine` ao `~/.claude/settings.json` sem mexer no resto.

No fim, abra o Ghostty e faça login: `gh auth login` (CI das PRs na status line) e `claude`.

Para atualizar: `git -C ~/dotfiles pull`.

Opcionais, carregados só se estiverem instalados: nvm, pyenv, Go, gcloud, Istio, opencode.

## O que vem

| Arquivo | Destino |
| --- | --- |
| `zsh/.zshrc` | `~/.zshrc` — carrega todo `~/.zsh.d/*.sh` executável, em ordem |
| `zsh/.zsh.d/100-aliases.sh` | `kubectl` → `kubecolor`, `git_commit` (commit pelo Claude) |
| `zsh/.zsh.d/101-functions.sh` | `kctx` (troca de contexto k8s com fzf), `cwatch`, `retag` |
| `zsh/.zsh.d/110-env.sh` | Starship, Go, nvm, pyenv, gcloud… (só o que estiver instalado) |
| `starship/starship.toml` | `~/.config/starship.toml` |
| `ghostty/config` | `~/.config/ghostty/config` — quick terminal em `cmd+o` |
| `claude/statusline.sh` | `~/.claude/statusline.sh` |

## Segredos

Tokens e chaves vão em `~/.zsh.d/000-credentials.sh` (fora do git).
Use `zsh/.zsh.d/000-credentials.sh.example` como modelo e dê `chmod 700`.

## Status line do Claude Code

Duas linhas numa moldura:
- **trabalho:** agentes ativos, cluster k8s (⚠ em prod), branch, sync, diff, PR e CI;
- **sessão:** modelo, esforço, contexto, custo, limites de 5h/7d, cache e duração.

Ela se ajusta à largura do terminal. Depende de `jq` e `gh` (autenticado, para o CI das PRs).
`STATUSLINE_BUDGET_USD` (padrão 10) define a escala da barra de custo.
