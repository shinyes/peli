import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:peli/features/web/web_app_page.dart';

/// 分享明文副本的清理（`purgeSharedFiles`）。
///
/// 为什么专门测它：系统分享进来的图片是**明文**落在应用缓存目录里的，而"本地不残留
/// 明文媒体"是本项目的硬约束 —— 前缀写错、或误删引擎/插件的缓存文件，都会破坏这条
/// 约束，而且这类问题在真机上几乎观察不到（缓存目录看不到）。因此放在主机上，用临时
/// 目录把行为钉死。
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('peli-share-purge');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<File> write(String name) async {
    final File file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(<int>[1, 2, 3]);
    return file;
  }

  test('删除 shared_ 前缀的明文副本，保留其它缓存与子目录', () async {
    final File shared1 = await write('shared_1_IMG_0001.jpg');
    final File shared2 = await write('shared_2_IMG_0002.heic');
    final File engineCache = await write('flutter_engine_cache.bin');
    final File noPrefix = await write('IMG_0003.jpg');
    final Directory sub = Directory('${dir.path}${Platform.pathSeparator}webview_uploads');
    await sub.create();
    final File nested = File('${sub.path}${Platform.pathSeparator}shared_nested.jpg');
    await nested.writeAsBytes(<int>[9]);

    final int removed = await purgeSharedFiles(dir);

    expect(removed, 2);
    expect(shared1.existsSync(), isFalse);
    expect(shared2.existsSync(), isFalse);
    expect(engineCache.existsSync(), isTrue, reason: '引擎自己的缓存不能被误删');
    expect(noPrefix.existsSync(), isTrue, reason: '没有该前缀的文件不是分享副本');
    expect(nested.existsSync(), isTrue, reason: '不递归进子目录（交付目录另有整目录清理）');
  });

  test('目录不存在时返回 0，不抛异常', () async {
    final Directory missing = Directory('${dir.path}${Platform.pathSeparator}nope');
    expect(await purgeSharedFiles(missing), 0);
  });

  test('没有可删文件时返回 0', () async {
    await write('other.txt');
    expect(await purgeSharedFiles(dir), 0);
  });

  test('前缀是唯一识别条件（换前缀只影响对应文件）', () async {
    final File shared = await write('shared_a.jpg');
    final File custom = await write('tmp_b.jpg');

    expect(await purgeSharedFiles(dir, prefix: 'tmp_'), 1);

    expect(custom.existsSync(), isFalse);
    expect(shared.existsSync(), isTrue, reason: '换个前缀不应牵连 shared_ 文件');
  });
}
