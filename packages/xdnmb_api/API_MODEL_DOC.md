# xdnmb_api — API 与模型字段文档（面向 Windows/Flutter 客户端）

> 来源：`lib/src/xdnmb.dart`、`lib/src/urls.dart`、`lib/src/client.dart`、`lib/src/cookie.dart` 及 `test/` 用例。
>
> 目标：把 **你做客户端 UI 时需要展示/跳转/发帖/登录** 的字段语义说明白。

## 1. 快速上手（客户端建议调用顺序）

### 1.1 启动时
1. `final api = XdnmbApi(userHash: savedUserHashOrNull);`
2. `await api.updateUrls();`（可选但强烈建议）
3. 如遇主站不可用：`api.useBackupApi(true);`

### 1.2 浏览
- 入口：`getForumList()` / `getTimelineList()`
- 列表：`getForum(forumId, page)` / `getTimeline(timelineId, page)`
- 串页：`getThread(mainPostId, page)` / `getOnlyPoThread(mainPostId, page)`
- 引用：`getReference(postId)` 或 `getHtmlReference(postId)`

### 1.3 发串/回串（需要饼干 userhash）
- 发串：`postNewThread(...)` / `postNewThreadWithImage(...)`
- 回串：`replyThread(...)` / `replyThreadWithImage(...)`

### 1.4 账号登录 + 获取饼干（导出 userhash）
> **注意**：登录相关接口要求 **先获得 PHPSESSID**。

建议顺序：
1. `final bytes = await api.getVerifyImage();`（展示验证码，也会让 `Client` 拿到 PHPSESSID）
2. `await api.userLogin(email: ..., password: ..., verify: ...);`
3. `final list = await api.getCookiesList();`
4. `final cookie = await api.getCookie(cookieId);` → 得到 `XdnmbCookie.userHash`（客户端可保存）

---

## 2. 公共错误与异常

### 2.1 `XdnmbApiException`
- 业务/参数/权限/解析错误统一抛这个异常。
- 常见触发：
  - `forumId <= 0`、`page <= 0`、`mainPostId <= 0`
  - 发串/回串没饼干：`发串需要饼干` / `回串需要饼干`
  - 登录未先获取 PHPSESSID：`用户登陆需要 PHPSESSID`

### 2.2 `HttpStatusException`
- 底层 HTTP 状态码不是 200（OK）时抛。

---

## 3. URL 与容灾（`XdnmbUrls`）

### 3.1 单例与切换
- `XdnmbUrls()` 是单例。
- `XdnmbUrls().useBackupApi = true/false` 决定 `apiUrl`：
  - `false` → `baseUrl`
  - `true` → `backupApiUrl`

### 3.2 推荐做法
- App 启动时调用 `XdnmbApi.updateUrls()`（内部是 `XdnmbUrls.update(_client)`），减少域名改变造成的不可用。

---

## 4. 核心入口：`class XdnmbApi`

> `XdnmbApi` 内部持有一个 `Client`，同时维护：
> - `xdnmbCookie: XdnmbCookie?`（发言/部分板块访问用的“饼干”：`userhash=...`）
> - `xdnmbUserCookie: Cookie?`（账号登录后的用户 Cookie，用于饼干管理）

### 4.1 构造与状态
- `XdnmbApi({String? userHash, HttpClient? client, Duration? connectionTimeout, Duration? idleTimeout, String? userAgent})`
- `bool get isLogin`：`xdnmbUserCookie != null`
- `bool get hasPhpSessionId`：`_client.xdnmbPhpSessionId != null`
- `void close()`：关闭 HTTP client

### 4.2 基础信息
- `Future<void> updateUrls()`：更新域名/CDN/备用 API
- `void useBackupApi(bool)`：切换是否走备用 API
- `Future<Notice> getNotice()`：公告（JSON）
- `Future<List<Cdn>> getCdnList({String? cookie})`
- `Future<BackupApiList> getBackupApiList({String? cookie})`

### 4.3 版块/时间线
- `Future<ForumList> getForumList({String? cookie})`
- `Future<List<Timeline>> getTimelineList({String? cookie})`
- `Future<HtmlForum> getHtmlForumInfo(int forumId, {String? cookie})`：从网页版 HTML 解析版块名与版规

### 4.4 列表
- `Future<List<ForumThread>> getForum(int forumId, {int page = 1, String? cookie})`
  - 一页最多 20 串
- `Future<List<ForumThread>> getTimeline(int timelineId, {int page = 1, String? cookie})`

### 4.5 串详情
- `Future<Thread> getThread(int mainPostId, {int page = 1, String? cookie})`
  - 一页最多 19 回复
- `Future<Thread> getOnlyPoThread(int mainPostId, {int page = 1, String? cookie})`
- `Future<Reference> getReference(int postId, {String? cookie})`
- `Future<HtmlReference> getHtmlReference(int postId, {String? cookie})`

### 4.6 订阅（Feed）
- `Future<List<Feed>> getFeed(String feedId, {int page = 1, String? cookie})`（一页最多 10）
- `Future<(List<HtmlFeed>, int?)> getHtmlFeed({int page = 1, String? cookie})`（一页最多 20，额外返回最大页数）
- `Future<void> addFeed(String feedId, int mainPostId, {String? cookie})`
- `Future<void> deleteFeed(String feedId, int mainPostId, {String? cookie})`
- `Future<void> addHtmlFeed(int mainPostId, {String? cookie})`
- `Future<void> deleteHtmlFeed(int mainPostId, {String? cookie})`

### 4.7 发串/回串
- `Future<void> postNewThread({required int forumId, required String content, String? name, String? email, String? title, bool watermark = false, Image? image, String? cookie})`
- `Future<void> postNewThreadWithImage({required int forumId, required String content, required String imageFile, ...})`
- `Future<void> replyThread({required int mainPostId, required String content, String? name, String? email, String? title, bool watermark = false, Image? image, String? cookie})`
- `Future<void> replyThreadWithImage({required int mainPostId, required String content, required String imageFile, ...})`

### 4.8 发帖后拿“最新发的串”
- `Future<LastPost?> getLastPost({String? cookie})`
  - 注释说明：发新串后第一次调用返回最新发的串，再次可能返回 `null`
  - **没饼干会返回 `null`**

### 4.9 验证码 / 登录 / 饼干管理
- `Future<Uint8List> getVerifyImage()`：验证码图片 bytes
- `Future<void> userLogin({required String email, required String password, required String verify})`
  - 前置：`hasPhpSessionId == true`（先调 `getVerifyImage()`）
  - 成功后 `xdnmbUserCookie` 会被设置（cookie 名称期望为 `memberUserspapapa`）
- `Future<CookiesList> getCookiesList({String? userCookie})`
- `Future<XdnmbCookie> getCookie(int cookieId, {String? userCookie})`：导出饼干（得到 userhash）
- `Future<void> getNewCookie({required String verify, String? userCookie})`
  - 前置：需要 `PHPSESSID` + 用户 cookie
- `Future<void> deleteCookie({required int cookieId, required String verify, String? userCookie})`
  - 前置：需要 `PHPSESSID` + 用户 cookie

---

## 5. 模型字段文档

### 5.1 `enum PostType`
- `post`：普通串
- `tip`：官方 tip（可能广告）
- `reference`：引用
- `feed`：订阅
- `other`：兜底

便捷判断：`isPost/isTip/isReference/isFeed/isOther`

### 5.2 `abstract interface class PostBase`（所有“帖子类对象”的通用字段）
| 字段 | 类型 | 说明 | UI 常用场景 |
|---|---:|---|---|
| `id` | `int` | 串/引用/订阅条目的 ID | 跳转、引用 |
| `forumId` | `int?` | 所在版块 ID；部分模型恒为 `null` | 面包屑/跳转 |
| `replyCount` | `int?` | 主串回复数（含被删除）；回串为 0；有些模型为 `null` | 列表右侧“xx 回复” |
| `image` | `String` | 图片名（不含扩展） | 拼接图片 URL |
| `imageExtension` | `String` | 图片扩展（如 `.jpg`） | 拼接图片 URL |
| `postTime` | `DateTime` | 发帖时间 | 列表副标题 |
| `userHash` | `String` | 发帖者饼干名/标识（不是账号） | 显示饼干标识 |
| `name` | `String` | 昵称 | 显示“无名氏/自定义” |
| `title` | `String` | 标题 | 卡片标题 |
| `content` | `String` | 内容（可能含 HTML/标记） | 正文渲染 |
| `isSage` | `bool?` | 是否 sage（锁回复） | 标识/灰显 |
| `isAdmin` | `bool` | 是否红名管理员 | 颜色/徽章 |
| `isHidden` | `bool?` | 是否被隐藏 | 折叠/不展示 |
| `postType` | `PostType` | 类型 | UI 分支 |

#### `extension BasePostExtension on PostBase`
- `maxPage`：按 `replyCount/19` 推算主串最大页数（可能为 `null`）
- `hasImage`：`image.isNotEmpty`
- `imageFile`：`'$image$imageExtension'`
- `thumbImageUrl` / `imageUrl`：用 `XdnmbUrls().cdnUrl` 拼 `thumb/` 和 `image/`

> 客户端建议：不要自己拼 host/path，统一用这些扩展。

### 5.3 `class Post implements PostBase`（普通串/回复）
核心字段（均为非空）：
- `id`：串 ID
- `forumId`：版块 ID（注意：回复的 forumId 可能因移串与主串不一致，源码有说明）
- `replyCount`：仅主串有意义；回复通常为 0
- `image` / `imageExtension`
- `postTime`
- `userHash`
- `name`（缺省：无名氏）
- `title`（缺省：无标题）
- `content`
- `isSage`
- `isAdmin`
- `isHidden`

### 5.4 `class ForumThread`（列表页的“一个主串卡片”）
- `mainPost: Post`：主串
- `recentReplies: List<Post>`：最后回复，最多 5 个（但 **不保证** 一定有 5 个或与 replyCount 一致）
- `remainReplies: int?`：除 recentReplies 外剩余数量（来自接口字段 `RemainReplies`）
- `maxPage`：按主串 `replyCount/19` 计算

UI 建议：
- 列表卡片：主串 + recent replies 预览；若 `remainReplies != null && remainReplies > 0` 可显示“还有 xx 回复未展开”。

### 5.5 `class Thread`（串详情页）
- `mainPost: Post`
- `replies: List<Post>`：某一页回复（可能 0：被删光 or 真的没回复）
- `tip: Tip?`：官方 tip，随机出现（解析逻辑：如果 Replies[0]['fid'] == null 则视为 tip）
- `maxPage`：按主串 `replyCount/19` 计算

### 5.6 `class Tip implements PostBase`（官方 tip）
- `id` 默认 `9999999`
- `forumId/replyCount/isSage/isHidden` 都是 `null`
- `isAdmin` 默认 true

UI 建议：当作一种特殊“系统消息卡片”。

### 5.7 引用：`ReferenceBase` / `Reference` / `HtmlReference`
共性（`ReferenceBase`）：
- `forumId/replyCount/isHidden` 恒为 `null`
- `postType` 恒为 `reference`

#### `class Reference`（API JSON 引用）
字段：
- `id, image, imageExtension, postTime, userHash, name, title, content, isSage, isAdmin`
- `status: String`：注释写“总是 'n'”

#### `class HtmlReference`（HTML 引用）
- 与 Reference 类似
- `mainPostId: int?`：只有“引用串是主串”时才不是 null

UI 建议：
- 如果你需要判断“引用目标是否为主串”，优先用 `HtmlReference.mainPostId`。

### 5.8 订阅：`FeedBase` / `Feed` / `HtmlFeed`
共性（`FeedBase`）：
- `isSage` 恒为 `null`
- `postType` 恒为 `feed`

#### `class Feed`（API JSON 订阅）
字段：
- `id`
- `userId`：主串用户 ID
- `forumId`
- `replyCount`
- `recentReplies: List<int>`：最近回复串 ID（最多 5）
- `category`：注释说明“总是空字符串”
- `fileId`：图片文件 ID
- `image/imageExtension`
- `postTime`
- `userHash`
- `name`
- `email`
- `title`
- `content`
- `status`：注释“总是 'n'”
- `isAdmin`
- `isHidden`
- `po`：注释“总是空字符串”

#### `class HtmlFeed`（HTML 订阅）
- 字段更少：`id/image/imageExtension/postTime/userHash/name/title/content/isAdmin`
- `forumId/replyCount/isHidden` 恒为 null
- 解析函数返回：`(List<HtmlFeed>, int? maxPage)`

### 5.9 `class LastPost implements PostBase`（最新发的串）
- `id`
- `mainPostId: int?`：为 null 表示它本身是主串；不为 null 表示它是回串（`resto` 字段）
- `postTime/userHash/name/email/title/content/isSage/isAdmin`
- `forumId/replyCount/isHidden` 恒为 null
- `image/imageExtension` 恒为空字符串

UI 建议：发帖成功后可以用它来做“跳转到我刚发的串/回复”。

### 5.10 图片上传：`ImageType` / `Image`
- `ImageType`：仅支持 `jpeg/png/gif`
  - `mineType()`（注意：源码拼写是 mineType，实际含义是 mimeType）
  - `fromMimeType(String)`
- `Image`：
  - `filename`：文件名
  - `data`：bytes
  - `imageType`：如不传，会用 `mime.lookupMimeType` 根据文件名+headerBytes 推断，不支持则抛 `XdnmbApiException('无效的图片格式')`
  - `static Future<Image> fromFile(String path)`

---

## 6. 饼干相关模型（`lib/src/cookie.dart`）

### 6.1 `class XdnmbCookie`
- `userHash: String`：最关键字段
- `name: String?`：饼干显示名
- `id: int?`：饼干 ID
- `cookie`（getter）：`'userhash=$userHash'`（用于请求 header）

### 6.2 `class CookiesList`
- `canGetCookie: bool`：是否开放领取
- `currentCookiesNum: int`：当前已有饼干数量
- `totalCookiesNum: int`：上限（槽位）
- `cookiesIdList: List<int>`：饼干 ID 列表（配合 `getCookie(id)` 导出）

---

## 7. 论坛与版块模型（补充：基于源码前半段）

### 7.1 `abstract interface ForumBase`
| 字段 | 类型 | 说明 |
|---|---:|---|
| `id` | `int` | 版块/时间线 ID |
| `name` | `String` | 名称 |
| `displayName` | `String` | 显示名（为空则用 name） |
| `message` | `String` | 版块信息/版规 |
| `maxPage` | `int` | 最大页数（不同实现不同规则） |

扩展：`ForumBaseExtension.showName` → `displayName` 非空用它，否则 `name`。

### 7.2 `class ForumGroup`
- `id: int`：版块组 ID
- `sort: int`：排序（小的在前）
- `name: String`：组名
- `status: String`：注释“总是 'n'”

### 7.3 `class Forum implements ForumBase`
- `id`
- `forumGroupId`：所属组
- `sort`
- `name/displayName/message`
- `interval: int`：发串最小间隔（秒）
- `safeMode: bool`：保护模式
- `autoDelete: int`：自动删除时间间隔（含义不完全确定）
- `threadCount: int`：主串数量（含被删）
- `permissionLevel: int`：>0 时需要饼干访问；数值像是最低饼干槽要求（源码注释带问号）
- `forumFuseId: int`
- `createTime/updateTime: String`：字符串时间（不保证准确）
- `status: String`：注释“总是 'n'”
- `maxPage`：根据 `threadCount` 估算，最多 100 页

### 7.4 `class ForumList`
- `forumGroupList: List<ForumGroup>`
- `forumList: List<Forum>`
- `timelineList: List<Timeline>?`：有些数据把时间线混在 `getForumList()` 里（id < 0）

### 7.5 `class Timeline implements ForumBase`
- `id/name/displayName/message/maxPage(默认 20)`

### 7.6 `class HtmlForum implements ForumBase`
- `id/name/message`
- `displayName` 恒空字符串（所以显示用 `name`）
- `maxPage` 恒为 100

---

## 8. UI 渲染与内容格式（重要提示）
- `content` 字段来自接口，可能包含 HTML 片段或自定义标记（例如引用、折叠 `[h] [/h]`、骰子 `[n]` 等）。
- 源码内有 `_trimWhiteSpace()` 等 HTML 解析辅助，但 **并没有提供“把 content 渲染成富文本 Widget”** 的现成组件。

建议你后续告诉我你希望的渲染策略：
- 纯文本（去标签）
- 简易富文本（引用高亮、链接可点）
- 完整 HTML 渲染（Flutter 里通常需要额外依赖）

---

## 9. 已知“语义不完全确定”的字段（我建议你在 UI 里弱化依赖）
- `Forum.autoDelete`：注释带问号
- `Forum.permissionLevel`：注释推测为最低饼干槽要求（>0 才需要饼干）
- 某些 `status` 字段注释说总是 'n'（UI 可忽略或仅用于调试）

---

## 10. 需求覆盖
- ✅ 已输出：`XdnmbApi` 所有公开方法说明 + 相关模型字段语义（Post/Thread/ForumThread/Reference/Feed/Html* 等）
- ✅ 已补充：URL/容灾、异常处理、登录/饼干前置条件、图片拼接与上传约束

后续你给我“设计注意事项”后，我可以按你的 UI/架构偏好（如 Riverpod/BLoC、缓存策略、分页策略、富文本渲染规则）开始搭建 Windows 客户端工程与页面骨架。
