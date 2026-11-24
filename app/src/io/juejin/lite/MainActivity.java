package io.juejin.lite;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.View;
import android.widget.AbsListView;
import android.widget.ListView;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Feed screen: the Juejin recommend list. */
public class MainActivity extends Activity {

    private static final String TAG = JuejinApi.TAG;

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());

    private ArticleAdapter adapter;
    private ProgressBar loading;
    private TextView status;

    private String cursor = "0";
    private boolean hasMore = true;
    private boolean busy = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        adapter = new ArticleAdapter(this);
        loading = findViewById(R.id.loading);
        status = findViewById(R.id.status);
        ListView list = findViewById(R.id.list);
        list.setAdapter(adapter);

        list.setOnItemClickListener((parent, view, position, id) -> {
            Article article = adapter.get(position);
            Log.i(TAG, "tap article " + article.id + " at " + position);
            Intent intent = new Intent(MainActivity.this, DetailActivity.class);
            intent.putExtra(DetailActivity.EXTRA_ID, article.id);
            intent.putExtra(DetailActivity.EXTRA_TITLE, article.title);
            startActivity(intent);
        });

        list.setOnScrollListener(new AbsListView.OnScrollListener() {
            @Override
            public void onScrollStateChanged(AbsListView view, int scrollState) {
            }

            @Override
            public void onScroll(AbsListView view, int firstVisible, int visibleCount, int totalCount) {
                if (totalCount > 0 && firstVisible + visibleCount >= totalCount - 3) {
                    load(false);
                }
            }
        });

        findViewById(R.id.btn_refresh).setOnClickListener(v -> {
            Log.i(TAG, "refresh tapped");
            load(true);
        });

        load(true);
    }

    private void load(final boolean reset) {
        if (busy || (!reset && !hasMore)) {
            return;
        }
        busy = true;
        if (reset) {
            cursor = "0";
            hasMore = true;
        }
        final String useCursor = cursor;
        if (adapter.size() == 0) {
            loading.setVisibility(View.VISIBLE);
        }
        status.setVisibility(View.GONE);

        io.execute(() -> {
            try {
                final JuejinApi.Page page = JuejinApi.fetchFeed(useCursor);
                main.post(() -> {
                    busy = false;
                    loading.setVisibility(View.GONE);
                    if (reset) {
                        adapter.clear();
                    }
                    adapter.addAll(page.articles);
                    cursor = page.nextCursor;
                    hasMore = page.hasMore;
                    Log.i(TAG, "feed loaded size=" + page.articles.size()
                            + " total=" + adapter.size()
                            + " cursor=" + cursor + " hasMore=" + hasMore);
                    if (adapter.size() == 0) {
                        showStatus("暂时没有内容，点右上角刷新试试");
                    }
                });
            } catch (final Exception e) {
                Log.e(TAG, "feed failed: " + e);
                main.post(() -> {
                    busy = false;
                    loading.setVisibility(View.GONE);
                    if (adapter.size() == 0) {
                        showStatus("加载失败\n" + e.getMessage() + "\n\n检查网络后点右上角重试");
                    } else {
                        Toast.makeText(MainActivity.this, "加载更多失败：" + e.getMessage(),
                                Toast.LENGTH_SHORT).show();
                    }
                });
            }
        });
    }

    private void showStatus(String text) {
        status.setText(text);
        status.setVisibility(View.VISIBLE);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        io.shutdownNow();
    }
}
