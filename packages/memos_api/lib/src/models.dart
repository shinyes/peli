/// 数据模型：严格对应 memos 0.31.0 的 `proto/api/v1/*.proto`。
///
/// 解析约定（来自 protojson 行为）：
/// - 字段名为 lowerCamelCase；
/// - 响应会输出 proto3 标量默认值，但**省略未设置的 message 字段**。
///
/// 因此所有解析都必须是"宽容"的：字段缺失、类型意外都不能抛异常。
library;

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

typedef Json = Map<String, Object?>;

String? asString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

String asStringOr(Object? value, String fallback) => asString(value) ?? fallback;

int? asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

Json asJson(Object? value) => value is Json ? value : const <String, Object?>{};

/// 把 `users/abc` 还原成资源 ID `abc`；不是资源名则原样返回。
String? resourceId(String? name) {
  final String? value = name?.trim();
  if (value == null || value.isEmpty) return null;
  final int slash = value.lastIndexOf('/');
  if (slash == -1) return value;
  final String tail = value.substring(slash + 1);
  return tail.isEmpty ? null : tail;
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// `memos.api.v1.User`
class RemoteUser {
  const RemoteUser({required this.id, required this.username, this.displayName});

  final String id;
  final String username;
  final String? displayName;

  factory RemoteUser.fromJson(Json json) => RemoteUser(
        id: resourceId(asString(json['name'])) ?? asStringOr(json['username'], ''),
        username: asStringOr(json['username'], ''),
        displayName: asString(json['displayName']),
      );

  @override
  String toString() => 'RemoteUser(users/$id, $username)';
}

/// `memos.api.v1.InstanceProfile`
class InstanceProfile {
  const InstanceProfile({required this.version});

  final String version;

  factory InstanceProfile.fromJson(Json json) =>
      InstanceProfile(version: asStringOr(json['version'], ''));

  /// 解析语义化版本，无法解析时为 null。
  ///
  /// 兼容两种编号：`0.31.0` 与日历版本 `26.09`（不足三段补 0）。
  List<int>? get versionParts {
    final RegExpMatch? match = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(version);
    if (match == null) return null;
    return <int>[
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.tryParse(match.group(3) ?? '') ?? 0,
    ];
  }

  /// 是否满足本项目要求的最低版本（0.31.0）。
  bool get isSupported {
    final List<int>? parts = versionParts;
    if (parts == null) return false;
    return _compareParts(parts, const <int>[0, 31, 0]) >= 0;
  }

  static int _compareParts(List<int> a, List<int> b) {
    for (int i = 0; i < 3; i++) {
      final int diff = a[i] - b[i];
      if (diff != 0) return diff;
    }
    return 0;
  }
}
