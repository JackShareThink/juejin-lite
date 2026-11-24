# 掘金 Lite

一个极简的掘金（Juejin）客户端 Android 应用：首页是掘金推荐流，点进去是文章详情。

- **零第三方依赖**：只用 Android framework（`Activity` / `ListView` / `WebView` / `HttpURLConnection` / `org.json`），不用 AndroidX、不用 Kotlin、不用图片库。
- **零 Gradle**：整套 APK 用 `aapt2 → javac → d8 → zipalign → apksigner` 手工构建，`build.sh` 一条命令出包，方便在没有 Android Studio 的机器上跑。
- 数据源是掘金的公开推荐流接口，详情页用 `juejin.cn` 的移动端文章页。

## 功能

| 功能 | 说明 |
| --- | --- |
| 推荐流 | `POST https://api.juejin.cn/recommend_api/v1/article/recommend_all_feed`，首页 20 条 |
| 上拉加载更多 | 滑到底部自动按接口返回的 `cursor` 取下一页 |
| 下拉不了，右上角刷新 | 无 AndroidX 就没有 SwipeRefreshLayout，用标题栏的刷新按钮重载 |
| 卡片列表 | 标题 / 摘要 / 封面图 / 作者头像 / 阅读数 / 点赞数 / 标签 |
| 文章详情 | WebView 打开 `https://juejin.cn/post/<article_id>`，带进度条和返回导航 |
| 图片 | 自带的 `ImageLoader`：4 线程 + `LruCache` + 列表复用防错位 |
| 异常兜底 | 断网、接口报错、空列表都有中文提示与重试入口 |

## 构建

需要 JDK 11+ 和 Android SDK 的 `build-tools` + 一个 `platform` 的 `android.jar`：

```bash
# 默认读 /c/Users/jack/android-sdk，可用环境变量覆盖
ANDROID_SDK=/path/to/android-sdk bash build.sh
```

产物是仓库根目录的 `app-1.0.0.apk`（debug 签名，首次构建会在 `keystore/` 生成 `debug.keystore`）。

构建流程见 `build.sh`：`aapt2 compile/link` → `javac`（对着 `android.jar` 编译）→ `d8` 生成 dex → 把 dex 塞进 APK → `zipalign` → `apksigner` 签名。

## 安装

```bash
adb install -r app-1.0.0.apk
adb shell am start -n io.juejin.lite/.MainActivity
```

小米 / HyperOS 上 `adb install` 会弹「USB安装提示」并返回 `INSTALL_FAILED_USER_RESTRICTED`，
需要点一次「继续安装」（`tools/e2e.sh` 会自动处理）。

## 端到端测试

`tools/e2e.sh` 会真的装包、启动、拉接口、点进文章、返回、上拉翻页，并逐步截图：

```bash
bash tools/e2e.sh 10.31.95.123:37797      # 指定设备序列号；不传则用唯一在线的设备
```

11 项断言：设备在线、安装成功、包已注册、Activity 启动、进程存活、推荐流加载
（`feed loaded size=N`）、无 `FATAL EXCEPTION`、列表渲染出条目、详情页 resumed、
`detail page finished`、返回可回列表、翻页触发第二次加载。截图落在 `docs/shots/`。

已在 **小米 Pad 6S Pro 12.4（Android 16, 2032×3048）** 和 x86_64 Android 14 模拟器上跑通 11/11。

| 推荐流 | 文章详情 |
| --- | --- |
| ![推荐流](docs/shots/e2e-01-feed.png) | ![文章详情](docs/shots/e2e-02-detail.png) |

## 目录

```
app/
  AndroidManifest.xml
  res/                     资源：布局、颜色、图标（矢量 + 脚本生成的 PNG）
  src/io/juejin/lite/
    MainActivity.java      推荐流
    DetailActivity.java    文章详情 WebView
    ArticleAdapter.java    列表适配器
    JuejinApi.java         接口封装与 JSON 解析
    ImageLoader.java       图片加载与缓存
    Article.java           数据模型
tools/make_icons.py        生成各密度启动图标
build.sh                   无 Gradle 构建脚本
```

## License

MIT
