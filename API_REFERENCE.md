# X 岛 API 参考文档

> 综合来源：TransparentLC/xdcmd Wiki + xdnmb_api 源码 + xdnmb_client 源码
> 生成日期：2026/04/21

---

## 一、基础信息

### 1.1 API 基础 URL

| 类型 | URL |
|------|-----|
| JSON API 基地址 | `https://api.nmb.best/api/` |
| 主站域名 | `www.nmbxd.com` |
| 备用 API | `https://api.nmb.best/` |
| CDN 基地址 | `https://image.nmb.best/` |
| 公告接口 | `https://nmb.ovear.info/nmb-notice.json` |
| 随机封面（302 跳转） | `https://nmb.ovear.info/h.php` |

### 1.2 URL 参数格式

支持两种格式（大小写不敏感）：
- 标准：`/?foo=bar&baz=qux`
- 路径式：`/foo/bar/baz/qux`

---

## 二、API 端点汇总

### 2.1 读取类接口

| 端点 | 方法 | 路径 | 说明 |
|------|------|------|------|
| 获取 CDN 列表 | GET | `Api/getCdnPath` | 返回可用 CDN 及权重 |
| 获取备用 API | GET | `Api/backupUrl` | 返回备用 API 域名列表 |
| 获取版块列表 | GET | `api/getForumList` | 返回所有版块及分组 |
| 获取时间线列表 | GET | `api/getTimelineList` | 返回时间线及 max_page |
| 查看版块 | GET | `api/showf` | 版块串列表 |
| 查看时间线 | GET | `api/timeline` | 时间线串列表 |
| 查看串 | GET | `api/thread` | 串内内容（含主串+回复） |
| 只看 PO | GET | `api/po` | 串内仅显示 PO 主回复 |
| 查看引用 | GET | `api/ref` | 单条帖子引用 |
| 查看订阅 | GET | `api/feed` | 订阅串列表 |
| 获取最新帖子 | GET | `Api/getLastPost` | 3 秒窗口内最新发帖 |
| 获取公告 | GET | `nmb-notice.json` | 系统公告 |

### 2.2 写入类接口

| 端点 | 方法 | 路径 | 说明 |
|------|------|------|------|
| 发新串 | POST | `Home/Forum/doPostThread.html` | |
| 回复串 | POST | `Home/Forum/doReplyThread.html` | |
| 添加订阅 | POST | `api/addFeed` | |
| 删除订阅 | POST | `api/delFeed` | |

---

## 三、串内内容接口（`/api/thread`）

### 3.1 请求参数

| 参数名 | 类型 | 必填 | 默认值 | 说明 |
|--------|------|------|--------|------|
| `id` | Number | 是 | — | 主串 ID |
| `page` | Number | 否 | 1 | 页码，从 1 开始 |

### 3.2 响应结构

```json
{
  "id": 12345678,
  "fid": 4,
  "ReplyCount": 57,
  "img": "",
  "ext": "",
  "now": "2026/04/20(日)14:30:15",
  "user_hash": "abcdefghi",
  "name": "无名氏",
  "title": "无标题",
  "content": "<p>主串内容</p>",
  "sage": 0,
  "admin": 0,
  "Hide": 0,
  "Replies": [
    {
      "id": 12345679,
      "fid": 4,
      "user_hash": "jklmnopqr",
      "name": "无名氏",
      "title": "无标题",
      "now": "2026/04/20(日)14:35:22",
      "content": "<p>回复1</p>",
      "img": "",
      "ext": "",
      "sage": 0,
      "admin": 0,
      "Hide": 0
    }
  ]
}
```

### 3.3 分页行为（关键）

| 特征 | 说明 |
|------|------|
| **每页回复上限** | **19 个**（主串不计入） |
| **实际回复数** | 可能不足 19，取决于该页实际有多少回复 |
| **页码从 1 开始** | `page=1` 返回主串 + 第 1 页回复 |
| **ReplyCount 含义** | 主串的**总回复数**，包含已被删除的回复 |
| **删帖影响** | 由于删帖，某页实际返回的回复数可能少于 19，甚至为 0 |
| **maxPage 计算** | `replyCount > 0 ? (replyCount / 19).ceil() : 1` |
| **尾页** | 可能不足 19 个回复；可能因删帖而为空 |

> **重要**：`ReplyCount` 统计的是包含已删除回复的总量。如果某串有 100 条回复但其中 20 条被删除，则 `ReplyCount = 100`，`maxPage = 6`。但实际各页返回的回复总数只有 80 条。

### 3.4 只看 PO 接口（`/api/po`）

参数和响应结构与 `/api/thread` 完全相同，但只返回 PO 主（主串发布者）的回复。

| 特征 | 说明 |
|------|------|
| 筛选逻辑 | 服务端按 `user_hash` 筛选 |
| 分页方式 | 与 `/thread` 相同的 page 参数，但每页最多 19 个 PO 回复 |
| 页码关系 | `/po` 的页码与 `/thread` 的页码**不对应**同一批回复 |

---

## 四、版块/时间线接口（`/api/showf`、`/api/timeline`）

### 4.1 请求参数

| 参数名 | 类型 | 必填 | 默认值 | 说明 |
|--------|------|------|--------|------|
| `id` | Number | 是 | — | 版块 ID / 时间线 ID |
| `page` | Number | 否 | 1 | 页码，从 1 开始 |

### 4.2 响应结构

返回串列表，每个串包含：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | Number | 串 ID |
| `fid` | Number | 版块 ID |
| `ReplyCount` | Number | 总回复数（含已删除） |
| `img` / `ext` | String | 图片信息 |
| `now` | String | 发布时间，格式：`2026/04/20(日)14:30:15` |
| `user_hash` | String | 发布者哈希 |
| `content` | String | HTML 内容 |
| `Replies` | Array | 最近最多 5 条回复（嵌入） |
| `RemainReplies` | Number | 省略的回复数量 |

> **注意**：由于删帖原因，`Replies` 的长度不一定等于 5，也不一定等于 `ReplyCount`（当 ReplyCount <= 5 时）。

### 4.3 分页行为

| 特征 | 说明 |
|------|------|
| 每页串数 | 固定 20 个 |
| 时间线 max_page | 综合线=20，创作线=30，非创作线=20 |
| 超页处理 | 超过 max_page 返回最后一页数据 |
| 版块 max_page | `min((threadCount / 20).ceil(), 100)` |

---

## 五、订阅接口（`/api/feed`）

### 5.1 请求参数

| 参数名 | 类型 | 必填 | 默认值 | 说明 |
|--------|------|------|--------|------|
| `uuid` | String | 是 | — | 订阅 ID（任意字符串） |
| `page` | Number | 否 | 1 | 页码 |

### 5.2 响应特点

- **所有数字字段返回为 String 类型**
- `reply_count`：总回复数（String）
- `recent_replies`：最近回复 ID 数组，格式为字符串 `"[0,1,2,3]"`

---

## 六、引用接口（`/api/ref`）

### 6.1 请求参数

| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `id` | Number | 是 | 帖子 ID |

### 6.2 响应特点

- 返回单条帖子，**不含父串 ID**
- 无法直接通过帖子 ID 查询其所在串的页码
- 字段结构与帖子相同，但 `forumId` 和 `replyCount` 为 `null`

---

## 七、数据类型详解

### 7.1 `Post`（帖子）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 帖子唯一 ID |
| `forumId` | int | 版块 ID |
| `replyCount` | int | **总回复数（含已删除）** |
| `image` | String | 图片相对路径 |
| `imageExtension` | String | 图片扩展名 |
| `postTime` | DateTime | 发布时间 |
| `userHash` | String | 用户哈希 |
| `name` | String | 昵称，默认"无名氏" |
| `title` | String | 标题，默认"无标题" |
| `content` | String | HTML 内容 |
| `isSage` | bool | 是否 sage |
| `isAdmin` | bool | 是否红名 |
| `isHidden` | bool? | 是否隐藏 |

### 7.2 `Thread`（串）

| 字段 | 类型 | 说明 |
|------|------|------|
| `mainPost` | Post | 主串 |
| `replies` | List&lt;Post&gt; | 该页的回复列表 |
| `tip` | Tip? | 随机出现的系统提示 |
| `maxPage` | int | `mainPost.replyCount > 0 ? (replyCount / 19).ceil() : 1` |

### 7.3 `ForumThread`（版块列表中的串项）

| 字段 | 类型 | 说明 |
|------|------|------|
| `mainPost` | Post | 主串 |
| `recentReplies` | List&lt;Post&gt; | 最近最多 5 条回复 |
| `remainReplies` | int? | 省略的回复数量 |
| `maxPage` | int | `(replyCount / 19).ceil()` |

---

## 八、分页模型关键约束

### 8.1 串内回复分页

```
Page 1: 主串 + 回复索引 0~18（实际可能不足19条）
Page 2: 主串 + 回复索引 19~37（实际可能不足19条）
Page 3: 主串 + 回复索引 38~56（实际可能不足19条）
...以此类推
```

**核心约束**：
1. API 按固定窗口分页（每页 19 条原始回复索引）
2. 但返回的实际回复数可能因删帖而少于 19
3. `ReplyCount` 是包含已删除回复的总量，**不能**用于从 flat index 反推页码
4. **没有接口**支持通过帖子 ID 查询其所在页码

### 8.2 对客户端的影响

| 影响点 | 说明 |
|--------|------|
| 无法精确从 flat index 计算页码 | 因为删帖导致各页实际回复数不一致 |
| 无法通过帖子 ID 直接定位 | 只能逐页加载查找 |
| 缓存策略需考虑删帖 | 缓存的页数据可能因删帖而与实际不符 |
| `maxPage` 可能虚高 | 基于 `ReplyCount` 计算，而 `ReplyCount` 含已删除回复 |

---

## 九、Cookie / 认证

| 项 | 说明 |
|----|------|
| Cookie 名 | `userhash` |
| 格式 | URL 编码后的值 |
| 作用 | 身份识别、红名判定、饼干权限 |
| 受限版面 | 必须通过 JSON API (`api.nmb.best`) 携带 cookie 访问 |

---

## 十、发串 / 回串接口

### 10.1 发新串（`POST Home/Forum/doPostThread.html`）

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | String | 否 | 默认"无名氏" |
| `title` | String | 否 | 默认"无标题" |
| `content` | String | 条件 | 内容和图片不能同时为空 |
| `fid` | Number | 是 | 版块 ID |
| `image` | File | 条件 | 附件图片 |
| `water` | Boolean | 否 | 是否加水印 |

### 10.2 回串（`POST Home/Forum/doReplyThread.html`）

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | String | 否 | 默认"无名氏" |
| `title` | String | 否 | 默认"无标题" |
| `content` | String | 条件 | 内容和图片不能同时为空 |
| `resto` | Number | 是 | 目标串 ID |
| `image` | File | 条件 | 附件图片 |
| `water` | Boolean | 否 | 是否加水印 |

---

## 十一、时间线 Max Page

| 时间线 | max_page |
|--------|----------|
| 综合线 | 20 |
| 创作线 | 30 |
| 非创作线 | 20 |

---

*本文档由 Claude 整理生成，供 xdnmb_client 开发参考使用。*
