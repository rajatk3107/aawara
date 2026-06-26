# ─── Gson + flutter_local_notifications ──────────────────────────────────────
# flutter_local_notifications serializes scheduled notifications with Gson using
# a TypeToken<ArrayList<NotificationDetails>>. R8 (full mode) strips the generic
# type signature, so Gson throws "Missing type parameter." and every
# zonedSchedule() call fails — no scheduled notification ever fires.
# Keeping the generic Signature attribute and the Gson/plugin model classes
# fixes it.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses, EnclosingMethod

# Gson
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type

# flutter_local_notifications model classes serialized via Gson
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepclassmembers class com.dexterous.flutterlocalnotifications.** { *; }

# ─── Samsung Health Data SDK ─────────────────────────────────────────────────
# The SDK uses reflection/Parcelable across its data + request models; keep them
# so R8 doesn't strip fields read over the Samsung Health IPC boundary.
-keep class com.samsung.android.sdk.health.data.** { *; }
-keepclassmembers class com.samsung.android.sdk.health.data.** { *; }
-dontwarn com.samsung.android.sdk.health.data.**
