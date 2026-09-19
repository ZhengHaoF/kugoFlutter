# 「我的」页三个统计数字 — 实现方案评估

> 日期：2026-09-19
> 位置：`app/lib/features/profile/profile_page.dart:132-139`
> 现状：`$likesCount`（真）/ `'56'`（假）/ `'12'`（假）
> **状态：评估中，未实施**

---

## 一、先看清现在是什么

```dart
Row(
  children: [
    Expanded(child: _Stat(label: '我喜欢', value: '$likesCount')),
    const _Divider(),
    Expanded(child: _Stat(label: '最近播放', value: '56')),
    const _Divider(),
    Expanded(child: _Stat(label: '歌单', value: '12')),
  ],
),
```

三个数字的数据性质**完全不同**，不能一起处理：

| 数字 | 数据性质 | 来源 | 难度 |
| --- | --- | --- | --- |
| 我喜欢 | 本地 | `likesProvider`（SharedPreferences，已有长度） | 已完成 |
| 最近播放 | 本地 | Drift `historyTracks` 表 | 低 |
| 歌单 | **远端** | 酷狗 `/user/playlist`（需登录 + 签名） | 中 |

---

## 二、逐个评估

### 2.1 我喜欢 —— 已经是真的

`likesProvider` 直接给长度，无需改动。**但有个隐患**：`LikesNotifier.build()` 里
`unawaitedLoad()` 是异步的，首帧会以空列表渲染，数字会从 `0` 跳到真实值。
现在因为旁边两个是死数字，这个跳变不明显；三个都变真之后会更刺眼。

**建议**：给 `_Stat` 加 `isLoading` 态显示 `—`（保留占位宽度避免抖动），
三个数字统一处理。

### 2.2 最近播放 —— 纯本地，成本最低

数据已经在 Drift 里：`kugo_db.dart` 的 `HistoryTracks` 表，
`QueueStore.loadHistoryAsync()` 已能取到 `List<Track>`。

**两个实现选项**：

| 方案 | 做法 | 评价 |
| --- | --- | --- |
| A. 复用 `loadHistoryAsync()` 取全量再 `.length` | 一行 | ❌ 为拿个数字把 200 行歌曲读进内存 |
| B. 加 SQL `COUNT(*)` | `kugo_db.dart` 加个 `countHistory()` | ✅ 推荐 |

方案 B 大概 6 行代码：

```dart
Future<int> countHistory() => historyTracks.count().getSingle();
```

再在 `QueueStore` 暴露一个 `Future<int> historyCount()` 转发。
**注意**：`historyTracks` 的上限是 200（`appendHistory` 里裁过），
所以这个数字最大显示 200。如果想让「最近播放」表示累计次数而非去重曲目数，
需要另加一张计数表 —— 但按「最近播放」的字面语义，**当前 200 去重上限是对的**。

**关键决策点**：要不要建 Provider？

- 现在 `history_page.dart` 和 `profile_page.dart` 都是各自 `initState` 里现拉。
- 如果只在 profile 用，**不需要 Provider**，在 profile 加个 `_historyCount` state 即可。
- 但如果之后要做「播放历史」页的实时联动，值得抽一个 `historyCountProvider`。
  我倾向**先不抽**，避免过度设计 —— 数字只在「我的」页出现。

### 2.3 歌单 —— 唯一的真难题

这是三个里唯一需要**网络 + 登录 + 签名**的。

**接口**：EchoMusic 用的是 `GET /user/playlist?page=1&pagesize=30`
（`src/renderer/api/playlist.ts:40`），走的是它自建的 `/api` 代理层。

**kugo 的现实约束**：

1. **必须登录** —— `AuthTokenHolder.userId` 有值才查得到，游客无歌单。
2. **网关可达性** —— 本项目已知问题：开发网对 `*.kugou.com` 有 URL 过滤，
   且 `mobilecdn` / `wwwapi` 这类公开 CDN 域名**没有** `/user/playlist`。
   需要走 `gateway.kugou.com` 或 `relation.user.kugou.com` 一类**带签名**的域名。
   现有 `login_repository.dart` 已经在用 `gateway.kugou.com`（`/v3/get_my_info`），
   说明这条链路在目标网络下是通的，但**签名参数（signature）是否覆盖 `/user/playlist`
   尚未验证**。
3. **纯数字是浪费** —— 拉 30 条歌单只为了页面上一个 `12`，性价比低。

**三个可选方案**：

| 方案 | 做法 | 成本 | 评价 |
| --- | --- | --- | --- |
| A. 拉列表取长度 | 复用 EchoMusic 的 `/user/playlist` | 中（含签名调通） | 数字是真的，但只为一个数拉列表 |
| B. 未登录/失败时显示 `—` | 不给假数，能取到才显示 | 低 | ✅ **推荐起步**：先说真话 |
| C. 做完整「我的歌单」页再回填 | 二期自建歌单功能的一部分 | 高 | ✅ **推荐终局**：数字自然就有了 |

**我的建议**：**C 是终局，但不要为 C 提前做 A。**
歌单数在「自建歌单」功能（gap 清单 P1 第 7 项）落地时会天然拥有数据源，
届时顺手回填即可。现在单独为它打通一条签名链路，收益太低。

**过渡做法（推荐）**：按 B 处理 ——
- 已登录且接口成功 → 显示真实数
- 未登录 / 接口失败 → 显示 `—`（或直接不显示该列）

---

## 三、推荐方案

分两步，第一步就能把「假数字」问题清掉：

### 第一步（小，建议现在就做）

1. `_Stat` 增加 `isLoading` / 空值态 → 显示 `—`，宽度用固定 minWidth 防抖
2. 「我喜欢」接 loading 态（修首帧跳变）
3. 「最近播放」加 `countHistory()` SQL 计数 + `QueueStore` 转发 + profile 内 state
4. 「歌单」**未登录时显示 `—`**；已登录但接口未接通也显示 `—`

产出：**页面上不再有任何假数字**。工作量约 0.5 人日，无网络依赖，可离线验收。

### 第二步（跟「自建歌单」一起做，不要单独排期）

在实现 P1「自建歌单 CRUD」时，顺手接 `/user/playlist` 拿列表与总数，
把「歌单」的真值回填。那时签名链路本来就要打通，边际成本接近零。

---

## 四、风险与注意

| 风险 | 说明 | 对策 |
| --- | --- | --- |
| 首帧闪烁 | 三个数字都是异步来的，会 0 → N 跳变 | 统一 loading 态显示 `—`，固定宽度 |
| 歌单列语义 | 「歌单」是指**自建**还是**收藏**？EchoMusic 两者都在 `/user/playlist` 里（`type` 区分） | 定下来再实现：建议显示「自建 + 收藏」总数，或拆两列 |
| 网络失败 | 歌单数拿不到时若回落到假数，就白改了 | 失败**必须**显 `—`，绝不回填假值 |
| 游客态 | 游客没有歌单，显示 `0` 还是 `—`？ | 建议 `—`（`0` 会被误读为「有账号但没歌单」） |
| 历史上限 | `historyTracks` 上限 200，数字封顶 | 若想显示累计值需另建计数表，先不做 |

---

## 五、涉及改动文件（预估）

**第一步**：
- `app/lib/data/storage/kugo_db.dart` — 加 `countHistory()`
- `app/lib/data/storage/queue_store.dart` — 加 `historyCount()` 转发
- `app/lib/features/profile/profile_page.dart` — `_Stat` 加态、接两个真数、歌单占位

**第二步**（随自建歌单）：
- `app/lib/data/repositories/playlist_repository.dart` — 加 `fetchMyPlaylists()`
- `app/lib/features/profile/profile_page.dart` — 回填
