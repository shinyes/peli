# 本项目为纯 Dart/Java 交互（通过官方插件），不需要额外的 keep 规则。
# 仅保留 Flutter 与 SQLCipher 的必要项，避免 release 混淆后运行时失败。

-keep class io.flutter.** { *; }
-keep class net.sqlcipher.** { *; }
-keep class net.zetetic.** { *; }
-dontwarn net.sqlcipher.**

# flutter_secure_storage：通过 JNI 反射调用 Keystore 相关类。
-keep class com.it_nomads.fluttersecurestorage.** { *; }
