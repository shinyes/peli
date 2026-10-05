# memos_api

纯 Dart 实现的 [memos](https://github.com/usememos/memos) **0.31.0** 服务端 API 客户端。

- 只支持 memos 0.31.0 的 v1 REST（grpc-gateway / protojson）
- 认证走 Personal Access Token（`Authorization: Bearer memos_pat_...`）
- 零重型依赖（只用 `package:http`），可脱离 Flutter 使用与测试

```dart
final client = MemosClient(
  baseUrl: Uri.parse('https://memos.example.com'),
  accessToken: 'memos_pat_xxx',
);

final profile = await client.getProfile();
final page = await client.listMemos(pageSize: 50, orderBy: 'update_time desc');
for (final memo in page.memos) {
  print('${memo.name} ${memo.content}');
}
```

主要能力：`signIn` / `createPersonalAccessToken` / `getProfile` / `getCurrentUser` /
`listMemos` / `createMemo` / `updateMemo` / `deleteMemo` / `setMemoAttachments` /
`createAttachment`（含分片上传）/ `deleteAttachment` / `getUserStats` / `getGeneralSetting` / `listMemoViews`。
