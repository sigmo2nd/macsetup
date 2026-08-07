#!/usr/bin/env bash
# bootstrap.sh — **1차: 게이트웨이.** 새 맥에 앉아서 딱 한 번 돌린다.
#
#   git clone git@github.com:sigmo2nd/macsetup.git && ./macsetup/bootstrap.sh
#
# ── 왜 둘로 갈랐나 ──────────────────────────────────────────────
#
#   손으로 해야 하는 일은 전부 **「닿기 전」**에 몰려 있다. 닿고 나면 다 자동이다.
#   그래서 1차는 **닿을 수 있게**만 하고, 나머지는 마스터에서 원격으로 민다.
#
#     1차 (여기)      brew · Tailscale · SSH 확인          ← 암호가 필요한 것만
#     2차 (handover)  OrbStack · Python · 프롬프트 · 권한   ← 마스터에서 원격으로
#
#   1차가 끝나는 순간 그 기계는 **이름으로 닿는다** — 포트 포워딩도 고정 IP 도 필요 없다.
#
# ── 손으로 해야 하는 것 ────────────────────────────────────────
#   1. 시스템 설정 → 일반 → 공유 → **원격 로그인(SSH) 켜기**
#   2. 이 스크립트가 묻는 **관리자 암호** (Homebrew · Tailscale 데몬)
#
#   ⭐ 인증키를 주면 Tailscale 가입도 자동이라 브라우저를 안 연다:
#      TS_AUTHKEY=tskey-auth-… ./bootstrap.sh
#
# ── 다시 돌려도 안전하다 ────────────────────────────────────────

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

# ── 2. Tailscale ───────────────────────────────────────────────
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

# ── 끝 ─────────────────────────────────────────────────────────
step "1차 끝"
ok "게이트웨이가 섰다"

TS_NAME="$(hostname -s)"
TS_IP="$("$TS_CLI" ip -4 2>/dev/null | head -1 || true)"
if [ -n "$TS_IP" ]; then
  ok "메시 주소: $TS_IP  ($TS_NAME)"
  echo
  c "0;33" "  이제 마스터(맥북)에서 2차를 민다:"
  echo "      ./handover.sh $TS_NAME"
else
  echo
  c "0;33" "  아직 메시에 안 붙었다. 이 기계에서 한 번:"
  echo "      sudo brew services start tailscale"
  echo "      sudo tailscale up --ssh"
  echo
  echo "  그 다음 마스터에서:  ./handover.sh <이름>"
fi

if [ "$ROLE" = "node" ] && ! pmset -g 2>/dev/null | grep -q "autorestart *1"; then
  echo
  c "0;33" "  ⚠️ 서버로 쓸 거면 — 정전 후 자동 시작이 꺼져 있다 (시스템 설정 → 에너지)"
fi
