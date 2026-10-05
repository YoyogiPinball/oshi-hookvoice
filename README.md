# oshi-hookvoice

推しのシステムボイスを Claude Code や Codex の通知音として導入する際の補助を行うSKILLです。

どのタイミングでどの音を鳴らすかは設定用の入力フォームを用いてプロンプトを作成し、
実際の設定作業はフォームの回答を受け取った AI が済ませます。

## 音声ファイルは同梱していません

システムボイスは各自で購入・用意したものを使ってください。
フォームで選択したファイルはブラウザの中で読み込むだけで外部には送信しません。

## 使い方

1. `git clone` か ZIP でこのリポジトリを手元に置く
2. `index.html` をブラウザで開く
3. システムボイスのフォルダーを選択してフルパスを入力する
4. 応答完了や承認待ちなど、音を鳴らすタイミング（イベント）ごとに音を選択する
5. 「回答をコピー」を押して Claude Code か Codex に貼り付ける
6. AI が出す変更案を確かめて承認する
7. AI の案内に従って音が鳴るか確かめる

導入のときに、AI がこの手順書をスキルとして手元にコピーします。
あとで音を替えたいときや外したいときは、AI に「推しボイスの音を替えて」「推しボイスを外して」と頼むだけで済みます。

面倒だったりよく分からなかったらAIにこのページのURLを渡して導入をサポートしてもらうと楽です。

## リポジトリの中身

| パス | 中身 |
|---|---|
| `index.html` | 設定用フォーム |
| `skill/SKILL.md` | 導入を担当する AI が読む手順書 |
| `skill/templates/oshi-hookvoice.sh` | hook（応答完了などのタイミングで、設定したコマンドを Claude Code や Codex が実行する機能）から呼ばれて音を鳴らすスクリプト。導入時に AI が利用者の環境へコピーする |
| `skill/templates/config.example` | 設定ファイルの雛形 |
| `skill/references/` | hook の設定一覧と、作者の環境で起きた問題への対処 |

## イベント

| イベント | 鳴るとき | Claude Code の hook | Codex の hook |
|---|---|---|---|
| 応答完了 | 応答が終わったとき | `Stop` | `Stop` |
| 危険な操作をブロック | auto モードの判定で操作が拒否されたとき | `PermissionDenied` | 鳴らない |
| エラーで中断 | API エラーなどで応答が止まったとき | `StopFailure` | 鳴らない |
| 承認待ち | コマンドの実行やファイル編集の承認を求められたとき | `Notification` | `PermissionRequest` |
| コミット完了 | `git commit` が通ったとき | `PostToolUse`（Bash） | `PostToolUse`（Bash） |
| 委譲開始 | Claude Code から Codex に作業を依頼したとき | `PreToolUse` | 鳴らない |
| 委譲完了 | Codex に依頼した作業が終わったとき（バックグラウンドで実行した `codex exec` では鳴らない） | `PostToolUse` | 鳴らない |
| セッション開始 | 起動したときと再開したとき | `SessionStart` | `SessionStart` |
| セッション終了 | 終了したとき | `SessionEnd` | `SessionEnd` |
| /compact 完了 | 手動で /compact を実行したとき | `PostCompact` | `PostCompact` |

表の上から4つは、応答が最終的にどう終わったかで鳴る音が決まり、1回の応答につき1つだけ鳴ります。
応答の途中で操作が拒否された場合は、応答完了時にブロックの音が鳴ります。
承認待ちで止まったときはそこまでを1回の応答と数えます。
ほかのイベントは起きたその場で鳴ります。

Claude Code の承認待ちの音は、承認を求める画面が出てから約6秒、何も入力しなかったときに鳴ります（Claude Code の仕様）。

Codex では、セッション開始の音は起動した時点ではなく、最初のメッセージを送ったときに鳴ります。
また `/exit` で画面を閉じてもセッションはすぐには終わらないため、セッション終了の音はその場では鳴りません。

危険なコマンドを止める自作の hook からもブロックの音を鳴らせます。
自作の hook から再生スクリプトを呼ぶ方法は `skill/references/wiring.md` を見てください。

表にないタイミングで鳴らしたいときはフォームの「イベントを追加」で足せます。
どの hook で鳴らすかは回答を受け取った AI が環境に合わせて決めます。

## 参考にした公式ドキュメント

| ページ | 内容 |
|---|---|
| [Claude Code: Hooks reference](https://code.claude.com/docs/en/hooks) | hook のイベント一覧と、hook に渡される入力 |
| [Claude Code: Notification](https://code.claude.com/docs/en/hooks#notification) | 承認待ちなどの通知が出る条件（約6秒の待ち時間を含む） |
| [Claude Code: Automate actions with hooks](https://code.claude.com/docs/en/hooks-guide) | hook の設定のしかた |
| [Codex: Hooks](https://developers.openai.com/codex/hooks) | Codex の hook のイベント一覧と設定のしかた |

## 動作確認済みの環境

- Windows 11 ＋ WSL2（Ubuntu）
- Claude Code、Codex CLI
- フォームは Chromium（Chrome や Edge のもとになっているブラウザ）で確認

ほかの環境では確認していません。

## 作者

[YoyogiPinball](https://yoyogipinball.github.io/)
