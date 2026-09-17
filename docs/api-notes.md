# API 调研笔记

> 仅记录端点与字段形态，**不入库密钥/签名**。接口随时可能变更。

## 当前网络环境（开发机/模拟器 · App 内日志实测）

| 通道 | 结果 |
| --- | --- |
| `http://mobilecdn.kugou.com/api/v3/*` | HTTP 200，但 body 是 **HTML「URL过滤」**（access control policy） |
| 歌词 / 播放域 / HTTPS | 同样被网关策略拦或 TLS 失败 |
| 一般站点（如百度） | 正常 |

**结论**：不是 App 权限问题，是路由器/企业网关对 `*.kugou.com` 的内容过滤。  
App 已识别该 HTML 并抛出「网络网关拦截」，首页/发现会显示明确提示。

**解除方式**

1. 模拟器改连手机热点  
2. 路由器关闭「上网行为管理 / 家长控制 / 流媒体限制」，或放行 `*.kugou.com`  
3. 使用可用代理  

验证：设置 → 网络请求日志 → 测试网络。

## 端点（已在 `lib/core/api/endpoints.dart`）

| 用途 | URL | 参数要点 |
| --- | --- | --- |
| 搜索单曲 | `mobilecdn.kugou.com/api/v3/search/song` | `format=json&keyword=&page=&pagesize=&showtype=1` |
| 热搜 | `.../api/v3/search/hot` | `format=json&plat=0&count=` |
| 歌单详情 | `.../api/v3/playlist/info` | `specialid=&page=&pagesize=&format=json` |
| 榜单列表 | `.../api/v3/rank/list` | `format=json&plat=0` |
| 播放地址 | `wwwapi.kugou.com/yy/index.php` | `r=play/getdata&hash=&album_id=&mid=&guid=&platid=4&appid=1014` |
| Tracker 备用 | `trackercdn.kugou.com/i/v2/` | `cmd=23&pid=1&behavior=play&hash=&album_id=&key=` |
| 歌词搜索 | `lyrics.kugou.com/search` | `ver=1&man=yes&client=pc&keyword=&hash=&timelength=` |
| 歌词下载 | `lyrics.kugou.com/download` | `ver=1&client=pc&id=&accesskey=&fmt=lrc&charset=utf8` |

### 播放地址（2026-09 实测）

EchoMusic 播放能力来自 submodule **[MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi)** 的 `/song/url` → 概念版 `module/song_url.js`：

| 步骤 | 说明 |
| --- | --- |
| 端点 | `https://gateway.kugou.com/v5/url` + header `x-router: trackercdn.kugou.com` |
| 平台 | concept/lite：`appid=3116` `clientver=11440` `pid=411` `page_id=967177915` |
| signKey | `md5(hash + 185672dd44712f60bb1736df5a377e82 + appid + mid + userid)` |
| signature | `md5(LnT6xpN3khm36zse0QzvmgTZ3waWdRSA + 排序key=value + salt)` |
| dfid | **每次请求随机 24 位**（`randomString(24)`），mid 用设备稳定值 |
| mid | `BigInt(md5(guid)).toString()`（十进制） |

App 行为：
1. 带 token 请求 `/v5/url`
2. 失败则换 `ppage_id` 重试
3. 仍失败（SSA 20028）→ **无 token 再签一次**
4. 播放页显示真实错误；`/v5/url` 已进网络日志

| 旧通道 | 结果 |
| --- | --- |
| `wwwapi` `play/getdata` | `err_code=30020` 无 url |
| tracker `cmd=23` + kgcloudv2 key | VIP `status=2` 无 url |

**歌词**：download 返回 JSON，`content` 为 **base64 LRC**；只取前 2 个候选，避免刷日志。

## 响应形态（映射层）

- **Content-Type 常为 `text/html`**，body 却是 JSON：客户端必须 `jsonDecode` 字符串体（`KugoClient.getJson` 已处理）。
- 搜索单曲常见路径：`data.info[]`；字段 `hash` / `songname` / `singername` / `duration` / `album_id` / `audio_id` / `mixsongid`
- 播放地址：`data.url` + `data.backup_url`（或嵌套 `urls`）
- 歌词候选：`candidates[]` → `id` + `accesskey` → download 得 LRC 文本

### 已知被拒端点（2026-09 实测）

| 端点 | 结果 |
| --- | --- |
| `/api/v3/playlist/square` | HTTP 200，body=`Access Deny ! No Actions !` |
| `/api/v3/playlist/class` | 同上 |
| `/api/v3/playlist/recommend` | 同上 |
| `/api/v3/rank/list` | 可用（首页 Hero / 推荐卡兜底数据源） |
| `/api/v3/search/song` | 可用 |
| `/api/v3/search/hot` | 可用 |

## 探测脚本

```powershell
cd app
dart run tool/probe_api.dart
```

## 下一步（网络可达时）

1. 用 `probe_api.dart` 确认 search / play / lyric 全通
2. 真机：发现 → 搜索「周杰伦」→ 点播 → 锁屏控制
3. 校准字段映射（不同接口版本字段名有差异）
