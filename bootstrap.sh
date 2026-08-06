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
  # 데몬 등록 — 부팅에 자동으로 뜬다 (sudo 필요)
  warn "tailscaled 를 등록한다 (관리자 암호)"
  sudo "$BREW" services start tailscale || warn "서비스 등록 실패 — 'sudo brew services start tailscale' 을 직접"
  ok "설치했다"
fi

if [ -n "${TS_AUTHKEY:-}" ]; then
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
step "zsh 프롬프트"
if [ -x "$HERE/lib/setup-prompt.sh" ]; then
  "$HERE/lib/setup-prompt.sh" --local
else
  # curl | bash 로 온 경우 — 저장소가 없으니 받아서 쓴다
  tmp="$(mktemp)"
  curl -fsSL https://raw.githubusercontent.com/sigmo2nd/macsetup/main/lib/setup-prompt.sh -o "$tmp"
  bash "$tmp" --local
  rm -f "$tmp"
fi

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
