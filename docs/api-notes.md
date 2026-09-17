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
| Tracker 备用 | `trackercdn.kugou.com/i/v2/` | `cmd=23&pid=1&behavior=play&hash=&album_id=` |
| 歌词搜索 | `lyrics.kugou.com/search` | `ver=1&man=yes&client=pc&keyword=&hash=&timelength=` |
| 歌词下载 | `lyrics.kugou.com/download` | `ver=1&client=pc&id=&accesskey=&fmt=lrc&charset=utf8` |

## 响应形态（映射层）

- 搜索列表常见路径：`data.info[]` / `info[]`；字段 `hash` / `songname` / `singername` / `duration` / `album_id` / `audio_id` / `mixsongid`
- 播放地址：`data.url` + `data.backup_url`（或嵌套 `urls`）
- 歌词候选：`candidates[]` → `id` + `accesskey` → download 得 LRC 文本

## 探测脚本

```powershell
cd app
dart run tool/probe_api.dart
```

## 下一步（网络可达时）

1. 用 `probe_api.dart` 确认 search / play / lyric 全通
2. 真机：发现 → 搜索「周杰伦」→ 点播 → 锁屏控制
3. 校准字段映射（不同接口版本字段名有差异）
