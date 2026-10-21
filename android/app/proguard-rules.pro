# Plugins built on package:jni call these Java/Kotlin members by name from Dart.
# R8 cannot see those calls, so without these rules it removes the members and
# release builds fail at startup with NoSuchMethodError.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
# Their JNI signatures name Kotlin coroutine types (suspend functions take a
# kotlin.coroutines.Continuation), so those classes must keep their names too.
-keep class kotlin.coroutines.** { *; }
# package:jni's coroutine bridge looks these up by name (kotlin/Result,
# kotlin/Result$Failure, kotlin/Unit); renaming them breaks suspend calls.
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.Unit { *; }
