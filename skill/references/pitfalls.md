# つまずきと対処

作者の環境（Windows 11 + WSL2 Ubuntu、Claude Code、Codex CLI）で実際に起きた問題と、その対処。

## 再生

| 症状 | 原因 | 対処 |
|---|---|---|
| エラーは出ないのに音が鳴らない | Windows の `System.Media.SoundPlayer` は 24bit PCM の wav を再生できず、エラーも出さない。グッズのボイスは 24bit のことが多い | WPF の `MediaPlayer`（Media Foundation 経由）で鳴らす。`oshi-hookvoice.sh` はこちらを使う |
| Windows の音量ミキサーで下げても次の再生で戻る | 再生のたびに新しい PowerShell が起動し、音声セッションが作り直される | 再生音量は設定ファイルの `volume` で指定する（`oshi-hookvoice.sh volume` で調整） |
| 音量ミキサーに PowerShell の行が出ない | 同上。鳴り終わると消える | 同上 |
| PowerShell に環境変数が渡らない | WSL から Windows のプロセスへは、`WSLENV` に名前を並べた変数しか渡らない | `WSLENV="VAR1:VAR2"` を付けて起動する |
| 音が無いのに再生処理が動く | WSL は環境変数 `NAME` にホスト名を入れている。スクリプトの変数名が `NAME` だと初期値を持つ | 変数を使う前に空で初期化する |
| hook がタイムアウトする・応答が遅れる | 再生の終了を待っている | 再生は `setsid nohup ... &` で切り離し、hook は即座に exit 0。Claude Code では `async: true` も付ける |

## 判定

| 症状 | 原因 | 対処 |
|---|---|---|
| 1回の応答で完了音が2回鳴る | 他の Stop hook が応答の続行を求めると、Claude Code が応答を続け、Stop hook がもう一度実行される | 応答ごとの状態ファイルに `played` を書き、2回目は鳴らさない（`oshi-hookvoice.sh` に実装済み） |
| 前の応答の「ブロック」の記録が次の応答に残る | Esc で応答を中断すると、Stop hook が実行されない | `UserPromptSubmit` で状態ファイルを消す。`turn-start` の hook を省かない |
| 承認を求められてもすぐには鳴らない | Claude Code の `Notification`（`permission_prompt`）は、承認の画面が出てから約6秒、何も入力しなかったときに実行される | 仕様どおりの動作。すぐ鳴らしたいときは `PermissionRequest` の hook を使う（作者の環境では未確認） |
| Claude Code が Codex や `claude -p` を呼ぶと、そちらでも鳴る | 委譲先の AI も同じ hook 設定を読む | 祖先プロセスに claude / codex が2つ以上いたら鳴らさない。サブエージェントは hook 入力の `agent_id` で見分ける |
| コマンドが失敗するたびに鳴ってうるさい | `grep` の該当なしや `diff` の差分ありも終了コード 1 になる | コマンドの失敗では鳴らさない。Codex の `PostToolUse` はそもそも終了コードを受け取れない |
| checkout や pull でコミット音が鳴る | HEAD の変化だけで判定している | コマンドに `commit` を含み、かつ HEAD が進んだときだけ鳴らす |

## Codex

| 症状 | 原因 | 対処 |
|---|---|---|
| 起動時に hook の警告が出る | hook の定義が `config.toml` と `hooks.json` の2か所にある | hook の定義を `config.toml` と `hooks.json` のどちらか1か所にまとめる |
| 追加した hook が動かない | 新しい hook・変更した hook は信頼されるまで動かない | 利用者が Codex の `/hooks` で信頼する |
| Codex を開いても開始の音が鳴らない | 作者の環境（Codex 0.160）では、`SessionStart` の hook は起動時ではなく最初のメッセージを送ったときに実行された | 仕様どおりの動作として扱う。確認するときはメッセージを1つ送る |
| `/exit` で閉じても終了の音が鳴らない | Codex の画面は裏で動くサーバーにつながっているだけで、`/exit` では接続が切れるだけ。`SessionEnd` は会話のアーカイブ・削除、Codex の正常終了、どの画面からも開かれないまま30分たったときに実行される（公式文書） | 仕様どおりの動作として扱う |
| `SessionEnd` で `async` が無視される | 公式文書に「`SessionEnd` の hook は `async` が true でも常に同期で実行する」とある | `SessionEnd` だけ `async` を外す |
