#!/usr/bin/env bash
# Claude Code status line — modernized with Nerd Font glyphs + truecolor

input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
tokens_used=$(echo "$input" | jq -r '.context_window.used_tokens // empty')
tokens_total=$(echo "$input" | jq -r '.context_window.total_tokens // empty')
plan_used=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')

dir=$(basename "$cwd")

# ── Git info ───────────────────────────────────────────────────────
branch=""
git_state=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" -c core.fsmonitor=false symbolic-ref --short HEAD 2>/dev/null \
    || git -C "$cwd" -c core.fsmonitor=false rev-parse --short HEAD 2>/dev/null)

  if ! git -C "$cwd" -c core.fsmonitor=false diff --quiet 2>/dev/null \
    || ! git -C "$cwd" -c core.fsmonitor=false diff --cached --quiet 2>/dev/null; then
    git_state="±"
  fi

  upstream=$(git -C "$cwd" -c core.fsmonitor=false rev-list --left-right --count @{u}...HEAD 2>/dev/null)
  if [ -n "$upstream" ]; then
    behind=$(echo "$upstream" | awk '{print $1}')
    ahead=$(echo "$upstream" | awk '{print $2}')
    [ "$ahead" -gt 0 ] 2>/dev/null && git_state="${git_state}↑${ahead}"
    [ "$behind" -gt 0 ] 2>/dev/null && git_state="${git_state}↓${behind}"
  fi
fi

# ── Truecolor palette (Catppuccin-inspired) ────────────────────────
FG_DIR="\033[38;2;137;180;250m"       # blue
FG_BRANCH="\033[38;2;203;166;247m"    # mauve
FG_DIRTY="\033[38;2;243;139;168m"     # red/pink
FG_MODEL="\033[38;2;249;226;175m"     # yellow
FG_SES_LOW="\033[38;2;137;220;235m"   # sky     (session used low)
FG_SES_MID="\033[38;2;249;226;175m"   # yellow  (session used mid)
FG_SES_HIGH="\033[38;2;250;179;135m"  # peach   (session used high)
FG_PLAN_LOW="\033[38;2;166;227;161m"  # green   (plan usage low)
FG_PLAN_MID="\033[38;2;249;226;175m"  # yellow  (plan usage mid)
FG_PLAN_HIGH="\033[38;2;243;139;168m" # red     (plan usage high)
FG_BAR_EMPTY="\033[38;2;69;71;90m"    # dim gray
FG_SEP="\033[38;2;88;91;112m"         # subtle gray
FG_PCT="\033[38;2;205;214;244m"       # off-white
RESET="\033[0m"

SEP=" $(printf "${FG_SEP}›${RESET}") "

# ── Helper: render a block bar ─────────────────────────────────────
# Usage: make_bar <filled_color> <filled_count> <empty_count>
make_bar() {
  local color="$1" filled="$2" empty="$3" bar=""
  [ "$filled" -gt 0 ] && bar+=$(printf "${color}%*s${RESET}" "$filled" "" | tr ' ' '▓')
  [ "$empty" -gt 0 ]  && bar+=$(printf "${FG_BAR_EMPTY}%*s${RESET}" "$empty" "" | tr ' ' '░')
  printf "%b" "$bar"
}

# ── Build segments ─────────────────────────────────────────────────
segments=()

# Directory
segments+=("$(printf "${FG_DIR} %s${RESET}" "$dir")")

# Git
if [ -n "$branch" ]; then
  if [ -n "$git_state" ]; then
    segments+=("$(printf "${FG_BRANCH} %s${FG_DIRTY}%s${RESET}" "$branch" "$git_state")")
  else
    segments+=("$(printf "${FG_BRANCH} %s${RESET}" "$branch")")
  fi
fi

# Model
if [ -n "$model" ]; then
  segments+=("$(printf "${FG_MODEL}󰧑 %s${RESET}" "$model")")
fi


# Session progress bar (how much has been used — fills up over time)
if [ -n "$remaining" ]; then
  used_pct=$(( 100 - $(printf "%.0f" "$remaining") ))
  [ "$used_pct" -lt 0 ] && used_pct=0
  [ "$used_pct" -gt 100 ] && used_pct=100

  total=8
  filled=$(( (used_pct * total + 50) / 100 ))
  [ "$filled" -gt "$total" ] && filled=$total
  [ "$filled" -lt 0 ] && filled=0
  empty=$(( total - filled ))

  if [ "$used_pct" -le 40 ]; then
    ses_color="$FG_SES_LOW"
  elif [ "$used_pct" -le 70 ]; then
    ses_color="$FG_SES_MID"
  else
    ses_color="$FG_SES_HIGH"
  fi

  # Show human-readable token count if available
  if [ -n "$tokens_used" ] && [ -n "$tokens_total" ]; then
    used_k=$(awk "BEGIN {printf \"%.0f\", $tokens_used/1000}")
    total_k=$(awk "BEGIN {printf \"%.0f\", $tokens_total/1000}")
    label="${used_k}k/${total_k}k"
  else
    label="${used_pct}%"
  fi

  bar=$(make_bar "$ses_color" "$filled" "$empty")
  segments+=("$(printf "󰆒 ${FG_SEP}Token Used${RESET} %b ${FG_PCT}%s${RESET}" "$bar" "$label")")
fi

# Plan usage bar (5-hour session window — fills up, resets on timer)
if [ -n "$plan_used" ]; then
  plan_pct=$(printf "%.0f" "$plan_used")
  [ "$plan_pct" -lt 0 ]   && plan_pct=0
  [ "$plan_pct" -gt 100 ] && plan_pct=100

  total=10
  filled=$(( (plan_pct * total + 50) / 100 ))
  [ "$filled" -gt "$total" ] && filled=$total
  empty=$(( total - filled ))

  if [ "$plan_pct" -le 50 ]; then
    plan_color="$FG_PLAN_LOW"
  elif [ "$plan_pct" -le 80 ]; then
    plan_color="$FG_PLAN_MID"
  else
    plan_color="$FG_PLAN_HIGH"
  fi

  bar=$(make_bar "$plan_color" "$filled" "$empty")

  segments+=("$(printf "󰅒 ${FG_SEP}Session Used${RESET} %b ${FG_PCT}%s%%${RESET}" "$bar" "$plan_pct")")
fi

# ── Join with separator ────────────────────────────────────────────
line=""
for idx in "${!segments[@]}"; do
  [ "$idx" -gt 0 ] && line="${line}${SEP}"
  line="${line}${segments[$idx]}"
done

printf "%b" "$line"
