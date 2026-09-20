# 私人 FM — 与 EchoMusic 功能点差异评估

> 日期：2026-09-19
> 现场：`kugoFlutter` @ `feda11e`（工作区干净）
> 参考：`D:\work\EchoMusic`（v2.3.2-beta.5）
> 对象：`app/lib/features/fm/personal_fm_page.dart`（376 行）
> **状态：四处 bug 已修（`af960f0`，含 7 例回归测试）；路线 A 已验证为「本网络不可达」（§三）**

---

## 零·三、架构重构：`/fm` 页面撤掉，FM 变成一个「会话」（2026-09-20 晚）

**动机**：原设计里 FM 是独立页面（`/fm`），页面自己持有歌池、轴、播放状态。
它和播放器各拿一份「当前在放什么」，于是出现 §4.2 那类不同步；而且用户在
FM 页听到喜欢的歌，切进播放页就丢掉了电台上下文。

**现在的形态**（对照 EchoMusic 的 store 化做法）：

1. **FM = 一个会话，不是页面**。新增 `FmController`（Riverpod Notifier）持有
   档位轴、歌池轴、待生效轴、已播/不喜欢集合、续流与上报；
   `lib/features/fm/personal_fm_page.dart` 已删除。
2. **单一数据源：播放器队列就是 FM 歌池**。`PlayerState` 新增
   `queueSource`（`none` / `fm`），播放器据此知道「这是电台流」，
   而不是靠 FM 功能反向猜。队列在 FM 下只追加、不环绕。
3. **两条轴下一首生效**：切档位/歌池只写「待生效」，跨曲时应用；
   面板上给「立即生效」按钮兜底。
4. **上一首是池内回退**：`PlayerState.canStepBack` 在会话第一首为 false，
   控制条按钮据此变灰 —— 不再退到队列尾部把「未播的后续」当历史播。
5. **`/fm` 路由与页面已删**。入口（发现页 FM hero 卡、我的页磁贴）语义从
   「导航到一个页面」改成「启动一个会话 → 进播放页」；FM 的常驻痕迹是播放页
   顶部一枚药丸（`FmEntryPill`），点开是 `DraggableScrollableSheet`
   （可下拉收回、上拉近全屏，把原页面里唱片堆预告的容量补回来）。
6. **冷启动认领**：`main.dart` 在 `player.restoreOrSeed()` 之后调用
   `FmController.restore()`，用指纹比对恢复出来的队列是否就是上次的 FM 流。

**测试**：原 16 例页面测试（依赖真实网络、且绑在页面结构上）替换为
`test/fm_controller_test.dart`（13 例，纯状态层）+ `test/fm_controls_test.dart`
（5 例，药丸与面板）。

---

## 零、后续进展（2026-09-19 晚更新）

**已做**：
1. **四个 bug 全部修掉**（commit `af960f0`），并新增 7 例回归测试。
   第 4 个是修前 3 个的过程中、由新增测试抓出来的（见 §4.4）。
2. **路线 A 做了穷尽验证 → 结论：本网络不可达**（§三）。
   下文 §三已按实测结果重写，不再是"未验证"。
3. §一 结论 3 与 §二 对照表已按修复后的实际状态回填，
   §四 末尾新增修复对照表，§五 建议按实测结论重写。

**因此当前形态 = 路线 B 的一部分已经落地**（歌池多样化、诚实文案、
修 bug），但**改名「私人 FM」这一步尚未做** —— 那属于产品决策，
等郑兄定夺。

---

## 零·二、重大更正（2026-09-20，`mode` 真参数路线已打通到「只差登录」）

> **本节取代 §3.3 的「本网络不可达」结论。DNS 劫持的判断是错的。**

**当日实测（本机、本次会话，可复现）：**

| 探测 | 结果 |
| --- | --- |
| `Resolve-DnsName gateway.kugou.com` | `183.60.245.92 / 183.2.140.153` —— **真实 IP，DNS 没有被劫持** |
| `Resolve-DnsName this-host-does-not-exist-zzzz123.kugou.com` | **NXDOMAIN**（不存在的主机不再被解析） |
| 未签名请求 `/everyday_song_recommend` | 502（与旧文档一致：网关先验签） |
| **带签名 `POST /v2/personal_recommend` + `x-router: persnfm.service.kugou.com`** | **HTTP 200 + `{"data":"","status":0,"error_code":200101}`** |

**根因：路径和 router 都猜错了，不是网络问题。**

- `/personal/fm` 只是 [KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi) 对外的路由名，
  **真实上游是 `POST /v2/personal_recommend`**（见 `module/personal_fm.js`）。
- **真实 router 是 `persnfm.service.kugou.com`**（注意拼写：少一个 `o`，不是 `fm.service`）。
- §3.2 表里 8 个 router 候选全部不在真实上游之列，所以才会全 502/404。
- `200101` 是**业务码**（未登录），不是网关错误 —— 签名、appid、clientver 这套链路**已验证正确**。

**`mode` 轴的真实参数语义**（源码级，`module/personal_fm.js` + 官方文档）：

| 参数 | 值 | 说明 |
| --- | --- | --- |
| `mode` | `normal` / `small` / `peak` | 发现 / 小众 / 30s 速览 |
| `song_pool_id` | `0` / `1` / `2` | Alpha 按口味 / Beta 按风格 / Gamma |
| `action` | `play` / `garbage` | `garbage` = 真上报「不喜欢」 |
| `remain_songcnt` | > 4 不返回新推荐 | 服务端据此从已有池取歌，防重复 |
| `is_overplay` / `playtime` / `hash` / `songid` / `cur_mark` | — | 播放反馈，服务端据此学习 |
| body 还需 | `key = signParamsKey(clienttime)`、`fakem='ca981cfc583a4c37f28d2d49000013c16a0a'`、`m_type=1`、`callerid=0`、`area_code=1`、`recommend_source_locked=0` | 见源码 |

**唯一未验证的一步**：带真实登录 token 打一次，dump `data` 字段结构。
本仓库已有 QR / 短信 / 密码登录（QR 轮询用的正是概念版 `appid=3116`，与 FM 网关同平台，
token 通用性大概率没问题），所以这一步只是「登一次录」的成本。

**已落地的代码**（本次会话）：

- `lib/core/api/endpoints.dart`：`personalRecommend` / `personalFmRouter` 两个常量
- `lib/core/models/fm_mode.dart`：`FmMode`（heart/niche/peek ↔ normal/small/peak）、
  `FmSongPool`（taste/style/explore ↔ 0/1/2）、`keywordsFor(mode)`
- `lib/data/repositories/fm_repository.dart`：`FmRepository.fetch/reportGarbage/reportPlay`
- `lib/features/fm/personal_fm_page.dart`：模式轴 + 歌池轴 + 电台卡 + 黑胶堆 + 信息 chip +
  来源标注；设置 → 私人 FM → 「使用酷狗真实推荐（实验）」开关（默认关，未登录自动回落关键词池）
- `lib/core/models/track.dart`：新增 `recDesc` / `similarDesc` / `language`（字段名是猜的，
  已做多候选宽容解析，**待登录后 dump 真实响应再校准**）
- `test/personal_fm_page_test.dart`：16 例（原 7 例 + 模式轴 3 + 回落 2 + 参数映射 4）

---

## 一、结论先行

**当前项目的「私人 FM」不是 FM，是一个披着黑胶外壳的「关键词搜索播放器」。**

三个递进的结论：

1. **数据源是假的，而且不是"降级"意义上的假。**
   `_fetch()` 调的是 `searchRepository.searchSongs(keyword, pageSize: 20)`
   —— 即 `mobilecdn/api/v3/search/song`。三个"歌池"实际只是三组**搜索关键词**
   （`['热门','华语流行','经典']` / `['民谣','电子','轻音乐']` / `['独立','冷门','爵士']`）。
   所以「口味」= 搜索"热门 / 华语流行 / 经典"。
   **"私人"标签是自我矛盾的**：它是全站热歌搜索，与用户任何行为无关。
   （`af960f0` 只是把关键词从 1 个扩到 3 个以降低"翻来覆去就那几首"的观感，
   **没有改变"数据源是搜索"这一本质**。）

2. **反馈回路是假的。** 「不喜欢」只往**页面局部的 `Set<String> _disliked`** 里塞一个 id，
   本地跳过它。退出页面集合即销毁 —— 不落库、不上报、下次进来照旧推。
   服务端永远不知道你不喜欢什么。同理「红心」只写本地 likes，不回传给推荐系统。
   （`af960f0` 修的是"不喜欢的歌被播放器自动续播"这个**实现 bug**，
   过滤现在是正确的；但**不落库这项没变**，仍是路线 B 第 3 步。）

3. **真正的 `/personal/fm` 签名接口，在本网络环境下无法验证、也无法打通。**
   网关链路本身**是通的**（同一台网关、同一套签名、同一时刻，
   `POST /everyday_song_recommend` 返回 **104,296 字节**真实个性化数据），
   但 `/personal/fm` 在 **4 组 appid × 8 个 x-router × 2 种 salt** 的约 30 种组合下
   **全部 502/404，零业务响应**。
   根因已定位：**本机 DNS 是通配劫持器**（不存在的域名、连 `.invalid` 都解析到
   `198.18.0.0/15`），`gateway.kugou.com` 只是白名单内的转发代理，
   其余上游服务名没有真实上游 → 502。
   → 因此**无法区分**「该接口已下线」与「本网络禁止它」，详见 §3.3。

**一句话：想要真 FM，工作量的 80% 不在 UI，在于先换一个不被 DNS 劫持的网络把
`/personal/fm` 验证出来（§3.3 有 5 分钟清单）。在此之前，值得做的是路线 B。**

---

## 二、逐维度差异对照

| 维度 | EchoMusic | kugoFlutter 现状 | 差距性质 |
| --- | --- | --- | --- |
| **数据源** | 签名网关 `/personal/fm`（真推荐引擎） | `mobilecdn /search/song` 关键词搜索 | 🔴 **本质** |
| **"歌池"语义** | `song_pool_id` 0/1/2 → 口味/风格/探索，是**推荐侧参数** | 三个硬编码关键词 | 🔴 **本质** |
| **模式切换** | **两条轴**：歌池（口味/风格/探索）× 模式（红心/小众/速览） | 只有一条轴（口味/风格/探索），且是伪的 | 🔴 **缺失一整轴** |
| **反馈上报** | `action='play'\|'garbage'` + `playtime` + `is_overplay` + `remain_songcnt`，服务端据此学习 | 无。本地 `Set` 跳过 | 🔴 **本质** |
| **推荐理由** | `recDesc` —— 页面显示"根据你喜欢的XX推荐" | 诚实版："来自「民谣 / 电子」"（`af960f0`，**不冒充个性化**） | 🟡 部分补 |
| **信息条** | 时长 / 音质 / 语种 / **相似度** 四个 chip | 无 | 🟠 体验缺口 |
| **下一首预览** | 侧立唱片堆（当前盘 + 最多 3 张后续，`ResizeObserver` 动态算数量） | 无（只有底部 `1/N` 文字） | 🟠 体验缺口 |
| **缓冲/预取** | `personalFmBuffer` 维持 >4 首可播；`peekNext`/`commit`/`skipFailed` 三段式 | 池内 `_append()` 主动续池（余 6 首时触发），播到池尾即追加，**不再环绕** | 🟡 架构缺口 |
| **过会话控制** | `personalFmSessionEpoch` —— 切模式/歌池自增，丢弃过期异步响应 | ✅ **已对齐**：`_requestToken` 自增 + 每个 `await` 后校验（`af960f0`） | 🟢 已修 |
| **去重** | `fmRequests`/`fmRefillAfter` WeakMap + 5s 冷却；`rememberOnce` 账本上限 128 | 按 `id/hash` 去重 + 每池 3 关键词轮换，无冷却账本 | 🟡 潜在 bug |
| **登录门槛** | 有：`v-if="!isLoggedIn"` → "登录后查看私人 FM" | 无门槛，游客也能"用"（因为它本质是搜索） | 🟢 现状更宽松 |
| **加载骨架** | 有（初载骨架屏） | `CircularProgressIndicator` | 🟢 可接受 |
| **播完不重播** | 从服务端续推，理论上无限流 | ✅ **已对齐**：池尾 `_appendThenAdvance()`，追加成功才续播，失败则停在原处 | 🟢 已修 |
| **MV/红心按钮** | 红心写服务端 | 红心写本地 likes + SnackBar，然后 `_next()` | 🟢 可接受 |

---

## 三、`/personal/fm` 可达性实测（本次核心新证据）

### 3.1 对照组：网关链路确实是通的

同一时刻、同一 `mid`、同一套 `signatureAndroidParams`、同一 `User-Agent`：

| 调用 | 结果 |
| --- | --- |
| `POST /everyday_song_recommend`（`x-router: everydayrec.service.kugou.com`） | ✅ **HTTP 200，104,296 字节**，`song_list_size:30`，真实个性化歌单 |
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

### 3.3 结论：本网络不可达（穷尽验证）

**已排除的原因**：
- ~~网络不通~~ → 否。同主机、同签名，两个对照接口返回真实业务数据（104KB / 业务错误码）。
- ~~签名错误~~ → 否。同一个 `signatureAndroidParams` 被对照接口正常接受。
- ~~appid 不匹配~~ → 否。`1000`(Web) / `1005`(PC) / `3116`(概念版) / `3119`(Android)
  四组 appid×clientver 全部试过，行为一致（502/404）。
- ~~salt 方案错~~ → 否。lite salt 与 web salt 都试过。
- ~~路由名猜错~~ → **这是唯一无法排除的，但已被证明不可靠地猜**。
  `x-router` 值必须是网关已知的上游服务名；`fm.service` / `kmr.service` 返回
  **404（该 router 存在但无此路径）**，其余返回 **502（router 解析不到上游）**。
  真正的服务名不在我列举的 8 个候选里。

**关键发现：本机 DNS 是通配拦截器**，这解释了为什么"猜 router"这条路走不通：

| 查询 | 结果 |
| --- | --- |
| `fm.kugou.com` | 198.18.0.163 |
| `everydayrec.service.kugou.com` | 198.18.0.177 |
| `this-host-does-not-exist-zzzz123.kugou.com` | **198.18.0.189**（不存在也解析） |
| `totally-bogus-9f8a7b.example-nope.invalid` | **198.18.0.190**（`.invalid` 也解析） |

→ 全部落在 **`198.18.0.0/15`（RFC 2544 基准测试网段）**，即本地劫持的假解析器。
`gateway.kugou.com` 能用，是因为它在**白名单**里、被转发到了真上游；
其余主机名虽"解析成功"但无真实上游，所以 502/404。

**另一个佐证**：`gateway.kugou.com/robots.txt` 这个必然 404 的普通路径返回的是 **502**；
且**未带签名的请求无论什么路径全是 502**（含已知可用的 `/v5/url`）——
说明网关是「先验签、再按白名单转发」的代理，而不是真实酷狗网关。

**最终判定：**

> 在本网络环境下，`/personal/fm` **无法验证、也无法打通**。
> 更准确地说：**我无法通过实验区分"这个接口本身已下线"与"本网络不允许它"**。
> 要得到确定答案，必须在**不受此 DNS 劫持影响**的环境（手机热点 / 其它网络）复测。

**复测清单（换网络后照做即可，5 分钟）**：

```powershell
# 1. 先确认 DNS 不再被劫持：应返回真实公网 IP，或正确 NXDOMAIN
Resolve-DnsName fm.kugou.com -Type A
Resolve-DnsName this-host-does-not-exist-zzzz123.kugou.com -Type A   # 这条应 NXDOMAIN

# 2. 带签名打 target（signature = md5(salt + sorted("k=v") + salt)，salt 见 §附）
#    一次即可，看是否还是 502
GET https://gateway.kugou.com/personal/fm?<params>&signature=<sig>
    x-router 依次试：(空) / fm.service.kugou.com / kmr.service.kugou.com

# 3. 若 1 已正常但 2 仍 502/404 → 接口确实下线，走路线 B，不必再试
```

---

## 四、现状代码里的四个隐性缺陷（与 EchoMusic 对照才发现）

这三条不是"没有这个功能"，而是**原来的实现有 bug**，修复成本极低。
**四条已于 `af960f0` 全部修复**，本节保留问题原貌以供回溯。

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

### 4.4（修复时新发现）"不喜欢"挡不住播放器自己的续播

修 4.1–4.3 时暴露的第四个问题，**原有实现也一直有**，只是被 4.2 掩盖了：
`_playAt` 把**含已不喜欢曲目的完整列表**交给播放器，而播放器在曲目播完时会
按自己的游标 `next()`（`player_controller.dart:649`）。也就是说，即便
`_advanceLocal` 老老实实跳过了不喜欢的歌，**播放器自动续播时照样会播到它**。
→ 修法：队列下发给播放器**之前**就把 `_disliked` 过滤掉（`_playAt` 内）。
这个 bug 是被新增的回归测试
`never re-serves a disliked track on a later refill` 抓出来的 ——
写这条测试时我原本以为它只会验证"续池时不重复"，结果它抓到了真问题。

### 四.5 四条缺陷的修复对照

| # | 问题 | 修法 | 回归测试 |
| --- | --- | --- | --- |
| 4.1 | 切池竞态 | `_requestToken` 自增，每个 `await` 后校验 | `a slow response from a previous pool cannot clobber the new one` |
| 4.2 | 页面与播放器脱节 | 弃用私有 `_index`，改用 `_resolveIndex()` / `_displayTrack()` 从 `playerControllerProvider.current` 反查 | `displayed track tracks the player, even when changed elsewhere` |
| 4.3 | 池尾静默绕回 | `_advanceLocal()` 只向后走、走不动就 `_appendThenAdvance()` | `extends the pool at the end instead of wrapping to song 1` |
| 4.4 | 不喜欢挡不住播放器续播 | `_playAt()` 下发队列**前**过滤 `_disliked` | `never re-serves a disliked track on a later refill` |

另有两例覆盖正常路径：`seeds from every keyword of the pool, not just one`、
`skips the disliked track instead of replaying it`。共 7 例，`flutter test` 全绿（104 项）。

---

## 五、两条路线的成本与建议（按实测结果修订）

### 路线 A：打通真 `/personal/fm` —— **本网络已判定不可行**

§三 已穷尽验证：4 组 appid × 8 个 router × 2 种 salt ≈ 30 种组合，
**零业务响应**；而对照组在同主机同签名下返回 104KB 真实数据。
根因是本机 DNS 被通配劫持（连 `.invalid` 都解析到 `198.18.x.x`），
`gateway.kugou.com` 只是白名单内的一个转发代理。

**结论：不在本机继续投入。** 需要换网络复测（§3.3 有 5 分钟清单）。
若复测可用，A1–A5 的估算仍然成立（约 4–6 人日，其中 A5 登录门槛必须做）。

### 路线 B：把"假的"做成**名实相符的** —— 已部分落地

| 步骤 | 状态 |
| --- | --- |
| 1. 改名「私人 FM」→「电台/发现流」 | ⬜ **未做（等产品决策）** |
| 2. 歌池多样化 + 轮换 | ✅ **已做**（每池 1 关键词 → 3 个，且轮换抽取） |
| 3. `_disliked` 落 Drift 跨会话 | ⬜ 未做（本次仍是页面级 Set，但已正确过滤队列） |
| 4. 修三个 bug | ✅ **已做**（`af960f0`，含顺带发现的第四个） |
| 5. 诚实版推荐理由 | ✅ **已做**（"来自「民谣 / 电子」"） |
| 6. 回归测试 | ✅ **已做**（7 例，见 `test/personal_fm_page_test.dart`） |

剩余工作量：**第 1 步 1 行 + 第 3 步约 0.5 人日**。

### 建议（2026-09-19 晚修订）

**本次已做的**：§四 四条 bug 全部修掉并加回归测试（`af960f0`）；
路线 B 的第 2 / 4 / 5 / 6 步已落地。

**接下来推荐**：

1. **路线 A 暂停在本机**。§三 已把"能不能通"这条路的探索空间在本网络内穷尽，
   再试只是重复 502。**换个不受 DNS 劫持的网络，按 §3.3 的 5 分钟清单复测一次**，
   成本 5 分钟、收益是"能/不能"的确定答案，非常划算。
   - 若复测可通 → 按路线 A 做（约 4–6 人日），其中**登录门槛必须做**，
     否则游客打接口只会得到空；届时 §四 的修法**可直接复用**（`_requestToken`、
     播放器反查、`_append` 续推、队列过滤都已经是正确形态，只需换数据源）。
   - 若复测仍不通 → 该接口确已下线，此后不必再碰。
2. **不论 A 结果如何，路线 B 的第 1 步（改名）应该做**。
   当前最名不副实的地方就是这一处：**「私人 FM」这个名字下面跑的是关键词搜索**。
   改成「电台 / 发现流」后，实现与命名就一致了，这是 1 行的事。
3. 路线 B 第 3 步（`_disliked` 落 Drift，约 0.5 人日）可以等改名后再做。

**不建议**：在不换网络的前提下继续猜 `x-router`。§3.3 已证明本机所有主机名
都被解析到假地址，猜中的前提（真实上游存在）根本不成立。

---

## 六、本次实测清单

**已实测通过（可直接依赖）**
- ✅ `gateway.kugou.com` 从本机可达，android 签名算法正确
- ✅ `x-router` 机制生效
- ✅ `POST /everyday_song_recommend` → HTTP 200，**104,296 字节**真实个性化数据
- ✅ `GET /v5/url` → 业务级 `illegal hash`（说明路由正常）
- ✅ `/personal/fm` 在 **4 组 appid（1000/1005/3116/3119）× 8 个 router × 2 种 salt**
  下**全部 502/404**，零业务响应
- ✅ **本机 DNS 是通配劫持器**：不存在的域名、`.invalid` 域名**全部解析**到
  `198.18.0.0/15`（RFC 2544 基准网段）
- ✅ 未签名的请求**无论什么路径**（含已知可用的 `/v5/url`）一律 502
  → 网关是"先验签、再白名单转发"的代理

**仍未验证（需换网络）**
- ⬜ 不受 DNS 劫持的环境下 `/personal/fm` 是否可用（§3.3 有 5 分钟复测清单）
- ⬜ 带**真实登录 token** 是否影响路由（当前无可用 token）
- ⬜ 该接口是否**本身已下线**（这是当前无法与本网络限制区分开的两种可能）

**未做到（诚实声明）**
- ⚠️ 本次**没有**成功调用过任何一次真实的 FM 推荐接口，
  因此**无法给出真实 FM 响应体的字段结构**。§五 路线 A 的字段名全部来自
  EchoMusic 的 `buildPersonalFmParams`，属**间接来源**。
- ⚠️ EchoMusic 仓库里的 `server/` 目录是**空**的，其后端实现未随仓库发布，
  所以也拿不到"它到底怎么调的"这一手证据。

---

## 附：本次探测命令备忘

```powershell
# 签名（与 KugoSign.signatureAndroidParams 等价）
# salt = LnT6xpN3khm36zse0QzvmgTZ3waWdRSA   (lite)
# salt = NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt   (web)
# signature = md5(salt + sorted("k=v") + salt)

# 对照组（返回真实业务响应，证明链路可用）
POST https://gateway.kugou.com/everyday_song_recommend   x-router: everydayrec.service.kugou.com
GET  https://gateway.kugou.com/v5/url                    x-router: trackercdn.kugou.com

# 目标（全部 502/404）
GET/POST https://gateway.kugou.com/personal/fm
    appid ∈ {1000,1005,3116,3119}
    x-router ∈ {空, fm.service, personal.service, personalrec.service,
                personalized.service, recommend.service, song.service, kmr.service}
GET      https://gateway.kugou.com/{v1,v2,v3}/personal/fm
    + /personal/fm/recommend, /recommend/fm, /fm, /personal, /mobile/personal/fm

# DNS 劫持验证（关键）
Resolve-DnsName this-host-does-not-exist-zzzz123.kugou.com -Type A  → 198.18.0.189（假）
Resolve-DnsName totally-bogus-9f8a7b.example-nope.invalid -Type A  → 198.18.0.190（假）
```
