// Temporary CI check: drives EmbeddedBridge through the same JNI contract
// ios/.../EmbeddedJvm.mm uses (vfprintf/exit/abort hooks, RegisterNatives +
// installLogCapture, UTF-16 strings) on desktop HotSpot, and fails on any gap.
#include <jni.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static FILE *logFile;
static int failures, vmLines, captureInstalled, javaLines;
static void check(int ok, const char *what) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) failures++;
}

static void emit(const char *tag, const char *line) {
  if (!strcmp(tag, "vm")) vmLines++;
  if (!strcmp(tag, "stdout") || !strcmp(tag, "stderr")) javaLines++;
  if (strstr(line, "Java log capture installed")) captureInstalled = 1;
  fprintf(stdout, "[%s] %s\n", tag, line);
  if (logFile) { fprintf(logFile, "[%s] %s\n", tag, line); fflush(logFile); }
}

static char vmBuf[65536]; static size_t vmLen;
static jint JNICALL vmVfprintf(FILE *fp, const char *fmt, va_list args) {
  (void)fp;
  char tmp[8192];
  int n = vsnprintf(tmp, sizeof tmp, fmt, args);
  if (n < 0) return n;
  size_t add = (size_t)n < sizeof tmp ? (size_t)n : sizeof tmp - 1;
  if (vmLen + add >= sizeof vmBuf) vmLen = 0;
  memcpy(vmBuf + vmLen, tmp, add); vmLen += add; vmBuf[vmLen] = 0;
  char *nl;
  while ((nl = strchr(vmBuf, '\n'))) {
    *nl = 0; emit("vm", vmBuf);
    size_t rest = vmLen - (size_t)(nl + 1 - vmBuf);
    memmove(vmBuf, nl + 1, rest); vmLen = rest; vmBuf[vmLen] = 0;
  }
  return n;
}
static void JNICALL vmExit(jint code) { char b[64]; snprintf(b, sizeof b, "JVM called exit(%d)", code); emit("vm", b); }
static void JNICALL vmAbort(void) { emit("vm", "JVM aborted"); }

// UTF-16 -> UTF-8 for display (handles surrogate pairs)
static void utf16ToUtf8(const jchar *s, jsize n, char *out, size_t cap) {
  size_t o = 0;
  for (jsize i = 0; i < n && o + 4 < cap; i++) {
    unsigned cp = s[i];
    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < n) { cp = 0x10000 + ((cp - 0xD800) << 10) + (s[++i] - 0xDC00); }
    if (cp < 0x80) out[o++] = cp;
    else if (cp < 0x800) { out[o++] = 0xC0 | cp >> 6; out[o++] = 0x80 | (cp & 63); }
    else if (cp < 0x10000) { out[o++] = 0xE0 | cp >> 12; out[o++] = 0x80 | (cp >> 6 & 63); out[o++] = 0x80 | (cp & 63); }
    else { out[o++] = 0xF0 | cp >> 18; out[o++] = 0x80 | (cp >> 12 & 63); out[o++] = 0x80 | (cp >> 6 & 63); out[o++] = 0x80 | (cp & 63); }
  }
  out[o] = 0;
}
static char *fromJava(JNIEnv *env, jstring s) {
  if (!s) return strdup("(null)");
  jsize n = (*env)->GetStringLength(env, s);
  const jchar *c = (*env)->GetStringChars(env, s, NULL);
  size_t cap = (size_t)n * 4 + 1; char *out = malloc(cap);
  utf16ToUtf8(c, n, out, cap);
  (*env)->ReleaseStringChars(env, s, c);
  return out;
}
// UTF-8 -> UTF-16 (what NSString's getCharacters gives the real host)
static jstring toJava(JNIEnv *env, const char *u) {
  size_t len = strlen(u); jchar *b = malloc((len + 1) * 2 * sizeof(jchar)); jsize n = 0;
  for (size_t i = 0; i < len;) {
    unsigned char c = u[i]; unsigned cp;
    if (c < 0x80) { cp = c; i += 1; }
    else if ((c >> 5) == 6) { cp = (c & 31) << 6 | (u[i+1] & 63); i += 2; }
    else if ((c >> 4) == 14) { cp = (c & 15) << 12 | (u[i+1] & 63) << 6 | (u[i+2] & 63); i += 3; }
    else { cp = (c & 7) << 18 | (u[i+1] & 63) << 12 | (u[i+2] & 63) << 6 | (u[i+3] & 63); i += 4; }
    if (cp >= 0x10000) { cp -= 0x10000; b[n++] = 0xD800 + (cp >> 10); b[n++] = 0xDC00 + (cp & 0x3FF); }
    else b[n++] = cp;
  }
  jstring s = (*env)->NewString(env, b, n); free(b); return s;
}

static void JNICALL nativeLog(JNIEnv *env, jclass c, jint stream, jstring line) {
  (void)c; char *t = fromJava(env, line); emit(stream == 2 ? "stderr" : "stdout", t); free(t);
}

static jclass bridge; static jmethodID mLoad, mCall;

static void describe(JNIEnv *env, const char *what) {
  if ((*env)->ExceptionCheck(env)) { fprintf(stdout, "EXCEPTION in %s\n", what); (*env)->ExceptionDescribe(env); exit(2); }
}

static char *call(JNIEnv *env, const char *jar, const char *req) {
  jstring jp = toJava(env, jar), jr = toJava(env, req);
  struct timespec a, b; clock_gettime(CLOCK_MONOTONIC, &a);
  jstring r = (*env)->CallStaticObjectMethod(env, bridge, mCall, jp, jr);
  clock_gettime(CLOCK_MONOTONIC, &b);
  describe(env, "call");
  char *out = fromJava(env, r);
  fprintf(stdout, "== call %.120s -> %ld ms\n", req, (b.tv_sec - a.tv_sec) * 1000 + (b.tv_nsec - a.tv_nsec) / 1000000);
  return out;
}

int main(int argc, char **argv) {
  if (argc < 5) { fprintf(stderr, "usage: harness <embedded-bridge.jar> <plugin.jar> <dataDir> <expectedApkCount>\n"); return 1; }
  int expectedApks = atoi(argv[4]);
  logFile = fopen("jvm.log", "w");
  char cp[4096], err[4096];
  snprintf(cp, sizeof cp, "-Djava.class.path=%s", argv[1]);
  snprintf(err, sizeof err, "-XX:ErrorFile=%s/hs_err.log", ".");
  JavaVMOption o[] = {
    {"-Ddartotsu.runtime=ios", NULL}, {cp, NULL}, {"-Djava.awt.headless=true", NULL},
    {"-Dfile.encoding=UTF-8", NULL}, {"-XX:+UseSerialGC", NULL}, {"-Xms128m", NULL}, {"-Xmx512m", NULL},
    {"-Xss8m", NULL}, {err, NULL},
    {"vfprintf", (void *)vmVfprintf}, {"exit", (void *)vmExit}, {"abort", (void *)vmAbort},
  };
  JavaVMInitArgs args = {JNI_VERSION_1_8, sizeof o / sizeof o[0], o, JNI_FALSE};
  JavaVM *vm; JNIEnv *env;
  if (JNI_CreateJavaVM(&vm, (void **)&env, &args) != JNI_OK) { fprintf(stderr, "create failed\n"); return 1; }
  bridge = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "com/aayush262/dartotsu_extension_bridge/EmbeddedBridge"));
  describe(env, "FindClass");
  JNINativeMethod nm[] = {{"nativeLog", "(ILjava/lang/String;)V", (void *)nativeLog}};
  if ((*env)->RegisterNatives(env, bridge, nm, 1) != JNI_OK) { describe(env, "RegisterNatives"); }
  (*env)->CallStaticVoidMethod(env, bridge, (*env)->GetStaticMethodID(env, bridge, "installLogCapture", "()V"));
  describe(env, "installLogCapture");
  mLoad = (*env)->GetStaticMethodID(env, bridge, "load", "(Ljava/lang/String;)V");
  mCall = (*env)->GetStaticMethodID(env, bridge, "call", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
  (*env)->CallStaticVoidMethod(env, bridge, mLoad, toJava(env, argv[2]));
  describe(env, "load");

  check(captureInstalled, "Java stdout is captured through nativeLog");

  char req[8192]; char *r;
  snprintf(req, sizeof req, "{\"method\":\"initializeDesktop\",\"args\":{\"path\":\"%s\"}}", argv[3]);
  r = call(env, argv[2], req); printf("   %.300s\n", r);
  check(strstr(r, "\"success\":true") != NULL, "initializeDesktop succeeds");
  free(r);

  snprintf(req, sizeof req, "{\"method\":\"getInstalledAnimeExtensions\",\"args\":{\"path\":\"%s/extensions/Anime\"}}", argv[3]);
  r = call(env, argv[2], req); printf("   %zu bytes: %.600s\n", strlen(r), r);
  check(strstr(r, "\"success\":true") != NULL, "getInstalledAnimeExtensions succeeds");
  if (expectedApks > 0) {
    int found = 0; for (const char *p = r; (p = strstr(p, "pkgName")); p++) found++;
    printf("   %d sources loaded from %d APKs\n", found, expectedApks);
    check(found > 0, "real extension APKs load as sources");
  }
  free(r);

  const char *emoji = "emoji-\xF0\x9F\x98\x80-\xE6\xBC\xA2";
  snprintf(req, sizeof req, "{\"method\":\"getPopular\",\"args\":{\"sourceId\":\"%s\",\"isAnime\":true,\"page\":1}}", emoji);
  r = call(env, argv[2], req); printf("   %.400s\n", r);
  check(strstr(r, emoji) != NULL, "non-BMP text survives the JNI round trip");
  check(strstr(r, "\"trace\"") != NULL, "failed calls carry a Java stack trace");
  free(r);

  check(vmLines > 0, "HotSpot output reaches the vfprintf hook");
  check(javaLines > 0, "Java output lines were logged");
  printf("%d failure(s)\n", failures);
  return failures ? 1 : 0;
}
