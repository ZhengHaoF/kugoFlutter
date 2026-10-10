# kugoFlutter P0 Rework 实施与验收记录

本轮基于 `main@0154f6361d5450ff63a146f9b8033d24ba2a1db2`，分支为 `fix/rework-p0-security-playback-session`。按用户确认处理 [Rework 评估](rework-assessment-2026-10-10.md) 的 R01/R02/R06/R10，提交 PR 供审查，不直接合并 main，不推进 Wayland 专项适配。

## 实施

### R01：凭据传输

- **统一防护**：新增 `credential_transport.dart`，挂在酷狗通用 client 和所有自持 Dio 的酷狗 repository。含 Authorization/Cookie、token/t1/密码等凭据的请求只允许可信酷狗 HTTPS 主机，凭据请求及账号/设备注册请求不自动跟随重定向；注入测试 Dio 也不会绕过防护。
- **自动注入范围**：通用 KugoClient 只在 HTTPS `gateway.kugou.com` / `kugouvip.kugou.com` 自动附加会话，不再把账号 header 发送到公共 HTTP 媒体接口或外部连通性探测目标。
- **资料降级**：移除 relation/grade 的明文资料补充请求，保留既有 HTTPS usercenter/VIP。旧域名 HTTPS 证书校验失败，未禁用验证，也未进行 HTTP 回退；新等级/听歌时长等专属字段可能缺失，保留本地已有档案，不伪造数据。
- **短信**：发送验证码改为 HTTPS gateway + `x-router: login.user.kugou.com`，不再发向旧 HTTP 主机；请求结构已离线验证，真实短信发送未验收，也没有在本轮发送短信。
- **云盘**：初始化宿主改为经匿名 TLS 验证的 HTTPS bssulbig，曲库匹配走 HTTPS gateway，动态上传 host 必须为合法酷狗目标并升级 HTTPS；外部/带 userinfo/query 的目标安全拒绝。TLS 失败不会回退 HTTP。
- **账号切换**：资料补全显式传入该会话的 t1，禁止借用全局另一账号的 t1；尚未提交成功的登录会话不提前注入通用客户端。

2026-10-10 匿名网络验证使用系统证书校验：relation.user、userinfo.user、login.user 的 HTTPS 返回主机名不匹配，未建立已验证的 TLS 连接；bssulbig 与 gateway 的证书校验通过，匿名根路径分别返回 HTTP 404/403。这些只证明 TLS/匿名响应边界，不证明已登录资料、真实上传或短信业务成功。

### R10：日志安全

- **存储前脱敏**：NetworkLog 构造时处理 id/URL、重复 query、URL userinfo/fragment、headers、嵌套 Map/List、JSON/表单/错误文本。认证接口直接省略 payload，大小截断在脱敏之后。
- **字段策略**：包含 token/password/secret/signature 等名称及 Cookie/Authorization、MUSIC_U、SESSDATA、t1、验证码相关会话 key 等字段脱敏；不把“长度不超过 2KB”当作安全。
- **快照**：Map/List 深复制为不可变脱敏快照，避免记录后原输入被修改又带入密钥。
- **导出与崩溃**：复制输出再经过文本防护，CrashLog 的异常及 stack 文本也做凭据/URL 脱敏。
- **解析容错**：合法百分号文本、无效表单编码与畸形 URL 不让日志解析中断业务请求；不能安全解析的内容省略。签名媒体 URL 在表单解析前单独处理，编码后的敏感字段名与含凭据的 Map key 也脱敏。
- **边界**：字段策略不能识别任意无标签的秘密文本；敏感认证接口的原始 body 因此直接省略。它不是对所有可能 PII 的穷尽检测，更不是本地凭据存储加密。

### R02：播放生命周期

- **原生串行**：URL resolve 可以并发，但 `playUrl` 的原生变更排队，旧原生操作完成前新原生操作不重叠。
- **代次保护**：每个原生操作进入引擎前、完成后以及备用 URL 尝试前检查当前代次；旧任务不开始备用地址、不更新新曲目状态。失效队列项直接跳过，失败不污染下一次加载链。
- **失效收尾**：旧任务结束后在串行链中 pause，再放行新加载；销毁和停止递增加载代次，忽略旧播放/完成事件，延迟恢复 seek 前后也检查代次。
- **交互边界**：不能强行取消任意 backend 的在途 native Future，因此新曲目可能等待旧 native load 的已有超时或完成。此选择优先避免错播，不宣称实现了无等待的底层网络取消。
- **测试区域**：加载队列首次使用时在调用者 Zone 建立，避免在 Widget FakeAsync 区域预创建 Future 后，让 runAsync 的 FM 加载等不到队列完成；有专门回归用例和原有 FM 切源测试。
- **连带 R05**：停止使待完成 resolver/原生任务失效，不再出现停止后 resolver 又发起新的播放调用。此项是加载生命周期修复的自然覆盖，不代表其余 P1 已处理。

### R06：账号生命周期

- **会话 epoch**：启动恢复、QR/SMS/密码登录、资料刷新均检查当前会话代次，退出、游客切换、新登录尝试、QR 取消和销毁使旧结果失效。
- **身份检查**：资料刷新回写还核对 userId/token，旧账号响应不覆盖新账号。
- **凭据提交**：资料补全返回并通过代次检查后才提交全局会话；旧登录的返回值为 false，不冒充成功。
- **落盘队列**：会话 save/clear 串行化，尚未开始的旧 save 跳过；已开始写入之后仍执行退出 clear，不因销毁取消该 clear，从而避免磁盘会话在 logout 后复活。
- **存储边界**：本轮验证正常可写存储及可控的异步延迟；系统存储不可写时不能保证物理文件已清除，故障注入和安全存储迁移仍需后续处理。

## 自动验证

环境为 Ubuntu 26.04.1 x86_64、Flutter 3.47.7 / Dart 3.13.5。全部账号、短信、上传业务回归使用虚构字段和离线适配器，不使用真实账号或用户 Cookie。

| 项目 | 当前记录 |
|---|---|
| 新 P0 定向回归 | 新增网络安全、播放交错、账号/磁盘交错三个测试文件，共 47 项通过 |
| 原有定向回归 | 原有账号/播放器/上传 37 项与 B 站音源 15 项通过；与新增用例合计 99 项通过 |
| 静态分析 | 最终代码 `flutter analyze --no-pub` 无问题 |
| 全量测试 | 最终代码 `flutter test --no-pub --concurrency 2 --reporter expanded`，1,070 项全部通过，用时 12 分 12 秒 |
| Linux Release | 最终代码正式入口 Release 构建通过；另行构建的媒体探针不替代正式 bundle |
| 生产 X11 歌词 | 最终版本有合成、无合成、2× DPI 各 14 项通过；正式主窗/歌词子进程 6 项通过 |
| 基础媒体 | 最终版本 X11 与嵌套 Wayland 各 16 项通过；虚拟 PCM 峰值均为 8000，非零样本分别为 132116/180376 |
| Ubuntu 22.04/24.04 CI | PR 创建后以 Actions 实际结果为准；没有把配置存在当作远端通过 |

测试关注：旧原生操作迟到成功/失败、旧备用地址、过期排队曲目、stop/dispose、账号 A/B 逆序完成、QR/SMS/密码退出、在途 prefs save 之后的 logout clear、凭据目标/重定向、JSON/表单/错误文本脱敏和输入后续修改。全量测试中发现并修复了合法百分号文本导致日志解码抛错的回归，新增边界用例后，原有 B 站搜索测试也已通过。

## 复跑

从仓库根目录进入 app，使用与 lockfile 对应的 SDK；Release 和 probe 是不同入口，不能拿 probe bundle 代替正式发行产物。

```bash
cd app
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub \
  test/p0_network_security_test.dart \
  test/p0_playback_race_test.dart \
  test/p0_auth_session_test.dart \
  test/auth_controller_test.dart \
  test/player_controller_test.dart \
  test/cloud_upload_test.dart \
  test/bili_source_test.dart --reporter expanded
flutter test --no-pub --concurrency 2 --reporter expanded
flutter build linux --release --no-pub
xvfb-run -a -s '-screen 0 1440x1000x24' dbus-run-session -- \
  bash tool/run_x11_lyric_probe.sh \
  build/linux/x64/release/bundle/kugo build/rework-x11-lyrics
```

基础媒体探针沿用 `tool/linux_integration_probe.dart` / `tool/run_linux_probe.sh`；正式 bundle 应先保存，探针构建会替换 build 目录下的入口。嵌套 Wayland 仅作既有基础行为回归，不是恢复 Wayland 专项适配。

## 仍未闭环

- **真实账号**：HTTPS usercenter/VIP 返回、登录凭据恢复、短信 gateway 路由真实发送、真实云盘 HTTPS 秒传/分片都待真实账号验收。失败时应保持安全降级，不解除凭据防护。
- **硬件与平台**：真实 GNOME/KDE、混合 DPI、多显示器、两小时稳定性、Android/Windows 构建及真机回归不由本 Linux 虚拟桌面证明。
- **后续 Rework**：R03/R04/R07/R08/R09/R11/R12/R13/R14/R15/R16/R17 不在本次四 P0 的完成声明内；尤其日志修复不等于明文凭据存储、401 统一会话、音质切换或 schema 迁移已解决。
- **范围控制**：不新增 Wayland 全局歌词、layer-shell、桌面插件、发行安装包；不直接合并主分支。

## 代码依据

原始漏洞和风险依据保留在 [评估文档](rework-assessment-2026-10-10.md)，链接固定到基线提交，便于对照而不误认修复后代码。[基线账号实现](https://github.com/ZhengHaoF/kugoFlutter/blob/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/lib/features/auth/auth_controller.dart) [基线播放器](https://github.com/ZhengHaoF/kugoFlutter/blob/0154f6361d5450ff63a146f9b8033d24ba2a1db2/app/lib/features/player/player_controller.dart)
