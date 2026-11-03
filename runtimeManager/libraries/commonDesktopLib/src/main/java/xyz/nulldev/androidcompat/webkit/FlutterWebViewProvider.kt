package xyz.nulldev.androidcompat.webkit

import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Picture
import android.graphics.Rect
import android.graphics.drawable.Drawable
import android.net.Uri
import android.net.http.SslCertificate
import android.os.Bundle
import android.os.Handler
import android.os.Message
import android.print.PrintDocumentAdapter
import android.util.Log
import android.util.SparseArray
import android.view.DragEvent
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.PointerIcon
import android.view.View
import android.view.ViewGroup.LayoutParams
import android.view.WindowInsets
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeProvider
import android.view.autofill.AutofillValue
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.textclassifier.TextClassifier
import android.webkit.DownloadListener
import android.webkit.PermissionRequest
import android.webkit.RenderProcessGoneDetail
import android.webkit.ValueCallback
import android.webkit.WebBackForwardList
import android.webkit.WebChromeClient
import android.webkit.WebMessage
import android.webkit.WebMessagePort
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebView.HitTestResult
import android.webkit.WebView.PictureListener
import android.webkit.WebView.VisualStateCallback
import android.webkit.WebViewClient
import android.webkit.WebViewProvider
import android.webkit.WebViewProvider.ScrollDelegate
import android.webkit.WebViewProvider.ViewDelegate
import android.webkit.WebViewRenderProcess
import android.webkit.WebViewRenderProcessClient
import java.io.BufferedWriter
import java.io.File
import java.io.IOException
import java.util.concurrent.Executor
import kotlin.reflect.KFunction
import kotlin.reflect.full.declaredMemberFunctions
import kotlin.reflect.jvm.javaMethod
import com.aayush262.dartotsu_extension_bridge.FlutterBridge
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.util.Base64
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

class FlutterWebViewProvider(
    private val view: WebView,
) : WebViewProvider {
    private val settings = KcefWebSettings()
    private var viewClient = WebViewClient()
    private var chromeClient = WebChromeClient()
    private val mappings: MutableList<FunctionMapping> = java.util.concurrent.CopyOnWriteArrayList()
    private val handler = Handler(view.webViewLooper)
    private val gson = Gson()
    private val id = UUID.randomUUID().toString()

    private val commands =
        ThreadPoolExecutor(0, 1, 10, TimeUnit.SECONDS, LinkedBlockingQueue()) { r ->
            Thread(r, "webview-$id").apply { isDaemon = true }
        }

    @Volatile private var alive = true

    @Volatile private var created = false

    @Volatile private var currentUrl = "about:blank"

    @Volatile private var currentTitle: String? = null

    @Volatile private var progress = 0

    companion object {
        const val TAG = "FlutterWebViewProvider"
        private const val POLL_MS = 20_000
        private const val MAX_POLL_FAILURES = 10
    }

    private data class FunctionMapping(
        val interfaceName: String,
        val functionName: String,
        val obj: Any,
        val fn: KFunction<*>,
    )

    private class FlutterWebResourceRequest(
        private val url: String,
        private val main: Boolean,
    ) : WebResourceRequest {
        override fun getUrl(): Uri = Uri.parse(url)

        override fun isForMainFrame(): Boolean = main

        override fun isRedirect(): Boolean = false

        override fun hasGesture(): Boolean = false

        override fun getMethod(): String = "GET"

        override fun getRequestHeaders(): Map<String, String> = emptyMap()
    }

    private fun submit(block: () -> Unit) {
        try {
            commands.execute {
                try {
                    block()
                } catch (e: Throwable) {
                    Log.w(TAG, "WebView command failed", e)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "WebView command rejected", e)
        }
    }

    private fun call(
        method: String,
        args: Map<String, Any?> = emptyMap(),
        slow: Boolean = false,
    ): JsonObject = FlutterBridge.call(method, args + ("id" to id), slow)

    private fun text(res: JsonObject?): String? = res?.get("result")?.takeUnless { it.isJsonNull }?.asString

    private fun state(): JsonObject? {
        if (!created) return null
        return text(call("wvState"))?.let { runCatching { JsonParser.parseString(it).asJsonObject }.getOrNull() }
    }

    private fun action(name: String) = submit { if (created) call("wvAction", mapOf("action" to name)) }

    private fun ensure() {
        if (created) return
        val res = call("wvCreate")
        if (res["success"]?.asBoolean != true) {
            throw IllegalStateException("The app could not open a WebView: ${res["error"]?.asString}")
        }
        created = true
        startPoller()
    }

    private fun startPoller() {
        Thread({
            var failures = 0
            while (alive && created) {
                val res = runCatching { call("wvPoll", mapOf("timeoutMs" to POLL_MS), slow = true) }.getOrNull()
                val raw = text(res)
                if (raw == null) {
                    if (++failures >= MAX_POLL_FAILURES) {
                        created = false
                        break
                    }
                    Thread.sleep(500)
                    continue
                }
                failures = 0
                runCatching { JsonParser.parseString(raw).asJsonArray }.getOrNull()?.forEach {
                    runCatching { dispatch(it.asJsonObject) }.onFailure { e -> Log.w(TAG, "WebView event failed", e) }
                }
            }
        }, "webview-poll-$id").apply {
            isDaemon = true
            start()
        }
    }

    private fun JsonObject.str(key: String): String? = get(key)?.takeUnless { it.isJsonNull }?.asString

    @Suppress("DEPRECATION")
    private fun dispatch(event: JsonObject) {
        when (event.str("t")) {
            "start" -> {
                val url = event.str("url") ?: return
                currentUrl = url
                handler.post { viewClient.onPageStarted(view, url, null) }
            }
            "finish" -> {
                val url = event.str("url") ?: currentUrl
                currentUrl = url
                val title = event.str("title")
                currentTitle = title
                progress = 100
                handler.post {
                    viewClient.onPageFinished(view, url)
                    chromeClient.onProgressChanged(view, 100)
                    if (title != null) chromeClient.onReceivedTitle(view, title)
                }
            }
            "progress" -> {
                val p = event.get("p")?.asInt ?: return
                progress = p
                handler.post { chromeClient.onProgressChanged(view, p) }
            }
            "error" ->
                handler.post {
                    viewClient.onReceivedError(
                        view,
                        event.get("code")?.asInt ?: WebViewClient.ERROR_UNKNOWN,
                        event.str("desc") ?: "",
                        currentUrl,
                    )
                }
            "resource" -> {
                val url = event.str("url") ?: return
                viewClient.shouldInterceptRequest(view, FlutterWebResourceRequest(url, false))
                handler.post { viewClient.onLoadResource(view, url) }
            }
            "nav" -> {
                val url = event.str("url") ?: return
                val main = event.get("main")?.asBoolean ?: true
                if (main) viewClient.shouldInterceptRequest(view, FlutterWebResourceRequest(url, true))
                handler.post { viewClient.shouldOverrideUrlLoading(view, FlutterWebResourceRequest(url, main)) }
            }
            "js" -> invoke(event)
            "closed" -> created = false
        }
    }

    private fun invoke(event: JsonObject) {
        val callId = event.get("c")?.asLong ?: return
        val iface = event.str("i") ?: return
        val function = event.str("f") ?: return
        val args = event.getAsJsonArray("a")?.map { it.asString }.orEmpty().toTypedArray()
        val mapping = mappings.find { it.interfaceName == iface && it.functionName == function }
        handler.post {
            val (ok, value) =
                if (mapping == null) {
                    false to "No such function"
                } else {
                    try {
                        true to mapping.fn.call(mapping.obj, *args).toString()
                    } catch (e: Exception) {
                        Log.w(TAG, "JS-invoke on $iface.$function failed:", e)
                        false to (e.message ?: e::class.java.simpleName)
                    }
                }
            submit { call("wvEval", mapOf("script" to "window.__dartotsuReply($callId, $ok, ${gson.toJson(value)})")) }
        }
    }

    override fun init(
        javaScriptInterfaces: Map<String, Any>?,
        privateBrowsing: Boolean,
    ) {
        Log.v(TAG, "FlutterWebViewProvider: initialize")
        javaScriptInterfaces?.forEach { (name, obj) -> addJavascriptInterface(obj, name) }
    }

    // Deprecated - should never be called
    override fun setHorizontalScrollbarOverlay(overlay: Boolean): Unit = throw RuntimeException("Stub!")

    // Deprecated - should never be called
    override fun setVerticalScrollbarOverlay(overlay: Boolean): Unit = throw RuntimeException("Stub!")

    // Deprecated - should never be called
    override fun overlayHorizontalScrollbar(): Boolean = throw RuntimeException("Stub!")

    // Deprecated - should never be called
    override fun overlayVerticalScrollbar(): Boolean = throw RuntimeException("Stub!")

    override fun getVisibleTitleHeight(): Int = throw RuntimeException("Stub!")

    override fun getCertificate(): SslCertificate = throw RuntimeException("Stub!")

    override fun setCertificate(certificate: SslCertificate): Unit = throw RuntimeException("Stub!")

    override fun savePassword(
        host: String,
        username: String,
        password: String,
    ): Unit = throw RuntimeException("Stub!")

    override fun setHttpAuthUsernamePassword(
        host: String,
        realm: String,
        username: String,
        password: String,
    ): Unit = throw RuntimeException("Stub!")

    override fun getHttpAuthUsernamePassword(
        host: String,
        realm: String,
    ): Array<String> = throw RuntimeException("Stub!")

    override fun destroy() {
        alive = false
        if (created) {
            created = false
            submit { call("wvClose") }
        }
    }

    override fun setNetworkAvailable(networkUp: Boolean): Unit = throw RuntimeException("Stub!")

    override fun saveState(outState: Bundle): WebBackForwardList = throw RuntimeException("Stub!")

    override fun savePicture(
        b: Bundle,
        dest: File,
    ): Boolean = throw RuntimeException("Stub!")

    override fun restorePicture(
        b: Bundle,
        src: File,
    ): Boolean = throw RuntimeException("Stub!")

    override fun restoreState(inState: Bundle): WebBackForwardList = throw RuntimeException("Stub!")

    private fun begin() {
        alive = true
        progress = 0
        handler.post { chromeClient.onProgressChanged(view, 0) }
    }

    override fun loadUrl(
        loadUrl: String,
        additionalHttpHeaders: Map<String, String>,
    ) {
        begin()
        currentUrl = loadUrl
        submit {
            ensure()
            call(
                "wvLoad",
                mapOf("url" to loadUrl, "headers" to additionalHttpHeaders, "userAgent" to settings.userAgentString),
            )
        }
    }

    override fun loadUrl(url: String) {
        loadUrl(url, mapOf())
    }

    override fun postUrl(
        url: String,
        postData: ByteArray,
    ) {
        begin()
        currentUrl = url
        submit {
            ensure()
            call(
                "wvLoad",
                mapOf(
                    "url" to url,
                    "body" to Base64.getEncoder().encodeToString(postData),
                    "userAgent" to settings.userAgentString,
                ),
            )
        }
    }

    override fun loadData(
        data: String,
        mimeType: String?,
        encoding: String?,
    ) {
        loadDataWithBaseURL(null, data, mimeType, encoding, null)
    }

    override fun loadDataWithBaseURL(
        baseUrl: String?,
        data: String,
        mimeType: String?,
        encoding: String?,
        historyUrl: String?,
    ) {
        begin()
        currentUrl = baseUrl ?: "about:blank"
        submit {
            ensure()
            call("wvLoadHtml", mapOf("html" to data, "baseUrl" to baseUrl))
        }
    }

    override fun evaluateJavaScript(
        script: String,
        resultCallback: ValueCallback<String>?,
    ) {
        submit {
            ensure()
            val value = text(call("wvEval", mapOf("script" to script.removePrefix("javascript:"))))
            Log.v(TAG, "JS returned: $value")
            if (resultCallback != null) handler.post { resultCallback.onReceiveValue(value ?: "null") }
        }
    }

    override fun saveWebArchive(filename: String): Unit = throw RuntimeException("Stub!")

    override fun saveWebArchive(
        basename: String,
        autoname: Boolean,
        callback: ValueCallback<String>,
    ): Unit = throw RuntimeException("Stub!")

    override fun stopLoading() {
        action("stop")
    }

    override fun reload() {
        action("reload")
    }

    override fun canGoBack(): Boolean = state()?.get("canGoBack")?.asBoolean ?: false

    override fun goBack() {
        action("back")
    }

    override fun canGoForward(): Boolean = state()?.get("canGoForward")?.asBoolean ?: false

    override fun goForward() {
        action("forward")
    }

    override fun canGoBackOrForward(steps: Int): Boolean = throw RuntimeException("Stub!")

    override fun goBackOrForward(steps: Int): Unit = throw RuntimeException("Stub!")

    override fun isPrivateBrowsingEnabled(): Boolean = throw RuntimeException("Stub!")

    override fun pageUp(top: Boolean): Boolean = throw RuntimeException("Stub!")

    override fun pageDown(bottom: Boolean): Boolean = throw RuntimeException("Stub!")

    override fun insertVisualStateCallback(
        requestId: Long,
        callback: VisualStateCallback,
    ): Unit = throw RuntimeException("Stub!")

    override fun clearView(): Unit = throw RuntimeException("Stub!")

    override fun capturePicture(): Picture = throw RuntimeException("Stub!")

    override fun createPrintDocumentAdapter(documentName: String): PrintDocumentAdapter = throw RuntimeException("Stub!")

    override fun getScale(): Float = throw RuntimeException("Stub!")

    override fun setInitialScale(scaleInPercent: Int): Unit = throw RuntimeException("Stub!")

    override fun invokeZoomPicker(): Unit = throw RuntimeException("Stub!")

    override fun getHitTestResult(): HitTestResult = throw RuntimeException("Stub!")

    override fun requestFocusNodeHref(hrefMsg: Message): Unit = throw RuntimeException("Stub!")

    override fun requestImageRef(msg: Message): Unit = throw RuntimeException("Stub!")

    override fun getUrl(): String = currentUrl

    override fun getOriginalUrl(): String = currentUrl

    override fun getTitle(): String = currentTitle ?: ""

    override fun getFavicon(): Bitmap = throw RuntimeException("Stub!")

    override fun getTouchIconUrl(): String = throw RuntimeException("Stub!")

    override fun getProgress(): Int = progress

    override fun getContentHeight(): Int = throw RuntimeException("Stub!")

    override fun getContentWidth(): Int = throw RuntimeException("Stub!")

    override fun pauseTimers() {
        Log.v(TAG, "pauseTimers: doing nothing")
    }

    override fun resumeTimers() {
        Log.v(TAG, "resumeTimers: doing nothing")
    }

    override fun onPause() {
        Log.v(TAG, "onPause: doing nothing")
    }

    override fun onResume() {
        Log.v(TAG, "onResume: doing nothing")
    }

    override fun isPaused(): Boolean = false

    override fun freeMemory(): Unit = throw RuntimeException("Stub!")

    override fun clearCache(includeDiskFiles: Boolean): Unit = throw RuntimeException("Stub!")

    override fun clearFormData(): Unit = throw RuntimeException("Stub!")

    override fun clearHistory(): Unit = throw RuntimeException("Stub!")

    override fun clearSslPreferences(): Unit = throw RuntimeException("Stub!")

    override fun copyBackForwardList(): WebBackForwardList = throw RuntimeException("Stub!")

    override fun setFindListener(listener: WebView.FindListener): Unit = throw RuntimeException("Stub!")

    override fun findNext(forward: Boolean): Unit = throw RuntimeException("Stub!")

    override fun findAll(find: String): Int = throw RuntimeException("Stub!")

    override fun findAllAsync(find: String): Unit = throw RuntimeException("Stub!")

    override fun showFindDialog(
        text: String,
        showIme: Boolean,
    ): Boolean = throw RuntimeException("Stub!")

    override fun clearMatches(): Unit = throw RuntimeException("Stub!")

    override fun documentHasImages(response: Message): Unit = throw RuntimeException("Stub!")

    override fun setWebViewClient(client: WebViewClient) {
        viewClient = client
    }

    override fun getWebViewClient(): WebViewClient = viewClient

    override fun getWebViewRenderProcess(): WebViewRenderProcess? = throw RuntimeException("Stub!")

    override fun setWebViewRenderProcessClient(
        executor: Executor?,
        client: WebViewRenderProcessClient?,
    ): Unit = throw RuntimeException("Stub!")

    override fun getWebViewRenderProcessClient(): WebViewRenderProcessClient? = throw RuntimeException("Stub!")

    override fun setDownloadListener(listener: DownloadListener): Unit = throw RuntimeException("Stub!")

    override fun setWebChromeClient(client: WebChromeClient) {
        chromeClient = client
    }

    override fun getWebChromeClient(): WebChromeClient = chromeClient

    @Suppress("DEPRECATION")
    override fun setPictureListener(listener: PictureListener): Unit = throw RuntimeException("Stub!")

    override fun addJavascriptInterface(
        obj: Any,
        interfaceName: String,
    ) {
        val mapped =
            obj::class.declaredMemberFunctions.map {
                it.javaMethod?.isAccessible = true
                FunctionMapping(interfaceName, it.name, obj, it)
            }
        mappings.removeAll { it.interfaceName == interfaceName }
        mappings.addAll(mapped)
        Log.v(TAG, "Exposing: $interfaceName ${mapped.map { it.functionName }}")
        submit {
            ensure()
            call("wvInterface", mapOf("name" to interfaceName, "functions" to mapped.map { it.functionName }.distinct()))
        }
    }

    override fun removeJavascriptInterface(interfaceName: String) {
        val removed = mappings.removeAll { it.interfaceName == interfaceName }
        Log.v(TAG, if (removed) "Removed interface mappings for $interfaceName" else "No interface mappings for $interfaceName to remove")
        if (removed) submit { if (created) call("wvUnInterface", mapOf("name" to interfaceName)) }
    }

    override fun createWebMessageChannel(): Array<WebMessagePort> = throw RuntimeException("Stub!")

    override fun postMessageToMainFrame(
        message: WebMessage,
        targetOrigin: Uri,
    ): Unit = throw RuntimeException("Stub!")

    override fun getSettings(): WebSettings = settings

    override fun setMapTrackballToArrowKeys(setMap: Boolean): Unit = throw RuntimeException("Stub!")

    override fun flingScroll(
        vx: Int,
        vy: Int,
    ): Unit = throw RuntimeException("Stub!")

    override fun getZoomControls(): View = throw RuntimeException("Stub!")

    override fun canZoomIn(): Boolean = throw RuntimeException("Stub!")

    override fun canZoomOut(): Boolean = throw RuntimeException("Stub!")

    override fun zoomBy(zoomFactor: Float): Boolean = throw RuntimeException("Stub!")

    override fun zoomIn(): Boolean = throw RuntimeException("Stub!")

    override fun zoomOut(): Boolean = throw RuntimeException("Stub!")

    override fun dumpViewHierarchyWithProperties(
        out: BufferedWriter,
        level: Int,
    ): Unit = throw RuntimeException("Stub!")

    override fun findHierarchyView(
        className: String,
        hashCode: Int,
    ): View = throw RuntimeException("Stub!")

    override fun setRendererPriorityPolicy(
        rendererRequestedPriority: Int,
        waivedWhenNotVisible: Boolean,
    ): Unit = throw RuntimeException("Stub!")

    override fun getRendererRequestedPriority(): Int = throw RuntimeException("Stub!")

    override fun getRendererPriorityWaivedWhenNotVisible(): Boolean = throw RuntimeException("Stub!")

    @SuppressWarnings("unused")
    override fun setTextClassifier(textClassifier: TextClassifier?) {
    }

    override fun getTextClassifier(): TextClassifier = TextClassifier.NO_OP

    // -------------------------------------------------------------------------
    // Provider internal methods
    // -------------------------------------------------------------------------

    override fun getViewDelegate(): ViewDelegate = throw RuntimeException("Stub!")

    override fun getScrollDelegate(): ScrollDelegate = throw RuntimeException("Stub!")

    override fun notifyFindDialogDismissed(): Unit = throw RuntimeException("Stub!")

    // -------------------------------------------------------------------------
    // View / ViewGroup delegation methods
    // -------------------------------------------------------------------------

    class KcefViewDelegate : ViewDelegate {
        override fun shouldDelayChildPressedState(): Boolean = throw RuntimeException("Stub!")

        override fun onProvideVirtualStructure(structure: android.view.ViewStructure): Unit = throw RuntimeException("Stub!")

        override fun onProvideAutofillVirtualStructure(
            @SuppressWarnings("unused") structure: android.view.ViewStructure,
            @SuppressWarnings("unused") flags: Int,
        ) {
        }

        override fun autofill(
            @SuppressWarnings("unused") values: SparseArray<AutofillValue>,
        ) {
        }

        override fun isVisibleToUserForAutofill(
            @SuppressWarnings("unused") virtualId: Int,
        ): Boolean {
            return true // true is the default value returned by View.isVisibleToUserForAutofill()
        }

        override fun onProvideContentCaptureStructure(
            @SuppressWarnings("unused") structure: android.view.ViewStructure,
            @SuppressWarnings("unused") flags: Int,
        ) {
        }

        override fun getAccessibilityNodeProvider(): AccessibilityNodeProvider = throw RuntimeException("Stub!")

        override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo): Unit = throw RuntimeException("Stub!")

        override fun onInitializeAccessibilityEvent(event: AccessibilityEvent): Unit = throw RuntimeException("Stub!")

        override fun performAccessibilityAction(
            action: Int,
            arguments: Bundle,
        ): Boolean = throw RuntimeException("Stub!")

        override fun setOverScrollMode(mode: Int): Unit = throw RuntimeException("Stub!")

        override fun setScrollBarStyle(style: Int): Unit = throw RuntimeException("Stub!")

        override fun onDrawVerticalScrollBar(
            canvas: Canvas,
            scrollBar: Drawable,
            l: Int,
            t: Int,
            r: Int,
            b: Int,
        ): Unit = throw RuntimeException("Stub!")

        override fun onOverScrolled(
            scrollX: Int,
            scrollY: Int,
            clampedX: Boolean,
            clampedY: Boolean,
        ): Unit = throw RuntimeException("Stub!")

        override fun onWindowVisibilityChanged(visibility: Int): Unit = throw RuntimeException("Stub!")

        override fun onDraw(canvas: Canvas): Unit = throw RuntimeException("Stub!")

        override fun setLayoutParams(layoutParams: LayoutParams): Unit = throw RuntimeException("Stub!")

        override fun performLongClick(): Boolean = throw RuntimeException("Stub!")

        override fun onConfigurationChanged(newConfig: Configuration): Unit = throw RuntimeException("Stub!")

        override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection = throw RuntimeException("Stub!")

        override fun onDragEvent(event: DragEvent): Boolean = throw RuntimeException("Stub!")

        override fun onKeyMultiple(
            keyCode: Int,
            repeatCount: Int,
            event: KeyEvent,
        ): Boolean = throw RuntimeException("Stub!")

        override fun onKeyDown(
            keyCode: Int,
            event: KeyEvent,
        ): Boolean = throw RuntimeException("Stub!")

        override fun onKeyUp(
            keyCode: Int,
            event: KeyEvent,
        ): Boolean = throw RuntimeException("Stub!")

        override fun onAttachedToWindow(): Unit = throw RuntimeException("Stub!")

        override fun onDetachedFromWindow(): Unit = throw RuntimeException("Stub!")

        override fun onMovedToDisplay(
            displayId: Int,
            config: Configuration,
        ) {
        }

        override fun onVisibilityChanged(
            changedView: View,
            visibility: Int,
        ): Unit = throw RuntimeException("Stub!")

        override fun onWindowFocusChanged(hasWindowFocus: Boolean): Unit = throw RuntimeException("Stub!")

        override fun onFocusChanged(
            focused: Boolean,
            direction: Int,
            previouslyFocusedRect: Rect,
        ): Unit = throw RuntimeException("Stub!")

        override fun setFrame(
            left: Int,
            top: Int,
            right: Int,
            bottom: Int,
        ): Boolean = throw RuntimeException("Stub!")

        override fun onSizeChanged(
            w: Int,
            h: Int,
            ow: Int,
            oh: Int,
        ): Unit = throw RuntimeException("Stub!")

        override fun onScrollChanged(
            l: Int,
            t: Int,
            oldl: Int,
            oldt: Int,
        ): Unit = throw RuntimeException("Stub!")

        override fun dispatchKeyEvent(event: KeyEvent): Boolean = throw RuntimeException("Stub!")

        override fun onTouchEvent(ev: MotionEvent): Boolean = throw RuntimeException("Stub!")

        override fun onHoverEvent(event: MotionEvent): Boolean = throw RuntimeException("Stub!")

        override fun onGenericMotionEvent(event: MotionEvent): Boolean = throw RuntimeException("Stub!")

        override fun onTrackballEvent(ev: MotionEvent): Boolean = throw RuntimeException("Stub!")

        override fun requestFocus(
            direction: Int,
            previouslyFocusedRect: Rect,
        ): Boolean = throw RuntimeException("Stub!")

        override fun onMeasure(
            widthMeasureSpec: Int,
            heightMeasureSpec: Int,
        ): Unit = throw RuntimeException("Stub!")

        override fun requestChildRectangleOnScreen(
            child: View,
            rect: Rect,
            immediate: Boolean,
        ): Boolean = throw RuntimeException("Stub!")

        override fun setBackgroundColor(color: Int): Unit = throw RuntimeException("Stub!")

        override fun setLayerType(
            layerType: Int,
            paint: Paint,
        ) {
            // ignore
        }

        override fun preDispatchDraw(canvas: Canvas): Unit = throw RuntimeException("Stub!")

        override fun onStartTemporaryDetach(): Unit = throw RuntimeException("Stub!")

        override fun onFinishTemporaryDetach(): Unit = throw RuntimeException("Stub!")

        override fun onActivityResult(
            requestCode: Int,
            resultCode: Int,
            data: Intent,
        ): Unit = throw RuntimeException("Stub!")

        override fun getHandler(originalHandler: Handler): Handler = throw RuntimeException("Stub!")

        override fun findFocus(originalFocusedView: View): View = throw RuntimeException("Stub!")

        @SuppressWarnings("unused")
        override fun onCheckIsTextEditor(): Boolean = false

        @SuppressWarnings("unused")
        override fun onApplyWindowInsets(insets: WindowInsets?): WindowInsets? = null

        @SuppressWarnings("unused")
        override fun onResolvePointerIcon(
            event: MotionEvent,
            pointerIndex: Int,
        ): PointerIcon? = null
    }

    class KcefScrollDelegate : ScrollDelegate {
        override fun computeHorizontalScrollRange(): Int = throw RuntimeException("Stub!")

        override fun computeHorizontalScrollOffset(): Int = throw RuntimeException("Stub!")

        override fun computeVerticalScrollRange(): Int = throw RuntimeException("Stub!")

        override fun computeVerticalScrollOffset(): Int = throw RuntimeException("Stub!")

        override fun computeVerticalScrollExtent(): Int = throw RuntimeException("Stub!")

        override fun computeScroll(): Unit = throw RuntimeException("Stub!")
    }
}
