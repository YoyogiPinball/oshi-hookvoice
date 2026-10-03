#!/bin/bash
# oshi-hookvoice.sh — Claude Code / Codex の hook から呼ばれ、イベントに合わせてシステムボイスを鳴らす。
#
# 使い方:
#   oshi-hookvoice.sh <イベント>       hook から呼ぶ。hook の JSON は標準入力で受ける
#   oshi-hookvoice.sh volume           端末で音量を合わせる（↑↓ ±1、←→ ±5、Space 試聴、Enter / q 終了）
#   oshi-hookvoice.sh test <キー>      sound.<キー> の音をその場で鳴らす（導入時の確認用）
#
# イベント:
#   notify       承認待ち。応答1回と数え、応答ごとの状態ファイルを消してから鳴らす
#   start / end / fail / helper-in / helper-out / compact   その場で鳴らす
#   turn-start   ユーザーの送信。応答ごとの状態ファイルを消す（鳴らさない）
#   block        操作が拒否された（auto モードの判定か、危険なコマンドを止める自作の hook）。
#                状態ファイルにブロックを記録し、応答完了時に block の音を鳴らす（この時点では鳴らさない）
#   stop         応答完了。1応答につき1回だけ、stop か block の音を鳴らす
#   pre-bash / post-bash   Bash の前後。codex exec の開始と終了、git commit の完了を見分ける
#   その他        設定ファイルに sound.<イベント> があれば、その場で鳴らす（追加したイベント用）
#
# 鳴らし方の原則は「1応答1音」。画面を見ていないセッションの応答がどう終わったか（完了・ブロック・エラー・承認待ち）を音で知るため。
# 状態ファイルは $STATE_DIR にセッションごとに置き、その応答でブロックがあったか・音を鳴らし終えたかを記録する。
# 委譲先（祖先プロセスに claude / codex が2つ以上いる、または Claude Code のサブエージェント）では鳴らさない。
# hook を呼んだ Claude Code・Codex を待たせないよう、再生は別プロセスで行い、常に exit 0 で返す。

EVENT="${1:-}"
CONFIG="${OSHI_HOOKVOICE_CONFIG:-$HOME/.config/oshi-hookvoice/config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/oshi-hookvoice"

# 設定ファイルから1キーの値を取る。行頭 # と「空白 + #」以降はコメント
conf() {
  [[ -r "$CONFIG" ]] || return
  awk -v k="$1" '
    /^[[:space:]]*#/ { next }
    {
      i = index($0, "="); if (!i) next
      key = substr($0, 1, i - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key != k) next
      v = substr($0, i + 1); sub(/[[:space:]]+#.*$/, "", v); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      print v; exit
    }' "$CONFIG"
}

# 音量は 1〜100 の整数。読めない・範囲外なら 50
read_volume() {
  local v
  v=$(conf volume)
  if [[ "$v" =~ ^[0-9]{1,3}$ ]] && ((10#$v >= 1 && 10#$v <= 100)); then
    echo $((10#$v))
  else
    echo 50
  fi
}

# 設定ファイルの volume 行を書き換える（無ければ末尾に足す）
write_volume() {
  local tmp
  [[ -w "$CONFIG" ]] || return
  tmp=$(mktemp "$CONFIG.XXXXXX") || return
  awk -v v="$1" '
    !done && /^[[:space:]]*volume[[:space:]]*=/ { print "volume = " v; done = 1; next }
    { print }
    END { if (!done) print "volume = " v }' "$CONFIG" >"$tmp" && mv "$tmp" "$CONFIG"
}

# 「a | b | c」からランダムに1つ選ぶ
pick() {
  local -a items
  IFS='|' read -ra items <<<"$1"
  ((${#items[@]})) || return
  local item="${items[RANDOM % ${#items[@]}]}"
  item="${item#"${item%%[![:space:]]*}"}"
  echo "${item%"${item##*[![:space:]]}"}"
}

is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

# sound_dir を、このシェルから読めるパスにする（WSL で Windows 形式のパスが書かれていても読めるように）
sound_dir() {
  local dir
  dir=$(conf sound_dir)
  if [[ "$dir" =~ ^([A-Za-z]:[\\/]|\\\\) ]] && is_wsl; then
    dir=$(wslpath -u "$dir" 2>/dev/null) || return
  fi
  echo "$dir"
}

# sound_dir からの相対パスで指定した音声ファイルを、別プロセスで再生する。第2引数で音量（1〜100）を上書きできる
play() {
  local file vol
  # OSHI_HOOKVOICE_MUTE=1 なら、判定や状態ファイルの更新はそのまま行い、再生だけしない（hook のテスト用）
  [[ -n "${OSHI_HOOKVOICE_MUTE:-}" ]] && return
  file="$(sound_dir)/$1"
  [[ -n "$1" && -f "$file" ]] || return
  vol=$(awk -v v="${2:-$(read_volume)}" 'BEGIN { printf "%.2f", v / 100 }')

  if is_wsl && command -v powershell.exe >/dev/null; then
    # Windows の SoundPlayer は 24bit PCM の wav を再生できず、例外も出さないため、
    # Media Foundation 経由で再生する WPF の MediaPlayer を使う（mp3 も鳴る）。
    # 長さが分かるまで待ち、鳴り終わるまで PowerShell を残す。$ は PowerShell 側で展開させる
    # shellcheck disable=SC2016
    local ps_play='Add-Type -AssemblyName PresentationCore
$m = New-Object System.Windows.Media.MediaPlayer
$m.Volume = [double]$env:OSHI_HOOKVOICE_VOL
$m.Open([uri]$env:OSHI_HOOKVOICE_FILE); $m.Play()
$t = 0; while (-not $m.NaturalDuration.HasTimeSpan -and $t -lt 40) { Start-Sleep -Milliseconds 50; $t++ }
$ms = 3000; if ($m.NaturalDuration.HasTimeSpan) { $ms = [int]$m.NaturalDuration.TimeSpan.TotalMilliseconds + 200 }
Start-Sleep -Milliseconds $ms'
    local win_path
    win_path=$(wslpath -w "$file" 2>/dev/null) || return
    # WSLENV に名前を足すと、その環境変数が Windows 側のプロセスにも渡る
    OSHI_HOOKVOICE_FILE="$win_path" OSHI_HOOKVOICE_VOL="$vol" WSLENV="OSHI_HOOKVOICE_FILE:OSHI_HOOKVOICE_VOL${WSLENV:+:$WSLENV}" \
      setsid nohup powershell.exe -NoProfile -NonInteractive -Command "$ps_play" \
      >/dev/null 2>&1 </dev/null &
  elif command -v afplay >/dev/null; then
    # macOS（未確認）
    setsid nohup afplay -v "$vol" "$file" >/dev/null 2>&1 </dev/null &
  elif command -v pw-play >/dev/null; then
    # Linux / PipeWire（未確認）
    setsid nohup pw-play --volume="$vol" "$file" >/dev/null 2>&1 </dev/null &
  elif command -v paplay >/dev/null; then
    # Linux / PulseAudio（未確認）。音量は 0〜65536
    setsid nohup paplay --volume="$(awk -v v="$vol" 'BEGIN { printf "%d", v * 65536 }')" "$file" \
      >/dev/null 2>&1 </dev/null &
  fi
}

# 端末で音量を合わせる。変えるたびに設定ファイルへ保存し、Space で試聴する
volume_cli() {
  [[ -t 0 && -t 1 ]] || { echo "端末から実行してください" >&2; exit 1; }
  [[ -w "$CONFIG" ]] || { echo "設定ファイルがないか、書き込めません: $CONFIG" >&2; exit 1; }
  local vol key rest note="" test_sound
  local c_val=$'\e[1;36m' c_dim=$'\e[2m' c_ok=$'\e[32m' c_mid=$'\e[33m' c_hi=$'\e[31m' c_key=$'\e[35m' c_off=$'\e[0m'
  vol=$(read_volume)
  # 試聴する音: test_sound があればそれ、無ければ応答完了の音から1つ
  test_sound=$(conf test_sound)
  [[ -n "$test_sound" ]] || test_sound=$(pick "$(conf sound.stop)")

  draw() {
    local filled=$((vol / 5)) color=$c_ok bar
    ((vol > 60)) && color=$c_mid
    ((vol > 85)) && color=$c_hi
    bar="$color$(printf '%*s' "$filled" '' | tr ' ' '#')$c_dim$(printf '%*s' $((20 - filled)) '' | tr ' ' '.')$c_off"
    printf '\r\e[K音量 %s%3d%s [%s]  %s↑↓%s ±1  %s←→%s ±5  %sSpace%s 試聴  %sEnter/q%s 終了  %s' \
      "$c_val" "$vol" "$c_off" "$bar" "$c_key" "$c_off" "$c_key" "$c_off" "$c_key" "$c_off" "$c_key" "$c_off" "$note"
  }
  finish() {
    write_volume "$vol"
    printf '\n音量 %s%d%s を保存しました %s(%s)%s\n' "$c_val" "$vol" "$c_off" "$c_dim" "$CONFIG" "$c_off"
    exit 0
  }
  trap finish INT TERM

  draw
  while IFS= read -rsn1 key; do
    note=""
    case "$key" in
      $'\e')
        rest=""
        read -rsn2 -t 0.01 rest
        case "$rest" in
          '[A') vol=$((vol + 1)) ;;
          '[B') vol=$((vol - 1)) ;;
          '[C') vol=$((vol + 5)) ;;
          '[D') vol=$((vol - 5)) ;;
          '') finish ;;
        esac ;;
      ' ')
        if [[ -n "$test_sound" && -f "$(sound_dir)/$test_sound" ]]; then
          play "$test_sound" "$vol"
          note="$c_dim♪ $test_sound$c_off"
        else
          note="${c_hi}試聴する音が見つかりません$c_off"
        fi ;;
      ''|q|Q) finish ;;
    esac
    ((vol > 100)) && vol=100
    ((vol < 1)) && vol=1
    [[ "$key" != ' ' ]] && write_volume "$vol"
    draw
  done
  finish
}

case "$EVENT" in
  volume) volume_cli ;;
  test)
    # 導入時の確認用。委譲先の判定も状態ファイルも見ずに、指定したキーの音を1つ鳴らす
    [[ -n "${2:-}" ]] || { echo "使い方: oshi-hookvoice.sh test <キー>（例: stop）" >&2; exit 1; }
    s=$(pick "$(conf "sound.$2")")
    [[ -n "$s" ]] || { echo "sound.$2 が設定されていません" >&2; exit 1; }
    [[ -f "$(sound_dir)/$s" ]] || { echo "ファイルがありません: $(sound_dir)/$s" >&2; exit 1; }
    play "$s"
    echo "♪ sound.$2 → $s"
    exit 0 ;;
esac

INPUT=""
[[ -t 0 ]] || INPUT=$(cat)

# 祖先に AI（claude / codex）が2つ以上いたら委譲先とみなす。
# Claude Code が呼んだ Codex（MCP・codex exec）も、Claude Code が Bash で起こした claude -p もこれに当たる。
# バックグラウンドで起動されて祖先から Claude Code が外れた Codex に備え、CLAUDECODE（Claude Code が子プロセスへ渡す環境変数）も見る
is_delegated() {
  local pid=$PPID comm agents=0 in_codex=""
  while [[ -n "$pid" && "$pid" -gt 1 ]]; do
    comm=$(cat "/proc/$pid/comm" 2>/dev/null) || break
    case "$comm" in
      claude) agents=$((agents + 1)) ;;
      codex)  agents=$((agents + 1)); in_codex=1 ;;
    esac
    pid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null)
  done
  ((agents >= 2)) || [[ -n "$in_codex" && -n "${CLAUDECODE:-}" ]]
}

is_delegated && exit 0

# Claude Code のサブエージェント内のイベントには agent_id が付く
[[ -n "$INPUT" && -n "$(jq -r '.agent_id // empty' <<<"$INPUT" 2>/dev/null)" ]] && exit 0

# 応答ごとの状態ファイル。session_id ごとに置き、次の送信（turn-start）で消す。
# Esc で応答を中断すると Stop hook が実行されないので、送信の時点で消さないと前の応答の記録が次の応答に残る
SESSION=$(jq -r '.session_id // empty' <<<"$INPUT" 2>/dev/null | tr -cd 'A-Za-z0-9_-')
TURN_FILE="$STATE_DIR/turn-${SESSION:-unknown}"

# Bash で codex exec を実行したか（Codex への作業依頼）
is_delegate_command() {
  jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null | grep -qE '(^|[^[:alnum:]_-])codex +exec\b'
}

# Bash の後始末: コミットが増えていたら commit、前景で codex exec が終わったら helper-out。
# コマンドの失敗では鳴らさない（grep の該当なしなど、失敗でないのに 1 を返すコマンドが多いため）
post_bash() {
  local head key file old
  if is_delegate_command; then
    [[ "$(jq -r '.tool_input.run_in_background // false' <<<"$INPUT" 2>/dev/null)" == true ]] || echo helper-out
    return
  fi
  head=$(git rev-parse HEAD 2>/dev/null) || return
  key=$(git rev-parse --show-toplevel 2>/dev/null | md5sum | cut -c1-12)
  file="$STATE_DIR/head-$key"
  mkdir -p "$STATE_DIR"
  old=$(cat "$file" 2>/dev/null)
  echo "$head" >"$file"
  # HEAD は毎回記録し、commit を含むコマンドで HEAD が進んだときだけ鳴らす（checkout・pull では鳴らさない）
  [[ -n "$old" && "$old" != "$head" ]] || return
  jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null | grep -qE '\bcommit\b' && echo commit
}

# 応答完了。1応答で1回だけ鳴らす（他の Stop hook が応答の続行を求め、Stop hook がもう一度実行されても2度鳴らさない）
on_stop() {
  local state
  state=$(cat "$TURN_FILE" 2>/dev/null)
  [[ "$state" == *played* ]] && return
  mkdir -p "$STATE_DIR"
  echo "$state played" >"$TURN_FILE"
  if [[ "$state" == *block* ]]; then echo block; else echo stop; fi
}

# 環境によっては NAME という環境変数が既にある（WSL はホスト名が入る）ので、必ず空から始める
NAME=""
case "$EVENT" in
  turn-start) rm -f "$TURN_FILE"; exit 0 ;;
  block)      mkdir -p "$STATE_DIR"; echo block >>"$TURN_FILE"; exit 0 ;;
  # 承認待ちも応答1回と数える。ここで区切り、承認後の続きは新しい応答として扱い、前の記録を持ち越さない
  notify)     rm -f "$TURN_FILE"; NAME=notify ;;
  stop)       NAME=$(on_stop) ;;
  pre-bash)   is_delegate_command && NAME=helper-in ;;
  post-bash)  NAME=$(post_bash) ;;
  *)
    # start / end / notify / fail / helper-in / helper-out / compact と、追加したイベント
    [[ "$EVENT" =~ ^[A-Za-z0-9_-]+$ ]] && NAME=$EVENT ;;
esac
[[ -n "$NAME" ]] && play "$(pick "$(conf "sound.$NAME")")"
exit 0
