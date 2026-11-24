package io.juejin.lite;

import android.content.Context;
import android.text.TextUtils;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.ImageView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

final class ArticleAdapter extends BaseAdapter {

    private final List<Article> items = new ArrayList<>();
    private final LayoutInflater inflater;

    ArticleAdapter(Context context) {
        this.inflater = LayoutInflater.from(context);
    }

    void clear() {
        items.clear();
        notifyDataSetChanged();
    }

    void addAll(List<Article> more) {
        items.addAll(more);
        notifyDataSetChanged();
    }

    int size() {
        return items.size();
    }

    Article get(int position) {
        return items.get(position);
    }

    @Override
    public int getCount() {
        return items.size();
    }

    @Override
    public Article getItem(int position) {
        return items.get(position);
    }

    @Override
    public long getItemId(int position) {
        return position;
    }

    @Override
    public View getView(int position, View convertView, ViewGroup parent) {
        ViewHolder holder;
        View view = convertView;
        if (view == null) {
            view = inflater.inflate(R.layout.item_article, parent, false);
            holder = new ViewHolder();
            holder.title = view.findViewById(R.id.item_title);
            holder.brief = view.findViewById(R.id.item_brief);
            holder.cover = view.findViewById(R.id.item_cover);
            holder.avatar = view.findViewById(R.id.item_avatar);
            holder.author = view.findViewById(R.id.item_author);
            holder.meta = view.findViewById(R.id.item_meta);
            view.setTag(holder);
        } else {
            holder = (ViewHolder) view.getTag();
        }

        Article article = items.get(position);
        holder.title.setText(article.title);
        holder.brief.setText(article.brief);
        holder.brief.setVisibility(TextUtils.isEmpty(article.brief) ? View.GONE : View.VISIBLE);

        boolean hasCover = !TextUtils.isEmpty(article.cover);
        holder.cover.setVisibility(hasCover ? View.VISIBLE : View.GONE);
        if (hasCover) {
            ImageLoader.load(holder.cover, article.cover);
        }

        String author = TextUtils.isEmpty(article.author) ? "掘金" : article.author;
        if (!TextUtils.isEmpty(article.tag)) {
            author = author + " · " + article.tag;
        }
        holder.author.setText(author);
        ImageLoader.load(holder.avatar, article.avatar);

        holder.meta.setText(String.format(Locale.US, "%s 阅读 · %s 赞",
                formatCount(article.views), formatCount(article.diggs)));
        return view;
    }

    private static String formatCount(int count) {
        if (count >= 10000) {
            return String.format(Locale.US, "%.1fw", count / 10000.0);
        }
        return String.valueOf(count);
    }

    private static final class ViewHolder {
        TextView title;
        TextView brief;
        TextView author;
        TextView meta;
        ImageView cover;
        ImageView avatar;
    }
}
