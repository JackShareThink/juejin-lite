package io.juejin.lite;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.ProgressBar;
import android.widget.TextView;

/** Article detail, rendered from the Juejin mobile web article page. */
public class DetailActivity extends Activity {

    static final String EXTRA_ID = "article_id";
    static final String EXTRA_TITLE = "article_title";

    private static final String TAG = JuejinApi.TAG;

    private WebView web;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_detail);

        String title = getIntent().getStringExtra(EXTRA_TITLE);
        String id = getIntent().getStringExtra(EXTRA_ID);

        TextView titleView = findViewById(R.id.detail_title);
        titleView.setText(title == null ? "文章详情" : title);
        findViewById(R.id.btn_back).setOnClickListener(v -> finish());

        final ProgressBar progress = findViewById(R.id.detail_progress);
        web = findViewById(R.id.web);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        settings.setSupportZoom(true);

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                progress.setProgress(newProgress);
                progress.setVisibility(newProgress >= 100 ? View.INVISIBLE : View.VISIBLE);
            }

            @Override
            public boolean onCreateWindow(WebView view, boolean isDialog, boolean isUserGesture, android.os.Message resultMsg) {
                // Juejin opens app-download / share links in popups; keep everything in this WebView.
                return false;
            }
        });
        web.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                Log.i(TAG, "detail page finished " + url);
                hideAppPromo(view);
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                // The page ships "open in app" links (juejin://, intent://, market://); loading those
                // inside the WebView fails and lets the system throw the "继续浏览内容" chooser over us.
                if (url != null && (url.startsWith("http://") || url.startsWith("https://"))) {
                    view.loadUrl(url);
                } else {
                    Log.i(TAG, "blocked non-web url " + url);
                }
                return true;
            }
        });

        String url = "https://juejin.cn/post/" + id;
        Log.i(TAG, "detail load " + url);
        web.loadUrl(url);
    }

    /**
     * The mobile article page injects its own "继续浏览内容 / APP内打开" sheet that dims the
     * article and offers the Juejin app or Chrome. Inside a WebView that sheet is dead weight,
     * so it is stripped once the page settles (and again after late DOM churn).
     */
    private void hideAppPromo(WebView web) {
        String js = "(function(){"
                + "var KILL=/继续浏览内容|APP内打开|打开APP|下载掘金|用App打开/;"
                + "function sweep(){"
                + "  var all=document.querySelectorAll('div,section,aside,article');"
                + "  for(var i=0;i<all.length;i++){"
                + "    var el=all[i];"
                + "    var t=(el.innerText||'').replace(/\\s+/g,'');"
                + "    if(!t||t.length>60||!KILL.test(t))continue;"
                + "    var box=el;"
                + "    while(box&&box!==document.body){"
                + "      var st=window.getComputedStyle(box);"
                + "      if(st.position==='fixed'||st.position==='sticky'){break;}"
                + "      box=box.parentElement;"
                + "    }"
                + "    var target=(box&&box!==document.body)?box:el;"
                + "    var r=target.getBoundingClientRect();"
                + "    if(r.height>window.innerHeight*0.75)continue;"   // never nuke the article itself
                + "    target.style.setProperty('display','none','important');"
                + "  }"
                + "}"
                + "sweep();"
                + "var n=0,id=setInterval(function(){sweep();if(++n>20)clearInterval(id);},1500);"
                + "})();";
        web.evaluateJavascript(js, null);
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        if (web != null) {
            web.destroy();
        }
        super.onDestroy();
    }
}
