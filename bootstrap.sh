#!/usr/bin/env bash
# bootstrap.sh — **새 맥에 앉아서 한 줄.** 개발/서버 환경을 세운다.
#
#   curl -fsSL https://raw.githubusercontent.com/sigmo2nd/macsetup/main/bootstrap.sh | bash
#   # 또는
#   git clone git@github.com:sigmo2nd/macsetup.git && ./macsetup/bootstrap.sh
#
# ── 손으로 해야 하는 것은 **둘뿐**이다 ──────────────────────────
#   1. 시스템 설정 → 일반 → 공유 → **원격 로그인(SSH) 켜기**
#      (이게 켜져야 그 뒤로는 전부 원격에서 된다)
#   2. 이 스크립트가 묻는 **관리자 암호** (Homebrew 설치 · Tailscale 데몬 등록)
#
#   ⭐ Tailscale 인증키를 미리 주면 **가입까지 자동**이라 브라우저를 안 열어도 된다:
#      TS_AUTHKEY=tskey-auth-… ./bootstrap.sh
#      키는 Tailscale 관리 콘솔 → Settings → Keys 에서 만든다(일회용 권장).
#
#   그 밖에는 다 자동이다. OrbStack 도 GUI 를 안 열고 `orb start` 로 띄운다.
#
# ── 무엇을 세우나 ──────────────────────────────────────────────
#   Homebrew · OrbStack(도커) · Python 3.12 · Tailscale · zsh 프롬프트
#
#   ⚠️ Python 은 **3.12 고정**이다. 운영 컨테이너가 `FROM python:3.12-slim` 이라
#      다른 버전을 쓰면 **테스트를 운영과 다른 파이썬에서 돌리게 된다**
#      (2026-08-06 에 실제로 그랬다 — 맥북 3.11 · 서버 3.9 · 운영 3.12).
#
# ── 다시 돌려도 안전하다 ────────────────────────────────────────
#   이미 있는 것은 건너뛴다. 프롬프트는 덮어쓴다(두 벌로 안 쌓인다).

set -euo pipefail

# ── 역할 ────────────────────────────────────────────────────────
#   master  이 맥북 — **여기서 나머지로 붙는다.** 호스트 목록(~/.ssh/config)의 정본이고
#           설정을 뿌리는 쪽이다.
#   node    접속지 — 서버·노드. 받는 쪽이다. 서버로 쓰려면 확인할 게 셋 더 있다
#           (SSH 켜짐 · 자동 로그인 · 정전 복귀).
#
#   기본은 **접속 경로로 판정**한다: SSH 로 들어와 돌리고 있으면 node.
ROLE="${ROLE:-}"
if [ -z "$ROLE" ]; then
  if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_TTY:-}" ]; then ROLE=node; else ROLE=master; fi
fi

PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREW="/opt/homebrew/bin/brew"

c(){ printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
step(){ echo; c "1;36" "▸ $1"; }
ok(){ c "0;32" "  ✓ $1"; }
skip(){ c "0;90" "  · $1"; }
warn(){ c "0;33" "  ! $1"; }
die(){ c "0;31" "  ✗ $1"; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "맥에서만 돈다"

# 프롬프트만 (여러 대에 뿌릴 때 lib/setup-prompt.sh 가 이 모드로 부른다)
if [ "${1:-}" = "--prompt-only" ]; then
  step "zsh 프롬프트"; install_prompt; exit 0
fi
c "1;35" "역할: $ROLE   ($(hostname -s))"

# ── 1. Homebrew ────────────────────────────────────────────────
step "Homebrew"
if [ -x "$BREW" ]; then
  skip "이미 있다 ($("$BREW" --version | head -1))"
else
  warn "관리자 암호를 한 번 묻는다"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  [ -x "$BREW" ] || die "Homebrew 설치 실패"
  ok "설치했다"
fi
eval "$("$BREW" shellenv)"

# ⚠️ brew 가 여기서 막히는 걸 실제로 겪었다 — 다른 설치 도구가 sudo 로 만든 root 소유
#    디렉터리 하나 때문에 `brew install` 전체가 멈춘다. 미리 확인만 하고 알려 준다.
for d in /opt/homebrew/var/log /opt/homebrew/var; do
  if [ -e "$d" ] && [ ! -w "$d" ]; then
    warn "$d 가 내 소유가 아니다 — brew 가 막힌다. 고치려면:"
    echo "      sudo rm -rf $d"
  fi
done

# ── 2. OrbStack ────────────────────────────────────────────────
step "OrbStack (도커)"
if [ -d /Applications/OrbStack.app ]; then
  skip "이미 있다"
else
  "$BREW" install --cask orbstack
  ok "설치했다"
fi
# ⚠️ **GUI 를 안 열어도 된다** — orb 가 데몬을 띄운다. 서버(헤드리스)에서 중요하다.
if command -v orb >/dev/null 2>&1; then
  orb start >/dev/null 2>&1 || true
  sleep 5
  if docker ps >/dev/null 2>&1; then ok "도커 엔진 살아 있다"; else warn "도커가 아직 안 뜬다 — 잠시 뒤 'orb start'"; fi
fi

# ── 3. Python ──────────────────────────────────────────────────
step "Python $PYTHON_VERSION"
if [ -x "/opt/homebrew/bin/python$PYTHON_VERSION" ]; then
  skip "이미 있다 ($(/opt/homebrew/bin/python$PYTHON_VERSION -V))"
else
  "$BREW" install "python@$PYTHON_VERSION"
  ok "$(/opt/homebrew/bin/python$PYTHON_VERSION -V)"
fi

# ── 4. Tailscale ───────────────────────────────────────────────
# 왜 넣나: 이게 있으면 **포트 포워딩도, 고정 IP 도 필요 없다.** 기계가 메시에 붙는 순간
# 이름으로 닿는다 — 새 기계를 세울 때마다 공유기를 만지던 일이 없어진다.
#
# formula(데몬+CLI)를 쓴다. GUI 앱(cask)은 로그인 세션이 있어야 하는데, 서버는
# 헤드리스로 도는 편이 낫다. 둘을 같이 깔면 서로 밟으므로 **하나만** 쓴다.
step "Tailscale"
if [ -d /Applications/Tailscale.app ]; then
  skip "GUI 앱(cask)이 이미 있다 — 데몬은 앱이 맡는다"
  TS_CLI="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
elif "$BREW" list --formula tailscale >/dev/null 2>&1; then
  skip "이미 있다"
  TS_CLI="/opt/homebrew/bin/tailscale"
else
  "$BREW" install tailscale
  TS_CLI="/opt/homebrew/bin/tailscale"
  ok "설치했다"
  # ⚠️ 데몬 등록엔 sudo 가 필요한데, **파이프로 들어온 SSH 에는 tty 가 없어** 암호를 못 묻는다
  #    (`ssh HOST 'bash -s' < bootstrap.sh` 가 그 경우다). 그때는 시키지 말고 알려만 준다.
  if [ -t 0 ] && sudo -v 2>/dev/null; then
    sudo "$BREW" services start tailscale && ok "tailscaled 등록 (부팅에 자동)" \
      || warn "서비스 등록 실패 — 'sudo brew services start tailscale'"
  else
    warn "데몬 등록은 **그 기계의 터미널에서** 해야 한다 (여기선 암호를 못 묻는다):"
    echo "      sudo brew services start tailscale"
    echo "      sudo tailscale up --ssh"
  fi
fi

if [ -n "${TS_AUTHKEY:-}" ] && { [ -t 0 ] || sudo -n true 2>/dev/null; }; then
  # ⚠️ 인증키는 **인자로 흘리면 프로세스 목록에 뜬다.** 환경변수로만 받는다.
  if sudo "$TS_CLI" up --authkey="$TS_AUTHKEY" --ssh 2>/dev/null; then
    ok "메시에 붙었다 — $("$TS_CLI" ip -4 2>/dev/null | head -1)"
  else
    warn "가입 실패 — 키가 만료됐거나 이미 붙어 있다"
  fi
elif "$TS_CLI" status >/dev/null 2>&1; then
  skip "이미 붙어 있다 — $("$TS_CLI" ip -4 2>/dev/null | head -1)"
else
  warn "아직 안 붙었다. 붙이려면:  sudo tailscale up --ssh"
  echo "      (또는 TS_AUTHKEY=… 를 주고 이 스크립트를 다시 돌린다)"
fi

# ── 5. 프롬프트 ─────────────────────────────────────────────────
# ⚠️ **여기 안에 들어 있다.** 처음엔 lib/setup-prompt.sh 를 부르고, 없으면 GitHub 에서
#    받게 했는데 — 저장소가 비공개라 raw 가 **404** 였다. 그리고 `ssh HOST 'bash -s' <
#    bootstrap.sh` 로 보내면 애초에 lib 이 안 따라간다. 한 파일로 서야 한다.
#    (lib/setup-prompt.sh 는 여러 대에 뿌리는 용도로 남아 있고, 그것도 이 파일을 보낸다.)
install_prompt() {
  local RC="$HOME/.zshrc"
  local B="# >>> touchbook prompt >>>" E="# <<< touchbook prompt <<<"
  [ -f "$RC" ] && cp "$RC" "$RC.bak.$(date +%Y%m%d%H%M%S)"
  # 우리 블록 걷기
  if [ -f "$RC" ] && grep -qF "$B" "$RC"; then
    local t; t="$(mktemp)"
    awk -v b="$B" -v e="$E" 'index($0,b){s=1} !s{print} index($0,e){s=0}' "$RC" > "$t"; mv "$t" "$RC"
  fi
  # 옛 판(setupomz)이 남긴 블록도 — D01 에 12벌 쌓여 있었다
  if [ -f "$RC" ] && grep -q "커스텀 프롬프트 설정" "$RC"; then
    local t; t="$(mktemp)"
    awk '/커스텀 프롬프트 설정/{s=1} !s{print} s&&/^fi$/{s=0}' "$RC" > "$t"; mv "$t" "$RC"
    warn "옛 판(setupomz) 블록도 걷어냈다"
  fi
  { echo ""; echo "$B"; cat <<'PROMPTEOF'
# 호스트명 > 디렉터리 git:(브랜치)
# SSH 로 들어왔으면 호스트명이 **노랑**, 직접 앉았으면 **초록** — 남의 기계에서 명령을
# 치고 있다는 걸 눈이 먼저 알아채라고.
setopt PROMPT_SUBST
if [ -d "$HOME/.oh-my-zsh" ]; then
  export ZSH="$HOME/.oh-my-zsh"; ZSH_THEME=""; plugins=(git)
  source "$ZSH/oh-my-zsh.sh"
  ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}git:(%{$fg[red]%}"
  ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%} "
  ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[yellow]%}✗"
  ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[blue]%})"
  _tb_git() { git_prompt_info }
else
  autoload -U colors && colors
  _tb_git() { }
fi
if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_TTY" ]; then
  PROMPT='%{$fg_bold[yellow]%}%m%{$reset_color%} > %{$fg_bold[cyan]%}%c%{$reset_color%} $(_tb_git)'
else
  PROMPT='%{$fg_bold[green]%}%m%{$reset_color%} > %{$fg_bold[cyan]%}%c%{$reset_color%} $(_tb_git)'
fi
export LS_COLORS="di=1;36:ln=1;35:so=1;32:pi=1;33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=34;43"
alias ls="ls -G"; alias ll="ls -alF"; alias la="ls -A"; alias l="ls -CF"
alias grep="grep --color=auto"
PROMPTEOF
    echo "$E"; } >> "$RC"
  ok "$RC 에 프롬프트를 넣었다"
}

step "zsh 프롬프트"
install_prompt

# ── 끝 ─────────────────────────────────────────────────────────
step "끝"
ok "새 셸을 열거나: source ~/.zshrc"

if [ "$ROLE" = "node" ]; then
  echo
  c "0;33" "  접속지(서버)로 쓸 거면 셋을 확인해라 — 여기서 못 고친다(GUI·권한):"
  # 실제 상태를 읽어서 알려 준다. 「하세요」만 적으면 안 하게 된다.
  if pmset -g 2>/dev/null | grep -q "autorestart *1"; then
    ok "정전 후 자동 시작 켜짐"
  else
    echo "    ✗ 정전 후 자동 시작 — 시스템 설정 → 에너지"
  fi
  if [ -d /Applications/OrbStack.app ]; then
    echo "    · 자동 로그인 — 시스템 설정 → 사용자 및 그룹"
    echo "      (OrbStack 은 로그인 세션이 있어야 뜬다. 재부팅 뒤 아무도 로그인 안 하면 서비스가 안 올라온다)"
  fi
  echo "    · 원격 로그인(SSH) — 이미 켜져 있으니 여기까지 왔을 것이다"
else
  echo
  c "0;33" "  마스터다. 접속지에 뿌리려면:"
  echo "    ./lib/setup-prompt.sh A07 G01 D01     # 프롬프트만"
  echo "    ssh A07 'bash -s' < bootstrap.sh      # 전체 (역할은 자동으로 node)"
  echo
  echo "  ⚠️ ~/.ssh/config 가 호스트 목록의 정본이다 — 이 기계에만 있으면 된다."
  echo "     접속지끼리는 서로 몰라도 된다(마스터를 거친다)."
fi
