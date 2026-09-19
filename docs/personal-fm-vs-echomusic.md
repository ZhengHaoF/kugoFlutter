# 私人 FM — 与 EchoMusic 功能点差异评估

> 日期：2026-09-19
> 现场：`kugoFlutter` @ `feda11e`（工作区干净）
> 参考：`D:\work\EchoMusic`（v2.3.2-beta.5）
> 对象：`app/lib/features/fm/personal_fm_page.dart`（376 行）
> **状态：仅评估，未动代码**

---

## 一、结论先行

**当前项目的「私人 FM」不是 FM，是一个披着黑胶外壳的「关键词搜索播放器」。**

三个递进的结论：

1. **数据源是假的，而且不是"降级"意义上的假。**
   `_load()` 调的是 `searchRepository.searchSongs(_pool.keyword, pageSize: 20)`
   —— 即 `mobilecdn/api/v3/search/song`。三个"歌池"实际只是三个**搜索关键词**
   （`'热门'` / `'民谣 电子'` / `'独立 冷门'`）。
   所以「口味」= 搜索"热门"，「风格」= 搜索"民谣 电子"。
   **"私人"标签是自我矛盾的**：它是全站热歌搜索，与用户任何行为无关。

2. **反馈回路是假的。** 「不喜欢」只往**页面局部的 `Set<String> _disliked`** 里塞一个 id，
   `_next()` 本地跳过它。退出页面集合即销毁 —— 不落库、不上报、下次进来照旧推。
   服务端永远不知道你不喜欢什么。同理「红心」只写本地 likes，不回传给推荐系统。

3. **真正的 `/personal/fm` 签名接口，本项目目前打不通 —— 但原因不是网络。**
   本次实测证明网关链路**是通的**（同一台网关、同一套签名、同一时刻，
   `POST /everyday_song_recommend` 返回 **103,698 字节**真实个性化数据）。
   而 `/personal/fm` 在所有候选路径/路由下返回 **502（网关错误）或 404**，
   从未拿到业务响应。→ 这是**路由/路径/参数形态问题**，不是 IP 被封。
   详见 §三。

**一句话：想要真 FM，工作量的 80% 不在 UI，在于把 `/personal/fm` 的正确请求形态试出来。**

---

## 二、逐维度差异对照

| 维度 | EchoMusic | kugoFlutter 现状 | 差距性质 |
| --- | --- | --- | --- |
| **数据源** | 签名网关 `/personal/fm`（真推荐引擎） | `mobilecdn /search/song` 关键词搜索 | 🔴 **本质** |
| **"歌池"语义** | `song_pool_id` 0/1/2 → 口味/风格/探索，是**推荐侧参数** | 三个硬编码关键词 | 🔴 **本质** |
| **模式切换** | **两条轴**：歌池（口味/风格/探索）× 模式（红心/小众/速览） | 只有一条轴（口味/风格/探索），且是伪的 | 🔴 **缺失一整轴** |
| **反馈上报** | `action='play'\|'garbage'` + `playtime` + `is_overplay` + `remain_songcnt`，服务端据此学习 | 无。本地 `Set` 跳过 | 🔴 **本质** |
| **推荐理由** | `recDesc` —— 页面显示"根据你喜欢的XX推荐" | 无 | 🟠 体验缺口 |
| **信息条** | 时长 / 音质 / 语种 / **相似度** 四个 chip | 无 | 🟠 体验缺口 |
| **下一首预览** | 侧立唱片堆（当前盘 + 最多 3 张后续，`ResizeObserver` 动态算数量） | 无（只有底部 `1/N` 文字） | 🟠 体验缺口 |
| **缓冲/预取** | `personalFmBuffer` 维持 >4 首可播；`peekNext`/`commit`/`skipFailed` 三段式 | 无（一次性 20 首，播完环绕回开头） | 🟠 架构缺口 |
| **过会话控制** | `personalFmSessionEpoch` —— 切模式/歌池自增，丢弃过期异步响应 | 无（切换即 `_load()`，**旧请求可能与新请求竞态**） | 🟡 潜在 bug |
| **去重** | `fmRequests`/`fmRefillAfter` WeakMap + 5s 冷却；`rememberOnce` 账本上限 128 | 无 | 🟡 潜在 bug |
| **登录门槛** | 有：`v-if="!isLoggedIn"` → "登录后查看私人 FM" | 无门槛，游客也能"用"（因为它本质是搜索） | 🟢 现状更宽松 |
| **加载骨架** | 有（初载骨架屏） | `CircularProgressIndicator` | 🟢 可接受 |
| **播完不重播** | 从服务端续推，理论上无限流 | `_next()` 播完 `i=0` **绕回第一首**，形成死循环 | 🟡 行为缺陷 |
| **MV/红心按钮** | 红心写服务端 | 红心写本地 likes + SnackBar，然后 `_next()` | 🟢 可接受 |

---

## 三、`/personal/fm` 可达性实测（本次核心新证据）

### 3.1 对照组：网关链路确实是通的

同一时刻、同一 `mid`、同一套 `signatureAndroidParams`、同一 `User-Agent`：

| 调用 | 结果 |
| --- | --- |
| `POST /everyday_song_recommend`（`x-router: everydayrec.service.kugou.com`） | ✅ **HTTP 200，103,698 字节**，`song_list_size:30`，真实个性化歌单 |
| `GET /v5/url`（`x-router: trackercdn.kugou.com`） | ✅ HTTP 200，业务级错误 `illegal hash or album_audio_id`（说明**路由到了业务处理器**，只是我给的 hash 是假的） |
| `POST /v3/get_my_info`（`x-router: usercenter`） | ✅ HTTP 200，`error_code: 20010`（未登录，属预期业务码） |
| `POST /mcomment/v1/cmtlist` | ✅ HTTP 200，`err_code:20006 invalid signature`（业务级校验，说明请求已抵达） |

→ **结论：`https://gateway.kugou.com` 从本机完全可达，签名算法正确，
`x-router` 机制生效。** 这条链路不是瓶颈。

### 3.2 目标：`/personal/fm` 全部失败

| 路径 | x-router | 方法 | 结果 |
| --- | --- | --- | --- |
| `/personal/fm` | 无 | GET | 502 |
| `/personal/fm` | 无 | POST | 502 |
| `/personal/fm` | `fm.service.kugou.com` | GET/POST | **404** |
| `/personal/fm` | `personal.service.kugou.com` | GET/POST | 502 |
| `/personal/fm` | `personalrec.service.kugou.com` | GET/POST | 502 |
| `/personal/fm` | `personalized.service.kugou.com` | GET/POST | 502 |
| `/personal/fm` | `recommend.service.kugou.com` | GET/POST | 502 |
| `/personal/fm` | `song.service.kugou.com` | GET/POST | 502 |
| `/personal/fm` | `kmr.service.kugou.com` | GET/POST | **404** |
| `/v1|v2|v3/personal/fm` | 无 | GET | 502 |
| `/personal/fm` | 带全套 kg-\* 头 | GET | 502 |

**没有任何一次拿到业务响应**（对比组全部拿到）。404 说明"该 router 认识这个域名但没这个路径"，
502 说明"router 解析不到上游"。

### 3.3 这说明什么

`/personal/fm` 是 KuGouMusicApi（EchoMusic 后端的蓝本）里的写法。
EchoMusic 本地能跑通，是因为它后端可能：
- 用了**不同的 appid / clientver**（概念版 `3116` 未必是 FM 接口的服务对象）；
- 或者 `/personal/fm` 是**较老的接口**，需要在网关之外的主机（`fm.kugou.com` 之类，本机 DNS/SSL 直接失败）；
- 或者需要**登录态**（`token`/`userid`）才路由。

**未验证事项（实施时第一步就试）**：
1. 带**真实登录 token** 再打一遍 `/personal/fm`（本次没有可用 token）；
2. 换 KuGouMusicApi 里其它 appid 组合（如 `1005` / `1000`，web 版）；
3. 直连 `fm.kugou.com` / `personal.kugou.com`（本次这两个主机 **SSL 握手直接失败**
   `基础连接已经关闭`，需判断是 DNS 污染还是证书链问题）；
4. 若以上均不通 → **放弃真 FM 接口**，转向方案 B（见 §五）。

---

## 四、现状代码里的三个隐性缺陷（与 EchoMusic 对照才发现）

这三个不是"没有这个功能"，而是**现在的实现有 bug**，修复成本极低：

### 4.1 竞态：切换歌池时旧请求可能覆盖新结果

```dart
onSelectionChanged: (s) {
  setState(() => _pool = s.first);
  _load();                       // ← 两次 _load 并发时无序号保护
},
```
`_load()` 里 `await searchRepository.searchSongs(...)` 之后直接
`setState(() => _tracks = list)`，**没有校验这次响应是否属于当前 `_pool`**。
快速连点两下，先发的慢请求后到 → 显示的是上一个歌池的歌。
EchoMusic 用 `personalFmSessionEpoch` 解决，本项目一行 `int _requestToken` 就能修。

### 4.2 播放队列与页面状态不同步

`_playAt` 把**整个 `_tracks`** 灌进 `playerControllerProvider`：
```dart
ref.read(playerControllerProvider.notifier).playQueue(_tracks, startIndex: idx);
```
后果：用户在**播放页/迷你条上按"下一首"**，走的是 player 自己的队列游标，
`_index` 完全不知道；回到 FM 页，`_index` 还停在旧位置 → **UI 显示的歌与实际在播的歌不一致**。
`_next()` / `_dislike()` 也只会读到过期的 `_index`。
这是"FM 页"和"播放器"两套状态各管各的必然结果。

### 4.3 歌池耗尽后静默绕回

`_next()`：`if (i >= _tracks.length) i = 0;`
20 首播完 → 回到第 1 首，**用户没有任何感知**（不重新拉取、不提示）。
真 FM 的语义是"永不重复的流"，这里退化成"循环歌单"。

---

## 五、两条路线的成本与建议

### 路线 A：打通真 `/personal/fm`

| 步骤 | 内容 | 预估 |
| --- | --- | --- |
| A0 | **摸清请求形态**：登录 token 重试 / 换 appid / 试直连主机 | 0.5–2 人日（**结果不确定**） |
| A1 | `PersonalFmRepository`：签名 GET + 参数（`mode`/`action`/`song_pool_id`/`remain_songcnt`/`hash`/`playtime`/`is_overplay`） | 0.5 人日 |
| A2 | 状态层 `PersonalFmController`：session epoch + 缓冲维护（>4 首）+ 预取 + 失败跳过 | 1 人日 |
| A3 | 回传钩子：play 上报（播够时长才记 `is_overplay`）、garbage 上报 | 0.5 人日 |
| A4 | UI：模式轴 + `recDesc` + 信息 chip + 侧立唱片堆 | 1–1.5 人日 |
| A5 | 登录门槛 + 未登录降级 | 0.25 人日 |
| | **合计** | **约 4–6 人日，且 A0 存在"试不通"风险** |

### 路线 B：不碰真接口，把"假的"做成**名实相符的**

承认拿不到推荐引擎，但把现有搜索池做成一个**诚实、可用、无 bug**的探索流：

1. **改名与文案**：`私人 FM` → `电台 / 发现流`，避免虚假承诺（1 行）；
2. **歌池真 diversify**：三个池从"1 个关键词"扩成"3–5 个关键词合并去重"，
   并**轮换**（每次刷新换种子），现在三个池每次刷新结果**完全一样**；
3. **反馈落到本地库**：`_disliked` 写入 Drift（新建 `fm_disliked` 表），
   跨会话生效；`_load()` 时在客户端过滤。**这就让"不喜欢"真的有意义了**；
4. **修 §4 的三个 bug**：请求序号、`player` 队列同步、耗尽后拉新页而非绕回；
5. **加分项**：把 `recDesc` 用诚实的措辞实现 ——
   "来自「民谣 电子」的歌" / "根据你红心过的 N 首歌"（后者可用本地 likes 算个相似歌手）。

| 步骤 | 预估 |
| --- | --- |
| 1 + 4（文案 + 三个 bug） | 0.5 人日 |
| 2（歌池多样化 + 轮换） | 0.5 人日 |
| 3（Drift 表 + 过滤 + 跨会话） | 0.5 人日 |
| 5（诚实版推荐理由） | 0.25 人日 |
| 测试 | 0.25 人日 |
| **合计** | **约 2 人日，零接口风险** |

### 建议

**先花半天做 A0 的验证**（带 token 重试一次即可，成本极低）。
- 若打通 → 按路线 A 做，但**A5（登录门槛）必须做**，否则游客打接口只会得到空；
- 若打不通 → **走路线 B**，并且把「私人 FM」这个名字改掉。
  **继续用一个打不通接口的名字 + 搜索关键词冒充推荐，是当前最该修的问题。**

无论走哪条，**§4 的三个 bug 都该立刻修**（合计不到 0.5 人日），
它们与选哪条路线无关，且现在就在影响用户。

---

## 六、本次实测清单

**已实测通过（可直接依赖）**
- ✅ `gateway.kugou.com` 从本机可达，android 签名算法正确
- ✅ `x-router` 机制生效（4 个对照接口全部返回业务级响应）
- ✅ `POST /everyday_song_recommend` → HTTP 200，**103,698 字节**真实个性化数据
- ✅ `GET /v5/url` → 业务级 `illegal hash`（说明路由正常）
- ✅ `/personal/fm` 在 8 个 x-router × 2 方法 × 3 版本路径下**全部 502/404**，零业务响应
- ✅ `fm.kugou.com` / `personal.kugou.com` / `musicapi.kugou.com` 直连 **SSL 握手失败**
- ✅ `mobilecdn.kugou.com` 直连 **SSL 信任失败**（但 HTTP 可用，项目一直走 HTTP）

**未验证（实施第一步就测）**
- ⬜ 带**真实登录 token** 时 `/personal/fm` 是否路由到业务（当前无 token）
- ⬜ 换 appid（`1005`/`1000`）能否打开 FM 接口
- ⬜ `fm.kugou.com` 是 DNS 污染还是证书问题（`Resolve-DnsName` + `-SkipCertificateCheck`）

**未做到（诚实声明）**
- ⚠️ 本次**没有**成功调用过任何一次真实的 FM 推荐接口，
  因此**无法给出真实 FM 响应体的字段结构**。§五 路线 A 的字段名全部来自
  EchoMusic 的 `buildPersonalFmParams`，属**间接来源**，实施时需以实测为准。

---

## 附：本次探测命令备忘

```powershell
# 签名（与 KugoSign.signatureAndroidParams 等价）
# salt = LnT6xpN3khm36zse0QzvmgTZ3waWdRSA
# signature = md5(salt + sorted("k=v") + salt)

# 对照组（全部 200）
POST https://gateway.kugou.com/everyday_song_recommend   x-router: everydayrec.service.kugou.com
GET  https://gateway.kugou.com/v5/url                    x-router: trackercdn.kugou.com
POST https://gateway.kugou.com/v3/get_my_info            x-router: usercenter.kugou.com
POST https://gateway.kugou.com/mcomment/v1/cmtlist       (无 x-router)

# 目标（全部 502/404）
GET/POST https://gateway.kugou.com/personal/fm           x-router: {空, fm, personal,
                                                         personalrec, personalized,
                                                         recommend, song, kmr}.service.kugou.com
GET      https://gateway.kugou.com/{v1,v2,v3}/personal/fm
```
