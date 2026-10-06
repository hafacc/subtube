# The player page calls this through addJavascriptInterface, on a WebView without message listeners.
-keepclassmembers class cc.hafa.subtube.ui.PlayerBridge {
    @android.webkit.JavascriptInterface <methods>;
}
