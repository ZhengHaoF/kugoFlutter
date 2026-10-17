/// 播放停滞检测：判定「音频游标长时间不推进」。
///
/// 只比较游标数值、不比较墙钟，因此引擎在缓冲/挂起时反复吐回同一个旧样本
/// （甚至 0）不会掩盖真正的卡死；反过来，「暂停」「正在加载」「临近曲末」
/// 这些本来就不该推进的场景，由调用方通过 [active] 排除，避免误判。
///
/// 纯逻辑、不碰引擎，可独立单测（对齐 EchoMusic 主进程看门狗后的
/// `recoverFromStall` 判定口径）。
class StallWatchdog {
  StallWatchdog({
    this.stallTimeout = const Duration(seconds: 8),
    this.tick = const Duration(seconds: 1),
  });

  /// 连续无推进多久判定为停滞。
  final Duration stallTimeout;

  /// 采样间隔；调用方按此间隔驱动 [onTick]。
  final Duration tick;

  int? _lastMs;
  Duration _noAdvance = Duration.zero;

  /// 喂一次采样；返回 true 表示此刻应当触发一次自愈。
  ///
  /// [active] 为 false 时只重置计时、不判定。
  bool onTick(int positionMs, {required bool active}) {
    if (!active) {
      _lastMs = positionMs;
      _noAdvance = Duration.zero;
      return false;
    }
    if (_lastMs == null || positionMs != _lastMs) {
      _lastMs = positionMs;
      _noAdvance = Duration.zero;
      return false;
    }
    _noAdvance += tick;
    if (_noAdvance < stallTimeout) return false;
    // 触发后重新累计：同一次停滞不应被连续触发。
    _noAdvance = Duration.zero;
    return true;
  }

  /// 清零（新加载开始 / 自愈结束后调用）。
  void reset() {
    _lastMs = null;
    _noAdvance = Duration.zero;
  }
}
