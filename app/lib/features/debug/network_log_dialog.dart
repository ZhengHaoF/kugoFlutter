import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/api/network_log.dart';
import '../../core/theme/kugo_theme.dart';
import 'network_log_provider.dart';

/// 网络请求日志弹窗（对齐 z_ai_img 的 NetworkLogDialog + 探测/复制）
class NetworkLogDialog extends ConsumerStatefulWidget {
  const NetworkLogDialog({super.key});

  @override
  ConsumerState<NetworkLogDialog> createState() => _NetworkLogDialogState();
}

class _NetworkLogDialogState extends ConsumerState<NetworkLogDialog> {
  NetworkLogType? _filterType;
  bool _testing = false;
  bool _live = false;
  int _liveInterval = 5;
  int _liveRound = 0;

  Future<void> _testNetwork() async {
    if (_testing) return;
    setState(() => _testing = true);

    // 对齐参考项目：先打一条通用连通性（百度）
    await _singleGet('https://www.baidu.com', methodLabel: '连通性');
    // 再打酷狗关键路径
    await _singleGet(
      buildUrl(KugoEndpoints.mobileCdn, KugoEndpoints.searchSong, {
        'format': 'json',
        'keyword': '晴天',
        'page': 1,
        'pagesize': 1,
        'showtype': 1,
      }),
      methodLabel: '搜索',
    );
    await _singleGet(
      buildUrl(KugoEndpoints.lyrics, KugoEndpoints.lyricSearch, {
        'ver': 1,
        'man': 'yes',
        'client': 'pc',
        'keyword': '周杰伦',
        'hash': '',
        'timelength': 0,
      }),
      methodLabel: '歌词',
      plain: true,
    );
    await _singleGet(
      buildUrl(KugoEndpoints.wwwApi, KugoEndpoints.playData, {
        'r': 'play/getdata',
        'hash': 'b3a52a7a958bf0aed0ebfba2e9a818b7',
        'mid': 'kugo_mid',
        'guid': 'kugo_guid',
        'platid': 4,
        'appid': 1014,
      }),
      methodLabel: '播放',
    );

    if (mounted) setState(() => _testing = false);
  }

  Future<void> _singleGet(
    String url, {
    required String methodLabel,
    bool plain = false,
  }) async {
    final notifier = ref.read(networkLogProvider.notifier);
    final requestId = '${DateTime.now().microsecondsSinceEpoch}-$url';
    final startTime = DateTime.now();

    notifier.addLog(
      NetworkLog(
        id: requestId,
        type: NetworkLogType.request,
        timestamp: DateTime.now(),
        method: 'GET',
        url: url,
        data: methodLabel,
      ),
    );

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 12),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
            'Referer': 'http://www.kugou.com/',
          },
        ),
      );
      final response = await dio.get<dynamic>(
        url,
        options: Options(
          responseType: plain ? ResponseType.plain : ResponseType.json,
        ),
      );
      final duration = DateTime.now().difference(startTime);
      final body = response.data;
      final bodyStr = body is String ? body : body.toString();
      final filtered = bodyStr.contains('URL过滤') ||
          bodyStr.contains('disable.htm');
      notifier.addLog(
        NetworkLog(
          id: requestId,
          type: NetworkLogType.response,
          timestamp: DateTime.now(),
          method: 'GET',
          url: url,
          statusCode: response.statusCode,
          data: truncateLogData(
            filtered ? '【内容过滤】$methodLabel\n$bodyStr' : bodyStr,
          ),
          duration: duration,
        ),
      );
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      notifier.addLog(
        NetworkLog(
          id: requestId,
          type: NetworkLogType.error,
          timestamp: DateTime.now(),
          method: 'GET',
          url: url,
          errorMessage: e.toString().split('\n').first,
          duration: duration,
        ),
      );
    }
  }

  Future<void> _copyAll(List<NetworkLog> logs) async {
    final text = logs.map((e) => e.toCopyText()).join('\n\n');
    if (text.trim().isEmpty) {
      _toast('暂无日志');
      return;
    }
    await Clipboard.setData(ClipboardData(text: '== kugo 网络日志 ==\n\n$text'));
    _toast('已复制全部日志 (${logs.length} 条)');
  }

  Future<void> _copyOne(NetworkLog log) async {
    await Clipboard.setData(ClipboardData(text: log.toCopyText()));
    _toast('已复制该条');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _toggleLive(bool value) {
    setState(() => _live = value);
    if (value) {
      _liveLoop();
      _toast('已开启实时探测');
    }
  }

  Future<void> _liveLoop() async {
    while (_live && mounted) {
      setState(() => _liveRound += 1);
      await _testNetwork();
      if (!_live || !mounted) break;
      await Future<void>.delayed(Duration(seconds: _liveInterval));
    }
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final logs = ref.watch(networkLogProvider);
    final filteredLogs = _filterType == null
        ? logs
        : logs.where((log) => log.type == _filterType).toList();

    return AlertDialog(
      title: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _live ? '网络请求日志 · 第 $_liveRound 轮' : '网络请求日志',
            style: kugo.section.copyWith(fontSize: 18),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: _testing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check),
                onPressed: _testing ? null : _testNetwork,
                tooltip: '测试网络',
              ),
              PopupMenuButton<NetworkLogType?>(
                icon: const Icon(Icons.filter_list),
                onSelected: (value) {
                  setState(() => _filterType = value);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: null, child: Text('全部')),
                  const PopupMenuItem(
                    value: NetworkLogType.request,
                    child: Text('请求'),
                  ),
                  const PopupMenuItem(
                    value: NetworkLogType.response,
                    child: Text('响应'),
                  ),
                  const PopupMenuItem(
                    value: NetworkLogType.error,
                    child: Text('错误'),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () => _copyAll(filteredLogs),
                tooltip: '复制全部',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  ref.read(networkLogProvider.notifier).clearLogs();
                },
                tooltip: '清空日志',
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 实时探测控制
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '实时探测',
                          style: kugo.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Switch(
                        value: _live,
                        onChanged: _toggleLive,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final s in const [3, 5, 10])
                        ChoiceChip(
                          label: Text('${s}s'),
                          selected: _liveInterval == s,
                          onSelected: (_) => setState(() => _liveInterval = s),
                          labelStyle: const TextStyle(fontSize: 11),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filteredLogs.isEmpty
                  ? Center(
                      child: Text('暂无日志', style: kugo.caption),
                    )
                  : ListView.separated(
                      itemCount: filteredLogs.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final log = filteredLogs[index];
                        return _LogTile(
                          log: log,
                          onCopy: () => _copyOne(log),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log, required this.onCopy});

  final NetworkLog log;
  final VoidCallback onCopy;

  Color get _typeColor {
    switch (log.type) {
      case NetworkLogType.request:
        return Colors.blue;
      case NetworkLogType.response:
        return Colors.green;
      case NetworkLogType.error:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _typeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              log.typeLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _typeColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              log.method,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (log.statusCode != null) ...[
            Text(
              '${log.statusCode}',
              style: TextStyle(
                fontSize: 12,
                color: log.statusCode! >= 200 && log.statusCode! < 300
                    ? Colors.green
                    : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            log.formattedTime,
            style: TextStyle(
              fontSize: 11,
              color: kugo.textTertiary,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16),
            tooltip: '复制此条',
            onPressed: onCopy,
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          log.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
      ),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: kugo.surfaceElevated.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (log.duration != null) ...[
                Text(
                  '耗时: ${log.duration!.inMilliseconds}ms',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              if (log.headers != null) ...[
                const Text(
                  'Headers',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                _JsonPreview(data: log.headers!),
                const SizedBox(height: 8),
              ],
              if (log.data != null) ...[
                const Text(
                  'Body',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                _JsonPreview(data: log.data!),
              ],
              if (log.errorMessage != null) ...[
                const SizedBox(height: 8),
                const Text(
                  '错误信息',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  log.errorMessage!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.red,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _JsonPreview extends StatelessWidget {
  const _JsonPreview({required this.data});

  final dynamic data;

  @override
  Widget build(BuildContext context) {
    final jsonStr = data.toString();
    return SelectableText(
      jsonStr.length > 500 ? '${jsonStr.substring(0, 500)}...' : jsonStr,
      style: const TextStyle(
        fontSize: 11,
        fontFamily: 'monospace',
      ),
    );
  }
}

/// 供设置页打开日志弹窗
void showNetworkLogDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => const NetworkLogDialog(),
  );
}
