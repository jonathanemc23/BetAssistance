# ML Kit text recognition only ships the Latin model; the plugin still
# references the optional Chinese, Devanagari, Japanese and Korean ones.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit creates its components by reflection and its native OCR code calls
# back into its Java classes by name. Without these, R8 removes the
# registrars' constructors and every scan fails ("couldn't read the slip").
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
