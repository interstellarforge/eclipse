#!/bin/zsh
# Watches that Eclipse's offline mode really keeps footage away from Claude. Read-only: it changes nothing.
#   scripts/offline-watch.sh          watch, refresh every 3 s (Ctrl-C to stop)
#   scripts/offline-watch.sh --once   one report
# Checks: 1) the blocked tools are hidden, 2) get_frame is refused, 3) no image ever reached a Claude transcript since you started
# watching, 4) which processes hold internet connections.
PORT=39127
TOKEN_FILE="$HOME/Library/Application Support/MovieMaker/mcp-token"
TRANSCRIPTS=(~/.claude/projects/*MovieMaker-assistant*/*.jsonl(N))
BLOCKED=(inspect_asset watch_asset watch_timeline get_frame transcribe_asset auto_captions find_match_cuts smart_reframe)
START=$(date +%s)

# image blocks in transcripts last modified after we started (baseline = count when we started)
count_images() { [[ ${#TRANSCRIPTS[@]} -gt 0 ]] && cat "${TRANSCRIPTS[@]}" 2>/dev/null | grep -o '"type":"image"' | wc -l | tr -d ' ' || echo 0; }
BASE=$(count_images)

report() {
  local now offline=ok tools list code
  now=$(date +%T)
  [[ -r "$TOKEN_FILE" ]] || { echo "[$now] Eclipse is not running (no MCP token)."; return; }
  local token; token=$(<"$TOKEN_FILE")
  list=$(curl -s -m 3 -X POST "http://127.0.0.1:$PORT/mcp" -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
  [[ -n "$list" ]] || { echo "[$now] Eclipse does not answer on port $PORT."; return; }
  local exposed=()
  for t in $BLOCKED; do [[ "$list" == *"\"name\":\"$t\""* ]] && exposed+=($t); done
  local selection=no; [[ "$list" == *'"name":"request_selection"'* ]] && selection=yes

  echo "[$now] ------------------------------------------------"
  if [[ ${#exposed[@]} -eq 0 && $selection == yes ]]; then
    echo "  OFFLINE  : ON  (blocked tools hidden, request_selection offered)"
  elif [[ ${#exposed[@]} -eq ${#BLOCKED[@]} ]]; then
    echo "  OFFLINE  : OFF (all analysis tools are available to Claude)"
  else
    echo "  OFFLINE  : !! PARTIAL, exposed: ${exposed[*]}"
  fi
  code=$(curl -s -m 3 -X POST "http://127.0.0.1:$PORT/mcp" -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_frame","arguments":{"time_ms":0}}}')
  if [[ "$code" == *"Offline mode is on"* ]]; then echo "  get_frame: refused (good)"
  else echo "  get_frame: answers (expected when offline mode is OFF; a problem if it is ON)"; fi

  local now_images; now_images=$(count_images)
  local new=$(( now_images - BASE ))
  if [[ $new -le 0 ]]; then echo "  IMAGES   : none sent to Claude since this watch started"
  else echo "  IMAGES   : !! $new image block(s) reached a Claude transcript since this watch started"; fi

  echo "  NETWORK  : internet connections (Eclipse and the agent it started; your other Claude sessions are skipped)"
  local name pid conns cwd shown=0
  for name in MovieMaker claude codex opencode; do
    for pid in $(pgrep -x "$name" 2>/dev/null); do
      if [[ $name != MovieMaker ]]; then
        cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | awk '/^n/ {print substr($0,2)}')
        [[ "$cwd" == *MovieMaker/assistant* ]] || continue
      fi
      conns=$(lsof -nP -i -a -p "$pid" 2>/dev/null | awk 'NR>1 && /ESTABLISHED/ {print $9}' | sed 's/.*->//' | sort -u | tr '\n' ' ')
      echo "    $name ($pid): ${conns:-no open connections}"; shown=1
    done
  done
  [[ $shown == 0 ]] && echo "    nothing running"
}

if [[ "$1" == "--once" ]]; then report; exit 0; fi
while true; do clear; echo "Eclipse offline watch (Ctrl-C to stop). Image baseline: $BASE"; report; sleep 3; done
