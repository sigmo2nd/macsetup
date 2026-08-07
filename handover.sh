#!/usr/bin/env bash
# handover.sh — **2차: 일할 수 있게.** 마스터에서 접속지로 민다.
#
#   ./handover.sh A07              # 도구 + 프롬프트
#   ./handover.sh A07 --keys       # + 권한(열쇠) 넘기기
#   ./handover.sh A07 G01 D01      # 여러 대
#
# ── 1차와 무엇이 다른가 ────────────────────────────────────────
#   1차는 그 기계에 **앉아서** 돌린다(암호가 필요하다). 2차는 **원격에서** 민다.
#   1차가 끝나 이름으로 닿으면, 그 뒤로 사람이 그 앞에 갈 일이 없다.
#
# ── ⭐ 권한은 「복사할 것」과 「새로 만들 것」을 가른다 ─────────────
#
#   복사가 편하지만 **복사하면 안 되는 것**이 있다. 열쇠를 복사하면 옛 기계의 접근을
#   나중에 끊을 수가 없다 — 같은 열쇠라서 하나를 지우면 둘 다 막힌다.
#
#     🔴 복사   터널 신원·백업 암호 같은 **신원 그 자체** (새로 만들면 옛 것이 죽는다)
#     🟢 생성   SSH 키 — **기계마다 따로.** 새 키를 등록해 두면 옛 기계만 골라 끊을 수 있다
#     ⛔ 안 함  도구 설정·남의 프로젝트 — 이사는 짐을 줄일 기회다
#
#   그래서 `--keys` 는 **키를 만들어 공개키를 보여줄 뿐** 개인키를 옮기지 않는다.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"

c(){ printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
step(){ echo; c "1;36" "▸ $1"; }
ok(){ c "0;32" "  ✓ $1"; }
skip(){ c "0;90" "  · $1"; }
warn(){ c "0;33" "  ! $1"; }
err(){ c "0;31" "  ✗ $1"; }

WITH_KEYS=0
HOSTS=()
for a in "$@"; do
  case "$a" in
    --keys) WITH_KEYS=1 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) HOSTS+=("$a") ;;
  esac
done
[ ${#HOSTS[@]} -gt 0 ] || { echo "쓸 호스트를 달라: ./handover.sh A07" >&2; exit 1; }

# ── 원격에서 돌 몸통 ────────────────────────────────────────────
# ⚠️ 'REMOTE' 를 따옴표로 감싼다 — 안의 $ 가 **마스터에서** 펼쳐지면 안 된다.
remote_body() {
cat <<'REMOTE'
set -euo pipefail
BREW=/opt/homebrew/bin/brew
c(){ printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
ok(){ c "0;32" "  ✓ $1"; }
skip(){ c "0;90" "  · $1"; }
warn(){ c "0;33" "  ! $1"; }
[ -x "$BREW" ] || { c "0;31" "  ✗ Homebrew 가 없다 — 1차(bootstrap.sh)를 먼저"; exit 1; }
eval "$("$BREW" shellenv)"
# ⚠️ 비로그인 SSH 셸의 PATH 는 /usr/bin:/bin:/usr/sbin:/sbin 뿐이다 —
#    OrbStack 이 심어 둔 **/usr/local/bin 의 docker 가 안 잡힌다.** 그래서 「도커 없음」으로
#    잘못 읽었다(실측). 여기서 넣어 준다.
export PATH="/usr/local/bin:$PATH"

# OrbStack — GUI 를 안 열고 orb 로 띄운다
if [ -d /Applications/OrbStack.app ]; then skip "OrbStack 이미 있다"; else
  "$BREW" install --cask orbstack >/dev/null && ok "OrbStack 설치"
fi
command -v orb >/dev/null 2>&1 && { orb start >/dev/null 2>&1 || true; sleep 4; }
docker ps >/dev/null 2>&1 && ok "도커 엔진 살아 있다" || warn "도커가 아직 — 잠시 뒤 'orb start'"

# Python — 버전은 마스터가 정해 보낸다
if [ -x "/opt/homebrew/bin/python${PYV}" ]; then skip "Python $("/opt/homebrew/bin/python${PYV}" -V | cut -d' ' -f2)"; else
  "$BREW" install "python@${PYV}" >/dev/null && ok "Python ${PYV} 설치"
fi

# gh — **설치만 한다. 로그인은 안 시킨다.**
# 토큰을 접속지로 보내면 그 기계가 마스터와 같은 권한을 갖는다. 아래에서 마스터가
# 이 기계의 **공개키만** 대신 등록해 주므로, 저장소 clone 에는 gh 로그인이 필요 없다.
# 나중에 그 기계에서 gh 를 쓰고 싶으면 거기서 `gh auth login` 하면 된다.
if command -v gh >/dev/null 2>&1; then skip "gh 이미 있다"; else
  "$BREW" install gh >/dev/null && ok "gh 설치 (로그인은 안 했다)"
fi

# 프롬프트
RC="$HOME/.zshrc"; B="# >>> touchbook prompt >>>"; E="# <<< touchbook prompt <<<"
[ -f "$RC" ] && cp "$RC" "$RC.bak.$(date +%Y%m%d%H%M%S)"
if [ -f "$RC" ] && grep -qF "$B" "$RC"; then
  t="$(mktemp)"; awk -v b="$B" -v e="$E" 'index($0,b){s=1} !s{print} index($0,e){s=0}' "$RC" > "$t"; mv "$t" "$RC"
fi
if [ -f "$RC" ] && grep -q "커스텀 프롬프트 설정" "$RC"; then
  t="$(mktemp)"; awk '/커스텀 프롬프트 설정/{s=1} !s{print} s&&/^fi$/{s=0}' "$RC" > "$t"; mv "$t" "$RC"
  warn "옛 판(setupomz) 블록도 걷어냈다"
fi
{ echo ""; echo "$B"; cat <<'PROMPTEOF'
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
  autoload -U colors && colors; _tb_git() { }
fi
# SSH 면 노랑, 직접이면 초록 — 남의 기계에서 치고 있다는 걸 눈이 먼저 알아채라고
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
ok "프롬프트"

# 열쇠 — **만들기만** 한다. 개인키는 안 옮긴다
if [ "${WANT_KEYS:-0}" = "1" ]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  if [ -f ~/.ssh/id_ed25519 ]; then
    skip "이 기계 키가 이미 있다"
  else
    ssh-keygen -q -t ed25519 -N "" -C "$(whoami)@$(hostname -s)" -f ~/.ssh/id_ed25519
    ok "이 기계 전용 키를 만들었다"
  fi
  echo
  c "1;35" "  ── 이 기계의 공개키 (GitHub·authorized_keys 에 등록) ──"
  cat ~/.ssh/id_ed25519.pub | sed 's/^/  /'
fi
REMOTE
}

for host in "${HOSTS[@]}"; do
  echo; c "1;35" "═══ $host ═══"
  if ! ssh -o ConnectTimeout=8 -o BatchMode=yes "$host" true 2>/dev/null; then
    err "연결 실패 — 1차가 끝났나? (Tailscale 이름/ssh config 확인)"; continue
  fi
  step "도구 · 프롬프트"
  remote_body | ssh "$host" "PYV='$PYTHON_VERSION' WANT_KEYS='$WITH_KEYS' bash -s" || err "실패"

  if [ "$WITH_KEYS" = "1" ]; then
    step "설정 넘기기"
    # 🟡 목록이지 값이 아니다 — 복사해도 된다.
    # ⚠️ 다만 **키를 가리키는 줄은 갈아 끼운다.** 마스터의 config 에는
    #    `Host github.com / IdentityFile ~/.ssh/github_id_rsa` 가 들어 있는데, 접속지엔
    #    그 파일이 없다 — 그대로 복사하면 ssh 가 「no such identity」로 **그 기계 제 키를
    #    안 써 본 채** 실패한다(실측). 접속지는 §키에서 만든 id_ed25519 를 쓴다.
    if [ -f "$HOME/.ssh/config" ]; then
      sed 's#IdentityFile .*github_id_rsa#IdentityFile ~/.ssh/id_ed25519#' "$HOME/.ssh/config" \
        | ssh "$host" 'cat > ~/.ssh/config && chmod 600 ~/.ssh/config' \
        && ok "~/.ssh/config (호스트 목록 — github 키는 이 기계 것으로)"
    fi

    # ⭐ **토큰을 보내는 대신 마스터가 대신 등록한다.**
    #    접속지에 토큰을 주면 그 기계가 마스터와 같은 권한을 갖는다 — 서버 한 대가
    #    털리면 GitHub 전체가 털린다. 공개키만 올리면 그 기계는 **읽기 권한만** 갖고,
    #    나중에 그 키 하나만 지우면 그 기계만 끊긴다.
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      pub="$(ssh "$host" 'cat ~/.ssh/id_ed25519.pub' 2>/dev/null || true)"
      if [ -n "$pub" ]; then
        title="$host ($(date +%Y-%m-%d))"
        if gh ssh-key list 2>/dev/null | grep -qF "$(echo "$pub" | awk '{print $2}')"; then
          skip "GitHub 에 이미 등록된 키다"
        else
          printf '%s\n' "$pub" | gh ssh-key add - --title "$title" >/dev/null 2>&1 \
            && ok "GitHub 에 등록했다 — \"$title\"" \
            || warn "GitHub 등록 실패 (권한 범위? 'gh auth refresh -s admin:public_key')"
        fi
        # 진짜 되는지 본다 — 등록했다는 말보다 붙는 게 증거다
        if ssh "$host" 'ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | head -1' 2>/dev/null | grep -q "successfully authenticated"; then
          ok "이 기계가 GitHub 에 제 열쇠로 붙는다"
        else
          warn "아직 GitHub 인증이 안 된다 (등록 반영에 몇 초 걸릴 수 있다)"
        fi
      fi
    else
      warn "마스터에 gh 로그인이 없다 — 공개키를 손으로 등록해라"
    fi

    warn "🔴 신원(터널 자격·백업 암호)은 **여기서 안 옮긴다** — 비밀번호 관리자를 거쳐라"
  fi
done

echo; c "0;32" "2차 끝."
