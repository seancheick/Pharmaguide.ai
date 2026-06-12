# Flutter deferred-components stubs referenced by the embedding but not bundled.
-dontwarn com.google.android.play.core.**

# MLKit barcode scanning (mobile_scanner) — keep model/runtime classes that are
# reached via reflection.
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
