import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 机密条目的持久化：只以**密文**形式落盘。
///
/// 当前架构里这里只放**图片缓存密钥**（见 [SessionSecrets]）：登录令牌存在加密
/// 数据库的 `accounts` 表里，不需要第二份。
///
/// 条目由 [FlutterSecureStorage] 保管，在 Android 上由 Keystore 保护
/// （RSA-OAEP 包裹密钥 + AES-GCM 加密内容；Keystore 密钥不可导出、不参与备份），
/// 因此随设备备份一起被提取的密文无法解密。
class SecretStore {
  SecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// 读取条目；不存在时返回 null。
  Future<Uint8List?> read(String key) async {
    final String? encoded = await _storage.read(key: key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return base64Decode(encoded);
    } catch (_) {
      // 数据损坏：当作不存在，由调用方重建。
      return null;
    }
  }

  /// 写入条目。
  Future<void> write(String key, Uint8List value) =>
      _storage.write(key: key, value: base64Encode(value));

  Future<void> delete(String key) => _storage.delete(key: key);
}

/// 运行时会话机密：附件图片的缓存密钥。
///
/// 为什么需要这一层：图片密文存在 WebView 的 IndexedDB 里，页面启动时必须拿到密钥
/// 才能解密（`web_app_page.dart` 以 `window.__memosImageKey` 注入，**只经内存**）。
/// 若把密钥明文留在 IndexedDB，加密就毫无意义 —— 所以密钥只在本类（Keystore 保护
/// 的条目）与进程内存里，密文与密钥分开存放。
class SessionSecrets {
  SessionSecrets({required this.accountId, SecretStore? store})
      : _store = store ?? SecretStore();

  final String accountId;
  final SecretStore _store;

  String get _imageKeyKey => 'session.imageKey.$accountId';

  /// 取得（必要时随机生成）图片缓存密钥：AES-GCM 用的 32 字节。
  Future<Uint8List> imageCacheKey() async {
    final Uint8List? existing = await _store.read(_imageKeyKey);
    if (existing != null && existing.length == 32) return existing;
    final Uint8List fresh = _randomBytes(32);
    await _store.write(_imageKeyKey, fresh);
    return fresh;
  }

  /// 图片密钥的 base64 形式（直接喂给页面的 Web Crypto）。
  Future<String> imageCacheKeyBase64() async =>
      base64Encode(await imageCacheKey());

  static Uint8List _randomBytes(int length) {
    final Random random = Random.secure();
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}
