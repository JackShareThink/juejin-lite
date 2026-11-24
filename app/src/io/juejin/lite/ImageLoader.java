package io.juejin.lite;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.LruCache;
import android.widget.ImageView;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Tiny bitmap loader with an in-memory LRU cache and view recycling guard. */
final class ImageLoader {

    private static final ExecutorService POOL = Executors.newFixedThreadPool(4);

    private static final LruCache<String, Bitmap> CACHE =
            new LruCache<String, Bitmap>((int) (Runtime.getRuntime().maxMemory() / 8)) {
                @Override
                protected int sizeOf(String key, Bitmap value) {
                    return value.getByteCount();
                }
            };

    private ImageLoader() {
    }

    static void load(ImageView view, String url) {
        view.setTag(url);
        if (url == null || url.isEmpty()) {
            view.setImageDrawable(null);
            return;
        }
        Bitmap cached = CACHE.get(url);
        if (cached != null) {
            view.setImageBitmap(cached);
            return;
        }
        view.setImageDrawable(null);
        POOL.execute(() -> {
            Bitmap bitmap = null;
            HttpURLConnection conn = null;
            try {
                conn = (HttpURLConnection) new URL(url).openConnection();
                conn.setConnectTimeout(10000);
                conn.setReadTimeout(15000);
                conn.setRequestProperty("User-Agent",
                        "Mozilla/5.0 (Linux; Android 16; 24018RPACC) JuejinLite/1.0.0");
                // Juejin images are served as webp/avif to modern UAs; ask for a plain image.
                conn.setRequestProperty("Accept", "image/png,image/jpeg,image/*");
                BitmapFactory.Options options = new BitmapFactory.Options();
                options.inSampleSize = 2;
                try (InputStream in = conn.getInputStream()) {
                    bitmap = BitmapFactory.decodeStream(in, null, options);
                }
            } catch (Exception ignored) {
                // Network or decode failures just leave the placeholder in place.
            } finally {
                if (conn != null) {
                    conn.disconnect();
                }
            }
            final Bitmap result = bitmap;
            if (result != null) {
                CACHE.put(url, result);
                view.post(() -> {
                    if (url.equals(view.getTag())) {
                        view.setImageBitmap(result);
                    }
                });
            }
        });
    }
}
