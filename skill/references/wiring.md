# hook の設定一覧

`<SCRIPT>` は `oshi-hookvoice.sh` を置いた絶対パスに置き換える（例: `/home/you/.local/bin/oshi-hookvoice.sh`）。
既存の設定に**追記**する。同じイベントに既存の hook があっても、消さずに配列へ1件足す。

## Claude Code（`~/.claude/settings.json` の `hooks`）

| イベント | matcher | 引数 | 意味 |
|---|---|---|---|
| `UserPromptSubmit` | なし | `turn-start` | 前の応答の状態ファイル（ブロックがあったか・音を鳴らし終えたかの記録）を消す（鳴らない）。1応答1音に必須 |
| `Stop` | なし | `stop` | 応答完了（ブロックの記録があれば block の音） |
| `StopFailure` | なし | `fail` | API エラーなどで応答が止まった |
| `PermissionDenied` | なし | `block` | auto モードの判定で操作が拒否された（記録を残すだけで、音は応答完了時に鳴る） |
| `Notification` | `permission_prompt\|elicitation_dialog\|agent_needs_input` | `notify` | 承認待ち |
| `PreToolUse` | `Bash` | `pre-bash` | `codex exec` の開始を見分ける |
| `PostToolUse` | `Bash` | `post-bash` | `git commit` の完了と `codex exec` の終了を見分ける |
| `PreToolUse` | Codex を呼ぶ MCP ツール名（例 `mcp__codex__.*`） | `helper-in` | 委譲開始。MCP で Codex を呼んでいない環境では設定しない |
| `PostToolUse` | 同上 | `helper-out` | 委譲完了 |
| `SessionStart` | `startup\|resume` | `start` | セッション開始・再開 |
| `SessionEnd` | なし | `end` | セッション終了 |
| `PostCompact` | `manual` | `compact` | 手動の /compact 完了 |

各エントリーの形（`async: true` で Claude Code の処理を待たせない）:

```json
{ "matcher": "Bash", "hooks": [ { "type": "command", "command": "<SCRIPT> post-bash", "async": true, "timeout": 5 } ] }
```

## Codex（`~/.codex/hooks.json` の `hooks`）

| イベント | matcher | 引数 |
|---|---|---|
| `UserPromptSubmit` | なし | `turn-start` |
| `Stop` | なし | `stop` |
| `PermissionRequest` | なし | `notify` |
| `PostToolUse` | `^Bash$` | `post-bash` |
| `SessionStart` | `startup\|resume` | `start` |
| `SessionEnd` | なし | `end`（`async` を付けない。`references/pitfalls.md` の Codex 節） |
| `PostCompact` | `manual` | `compact` |

- Codex にはエラーで中断・ブロックに当たるイベントが無いので、`fail` と `block` の hook は設定しない
- hook の定義が `~/.codex/hooks.json` と `~/.codex/config.toml` の `[hooks]` の2か所に分かれていると、起動時に警告が出る。既に `config.toml` 側に定義がある環境では、どちらのファイルにまとめるか利用者に確認する
- 追加・変更した hook は、利用者が Codex の `/hooks` で信頼（trust）するまで動かない

## 追加したイベント（`sound.custom1` など）

回答の行末コメントが「鳴らすタイミング」。それに合う hook を選び、引数にキー名（`custom1`）を渡す。
`oshi-hookvoice.sh` は、設定ファイルに `sound.<キー>` があれば、どのキーでもその場で鳴らす。

- 合う hook が無いタイミング（例: 「テストが通ったとき」）は、hook で検知できる形（`PostToolUse` の Bash で特定コマンドの成功を見る、など）を利用者に提案し、決めてもらう
- 検知に `oshi-hookvoice.sh` の改造が要るなら、改造箇所を示して承認を取る

## 危険なコマンドを止める自作の hook があるとき（任意）

危険なコマンドを止める自作の hook（PreToolUse でブロックするもの）がある環境では、
ブロックした箇所で `<SCRIPT> block` を呼ぶと、その応答の完了音が block の音になる。
hook の JSON を標準入力で渡すこと（`session_id` でセッションを見分け、そのセッションの状態ファイルに記録するため）。

```bash
"<SCRIPT>" block <<<"$INPUT"
```
