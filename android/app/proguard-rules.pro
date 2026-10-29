# Entry points that are only reached from native code or by reflection.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.ryanheise.** { *; }
-keep class com.github.dart_lang.** { *; }
-keep class com.tekartik.** { *; }
-keep class com.it_nomads.** { *; }
-keep class io.material.plugins.** { *; }

# Plugins probe for optional dependencies they do not bundle.
-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.play.**
