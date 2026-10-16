#!/usr/bin/env bash
# Status line do Claude Code, numa moldura de duas linhas:
# Com nome de sessão (/rename, --name ou o título automático), ele vira o rótulo da moldura:
#   ╭─ <nome da sessão> ──────
#   │  trabalho … / ╰─ sessão …
#   ╭─ trabalho: ☁ <config gcloud> · @<agente> (ativos ou principal) ⟳n (em segundo plano) · ⎈ <cluster> · ⎇ <branch> ⇡a ⇣b +ins/-rem ⚑n · PR #n <ci> (link)
#   ╰─ sessão:   [✦ <modelo>] ●●○○○ <effort> 🧠 ⚡ · Ctx <barra> · $ <barra> · 5h <barra> ↻hh:mm · 7d <barra>
#                · ❄ <cache> · ⏱ <duração>
# Abaixo, quando houver: uma linha por PR criada nesta sessão (com o CI).
# Recebe o JSON da sessão no stdin; tudo aqui precisa ser rápido (o CI do PR vem de um cache).
# Responsivo: lê a largura do terminal do Claude Code e corta itens, do menos ao mais importante,
# até cada linha caber (STATUSLINE_COLS força uma largura, útil para testar).
input=$(cat)

fg()   { printf '\e[38;2;%d;%d;%dm' "$1" "$2" "$3"; }
bg()   { printf '\e[48;2;%d;%d;%dm' "$1" "$2" "$3"; }
R=$'\e[0m'; B=$'\e[1m'
DIM=$(fg 108 112 134); SEPC=$(fg 88 91 112)
PINK=$(fg 245 194 231); MAUVE=$(fg 203 166 247); BLUE=$(fg 137 180 250); SKY=$(fg 137 220 235)
TEAL=$(fg 148 226 213); GREEN=$(fg 166 227 161); YELLOW=$(fg 249 226 175); PEACH=$(fg 250 179 135)
RED=$(fg 243 139 168); LAV=$(fg 180 190 254)
SEP=" ${SEPC}·${R} "

# Separador \x1f, não tab: tab é espaço em branco para o read, que juntaria campos vazios
# seguidos (ex. used_percentage nulo no início da sessão) e deslocaria todos os seguintes.
IFS=$'\x1f' read -r model dir ctx size ctx_pct tok_in tok_out cost dur_ms pr_num pr_url \
  effort thinking fast rl5_pct rl5_reset rl7_pct cache_hit cache_warm transcript session_id main_agent session_name < <(jq -r '
  (.context_window.current_usage // {}) as $u
  | (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) as $cur
  | [ (.model.display_name // "?"),
      (.workspace.current_dir // .cwd // "."),
      (if $cur > 0 then $cur else (.context_window.total_input_tokens // 0) end),
      (.context_window.context_window_size // 0),
      (.context_window.used_percentage // ""),
      (.context_window.total_input_tokens // 0),
      (.context_window.total_output_tokens // 0),
      (.cost.total_cost_usd // 0),
      (.cost.total_duration_ms // 0),
      (.pr.number // ""),
      (.pr.url // ""),
      (.effort.level // ""),
      (.thinking.enabled // false),
      (.fast_mode // false),
      (.rate_limits.five_hour.used_percentage // ""),
      (.rate_limits.five_hour.resets_at // ""),
      (.rate_limits.seven_day.used_percentage // ""),
      (if .prompt_cache.hit_ratio then (.prompt_cache.hit_ratio * 100 | floor) else "" end),
      (.prompt_cache.warm // false),
      (.transcript_path // ""),
      (.session_id // ""),
      (.agent.name // ""),
      (.session_name // "") ] | map(tostring) | join("\u001f")' <<<"$input")

fmt_k() { awk -v n="$1" 'BEGIN { if (n >= 1e6) printf "%.1fM", n/1e6; else if (n >= 1000) printf "%dk", n/1000; else printf "%d", n }'; }
link() { printf '\e]8;;%s\e\\%s\e]8;;\e\\' "$1" "$2"; }   # OSC 8: texto clicável

# bar <pct> [largura] -> células com gradiente verde→amarelo→vermelho; vazias em cinza
bar() {
  local p=$1 w=${2:-10} f i r g b t out=""
  [ "$p" -gt 100 ] && p=100; [ "$p" -lt 0 ] && p=0
  f=$(( (p * w + 50) / 100 )); [ "$p" -gt 0 ] && [ "$f" -eq 0 ] && f=1
  for ((i = 0; i < w; i++)); do
    if [ "$i" -lt "$f" ]; then
      t=$(( i * 100 / (w - 1) ))
      if [ "$t" -lt 50 ]; then r=$(( 166 + (249 - 166) * t / 50 )); g=$(( 227 - (227 - 226) * t / 50 )); b=$(( 161 + (175 - 161) * t / 50 ))
      else r=$(( 249 - (249 - 243) * (t - 50) / 50 )); g=$(( 226 - (226 - 139) * (t - 50) / 50 )); b=$(( 175 - (175 - 168) * (t - 50) / 50 )); fi
      out+="$(fg $r $g $b)▰"
    else
      out+="$(fg 69 71 90)▱"
    fi
  done
  printf '%s%s' "$out" "$R"
}
pct_color() { if [ "$1" -ge 80 ]; then printf '%s' "$RED"; elif [ "$1" -ge 50 ]; then printf '%s' "$YELLOW"; else printf '%s' "$GREEN"; fi; }

# ===== largura do terminal ==================================================================
# A status line roda sem tty: sobe pelos processos pais até achar o terminal do Claude Code.
term_cols() {
  local p=$PPID t i
  for i in 1 2 3 4 5; do
    t=$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')
    if [ -n "$t" ] && [ "$t" != "??" ]; then
      stty -f "/dev/$t" size 2>/dev/null | awk '{ print $2 }'
      return
    fi
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [ -z "$p" ] || [ "$p" -le 1 ] && return
  done
}
cols=${STATUSLINE_COLS:-$(term_cols)}
[ "${cols:-0}" -gt 0 ] || cols=${COLUMNS:-0}
[ "$cols" -gt 0 ] || cols=200   # sem terminal descoberto: não corta nada
max=$(( cols - 6 ))   # moldura + respiro que o Claude Code deixa nas bordas

# largura visível: sem cores nem links; emojis ocupam 2 colunas
vis() {
  perl -CSD -0777 -ne 's/\e\[[0-9;]*m//g; s/\e\]8;;[^\e]*\e\\//g; $n = length($_);
    $n++ while /[\x{1F300}-\x{1FAFF}\x{23F3}\x{26A1}]/g; print $n' <<<"$1"
}

# ===== dados da linha 1: trabalho =============================================================

# --- config ativa do gcloud (some quando não houver) --------------------------------------
gprofile="${CLOUDSDK_ACTIVE_CONFIG_NAME:-$(cat "$HOME/.config/gcloud/active_config" 2>/dev/null)}"

# --- cluster (kubectl; ⎈ = símbolo do Kubernetes/Helm, o mesmo do kube-ps1) ----------------
kubeconfig="${KUBECONFIG%%:*}"; kubeconfig="${kubeconfig:-$HOME/.kube/config}"
kctx=$(awk '/^current-context:/ { print $2; exit }' "$kubeconfig" 2>/dev/null | tr -d '"')
kctx="${kctx##*_}"             # gke_<projeto>_<região>_<cluster> -> <cluster>

# --- git: branch, sync com o remoto, mudanças locais, stash ----------------------------------
git_() { git -C "$dir" --no-optional-locks "$@" 2>/dev/null; }
branch=$(git_ branch --show-current)
[ -z "$branch" ] && branch=$(git_ rev-parse --short HEAD)
if [ -n "$branch" ]; then
  read -r behind ahead < <(git_ rev-list --left-right --count '@{upstream}...HEAD')
  read -r ins del < <(git_ diff HEAD --numstat | awk '{ a += $1; d += $2 } END { printf "%d %d", a, d }')
  stashes=$(git_ stash list | wc -l | tr -d ' ')

  # --- PR: número e link vêm do Claude Code; o CI via gh, em cache de 2 min em segundo plano ---
  root=$(git_ rev-parse --show-toplevel)
  cache="${TMPDIR:-/tmp}/claude-statusline-pr-$(printf '%s' "$root:$branch" | shasum | cut -c1-16)"
  if [ ! -f "$cache" ] || [ -n "$(find "$cache" -mmin +2 2>/dev/null)" ]; then
    touch "$cache"
    # "ok" só com o PR liberado para merge (mergeStateStatus): um check obrigatório que ainda não
    # reportou (ex. o Cloud Build atrasado) não aparece no rollup, e só com ele daria ✓ cedo demais
    ( cd "$root" && gh pr view "$branch" --json number,state,url,mergeStateStatus,statusCheckRollup --jq '
        [.statusCheckRollup[]? | (.conclusion // .state // "")] as $c
        | "\(.number) \(.state) \(
            if any($c[]; . == "FAILURE" or . == "ERROR" or . == "CANCELLED" or . == "TIMED_OUT") then "fail"
            elif (.mergeStateStatus == "CLEAN" or .mergeStateStatus == "HAS_HOOKS") then "ok"
            elif ($c | length) == 0 then "none"
            else "pending" end) \(.url)"' > "$cache.tmp" 2>/dev/null; mv -f "$cache.tmp" "$cache" ) >/dev/null 2>&1 &
  fi
  read -r c_num pr_state pr_ci c_url < "$cache" 2>/dev/null
  pr_num="${pr_num:-$c_num}"; pr_url="${pr_url:-$c_url}"
  if [ -n "$pr_num" ]; then
    [ "$c_num" = "$pr_num" ] || { pr_state=""; pr_ci=""; }   # cache de outra branch/PR
    case "$pr_state" in
      MERGED) pr_c=$MAUVE; pr_txt="PR #${pr_num} merged" ;;
      CLOSED) pr_c=$DIM;   pr_txt="PR #${pr_num} closed" ;;
      *) case "$pr_ci" in
           ok)      pr_c=$GREEN;  pr_txt="PR #${pr_num} ✓" ;;
           fail)    pr_c=$RED;    pr_txt="PR #${pr_num} ✗" ;;
           pending) pr_c=$YELLOW; pr_txt="PR #${pr_num} ⏳" ;;
           *)       pr_c=$BLUE;   pr_txt="PR #${pr_num}" ;;
         esac ;;
    esac
  fi
fi

# --- agentes trabalhando: sub-agentes desta sessão com transcript escrito no último minuto ------
# (<projeto>/<sessão>/subagents/agent-<id>.jsonl + .meta.json com o agentType)
agents_txt=""; bg=0; agent_lines=()
subdir="${transcript%/*}/${session_id}/subagents"
if [ -n "$session_id" ] && [ -d "$subdir" ]; then
  # cada ativo vira "<tipo> <forma>"; forma = background quando foi disparado em segundo plano
  active=$(find "$subdir" -name 'agent-*.jsonl' -mtime -60s 2>/dev/null | while read -r f; do
             jq -r '"\(.agentType // "") \(.requestShape // "")"' "${f%.jsonl}.meta.json" 2>/dev/null
           done)
  while read -r n type; do
    [ -z "$type" ] && continue
    agents_txt+="${agents_txt:+ }${GREEN}@${type}${R}"
    [ "$n" -gt 1 ] && agents_txt+="${DIM}×${n}${R}"
  done < <(awk 'NF { print $1 }' <<<"$active" | sort | uniq -c)
  bg=$(awk '$2 == "background"' <<<"$active" | grep -c .)

  # uma linha por sub-agente ativo (até 3, o mais recente primeiro): ritmo, ação atual, passos, tempo
  agent_lines=()
  while read -r f; do
    [ -n "$f" ] || continue
    type=$(jq -r '.agentType // "agente"' "${f%.jsonl}.meta.json" 2>/dev/null)
    # todos os tool_use do agente: "<ferramenta>\t<alvo>" (alvo = arquivo, padrão, URL ou descrição, conforme a ferramenta)
    calls=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
             | .name as $n | .input as $i
             | [$n, ((if   ($n | test("^(Read|Edit|Write|NotebookEdit)$")) then $i.file_path
                      elif ($n | test("^(Grep|Glob)$"))                    then $i.pattern
                      elif ($n | test("^Web"))                             then ($i.query // $i.url)
                      else ($i.description // $i.command // $i.prompt) end) // ""
                 | tostring | split("\n")[0])] | @tsv' "$f" 2>/dev/null)
    steps=$(grep -c . <<<"$calls")
    # ritmo: os últimos 8 passos, um ▰ por passo colorido pelo tipo (ler azul, buscar lilás, editar verde, comando amarelo)
    spark=""
    while IFS=$'\t' read -r tool _; do
      case "$tool" in
        Read|Glob)                       spark+="${SKY}▰" ;;
        Grep|WebSearch|WebFetch)         spark+="${LAV}▰" ;;
        Edit|Write|NotebookEdit)         spark+="${GREEN}▰" ;;
        Bash)                            spark+="${YELLOW}▰" ;;
        *)                               spark+="${DIM}▰" ;;
      esac
    done < <(tail -n 8 <<<"$calls")
    # ação atual em pt-BR: emoji + verbo + alvo curto (arquivos só pelo nome); emojis de um só
    # code point (sem seletor de variação) para a largura ser previsível
    IFS=$'\t' read -r tool target < <(tail -n 1 <<<"$calls")
    case "$tool" in
      Read)                    act="📖 lendo ${target##*/}" ;;
      Edit|Write|NotebookEdit) act="📝 editando ${target##*/}" ;;
      Bash)                    act="💻 ${target}" ;;
      Grep|Glob)               act="🔍 buscando \"${target}\"" ;;
      WebSearch|WebFetch)      act="🌐 web ${target}" ;;
      Agent|Task)              act="🤝 delegando ${target}" ;;
      SubagentHandback)        act="✅ entregando o relatório" ;;
      "")                      act="💭 pensando" ;;
      *)                       act="🔧 ${tool} ${target}" ;;
    esac
    [ "${#act}" -gt 60 ] && act="${act:0:59}…"
    age=$(( $(date +%s) - $(stat -f %B "$f" 2>/dev/null || date +%s) ))
    if [ "$age" -ge 3600 ]; then age_txt="$((age / 3600))h$(printf '%02d' $((age % 3600 / 60)))m"
    elif [ "$age" -ge 60 ]; then age_txt="$((age / 60))m$(printf '%02d' $((age % 60)))s"
    else age_txt="${age}s"; fi
    agent_lines+=("${GREEN}${B}@${type}${R} ${spark}${R} ${act}${SEP}${DIM}passo ${steps}${R}${SEP}${DIM}${age_txt}${R}")
  done < <(find "$subdir" -name 'agent-*.jsonl' -mtime -60s 2>/dev/null | xargs ls -t 2>/dev/null | head -3)
fi
[ -n "$agents_txt" ] || agents_txt="${GREEN}@${main_agent:-principal}${R}"
[ "${bg:-0}" -gt 0 ] && agents_txt+=" ${YELLOW}⟳${bg}${R}"   # quantos rodam em segundo plano

# line1 <nível>: quanto maior o nível, mais enxuta
#   1 sem stash · 2 sem +/- · 3 "⚠" sem "PROD" · 4 branch encurtada · 5 sem gcloud e agentes · 6 sem cluster
line1() {
  local l=$1 out="" br=$branch
  if [ "$l" -lt 5 ]; then
    [ -n "$gprofile" ] && out+="${SEP}${SKY}☁ ${gprofile}${R}"
    out+="${SEP}${agents_txt}"
  fi
  if [ "$l" -lt 6 ]; then
    if [ -z "$kctx" ]; then out+="${SEP}${DIM}⎈ sem contexto${R}"
    elif [[ $kctx == *prod* ]]; then
      if [ "$l" -lt 3 ]; then out+="${SEP}${RED}${B}⎈ ${kctx} ⚠ PROD${R}"; else out+="${SEP}${RED}${B}⎈ ${kctx} ⚠${R}"; fi
    else out+="${SEP}${TEAL}⎈ ${kctx}${R}"; fi
  fi
  if [ -n "$branch" ]; then
    [ "$l" -ge 4 ] && [ "${#br}" -gt 18 ] && br="${br:0:17}…"
    out+="${SEP}${MAUVE}⎇ ${br}${R}"
    [ "${ahead:-0}" -gt 0 ] && out+=" ${SKY}⇡${ahead}${R}"     # commits a enviar
    [ "${behind:-0}" -gt 0 ] && out+=" ${PEACH}⇣${behind}${R}"  # commits a puxar
    [ "$l" -lt 2 ] && out+=" ${GREEN}+${ins:-0}${R}${DIM}/${R}${RED}-${del:-0}${R}"
    [ "$l" -lt 1 ] && [ "${stashes:-0}" -gt 0 ] && out+=" ${YELLOW}⚑ ${stashes}${R}"
    if [ -n "$pr_num" ]; then
      if [ -n "$pr_url" ]; then out+="${SEP}${pr_c}$(link "$pr_url" "$pr_txt")${R}"
      else out+="${SEP}${pr_c}${pr_txt}${R}"; fi
    fi
  fi
  printf '%s' "${out#"$SEP"}"
}

# ===== dados da linha 2: sessão ===============================================================

case "$model" in   # selo do modelo: fundo pela família, texto escuro
  *Opus*)   mc="250 179 135" ;;   # pêssego
  *Sonnet*) mc="137 180 250" ;;   # azul
  *Haiku*)  mc="166 227 161" ;;   # verde
  *Fable*)  mc="203 166 247" ;;   # lilás
  *)        mc="180 190 254" ;;
esac
case "$effort" in
  low) en=1 ;; medium) en=2; effort=med ;; high) en=3 ;; xhigh) en=4 ;; max) en=5 ;; *) en=0 ;;
esac
dots=""; for ((i = 1; i <= 5; i++)); do [ "$i" -le "$en" ] && dots+="●" || dots+="○"; done
pct=""; [ "${size:-0}" -gt 0 ] && pct=${ctx_pct:-$(( ctx * 100 / size ))}
budget="${STATUSLINE_BUDGET_USD:-10}"
cost_pct=$(awk -v c="$cost" -v b="$budget" 'BEGIN { printf "%d", (b > 0 ? c * 100 / b : 0) }')
rl5_pct=${rl5_pct%.*}; rl7_pct=${rl7_pct%.*}
rl5_at=""; [ -n "$rl5_reset" ] && rl5_at=$(date -r "${rl5_reset%.*}" +%H:%M 2>/dev/null)
dur_s=$(( ${dur_ms%.*} / 1000 ))
if [ "$dur_s" -ge 3600 ]; then dur_txt="$((dur_s / 3600))h$(printf '%02d' $((dur_s % 3600 / 60)))m"
else dur_txt="$((dur_s / 60))m"; fi

# line2 <nível>: quanto maior o nível, mais enxuta
#   1 sem cache · 2 sem 7d · 3 sem tokens do ctx · 4 sem reset do 5h · 5 sem rótulo do esforço
#   6 $ sem barra · 7 ctx sem barra · 8 5h sem barra · 9 sem esforço/🧠/⚡ · 10 sem duração
line2() {
  local l=$1 out
  # shellcheck disable=SC2086
  out="$(fg $mc)▐$(bg $mc)$(fg 30 30 46)${B}✦ ${model}${R}$(fg $mc)▌${R}"
  if [ "$l" -lt 9 ]; then
    if [ "$en" -gt 0 ]; then
      out+=" ${PEACH}${dots}${R}"; [ "$l" -lt 5 ] && out+=" ${DIM}${effort}${R}"
    fi
    [ "$thinking" = "true" ] && out+=" 🧠"
    [ "$fast" = "true" ] && out+=" ⚡"
  fi
  if [ -n "$pct" ]; then
    out+="${SEP}${LAV}Ctx${R} "; [ "$l" -lt 7 ] && out+="$(bar "$pct") "
    out+="$(pct_color "$pct")${B}${pct}%${R}"; [ "$l" -lt 3 ] && out+=" ${DIM}$(fmt_k "$ctx")${R}"
  else
    out+="${SEP}${LAV}Ctx${R} ${DIM}$(fmt_k "$ctx")${R}"
  fi
  out+="${SEP}${YELLOW}\$${R} "; [ "$l" -lt 6 ] && out+="$(bar "$cost_pct") "
  out+="$(pct_color "$cost_pct")${B}$(printf '$%.2f' "$cost")${R}"
  if [ -n "$rl5_pct" ]; then
    out+="${SEP}${LAV}5h${R} "; [ "$l" -lt 8 ] && out+="$(bar "$rl5_pct" 6) "
    out+="$(pct_color "$rl5_pct")${B}${rl5_pct}%${R}"
    [ "$l" -lt 4 ] && [ -n "$rl5_at" ] && out+=" ${DIM}↻${rl5_at}${R}"
  fi
  if [ "$l" -lt 2 ] && [ -n "$rl7_pct" ]; then
    out+="${SEP}${LAV}7d${R} $(bar "$rl7_pct" 6) $(pct_color "$rl7_pct")${B}${rl7_pct}%${R}"
  fi
  if [ "$l" -lt 1 ] && [ -n "$cache_hit" ]; then   # cache de prompt: quente = azul, frio = cinza
    if [ "$cache_warm" = "true" ]; then out+="${SEP}${SKY}❄ ${cache_hit}%${R}"
    else out+="${SEP}${DIM}❄ ${cache_hit}% frio${R}"; fi
  fi
  [ "$l" -lt 10 ] && out+="${SEP}${LAV}⏱ ${dur_txt}${R}"
  printf '%s' "$out"
}

# fit <função> <último nível>: o primeiro nível que cabe em $max (ou o último)
fit() {
  local l out
  for ((l = 0; l <= $2; l++)); do
    out=$($1 "$l")
    [ "$(vis "$out")" -le "$max" ] && break
  done
  printf '%s' "$out"
}

# --- PRs criadas NESTA sessão (e pelos sub-agentes dela), com estado e checks --------------------
# Vêm do histórico da sessão: cada `gh pr create` e a URL que ele devolveu. Ficam até serem
# mergeadas (fechadas sem merge continuam, marcadas como fechadas). Outra sessão no mesmo
# repo não entra. Estado/checks via gh, em cache de 2 min atualizado em segundo plano.
pr_lines=()
if [ -n "$session_id" ] && [ -f "$transcript" ]; then
  prs_cache="${TMPDIR:-/tmp}/claude-statusline-prs-${session_id}"
  if [ ! -f "$prs_cache" ] || [ -n "$(find "$prs_cache" -mmin +2 2>/dev/null)" ]; then
    touch "$prs_cache"
    (
      files=("$transcript")
      [ -d "$subdir" ] && files+=("$subdir"/agent-*.jsonl)
      ids=$(cat "${files[@]}" 2>/dev/null | grep 'gh pr create' | jq -r 'select(.type == "assistant")
              | .message.content[]? | select(.type == "tool_use" and .name == "Bash")
              | select(.input.command | test("gh pr create")) | .id' 2>/dev/null)
      urls=$(for id in $ids; do
               cat "${files[@]}" 2>/dev/null | grep "\"tool_use_id\":\"$id\"" \
                 | grep -oE 'https://github\.com/[^/" ]+/[^/" ]+/pull/[0-9]+' | head -1
             done | awk '!seen[$0]++' | tail -n 15)
      for u in $urls; do
        # checks obrigatórios das regras do branch base: os que ainda não reportaram ("Expected")
        # não aparecem no rollup da PR, então entram como pendentes
        repo=$(sed -E 's#https://github.com/([^/]+/[^/]+)/pull/.*#\1#' <<<"$u")
        pr=$(gh pr view "$u" --json number,title,url,state,isDraft,baseRefName,mergeStateStatus,statusCheckRollup 2>/dev/null) || continue
        base=$(jq -r .baseRefName <<<"$pr")
        required=$(gh api "repos/$repo/rules/branches/$base" --jq '[.[] | select(.type == "required_status_checks")
                     | .parameters.required_status_checks[].context]' 2>/dev/null || echo '[]')
        jq -r --argjson req "${required:-[]}" '
          [.statusCheckRollup[]? | {name: (.name // .context), r: (.conclusion // .state // "")}] as $c
          | ($req - [$c[].name]) as $missing
          | ([$c[].r] + [$missing[] | "EXPECTED"]) as $all
          | [.number, .state, .isDraft, ($all | length),
             ([$all[] | select(. == "SUCCESS" or . == "NEUTRAL" or . == "SKIPPED")] | length),
             # verde = todos os checks reportados com sucesso (e os obrigatórios, se houver, presentes);
             # não depende do "merge liberado": a main pode não exigir checks
             (if any($all[]; . == "FAILURE" or . == "ERROR" or . == "CANCELLED" or . == "TIMED_OUT") then "fail"
              elif ($all | length) == 0 then "none"
              elif any($all[]; . == "PENDING" or . == "IN_PROGRESS" or . == "QUEUED" or . == "EXPECTED" or . == "") then "pending"
              else "ok" end),
             .url, .title] | @tsv' <<<"$pr"
      done > "$prs_cache.tmp"
      mv -f "$prs_cache.tmp" "$prs_cache"
    ) >/dev/null 2>&1 &
  fi
  while IFS=$'\t' read -r n state draft total passed ci url title; do
    [ -n "$n" ] || continue
    [ "$state" = "MERGED" ] && continue          # some da barra quando é mergeada
    [ "${#pr_lines[@]}" -ge 6 ] && break
    case "$state:$ci" in
      MERGED:*)  c=$MAUVE;  icon="⇄" ;;
      CLOSED:*)  c=$DIM;    icon="⊘" ;;
      *:ok)      c=$GREEN;  icon="✓" ;;
      *:fail)    c=$RED;    icon="✗" ;;
      *:pending) c=$YELLOW; icon="⏳" ;;
      *)         c=$DIM;    icon="○" ;;
    esac
    [ "${#title}" -gt 70 ] && title="${title:0:69}…"
    line="${c}${B}${icon} $(link "$url" "#${n}")${R} ${title}"
    case "$state" in
      MERGED) line+="${SEP}${MAUVE}merged${R}" ;;
      CLOSED) line+="${SEP}${DIM}fechada${R}" ;;
      *) [ "$total" -gt 0 ] && line+="${SEP}${c}checks ${passed}/${total}${R}"
         [ "$draft" = "true" ] && line+="${SEP}${DIM}rascunho${R}" ;;
    esac
    pr_lines+=("$line")
  done < "$prs_cache" 2>/dev/null
fi

# moldura: sem PRs, duas linhas; com PRs, um "│" separa, uma linha por PR e um "╰─" fecha
fit_line() { local a=$1; while [ "$(vis "$a")" -gt "$max" ] && [ "${#a}" -gt 20 ]; do a="${a%?}"; done; printf '%s' "$a"; }
l1=$(fit line1 6); l2=$(fit line2 10)
first="${SEPC}╭─${R} $l1"
if [ -n "$session_name" ]; then
  # nome da sessão como rótulo da moldura: "╭─ nome ───", com o traço até a largura do conteúdo
  title=$session_name
  [ "${#title}" -gt $(( max - 8 )) ] && title="${title:0:$(( max - 9 ))}…"
  w1=$(vis "$l1"); w2=$(vis "$l2"); w=$(( w1 > w2 ? w1 : w2 ))
  fill=$(( w - ${#title} - 1 )); [ "$fill" -lt 3 ] && fill=3
  rule=$(printf '%*s' "$fill" '' | sed 's/ /─/g')
  printf '%s\n' "${SEPC}╭─${R} ${PINK}${B}${title}${R} ${SEPC}${rule}${R}"
  first="${SEPC}│${R}  $l1"
fi
if [ "${#pr_lines[@]}" -eq 0 ]; then
  printf '%s\n%s' "$first" "${SEPC}╰─${R} $l2"
else
  printf '%s\n%s' "$first" "${SEPC}├─${R} $l2"
  # o detalhe de cada agente (o que está fazendo) fica no painel do próprio Claude Code, logo abaixo;
  # aqui só as PRs da sessão (os agentes ativos já aparecem na linha 1: @executor×2 ⟳2)
  printf '\n%s' "${SEPC}│${R}"
  for a in "${pr_lines[@]}"; do printf '\n%s %s' "${SEPC}├─${R}" "$(fit_line "$a")${R}"; done
  # fecha a moldura numa linha própria: separa da linha do Claude Code (auto mode…)
  printf '\n%s' "${SEPC}╰─${R}"
fi
