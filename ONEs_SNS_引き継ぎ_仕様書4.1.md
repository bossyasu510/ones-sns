# ONEs SNS 引き継ぎ仕様書 ver4.1

**最終更新日**: 2026年4月28日（火）01:15 JST  
**プロジェクト名**: ONEs SNS（brandyou.love）  
**コンセプト**: 招待制クローズドSNS（mixi風・グリーンテーマ）  
**キャッチコピー**: つながりを、ひとつに。

> **ver4.1 更新内容**: トラブルシューティング事例追加、git revert後の状態反映

---

## 📋 プロジェクト基本情報

### 技術構成
- **フロントエンド**: index.html単体（HTML/CSS/JS全部入り）
- **バックエンド**: Supabase（PostgreSQL）
- **ホスティング**: Vercel（自動デプロイ）
- **作業ディレクトリ**: `~/Desktop/ones-sns/`
- **本番URL**: brandyou.love

### 開発ワークフロー
```
1. Claudeでプロンプト作成
2. Cursorに貼り付け
3. Cmd+Shift+Y で承認
4. ターミナルで:
   cd ~/Desktop/ones-sns && git add . && git commit -m "メッセージ" && git push origin main
5. Vercel自動デプロイ(1〜2分)
6. PC: Cmd+Shift+R / スマホ: Safari履歴クリア
```

---

## 🚨 トラブルシューティング事例集（重要・必読）

### 🔴 事例1: PCブラウザで「くるくる」が止まらない（2026-04-28発生）

**症状**: 
- PCで brandyou.love をリロードしたら、マウスのくるくるが止まらない
- 画面は表示されているが、操作不能
- スマホでは正常動作

**原因**: 
**PCブラウザのJavaScriptキャッシュ汚染**
- 1日に13回 git push → Vercelデプロイを繰り返すと、ブラウザに古いJSインスタンスが累積
- 特に `setInterval(updateAllBadges, 30000)` のようなバックグラウンドタイマーが新コードに切り替わっても古いものが動き続ける
- 結果、CPU使用率が爆上がりしてくるくる発生

**解決方法**: 
1. ブラウザを完全に閉じる(全タブ・全ウィンドウ)
2. ブラウザを起動し直す
3. brandyou.love を開く

**または**:
- **シークレットウィンドウ**で開く（Cmd+Shift+N）→ 5秒で原因切り分け可能
- **Cmd+Shift+R**（ハードリロード）

**予防策**:
- 開発中はシークレットウィンドウで動作確認
- git push 後は必ずキャッシュクリア
- 1日の作業終了時にブラウザ完全リセット

---

### 🔴 事例2: Supabase SQL Editorで `DO $$ ... END $$;` がエラー

**症状**:
```
ERROR: 42601: unterminated dollar-quoted string at or near "$$
```

**原因**: 
Supabase SQL Editorは `$$` を含むPL/pgSQL構文の処理が不安定

**解決方法**:
- DOブロックを使わず、**個別のDELETE文を並べる**方式に変更

**例**:
```sql
-- ❌ 動かない
DO $$
BEGIN
  DELETE FROM ...;
END $$;

-- ✅ 動く
DELETE FROM stamps WHERE user_id = 'xxx';
DELETE FROM diaries WHERE author_id = 'xxx';
DELETE FROM members WHERE id = 'xxx';
```

---

### 🔴 事例3: 外部キー制約エラー

**症状**:
```
ERROR: 23503: update or delete on table "members" violates foreign key constraint
DETAIL: Key (id)=(xxx) is still referenced from table "invite_codes"
```

**原因**: 
削除しようとしているメンバーが、他のテーブルから参照されている

**解決方法**:
**参照先テーブルから先に削除**

例: members を削除する前に、invite_codes から該当データを削除：
```sql
DELETE FROM invite_codes WHERE issued_by_id = 'xxx' OR used_by = 'xxx';
DELETE FROM members WHERE id = 'xxx';
```

---

### 🔴 事例4: UUID型カラムへの文字列ID挿入エラー

**症状**:
```
ERROR: 22P02: invalid input syntax for type uuid: "m1777122263581"
```

**原因**: 
`member_tags.member_id` が UUID型なのに、members.id は text型（文字列）

**解決方法**:
- 該当テーブルの操作をスキップ
- 後日、`ALTER TABLE member_tags ALTER COLUMN member_id TYPE text;` で型を変更

---

### 🔴 事例5: スマホで自分の写真が表示されない（2026-04-27解決済み）

**症状**: 
- PC: 自分の投稿アイコンが写真で表示
- スマホ: 自分の投稿アイコンが絵文字のまま

**原因**:
**PCとスマホで別アカウントにログインしていた**
- PCで作成: m1777192483966（写真あり）
- スマホで作成: m1777083763025（写真なし）

招待リンクから登録するシステムだと、別デバイスで同じURLを開いても**新規アカウントとして作られる**ため発生。

**解決方法**:
1. デバッグボタン「写真状態を確認」で currentUser.id を表示
2. PCとスマホで異なるIDが判明
3. Supabaseで古いアカウント（スマホ側）を削除
4. スマホでキャッシュクリア → PC側のアカウントで再ログイン

**根本対策**: 
ログイン機能の実装（Phase 2-3で対応予定）

---

### 🔴 事例6: 重複アカウント（ダブルタップ事故）

**症状**: 
- 同じ名前のメンバーが0.05秒以内に2つ作成される
- 例: カズポン×2、キラリン×2

**原因**: 
登録ボタンの連打防止が無く、ダブルタップで同時実行

**解決方法**:
1. 古い方を残し、新しい方を削除（履歴・LocalStorageが古い方を覚えている可能性）
2. **invite_codes に外部キー制約**があるので、削除前に先にinvite_codesも削除

**根本対策**: 
Phase 4 で重複作成防止コードを実装予定
- 登録ボタン押下後 disabled
- サーバー側でも重複チェック
- 同名・同時刻の判定

---

## 🛡️ Git緊急復旧手順

問題のあるコードをデプロイしてしまった時の復旧方法：

### 直近のコミットを取り消す（履歴は残す）
```bash
cd ~/Desktop/ones-sns
git log --oneline -10
# 取り消したいコミットIDを確認

git revert <コミットID> --no-edit
git push origin main
```

### 強制的に前バージョンに巻き戻す（履歴を上書き）
```bash
cd ~/Desktop/ones-sns
git log --oneline -10

git reset --hard <戻したい時点のコミットID>
git push origin main --force
```

### 復旧後の確認
1. Vercelデプロイ完了まで1〜2分待つ
2. ブラウザを完全に閉じる
3. brandyou.love を開き直す
4. 動作確認

---

## 🗄️ データベース構造（Supabase 全15テーブル）

### メインテーブル

| テーブル | 主要カラム | 用途 |
|---|---|---|
| **members** | id, name, emoji, photo, bio, gender, age, location, job, hobby, birthday | メンバー情報 |
| **diaries** 📖 | id, **author_id**, author_name, author_emoji, title, body, visibility, good | 日記 |
| **voices** 💬 | id, **author_id**, author_name, author_emoji, body, good | つぶやき |
| **photos** 📷 | id, **author_id**, author_name, author_emoji, photo_url, caption, visibility | 写真 |
| **comments** | id, topic_id, **author_id**, author_name, author_emoji, body | コメント |
| **stamps** | id, record_id, table_type, **user_id**, emoji | スタンプ・リアクション |
| **footprints** 👣 | id, **visitor_id**, visitor_name, visitor_emoji, visited_id, visited_name | 足あと |
| **messages** 💌 | id, **from_id**, from_name, from_emoji, **to_id**, to_name, to_emoji, body | メッセージ |
| **wanmik** 👥 | id, **from_id**, to_id, from_name, to_name | ワンミク（友達関係） |
| **communities** 🏘️ | id, name, emoji, description, category, visibility, **owner_id**, owner_name | コミュニティ |
| **topics** | id, community_id, community_name, **author_id**, author_name | トピック |
| **notifications** 🔔 | id, user_id | お知らせ |
| **invite_codes** 🎫 | id, code, issued_by, **issued_by_id**, used_by, status, created_at | 招待コード |
| **member_tags** | id, **member_id (UUID型 ⚠️)** | 興味タグ |
| **message_folders** | id, owner_id, member_id | メッセージフォルダ |

### 🔐 ログイン機能用カラム（2026-04-28追加）

`members` テーブルに以下を追加済み：

| カラム名 | 型 | デフォルト | 用途 |
|---|---|---|---|
| **passphrase_hash** | text | NULL | 合言葉のSHA-256ハッシュ |
| **passphrase_salt** | text | NULL | 合言葉のソルト |
| **has_passphrase** | boolean | false | 合言葉設定済みフラグ |
| **last_login_at** | timestamptz | NULL | 最終ログイン日時 |
| **login_fail_count** | integer | 0 | ログイン失敗回数 |
| **locked_until** | timestamptz | NULL | アカウントロック解除時刻 |
| **invited_by_id** | text | NULL | 招待者ID |
| **invited_by_name** | text | NULL | 招待者名 |

### ⚠️ 既知の不具合

1. **member_tags.member_id が UUID型** なのに、members.id が text型
   - 型不一致のため、文字列IDのメンバーは member_tags に登録不可
   - **修正方針**: `ALTER TABLE member_tags ALTER COLUMN member_id TYPE text;` 

---

## ✅ 実装完了機能一覧

### コア機能
1. **メッセージ機能** 💌（mixi風・件名・タブ・60日自動削除）
2. **足あと機能** 👣（時系列・スパム防止）
3. **メンバー一覧「みんな」** 👥（興味合致順）
4. **カレンダー機能** 📅（ワンミク公開・参加表明）
5. **お知らせ・通知機能** 🔔（自動生成・既読管理）
   - ヘッダー🔔 = 全通知 / フッター💌 = メッセージのみ未読
6. **アイコン写真化対応** 🖼️
7. **プロフィール統計の実データ化**

### プロフィール強化（2026-04-27〜28）
8. **プロフィール画面カード型リニューアル**
9. **プロフィール項目拡張**（居住地・職業・年齢・誕生日・趣味・性別）

### コミュニティ機能（2026-04-28）
10. **コミュニティ主催者写真表示**
11. **コミュニティ作成 絵文字選択UI**（40種類）

### ナビゲーション（2026-04-28）
12. **ハンバーガーメニュー☰**（11項目）
13. **マイページ「📋 その他メニュー」**（6項目）

### デバッグ機能
14. **写真状態確認・強制再読込ボタン**

### ⚠️ 取り消した機能（2026-04-28 git revert）
- **プロフィール編集UX改善**（2000文字制限・インライン警告・✕ボタン）
  - 取り消し理由: PCでくるくるバグの原因と疑われたため、安全のため revert
  - 状態: コミット `87a6ec1` を `720c51a` でrevert済み
  - 再実装方針: より軽量な実装で Phase 6 として再挑戦予定

---

## 🧹 データクリーンアップ実施記録（2026-04-28）

### 重複アカウント削除
**実施前**: 31名（うち6名が3組の重複）  
**実施後**: 28名（クリーン）

#### 削除したアカウント
1. **カズポン2** (`m1777122263581`) - 同名重複（ダブルタップ事故）
2. **キラリン2** (`m1777183600700`) - 同名重複（ダブルタップ事故）
3. **BOSS_YASU新** (`m1777187821668`) - 重複（テストアカウント）

#### 残したアカウント
1. カズポン1 (`m1777122263433`) - 古い方を採用
2. キラリン1 (`m1777183600588`) - 古い方を採用
3. BOSS_YASU旧 (`m001`) - 本物（活動データ多数：メッセ19、ワンミク25、足あと6）

#### 削除手順（再現性のため記録）
```sql
-- カズポン2 削除（他2名も同じ手順）
DELETE FROM stamps WHERE user_id = 'm1777122263581';
DELETE FROM comments WHERE author_id = 'm1777122263581';
DELETE FROM diaries WHERE author_id = 'm1777122263581';
DELETE FROM voices WHERE author_id = 'm1777122263581';
DELETE FROM photos WHERE author_id = 'm1777122263581';
DELETE FROM messages WHERE from_id = 'm1777122263581' OR to_id = 'm1777122263581';
DELETE FROM wanmik WHERE from_id = 'm1777122263581' OR to_id = 'm1777122263581';
DELETE FROM footprints WHERE visitor_id = 'm1777122263581' OR visited_id = 'm1777122263581';
DELETE FROM topics WHERE author_id = 'm1777122263581';
DELETE FROM communities WHERE owner_id = 'm1777122263581';
DELETE FROM notifications WHERE user_id = 'm1777122263581';
DELETE FROM invite_codes WHERE issued_by_id = 'm1777122263581' OR used_by = 'm1777122263581';
DELETE FROM members WHERE id = 'm1777122263581';
```

**注意**: member_tagsはUUID型エラー出るためスキップ

---

## 🎯 解決済みPENDING問題

- ✅ **問題1**: スマホで自分の投稿アイコンが写真にならない → 別アカウント問題で解決
- ✅ **問題2**: openUserSheet の項目表示不足 → プロフィールカード化で解決
- ⏳ **問題3**: 取扱説明書・ヘルプ11カテゴリ拡張版 → 未着手（Phase 5以降）

---

## 🔐 ログイン機能 実装計画（Phase 1-6）

### ✅ Phase 0: データクリーンアップ（2026-04-28完了）
- 重複アカウント3名削除
- 31名 → 28名のクリーン状態に

### ✅ Phase 1: DB拡張（2026-04-28完了）
members テーブルに8カラム追加完了

### ⏳ Phase 2: 既存ユーザーへの強制合言葉設定モーダル
**目的**: 28名全員に合言葉を設定してもらう

**実装内容**:
- 起動時 has_passphrase をチェック
- false の場合、強制モーダル表示（閉じられない）
- 合言葉入力（2回確認）
- SHA-256でハッシュ化（クライアント側）
- ソルトはランダム生成
- has_passphrase = true で更新

**ハッシュ化コード例**:
```javascript
async function hashPassphrase(passphrase, salt){
  var msgBuffer = new TextEncoder().encode(passphrase + salt);
  var hashBuffer = await crypto.subtle.digest('SHA-256', msgBuffer);
  var hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

function generateSalt(){
  var arr = new Uint8Array(16);
  crypto.getRandomValues(arr);
  return Array.from(arr).map(b => b.toString(16).padStart(2, '0')).join('');
}
```

### ⏳ Phase 3: ログイン画面・ログアウト機能
- 別デバイスからアクセス時のログイン画面
- 「名前 + 合言葉」入力 → ハッシュ照合
- 失敗5回でロック・1時間
- 成功時に LocalStorage に member_id 保存

### ⏳ Phase 4: 重複アカウント作成防止
- 名前 + 招待コードで unique 制約
- 登録ボタン disabled処理
- 同名・同時刻の判定

### ⏳ Phase 5: 招待リンク発行機能の整備
- 既存 invite_codes テーブル活用
- マイページに「招待リンク発行」ボタン
- ランダム招待コード生成（UUID v4）
- 有効期限7日間

### ⏳ Phase 6: プロフィール編集UX改善（再挑戦）
- 2000文字制限
- インライン警告
- ✕ボタン
- **より軽量な実装**で「くるくるバグ」を回避

---

## 🎨 重要な共通関数

### renderProfileCard(member, isMyself)
プロフィールカード表示（マイページ・openUserSheet両用）

### postAvatarHtml(post)
投稿アイコン統一表示

### avatarHtmlFor(member, size)
任意サイズのアバター（CSS依存なし）

### getPhotoFor(memberId)
写真の優先順位取得（currentUser → cache → LocalStorage）

### loadAllPhotos()
全員分の写真を一括ロード

### syncMyPhoto()
自分の写真を最新化

### debugPhotoStatus()
写真キャッシュの状態確認（マイページのデバッグボタンから）

### showToast(msg)
成功通知のトースト表示（※ revert後は削除されている可能性あり）

---

## 🛠️ 運用ノウハウ

### スマホでデバッグする方法
1. マイページ → 「🔧 デバッグ」セクション
2. 「写真状態を確認」ボタン
3. アラートで currentUser.id, photo, cache size 等を確認

### スマホでキャッシュクリア
- iPhone設定 → Safari → 履歴とWebサイトデータを消去

### PCでキャッシュクリア
- **Chrome**: Cmd+Shift+Delete → 全期間 → Cookie+キャッシュ
- **Safari**: Safari → 履歴を消去 → すべての履歴

### PCで開発中のおすすめ
- **シークレットウィンドウ**で動作確認（Cmd+Shift+N）
- 毎回まっさらな状態でテストできる

### 強制ログアウト用ブックマークレット
```javascript
javascript:if(confirm('ログアウト&全データクリア?')){localStorage.clear();sessionStorage.clear();location.reload();}
```

---

## 📊 現在のメンバー28名（2026-04-28時点）

```
m001 - BOSS YASU(管理者)
m1777099014251 - ヴィーナスグロウ
m1777119790284 - 坂本龍馬
m1777119808688 - ku_mi.world
m1777119855219 - 快晴
m1777119859403 - Junko
m1777120111818 - yukko
m1777120167113 - makico*
m1777120229824 - ゆうなみ
m1777120243518 - KHO*
m1777122263433 - カズポン
m1777122581956 - msy
m1777122723061 - マサヨ
m1777124057882 - よんろ
m1777130111353 - k.manmo
m1777133483047 - ぐみーる
m1777134292375 - えみ
m1777161812088 - MIKI
m1777170589971 - mai758
m1777170866910 - Chinarin
m1777177626145 - YU-KO
m1777183600588 - キラリン
m1777187100924 - ゆうこ
m1777192483966 - ジローナモ(写真登録済み)
m1777198313060 - HARMIISHI
m1777199757423 - KURARA
m1777251617249 - caco929
m1777276821033 - YUKA0105
```

---

## 🚀 明日（2026-04-29）の予定

### 最優先タスク
1. **Phase 2 実装**: 強制合言葉設定モーダル
2. **Phase 3 実装**: ログイン画面
3. **Phase 4 実装**: 重複作成防止コード

### 中期タスク
4. **Phase 5 実装**: 招待リンク発行機能
5. **Phase 6 実装**: プロフィール編集UX改善（再挑戦）
6. **member_tags の UUID型問題修正**
7. **取扱説明書・ヘルプ11カテゴリ拡張版**（PENDING問題3）

### 着手時のおさらい
- Supabaseはカラム追加完了
- 既存28名は has_passphrase=false の状態
- 今のコードはまだLocalStorage頼み（ログイン認証なし）
- ハンバーガーメニュー・プロフィールカード化等は完成済み
- プロフィール編集UX改善は revert 済み（再実装が必要）

### 注意：開発時の事故防止
- **シークレットウィンドウで動作確認**を習慣化
- 大きな変更後は**git push前に動作確認**
- **setIntervalの使用は慎重に**（くるくるバグの原因になる）

---

## 💡 設計思想・原則

1. **mixi風UX**: 親しみやすく、温かみのある操作感
2. **クローズドSNS**: 招待制で信頼できる仲間と繋がる
3. **モバイルファースト**: スマホで快適に使える
4. **シンプル実装**: index.html単体・Supabase直結でメンテしやすく
5. **段階的改善**: 小さく速くリリース、フィードバックで磨く

---

## 📝 セッション間の引き継ぎプロトコル

新しいClaudeセッションを開始する時：

1. このMarkdownファイルを最初にアップロード
2. 「この仕様書を読み込んで記憶してください」と指示
3. 「Phase ○の続きをやります」と伝える
4. 必要に応じて現在の画面スクショを添付

---

**作成日**: 2026年4月28日（火）01:15 JST  
**作成者**: BOSS YASU + Claude  
**バージョン**: ver4.1  
**変更履歴**:
- ver4.0 (00:51): 初版作成
- ver4.1 (01:15): トラブルシューティング事例6件追加、git revert後の状態を反映

🌟 **明日も最高のONEs SNSにしましょう！** 🌟
