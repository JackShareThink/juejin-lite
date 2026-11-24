package io.juejin.lite;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** Thin client for the public Juejin (掘金) recommend feed API. */
final class JuejinApi {

    static final String TAG = "JuejinLite";

    private static final String FEED_URL =
            "https://api.juejin.cn/recommend_api/v1/article/recommend_all_feed?aid=2608"
                    + "&uuid=7050000000000000000&device_platform=android";
    private static final String USER_AGENT =
            "Mozilla/5.0 (Linux; Android 16; 24018RPACC) AppleWebKit/537.36 (KHTML, like Gecko) "
                    + "Chrome/124.0 Mobile Safari/537.36 JuejinLite/1.0.0";

    private JuejinApi() {
    }

    static final class Page {
        final List<Article> articles;
        final String nextCursor;
        final boolean hasMore;

        Page(List<Article> articles, String nextCursor, boolean hasMore) {
            this.articles = articles;
            this.nextCursor = nextCursor;
            this.hasMore = hasMore;
        }
    }

    static Page fetchFeed(String cursor) throws IOException {
        JSONObject body = new JSONObject();
        try {
            body.put("id_type", 2);
            body.put("client_type", 2608);
            body.put("sort_type", 200);
            body.put("cursor", cursor);
            body.put("limit", 20);
        } catch (JSONException e) {
            throw new IOException("build request failed", e);
        }

        String response = post(FEED_URL, body.toString());
        try {
            JSONObject root = new JSONObject(response);
            int errNo = root.optInt("err_no", -1);
            if (errNo != 0) {
                throw new IOException("接口返回错误 " + errNo + "：" + root.optString("err_msg"));
            }
            List<Article> out = new ArrayList<>();
            JSONArray data = root.optJSONArray("data");
            if (data != null) {
                for (int i = 0; i < data.length(); i++) {
                    Article article = parseItem(data.optJSONObject(i));
                    if (article != null) {
                        out.add(article);
                    }
                }
            }
            return new Page(out, root.optString("cursor", cursor), root.optBoolean("has_more", true));
        } catch (JSONException e) {
            throw new IOException("解析失败：" + e.getMessage(), e);
        }
    }

    private static Article parseItem(JSONObject item) {
        if (item == null || item.optInt("item_type") != 2) {
            return null;
        }
        JSONObject info = item.optJSONObject("item_info");
        if (info == null) {
            return null;
        }
        Article article = new Article();
        article.id = info.optString("article_id");
        JSONObject data = info.optJSONObject("article_info");
        if (data != null) {
            article.title = data.optString("title");
            article.brief = data.optString("brief_content");
            article.cover = data.optString("cover_image");
            article.views = data.optInt("view_count");
            article.diggs = data.optInt("digg_count");
            article.comments = data.optInt("comment_count");
            article.ctime = data.optLong("ctime");
        }
        JSONObject author = info.optJSONObject("author_user_info");
        if (author != null) {
            article.author = author.optString("user_name");
            article.avatar = author.optString("avatar_large");
        }
        JSONArray tags = info.optJSONArray("tags");
        if (tags != null && tags.length() > 0) {
            JSONObject tag = tags.optJSONObject(0);
            if (tag != null) {
                article.tag = tag.optString("tag_name");
            }
        }
        return article.id == null || article.id.isEmpty() ? null : article;
    }

    private static final int ATTEMPTS = 4;

    /**
     * Mobile networks hand out transient DNS failures and half-open connections, so every request
     * is retried a few times with a short backoff before the UI is allowed to show an error.
     */
    private static String post(String url, String payload) throws IOException {
        IOException last = null;
        for (int attempt = 1; attempt <= ATTEMPTS; attempt++) {
            try {
                return postOnce(url, payload);
            } catch (IOException e) {
                last = e;
                if (attempt == ATTEMPTS || !isTransient(e)) {
                    throw e;
                }
                android.util.Log.w(TAG, "request failed (attempt " + attempt + "/" + ATTEMPTS + "): " + e);
                try {
                    Thread.sleep(400L * attempt);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw e;
                }
            }
        }
        throw last != null ? last : new IOException("request failed");
    }

    private static boolean isTransient(IOException e) {
        if (e instanceof java.net.UnknownHostException
                || e instanceof java.net.SocketTimeoutException
                || e instanceof java.net.ConnectException
                || e instanceof java.net.SocketException) {
            return true;
        }
        String message = e.getMessage();
        if (message != null && message.startsWith("HTTP 5")) {
            return true;
        }
        return false;
    }

    private static String postOnce(String url, String payload) throws IOException {
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setRequestMethod("POST");
            conn.setConnectTimeout(15000);
            conn.setReadTimeout(20000);
            conn.setDoOutput(true);
            conn.setRequestProperty("Content-Type", "application/json;charset=UTF-8");
            conn.setRequestProperty("Accept", "application/json");
            conn.setRequestProperty("User-Agent", USER_AGENT);

            byte[] bytes = payload.getBytes(StandardCharsets.UTF_8);
            conn.setFixedLengthStreamingMode(bytes.length);
            try (OutputStream out = conn.getOutputStream()) {
                out.write(bytes);
            }

            int code = conn.getResponseCode();
            InputStream in = code >= 400 ? conn.getErrorStream() : conn.getInputStream();
            if (in == null) {
                throw new IOException("HTTP " + code);
            }
            String text = readAll(in);
            if (code >= 400) {
                throw new IOException("HTTP " + code + "：" + text);
            }
            return text;
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }

    private static String readAll(InputStream in) throws IOException {
        try (InputStream input = in) {
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            byte[] chunk = new byte[8192];
            int read;
            while ((read = input.read(chunk)) > 0) {
                buffer.write(chunk, 0, read);
            }
            return new String(buffer.toByteArray(), StandardCharsets.UTF_8);
        }
    }
}
