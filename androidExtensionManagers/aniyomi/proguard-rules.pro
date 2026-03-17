-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1> {
    static <1>$Companion Companion;
}

# Keep `serializer()` on companion objects (both default and named) of serializable classes.
-if @kotlinx.serialization.Serializable class ** {
    static **$* *;
}
-keepclassmembers class <2>$<3> {
    kotlinx.serialization.KSerializer serializer(...);
}

# Keep `INSTANCE.serializer()` of serializable objects.
-if @kotlinx.serialization.Serializable class ** {
    public static ** INSTANCE;
}
-keepclassmembers class <1> {
    public static <1> INSTANCE;
    kotlinx.serialization.KSerializer serializer(...);
}
-keepattributes Signature
-keep,allowoptimization class uy.kohesive.injekt.** { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.** { *; }
-keep,allowoptimization class com.aayush262.dartotsu_extension_bridge.** { *; }
-keep,allowoptimization class kotlin.** { public protected *; }
-keep,allowoptimization class kotlinx.coroutines.** { public protected *; }
-keep,allowoptimization class kotlinx.serialization.** { public protected *; }
-keep,allowoptimization class app.cash.quickjs.** { public protected *; }
-keepclassmembers class uy.kohesive.injekt.api.FullTypeReference {
    <init>(...);
}
-dontobfuscate
-keep,allowoptimization class okhttp3.** { public protected *; }
-keep,allowoptimization class androidx.preference.** { public protected *; }
# --- Okio (BufferedSource etc.) ---
-keep,allowoptimization class okio.** { public protected *; }

-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keep,allowoptimization class org.jsoup.** { *; }
-keepclassmembers class org.jsoup.nodes.Document { *; }

-keepattributes RuntimeVisibleAnnotations,AnnotationDefault

-dontwarn com.oracle.svm.**
-dontwarn org.graalvm.nativeimage.**
-dontwarn java.lang.Module