#!/usr/bin/env bash
# setup-prompt.sh — **어느 기계에서나** 쓰는 zsh 프롬프트 설정
#
#   D01 > touchbook2 git:(main)
#   └── 호스트명. SSH 로 들어왔으면 **노랑**, 그 기계에 직접 앉았으면 **초록**
#
# ── 왜 떼어 냈나 ────────────────────────────────────────────────
# 원본은 `creditcoin-mac/utils.sh` 의 `setupomz` (2,094줄 중 307줄)였다. 잘 되는데
# **크레딧코인 노드 기계에서만** 쓸 수 있었다 — utils.sh 전체를 셸 프로필에서 로드해야
# 하고, 그 파일은 노드 관리 함수 수십 개를 같이 끌고 온다.
# 프롬프트는 노드와 아무 상관이 없으므로 여기로 뗀다.
#
# ── 쓰는 법 ────────────────────────────────────────────────────
#   ./setup-prompt.sh              # 이 기계에 설치
#   ./setup-prompt.sh A07 G01      # 원격 여러 대에 설치 (ssh 로)
#   ./setup-prompt.sh --uninstall  # 걷어내기
#
# ── 원본과 다른 점 ──────────────────────────────────────────────
#  · 크레딧코인 의존 없음 (utils.sh·docker·노드 함수와 무관)
#  · **호스트명을 안 바꾼다.** 원본은 `scutil --set HostName` 으로 기계 이름을 고쳤는데,
#    그건 프롬프트와 별개 일이고 sudo 가 필요하며 되돌리기 번거롭다. 이름을 바꾸고 싶으면
#    따로 한다 — 이 스크립트는 **보여주기만** 한다.
#  · **두 번 돌려도 안 쌓인다.** 원본은 마커 사이만 지웠는데 D01 에는 같은 블록이 두 벌
#    붙어 있었다(실측). 여기서는 마커를 양쪽에 두고 그 사이를 통째로 걷어낸 뒤 다시 쓴다.
#  · oh-my-zsh 가 없으면 **그것 없이도** 선다 (git 표시만 빠진다).

set -euo pipefail

BEGIN_MARK="# >>> touchbook prompt >>>"
END_MARK="# <<< touchbook prompt <<<"
RC="$HOME/.zshrc"

c() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
ok()   { c "0;32" "  ✓ $1"; }
warn() { c "0;33" "  ! $1"; }
err()  { c "0;31" "  ✗ $1"; }

# ── 프로필에 넣을 블록 ─────────────────────────────────────────
# ⚠️ 'EOF' 를 따옴표로 감싼다 — 안의 $ 가 **지금** 펼쳐지면 안 된다(프롬프트는 매번 다시 
#    계산돼야 한다). 원본이 이걸 지켰고 여기서도 지킨다.
block() {
cat <<'EOF'
# 호스트명 > 디렉터리 git:(브랜치)
# SSH 로 들어왔으면 호스트명이 **노랑**, 직접 앉았으면 **초록** — 남의 기계에서 명령을
# 치고 있다는 걸 눈이 먼저 알아채라고. (원격에서 rm 을 치는 사고를 줄인다)
setopt PROMPT_SUBST

if [ -d "$HOME/.oh-my-zsh" ]; then
  export ZSH="$HOME/.oh-my-zsh"
  ZSH_THEME=""
  plugins=(git)
  source "$ZSH/oh-my-zsh.sh"
  ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}git:(%{$fg[red]%}"
  ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%} "
  ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[yellow]%}✗"
  ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[blue]%})"
  _tb_git() { git_prompt_info }
else
  # oh-my-zsh 가 없어도 선다 — git 표시만 빠진다
  autoload -U colors && colors
  _tb_git() { }
fi

if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_TTY" ]; then
  PROMPT='%{$fg_bold[yellow]%}%m%{$reset_color%} > %{$fg_bold[cyan]%}%c%{$reset_color%} $(_tb_git)'
else
  PROMPT='%{$fg_bold[green]%}%m%{$reset_color%} > %{$fg_bold[cyan]%}%c%{$reset_color%} $(_tb_git)'
fi

export LS_COLORS="di=1;36:ln=1;35:so=1;32:pi=1;33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=34;43"
alias ls="ls -G"
alias ll="ls -alF"
alias la="ls -A"
alias l="ls -CF"
alias grep="grep --color=auto"
EOF
}

strip_existing() {
  [ -f "$RC" ] || return 0
  grep -qF "$BEGIN_MARK" "$RC" || return 0
  local tmp; tmp="$(mktemp)"
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    index($0,b){skip=1} !skip{print} index($0,e){skip=0}' "$RC" > "$tmp"
  mv "$tmp" "$RC"
}

install_local() {
  c "1;36" "프롬프트 설치 — $(hostname -s)"
  if [ -f "$RC" ]; then
    cp "$RC" "$RC.bak.$(date +%Y%m%d%H%M%S)"
    ok "백업: $RC.bak.*"
  fi
  if grep -qF "$BEGIN_MARK" "$RC" 2>/dev/null; then
    strip_existing
    warn "기존 블록을 걷어냈다 (덮어쓰기)"
  fi
  # 옛 판(setupomz·setup-remote-zsh.sh)이 남긴 블록도 같이 걷는다 — D01 처럼 두 벌 쌓인 걸 봤다
  if grep -q "커스텀 프롬프트 설정" "$RC" 2>/dev/null; then
    local tmp; tmp="$(mktemp)"
    awk '/커스텀 프롬프트 설정/{skip=1} !skip{print} skip&&/^fi$/{skip=0}' "$RC" > "$tmp"
    mv "$tmp" "$RC"
    warn "옛 판(setupomz)이 남긴 블록도 걷어냈다"
  fi
  { echo ""; echo "$BEGIN_MARK"; block; echo "$END_MARK"; } >> "$RC"
  ok "$RC 에 추가했다"
  c "0;33" "  적용: source ~/.zshrc"
}

uninstall_local() {
  [ -f "$RC" ] || { warn "$RC 가 없다"; return 0; }
  cp "$RC" "$RC.bak.$(date +%Y%m%d%H%M%S)"
  strip_existing
  ok "걷어냈다 (백업 남김)"
}

install_remote() {
  local host="$1"
  c "1;36" "$host"
  if ! ssh -o ConnectTimeout=8 -o BatchMode=yes "$host" true 2>/dev/null; then
    err "연결 실패 — 건너뛴다"; return 1
  fi
  # 스크립트를 통째로 보내고 거기서 로컬 설치로 돌린다 — 원본은 원격에 heredoc 을 흘려
  # 넣었는데, 그러면 따옴표가 한 겹 더 필요해 $ 가 미리 펼쳐지는 사고가 나기 쉽다.
  ssh "$host" 'cat > /tmp/tb-setup-prompt.sh && chmod +x /tmp/tb-setup-prompt.sh && /tmp/tb-setup-prompt.sh --local && rm -f /tmp/tb-setup-prompt.sh' < "$0"
}

main() {
  case "${1:-}" in
    --uninstall) uninstall_local ;;
    --local|"")  install_local ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)
      for h in "$@"; do install_remote "$h" || true; done ;;
  esac
}
main "$@"
