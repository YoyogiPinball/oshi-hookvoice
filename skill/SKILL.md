---
name: oshi-hookvoice
description: 推しのシステムボイスを Claude Code・Codex の通知音として鳴らす仕組みを、利用者の環境を調べて導入・変更・削除する。割り当てフォームの回答（「# oshi-hookvoice 割り当てフォームの回答」で始まるテキスト）を渡されたとき、またはシステムボイスや通知音の hook の導入を頼まれたときに使う。
---

# oshi-hookvoice — システムボイスの導入

利用者が割り当てフォームで決めた「どのイベントでどの音を鳴らすか」を、利用者の環境の hook に設定する。
音源はリポジトリに含まれない。利用者が用意したフォルダーを参照する。

同じフォルダーにあるもの:

| パス | 中身 |
|---|---|
| `templates/oshi-hookvoice.sh` | hook から呼ばれて音を鳴らすスクリプト。利用者の環境へコピーして使う |
| `templates/config.example` | 設定ファイルの雛形 |
| `references/wiring.md` | Claude Code・Codex の hook の設定一覧 |
| `references/pitfalls.md` | 作者の環境で起きた問題と対処 |

## 守ること

- 利用者の既存の設定を消さない。hook は配列に**追記**し、書き換える前に設定ファイルをバックアップする
- ファイルを書く前に、変更案（置くファイル・書き換える設定・追加する hook）を利用者に見せて承認を取る
- 音源ファイルを移動・コピー・変換しない。設定ファイルからパスで参照する
- 動作を確認していない環境（macOS・Linux デスクトップ）では、その旨を利用者に伝えてから進める

## 手順

### 1. 回答を読む

回答は次の形のテキスト。`sound_dir` が空なら、フォルダーの場所を利用者に聞く。

```text
# oshi-hookvoice 割り当てフォームの回答
oshi-hookvoice リポジトリの skill/SKILL.md に従ってこの回答のとおりに導入してください。リポジトリ: https://github.com/YoyogiPinball/oshi-hookvoice
sound_dir = D:\voices\推しのシステムボイス
volume = 50

# 応答完了時
sound.stop       = 8_汎用ボイス①.wav | 9_汎用ボイス②.wav
...
# 追加したイベント（行末のコメントが鳴らすタイミング）
sound.custom1    = 10_汎用ボイス③.wav  # テストがすべて通ったとき

# 補足
Codex は使っていません。
```

- `# 補足` 以下は利用者からの自由記述。設定ファイルには写さず、導入の判断に使う
- `sound.<キー>` の値が空のイベントは鳴らさない（hook は設定してよい。あとで設定ファイルのそのキーに音声ファイル（`sound_dir` からの相対パス）を書けば鳴るようになる）

### 2. 環境を調べる

調べた結果を表にして利用者に見せる。

| 調べること | 見方の例 |
|---|---|
| OS の種類と、WSL を使っているか | `uname -s`、`grep -i microsoft /proc/version` |
| 再生手段 | WSL: `command -v powershell.exe`。macOS: `afplay`。Linux: `pw-play` か `paplay` |
| `jq` があるか | `command -v jq`。無ければ導入を提案する（`oshi-hookvoice.sh` が hook の入力を読むのに使う） |
| 使っている AI | `command -v claude codex`。回答の補足も見る |
| 設定ファイル | `~/.claude/settings.json`、`~/.codex/hooks.json`、`~/.codex/config.toml` の `[hooks]` の有無 |
| 既存の hook | 各イベントにどの hook が設定済みか（同じイベントに hook を追加するので、既存の hook と一緒に動かすと問題が起きそうなものは先に利用者へ伝える） |
| Codex を呼ぶ MCP ツール | Claude Code から MCP で Codex を呼んでいるか（`claude mcp list`、`~/.claude.json` の `mcpServers` のキー名だけを見る。値には鍵が入り得るので表示しない）。あれば `mcp__<サーバー名>__.*` を委譲開始・完了の matcher にする。無ければ MCP 用の hook は設定しない（Bash で実行する `codex exec` の開始と終了は、`pre-bash`・`post-bash` で判定する） |
| 音源 | `sound_dir` が読めるか（WSL では Windows 形式のパスを `wslpath -u` で変換して確かめる）。回答に書かれたファイルがすべてあるか |

回答に書かれたファイルが見つからないときは、導入を進める前に利用者へ伝える。

### 3. 変更案を出して承認を取る

既定の置き場所（利用者が別の場所を望めば従う）:

| 置くもの | 場所 |
|---|---|
| スクリプト | `~/.local/bin/oshi-hookvoice.sh`（実行権限を付ける） |
| 設定ファイル | `~/.config/oshi-hookvoice/config`（`templates/config.example` を元に、回答の値を入れる） |
| 状態ファイル | `~/.local/state/oshi-hookvoice/`（スクリプトが自動で作る） |

hook の設定は `references/wiring.md` に従う。追加したイベント（`sound.custom1` など）は、行末のコメントに合う hook を選んで提案する。合う hook が無ければ、その旨と代わりの案を示して利用者に決めてもらう。

- 「テストが通ったとき」のように、特定のコマンドの結果で決まるタイミングは、そのコマンド名と成功の条件を利用者に聞く。聞かずに推測で判定を作らない
- 決まらないうちは設定ファイルにだけ書いておき、「`oshi-hookvoice.sh custom1` を呼べば鳴る」ことを伝える

### 4. 導入する

1. 書き換える設定ファイルをバックアップする（例: `settings.json.bak-<日時>`）
2. スクリプトと設定ファイルを置く
3. hook を追記する。JSON は `jq` で編集し、書き終えたら `jq empty <ファイル>` で JSON として読めることを確かめる

### 5. 確かめる

1. キーごとに音を鳴らす: `oshi-hookvoice.sh test stop`、`oshi-hookvoice.sh test notify` などを、値のあるキーすべてについて実行する。利用者に聞こえたか確かめてもらう
2. 音量を合わせてもらう: 利用者に端末で `oshi-hookvoice.sh volume` を実行してもらう（↑↓ で ±1、←→ で ±5、Space で試聴、Enter で保存）
3. hook の入力と同じ形の JSON をスクリプトの標準入力に渡して、1応答1音の判定を確かめる。判定には、セッションごとの状態ファイル（その応答でブロックがあったか・音を鳴らし終えたかの記録）を使う。`OSHI_HOOKVOICE_MUTE=1` を付けると、判定と状態ファイルの更新は行い、再生だけを止める:

   ```bash
   echo '{"session_id":"t"}' | OSHI_HOOKVOICE_MUTE=1 oshi-hookvoice.sh turn-start
   echo '{"session_id":"t"}' | OSHI_HOOKVOICE_MUTE=1 oshi-hookvoice.sh block
   echo '{"session_id":"t"}' | OSHI_HOOKVOICE_MUTE=1 oshi-hookvoice.sh stop
   cat ~/.local/state/oshi-hookvoice/turn-t   # 「block played」なら、この応答では block の音が1回だけ鳴る判定
   ```
4. Codex を使っているなら、利用者に Codex の `/hooks` で追加した hook を信頼してもらう
5. 新しいセッションを開いて、セッション開始の音と応答完了の音が鳴るか確かめてもらう

確認中に音を止めたいときは、環境変数 `OSHI_HOOKVOICE_MUTE=1` を付けて実行する。

### 6. 報告する

置いたファイル、書き換えた設定とバックアップの場所、確かめたこと、確かめていないこと、外し方（下記）を伝える。

## 変更したいと言われたら

- 音の割り当て・音量だけ: 設定ファイル `~/.config/oshi-hookvoice/config` を直す。hook は触らない
- フォームをやり直した回答を渡されたら: 回答に書かれた設定値で設定ファイルを作り直し、追加したイベントの増減に合わせて hook を追加・削除する

## 外すとき

1. 各設定ファイルから、`oshi-hookvoice.sh` を呼ぶ hook だけを削除する（他の hook は残す。削除前にバックアップ）。`jq` なら次の式で、空になったイベントごと取り除ける:

   ```text
   .hooks |= (with_entries(.value |= map(.hooks |= map(select(.command | test("oshi-hookvoice\\.sh") | not)) | select(.hooks | length > 0))) | with_entries(select(.value | length > 0)))
   ```

2. `~/.local/bin/oshi-hookvoice.sh`・`~/.config/oshi-hookvoice/`・`~/.local/state/oshi-hookvoice/` を、利用者の承認を取って削除する
3. Codex を使っていれば、次の起動で hook の変更が反映される

## 鳴らし方の仕組み（説明を求められたとき）

- 原則は「1応答1音」。応答の終わりに、応答完了・危険な操作をブロック・エラーで中断・承認待ちのどれか1つだけが鳴る。承認待ちで止まったときも、そこで応答1回と数える。別ウィンドウで動かしているセッションの応答がどう終わったかを画面を見ずに音で知るため
- コミット完了・委譲開始と完了・セッションの開始と終了・/compact 完了は、その場で鳴る
- Claude Code から呼ばれた Codex や `claude -p`、サブエージェントの中では鳴らない（委譲先の判定）
- 詳しくは `templates/oshi-hookvoice.sh` の冒頭コメント
