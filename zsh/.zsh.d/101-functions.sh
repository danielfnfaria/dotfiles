#!/bin/sh

# troca de cluster
#   kctx             lista para selecionar (fzf)
#   kctx core        seletor já filtrado; se só um casar, troca direto
kctx() {
  local ctx current
  current=$(kubectl config current-context 2> /dev/null)

  if ! command -v fzf &> /dev/null; then
    [ -z "$1" ] && { kubectl config get-contexts; return; }
    ctx=$(kubectl config get-contexts -o name | grep -- "$1" | head -1)
  else
    ctx=$(kubectl config get-contexts -o name \
      | fzf --query "$1" --select-1 --exit-0 --height 40% --reverse \
            --prompt "kube> " --header "atual: ${current:-<nenhum>}")
  fi

  if [ -z "$ctx" ]; then
    [ -n "$1" ] && echo "ERR: nenhum contexto com '$1' em ${KUBECONFIG:-$HOME/.kube/config}"
    return 1
  fi
  kubectl config use-context "$ctx"
}

# roda um comando a cada 2s, limpando a tela: cwatch kubectl get pods
cwatch() {
  while true; do
    clear
    "$@"
    sleep 2
  done
}

# recria uma tag (local e no origin) no commit atual
retag() {
  local tag="$1"

  if [ -z "$tag" ]; then
    echo "uso: retag <tag>"
    return 1
  fi

  git tag -d "$tag" 2>/dev/null
  git push origin ":refs/tags/$tag" 2>/dev/null
  git tag -a "$tag" -m "$tag"
  git push origin "$tag"
}
