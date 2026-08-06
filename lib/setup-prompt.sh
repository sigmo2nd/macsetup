#!/usr/bin/env bash
# setup-prompt.sh — 프롬프트만 **여러 대에** 뿌린다.
#
#   ./lib/setup-prompt.sh A07 G01 D01
#
# ⚠️ 프롬프트의 **정본은 `bootstrap.sh` 안에 있다** (`--prompt-only`).
#    여기 또 적으면 두 벌이 되고, 언젠가 한쪽만 고쳐진다.
#    이 파일은 **보내는 일만** 한다.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT="$HERE/bootstrap.sh"
[ -f "$BOOT" ] || { echo "bootstrap.sh 를 못 찾겠다: $BOOT" >&2; exit 1; }

c(){ printf '\033[%sm%s\033[0m\n' "$1" "$2"; }

if [ $# -eq 0 ]; then
  bash "$BOOT" --prompt-only
  exit $?
fi

for host in "$@"; do
  c "1;36" "$host"
  if ! ssh -o ConnectTimeout=8 -o BatchMode=yes "$host" true 2>/dev/null; then
    c "0;31" "  ✗ 연결 실패 — 건너뛴다"; continue
  fi
  ssh "$host" 'bash -s -- --prompt-only' < "$BOOT" || c "0;31" "  ✗ 실패"
done
