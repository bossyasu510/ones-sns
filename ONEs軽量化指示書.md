# ONEs 軽量化・拡張性改善 指示書

目的は、現在 `members.photo` に入っているBase64画像による重さを解消し、**写真Storage化 + 取得制限 + キャッシュ** で500人規模に近づけること。

## 1. プロフィール写真をSupabase Storage化

現在は `members.photo` にBase64を保存しているため重い。  
今後は Supabase Storage に画像を保存し、`members.photo` には画像URLのみ保存する。

### 実装方針

- Storageバケット名: `profile-photos`
- アップロードパス: `profiles/<userId>/<timestamp>.jpg`
- `handlePhotoUpload()` で画像を圧縮後、Base64ではなくBlobをStorageへアップロード
- アップロード成功後、`getPublicUrl()` でURL取得
- `members.photo` にURLを保存
- `localStorage` にもURLをキャッシュ
  - `ones_profile_photo_<userId>`
  - `ones_photo_by_name_<name>`

### 注意

- 既存Base64写真は一旦そのまま表示可能にする
- 新規アップロード分からURL形式に移行する
- `img.src` はBase64でもURLでも表示できるため、表示側は大きく変えない

## 2. タイムラインの写真取得をキャッシュ優先に変更

`renderTL()` の投稿者アイコン取得処理を改善する。

### 現在の問題

- `members.photo` を一括取得しており、Base64が混ざると重い
- 名前検索まで行っているため取得量が増える

### 修正方針

- まず `localStorage` から読む
- 未キャッシュの `authorId` のみ Supabase から取得
- `.not('photo', 'is', null)` を付ける
- 名前検索は削除
- 取得したURL/Base64は `localStorage` へキャッシュ

### 差し替えイメージ

```js
var photoMap = {};
authorIds.forEach(function(id){
  var cached = localStorage.getItem('ones_profile_photo_'+id);
  if(cached) photoMap[id] = cached;
});
authorNames.forEach(function(name){
  var cached = localStorage.getItem('ones_photo_by_name_'+name);
  if(cached) photoMap[name] = cached;
});
var uncachedIds = authorIds.filter(function(id){ return !photoMap[id]; });
if(dbReady() && uncachedIds.length > 0){
  try {
    var pr = await sb.from('members')
      .select('id,name,photo')
      .in('id', uncachedIds)
      .not('photo', 'is', null);
    if(pr.data) pr.data.forEach(function(m){
      if(m.photo && m.photo.length > 0){
        photoMap[m.id] = m.photo;
        photoMap[m.name] = m.photo;
        try {
          localStorage.setItem('ones_profile_photo_'+m.id, m.photo);
          localStorage.setItem('ones_photo_by_name_'+m.name, m.photo);
        } catch(e){}
      }
    });
  } catch(e){
    console.warn('[ONEs] photoMap fetch:', e);
  }
}
```

## 3. 取得件数を制限

一覧系は必ず上限を付ける。

### 対象

- 日記: 最新20件
- つぶやき: 最新30件
- 写真: 最新10件
- メッセージ: 送信/受信それぞれ50件
- コメント: 1投稿あたり最新50件程度
- スタンプ: 表示中投稿のみ

### 修正例

```js
await sb.from('messages')
  .select('*')
  .eq('to_id', currentUser.id)
  .order('created_at', {ascending:false})
  .limit(50);
```

## 4. メッセージ一覧のデバッグ強化

`renderMsgs()` でメッセージが出ない原因を追えるようにする。

```js
var r1 = await sb.from('messages').select('*')
  .eq('to_id', currentUser.id)
  .order('created_at', {ascending: false})
  .limit(50);
console.log('[ONEs] messages r1:', r1.data, r1.error);

var r2 = await sb.from('messages').select('*')
  .eq('from_id', currentUser.id)
  .order('created_at', {ascending: false})
  .limit(50);
console.log('[ONEs] messages r2:', r2.data, r2.error);
```

## 5. Supabase側の準備

Storageバケットを作成。

```sql
-- members.photo はURL保存用としてtextのままでOK
alter table public.members
  add column if not exists photo text;

-- RLS無効運用の場合
alter table public.members disable row level security;
```

Supabase Storageで以下を作成:

- Bucket name: `profile-photos`
- Public bucket: `ON`

## 6. 完了条件

以下を確認できれば完了。

- 新規プロフィール写真がStorageに保存される
- `members.photo` にはBase64ではなくURLが入る
- マイページ、ヘッダー、TL、ワンミク一覧で写真が表示される
- TL表示が以前より軽い
- メッセージ一覧が `.limit(50)` で取得される
- コンソールで `messages r1/r2` の取得結果が確認できる

## 7. 優先順位

1. `renderTL` のphotoMapキャッシュ化
2. `renderMsgs` の `.limit(50)` + ログ追加
3. 新規プロフィール写真アップロードをStorage化
4. ワンミク一覧・プロフィール表示の写真URL対応確認

この順番で進めると、壊れにくく効果が出やすいです。

## 8. 既存Base64データの扱い（追記・確定）

- `members.photo` が Base64 でも URL でも `img.src` で表示可能とする
- 既存ユーザーが新しい写真をアップロードした時点で、Storage URL方式に自動で置き換える
- 一括移行スクリプトは作成しない（リスク回避）
