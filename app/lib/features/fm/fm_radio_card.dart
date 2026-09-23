import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../core/models/fm_mode.dart';
import '../../core/models/track.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../shared/widgets/cover_box.dart';

/// 私人 FM 的视觉件：电台卡 / 黑胶舞台 / 信息 chip / 来源标注 / 胶囊开关。
///
/// 版式对齐 EchoMusic `views/PersonalFm.vue`：
/// - 电台卡是**深底方卡**（深浅两档主题都一样，白字保证可读）：mode 轴在卡内，
///   footer 一行「频谱 + 不喜欢 + 播放 + 红心」，所以页面/面板里不再另放一排圆钮；
/// - 黑胶舞台是**一行**：当前盘压住电台卡右缘（[FmStageMetrics.overlap]），
///   右侧跟最多 3 张侧立待播盘；
/// - 歌池轴（Alpha/Beta/Gamma）不进卡，由页面抬头右上角承载。

/// 舞台几何：电台卡与封面圆盘怎么摆（EchoMusic radio-hero 的 Flutter 版）。
///
/// 桌面尺度更大（盘是「专辑物件」）；手机收一档，仍是「卡 + 盘一行」，
/// 不再拆成上下两块——那会在窄屏上变成一张空旷大蓝卡 + 孤零零的黑胶。
class FmStageMetrics {
  const FmStageMetrics._();

  /// 桌面：电台卡宽（卡是 1:1 方卡，高同此）。略窄于旧 280，给盘阵让宽；
  /// footer 三钮 + 频谱仍要塞得进，不再往下压。
  static const double cardWidth = 272;

  /// 桌面：当前盘 / 侧盘直径 —— 封面几乎铺满，视觉重量靠盘本身。
  static const double discSize = 200;

  /// 桌面：当前盘压住电台卡右缘的量：盘从卡里「抽出来」。
  /// 只影响视觉叠压，**不**参与 Row 的布局宽度计算。
  static const double overlap = 100;

  /// 桌面：盘与盘之间的间隙。
  static const double sideGap = 32;

  /// 桌面：舞台高度（= 方卡边长，盘在其中垂直居中）。
  static const double stageHeight = cardWidth;

  /// 手机：一行舞台里的方卡边长。约 47% 内容宽，给盘阵留出探出位。
  static const double cardWidthMobile = 180;

  /// 手机：当前盘直径（略小于卡，探出一截当「唱片抽出来」）。
  static const double discSizeMobile = 144;

  /// 手机：盘压住卡右缘的量（约盘径 1/3，探出可见弧）。
  static const double overlapMobile = 50;

  /// 手机：盘间隙（侧盘多半只露一角，不用太开）。
  static const double sideGapMobile = 14;

  /// 手机：舞台高度。
  static const double stageHeightMobile = cardWidthMobile;

  /// 侧盘最多几张。
  static const int maxSideDiscs = 3;

  static double cardWidthFor(bool desktop) =>
      desktop ? cardWidth : cardWidthMobile;

  static double discSizeFor(bool desktop) =>
      desktop ? discSize : discSizeMobile;

  static double overlapFor(bool desktop) => desktop ? overlap : overlapMobile;

  static double sideGapFor(bool desktop) => desktop ? sideGap : sideGapMobile;

  static double stageHeightFor(bool desktop) =>
      desktop ? stageHeight : stageHeightMobile;

  /// 盘行实际占宽：当前盘 + n 个（间隙 + 侧盘）。
  static double stageRowWidth(int sideCount) =>
      discSize + sideCount * (sideGap + discSize);

  /// 盘行在 Stack 里的布局宽度：从 `cardWidth - overlap` 画到内容列右缘。
  /// EchoMusic 的 current-disc 是 absolute + z-index 低于卡片，Flutter 侧
  /// 用 Stack 同样让盘在卡下层，因此布局盒要吃满「压在卡下的那一截」。
  static double discAreaWidth(double contentWidth, {bool desktop = true}) =>
      contentWidth - cardWidthFor(desktop) + overlapFor(desktop);

  /// 给定「盘行可用布局宽度」[available]，算得出几张侧立盘放得进来。
  static int visibleSideCount(double available, {bool desktop = true}) {
    if (!available.isFinite || available <= 0) return 0;
    final disc = discSizeFor(desktop);
    final gap = sideGapFor(desktop);
    var used = disc;
    var count = 0;
    for (var i = 0; i < maxSideDiscs; i++) {
      final next = used + gap + disc;
      if (next <= available) {
        used = next;
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  /// 内容列总宽 → 侧盘数（桌面舞台用；盘行布局宽见 [discAreaWidth]）。
  static int visibleSideCountForContent(
    double contentWidth, {
    bool desktop = true,
  }) {
    if (!contentWidth.isFinite || contentWidth <= 0) return 0;
    return visibleSideCount(
      discAreaWidth(contentWidth, desktop: desktop),
      desktop: desktop,
    );
  }
}

/// 电台舞台布局：卡在左、盘阵从卡右缘抽出（EchoMusic `radio-hero`）。
///
/// **桌面 / 窄屏同一行**：当前盘压住电台卡右缘，右侧跟侧立待播盘。
/// 窄屏只换 [FmStageMetrics] 的 mobile 档尺度，不再拆成上下两行。
/// 只负责构图，卡与盘的内容由调用方组装（发现页入口与 /fm 页共用）。
class FmStage extends StatelessWidget {
  const FmStage({
    super.key,
    required this.radioCard,
    required this.carousel,
    this.desktop = true,
  });

  final Widget radioCard;
  final Widget carousel;
  final bool desktop;

  /// 发现页 hero / 测试定位。
  static const Key stageKey = ValueKey('fm_hero_card');

  @override
  Widget build(BuildContext context) {
    // EchoMusic `radio-hero`：卡片 z-index 2，当前盘 z-index 1 从卡后探出。
    // Flutter Row 后画的子节点盖在前面，所以必须改用 Stack：盘在下、卡在上。
    final cardWidth = FmStageMetrics.cardWidthFor(desktop);
    final discLeft = cardWidth - FmStageMetrics.overlapFor(desktop);
    return SizedBox(
      key: stageKey,
      height: FmStageMetrics.stageHeightFor(desktop),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: discLeft,
            top: 0,
            bottom: 0,
            right: 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: carousel,
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SizedBox(
              width: cardWidth,
              child: radioCard,
            ),
          ),
        ],
      ),
    );
  }
}

/// EchoMusic `radio-card` 的等价物：模式轴 + 台名 + 当前曲 + 频谱 + 不喜欢/播放/红心。
///
/// 卡片永远是深底：浅色主题下如果跟随页面变浅，白字与紫渐变会糊在一起
/// （旧版正是如此）。底色 = 主题色按比例混入深蓝黑 [kCardBase]。
class FmRadioCard extends StatelessWidget {
  const FmRadioCard({
    super.key,
    required this.kugo,
    required this.accent,
    required this.mode,
    required this.pool,
    required this.onMode,
    required this.onPlay,
    required this.onDislike,
    required this.onLike,
    required this.isPlaying,
    required this.bars,
    required this.trackName,
    required this.artist,
    this.loading = false,
    this.actionsEnabled = true,
  });

  final KugoTheme kugo;

  /// 封面取色，只用于黑胶盘的光晕，不参与卡面（卡面用主题主色，保持可预期）。
  final Color accent;
  final FmMode mode;
  final FmSongPool pool;
  final ValueChanged<FmMode> onMode;
  final VoidCallback onPlay;
  final VoidCallback onDislike;
  final VoidCallback onLike;
  final bool isPlaying;
  final AnimationController bars;
  final String trackName;
  final String artist;
  final bool loading;

  /// 没有当前曲时（未起播）不喜欢/红心点了也是空操作，直接置灰。
  final bool actionsEnabled;

  /// 深底基色（EchoMusic `#0b1620`）。
  static const Color kCardBase = Color(0xFF0B1620);

  @override
  Widget build(BuildContext context) {
    Color mix(double t) =>
        Color.alphaBlend(kugo.primary.withValues(alpha: t), kCardBase);

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 一行舞台里的窄卡自动紧凑档：字号/内距/钮径跟着收，避免大卡排版塞进小卡。
          final compact = constraints.maxWidth < 220;
          final pad = compact ? 14.0 : 18.0;
          final titleSize = compact ? 20.0 : 27.0;
          final captionSize = compact ? 11.0 : 13.0;
          final actionSize = compact ? 32.0 : 40.0;
          final playSize = compact ? 40.0 : 48.0;
          final gap = compact ? 5.0 : 8.0;

          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 18 : 22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: compact ? 28 : 34,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(compact ? 18 : 22),
              child: Stack(
                children: [
                  // 底层：深墨蓝底 + 轻主色洗染（不再整块电光蓝，浅色页上才不「塑料」）。
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [mix(0.22), mix(0.30), kCardBase],
                          stops: const [0.0, 0.58, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // 上层：左上角一团弱高光，让卡面不死板。
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.68, -0.64),
                          radius: 1.15,
                          colors: [
                            kugo.primary.withValues(alpha: 0.22),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.all(pad),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          FmCapsuleSwitch<FmMode>(
                            kugo: kugo,
                            values: FmMode.values,
                            labelOf: (m) => m.label,
                            selected: mode,
                            onChanged: onMode,
                            compact: compact,
                            onDarkSurface: true,
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                mode.stationTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: kugo.greeting.copyWith(
                                  color: Colors.white,
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  height: 1.1,
                                ),
                              ),
                              SizedBox(height: compact ? 3 : 5),
                              Text(
                                trackName.isNotEmpty && artist.isNotEmpty
                                    ? '$trackName · $artist'
                                    : (trackName.isNotEmpty
                                          ? trackName
                                          : '${mode.subtitle} · ${pool.label}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: kugo.caption.copyWith(
                                  color: Colors.white70,
                                  fontSize: captionSize,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              // 频谱吃剩余宽度并裁切，卡再窄也不把 footer 挤爆。
                              Expanded(
                                child: ClipRect(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _Spectrum(
                                      bars: bars,
                                      active: isPlaying,
                                      compact: compact,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: gap),
                              _CardAction(
                                icon: Icons.thumb_down_alt_rounded,
                                tooltip: '不喜欢',
                                enabled: actionsEnabled,
                                onTap: onDislike,
                                size: actionSize,
                              ),
                              SizedBox(width: gap),
                              _CardPlayButton(
                                loading: loading,
                                isPlaying: isPlaying,
                                onTap: onPlay,
                                size: playSize,
                              ),
                              SizedBox(width: gap),
                              _CardAction(
                                icon: Icons.thumb_up_alt_rounded,
                                tooltip: '红心',
                                enabled: actionsEnabled,
                                onTap: onLike,
                                size: actionSize,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 横向可滑盘阵（方案 A）：整队列一盘一页，滑到左侧吸附位后由外部起播。
///
/// 吸附位 = viewport 左缘（桌面舞台上即电台卡右缘探出处）。交互约定：
/// - **用户滚动 settle** 到与 [currentIndex] 不同的下标 → [onPlayIndex]；
/// - **程序滚动**（外部改了 [currentIndex]，如自动下一首）→ 只对齐，不回调；
/// - 同下标 settle / 重复回调一律吞掉，避免「滑一下连播两次」。
///
/// 队列为空时画一张 ghost 当前盘，不参与滚动。
class FmVinylCarousel extends StatefulWidget {
  const FmVinylCarousel({
    super.key,
    required this.kugo,
    required this.accent,
    required this.spin,
    required this.tracks,
    required this.currentIndex,
    required this.fallbackCoverUrl,
    required this.playing,
    required this.onPlayIndex,
    required this.onTapCurrent,
    this.discSize = FmStageMetrics.discSize,
    this.sideGap = FmStageMetrics.sideGap,
    double? height,
  }) : height = height ?? discSize;

  final KugoTheme kugo;
  final Color accent;
  final AnimationController spin;
  final List<Track> tracks;
  final int currentIndex;

  /// 队列空时当前盘的占位封面（与页面 `player.current` 同源）。
  final String fallbackCoverUrl;
  final bool playing;
  final ValueChanged<int> onPlayIndex;
  final VoidCallback onTapCurrent;
  final double discSize;
  final double sideGap;
  final double height;

  /// 测试/调试用：盘阵容器。
  static const Key carouselKey = ValueKey('fm_vinyl_carousel');

  @override
  State<FmVinylCarousel> createState() => _FmVinylCarouselState();
}

class _FmVinylCarouselState extends State<FmVinylCarousel> {
  late final ScrollController _scrollController;

  /// 最近一次已处理的 settle 下标：吞掉重复 ScrollEnd / 程序回滚。
  int? _lastSettledIndex;

  /// 外部改 currentIndex 触发的对齐滚动，结束后不要再 onPlayIndex。
  bool _suppressPlayOnce = false;

  bool _attached = false;

  double get _pitch => widget.discSize + widget.sideGap;

  int get _clampedCurrent {
    if (widget.tracks.isEmpty) return 0;
    final max = widget.tracks.length - 1;
    return widget.currentIndex.clamp(0, max);
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _lastSettledIndex = _clampedCurrent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attached = true;
      _jumpTo(_clampedCurrent, animated: false);
    });
  }

  @override
  void didUpdateWidget(covariant FmVinylCarousel old) {
    super.didUpdateWidget(old);
    if (widget.currentIndex != old.currentIndex) {
      _lastSettledIndex = _clampedCurrent;
      _suppressPlayOnce = true;
      _jumpTo(_clampedCurrent, animated: _attached);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _jumpTo(int index, {required bool animated}) {
    if (widget.tracks.isEmpty || !_scrollController.hasClients) return;
    final target = index * _pitch;
    final pixels = _scrollController.offset;
    if ((pixels - target).abs() < 0.5) {
      _suppressPlayOnce = false;
      return;
    }
    if (animated) {
      _scrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
        if (mounted) _suppressPlayOnce = false;
      });
    } else {
      _scrollController.jumpTo(target);
      _suppressPlayOnce = false;
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollEndNotification) return false;
    if (notification.metrics.axis != Axis.horizontal) return false;
    if (widget.tracks.length <= 1) return false;
    // 等本帧布局稳定后再算吸附，避免 drag 结束当帧 offset 尚未落地。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleSettle();
    });
    return false;
  }

  void _handleSettle() {
    if (!_scrollController.hasClients || widget.tracks.length <= 1) return;

    final pitch = _pitch;
    if (pitch <= 0) return;

    final pixels = _scrollController.offset;
    final idx = (pixels / pitch)
        .round()
        .clamp(0, widget.tracks.length - 1);
    final target = idx * pitch;

    // 未对齐先吸到最近一页；下一次 settle 再判定是否起播。
    if ((pixels - target).abs() > 1.0) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    if (_suppressPlayOnce) {
      _suppressPlayOnce = false;
      _lastSettledIndex = idx;
      return;
    }

    if (idx == _lastSettledIndex) return;
    _lastSettledIndex = idx;

    if (idx != _clampedCurrent) {
      widget.onPlayIndex(idx);
    }
  }

  void _handleTap(int index) {
    if (index == _clampedCurrent) {
      widget.onTapCurrent();
      return;
    }
    _lastSettledIndex = index;
    widget.onPlayIndex(index);
  }

  Widget _buildDisc(int index) {
    final isCurrent = index == _clampedCurrent && widget.tracks.isNotEmpty;
    final track = widget.tracks.isEmpty ? null : widget.tracks[index];
    final coverUrl = track?.coverUrl ?? widget.fallbackCoverUrl;
    final disc = _Vinyl(
      coverUrl: coverUrl,
      size: widget.discSize,
      accent: isCurrent ? widget.accent : Colors.transparent,
      kugo: widget.kugo,
      onTap: () => _handleTap(index),
      isCurrent: isCurrent,
      ghost: false,
    );
    if (!isCurrent) return disc;
    return AnimatedBuilder(
      animation: widget.spin,
      builder: (context, child) {
        final angle = widget.playing ? widget.spin.value * 2 * math.pi : 0.0;
        return Transform.rotate(angle: angle, child: child);
      },
      child: disc,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tracks.isEmpty) {
      return SizedBox(
        key: FmVinylCarousel.carouselKey,
        height: widget.height,
        width: widget.discSize,
        child: Center(child: _buildDisc(0)),
      );
    }

    final pitch = _pitch;
    return SizedBox(
      key: FmVinylCarousel.carouselKey,
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportW = constraints.maxWidth;
          // 尾垫让最后一盘也能滑到左缘吸附位：maxScroll = (n-1)*pitch。
          final trailing = math.max(0.0, viewportW - pitch);
          return NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              // 盘外还有一圈圆形阴影（blur≈30–42）。ListView 默认按 viewport
              // 硬裁，会把圆影裁成矩形色块。Clip.none 放行溢出绘制；
              // scrollCacheExtent:0 避免屏外 item 的阴影提前漏进视口。
              clipBehavior: Clip.none,
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              padding: EdgeInsets.only(right: trailing),
              itemCount: widget.tracks.length,
              itemExtent: pitch,
              itemBuilder: (context, index) {
                return SizedBox(
                  width: pitch,
                  height: widget.height,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildDisc(index),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// 唱片区（静态）：一行排开 —— 当前盘在左（可点暂停/起播），右侧最多 [sideCount] 个槽位。
///
/// 槽位优先用 [upcoming] 里的真实封面；不足时用空盘占位（ghost），
/// 避免「半截舞台」——未起播或歌池见底时右侧仍是完整盘阵。
///
/// [overlap] > 0 时整行向左平移，让当前盘压住左边电台卡的右缘
/// （EchoMusic 的 `radio-current-overlap` 摆法）；页面外的复用方传 0 即可。
///
/// 播放页 FM 面板仍用这版；桌面 /fm 舞台已换成 [FmVinylCarousel]。
class FmVinylStage extends StatelessWidget {
  const FmVinylStage({
    super.key,
    required this.kugo,
    required this.accent,
    required this.spin,
    required this.coverUrl,
    required this.playing,
    required this.upcoming,
    required this.onPick,
    required this.onTapCurrent,
    this.sideCount = 0,
    this.overlap = 0,
    this.discSize = FmStageMetrics.discSize,
    this.sideGap = FmStageMetrics.sideGap,
    this.showGhosts = true,
    double? height,
  }) : height = height ?? discSize;

  final KugoTheme kugo;
  final Color accent;
  final AnimationController spin;
  final String coverUrl;
  final bool playing;
  final List<Track> upcoming;
  final ValueChanged<Track> onPick;
  final VoidCallback onTapCurrent;
  final int sideCount;
  final double overlap;
  final double discSize;
  final double sideGap;

  /// true = 侧位不足时用空盘补满 [sideCount]。
  final bool showGhosts;
  final double height;

  @override
  Widget build(BuildContext context) {
    final slots = math.max(0, sideCount);
    // 槽位结构：当前盘，然后每个槽 = 间隙 + 盘。末尾不留多余间隙，
    // 这样行宽 = disc + n*(gap+disc)，和 FmStageMetrics.stageRowWidth 一致。
    return SizedBox(
      height: height,
      child: Transform.translate(
        offset: Offset(-overlap, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: spin,
              builder: (context, child) {
                final angle = playing ? spin.value * 2 * math.pi : 0.0;
                return Transform.rotate(angle: angle, child: child);
              },
              child: _Vinyl(
                coverUrl: coverUrl,
                size: discSize,
                accent: accent,
                kugo: kugo,
                onTap: onTapCurrent,
                isCurrent: true,
              ),
            ),
            for (var i = 0; i < slots; i++) ...[
              SizedBox(width: sideGap),
              if (i < upcoming.length)
                _Vinyl(
                  coverUrl: upcoming[i].coverUrl,
                  size: discSize,
                  accent: Colors.transparent,
                  kugo: kugo,
                  onTap: () => onPick(upcoming[i]),
                )
              else if (showGhosts)
                _Vinyl(
                  coverUrl: '',
                  size: discSize,
                  accent: Colors.transparent,
                  kugo: kugo,
                  onTap: () {},
                  ghost: true,
                )
              else
                SizedBox(width: discSize),
            ],
          ],
        ),
      ),
    );
  }
}

/// 封面圆盘：EchoMusic「专辑物件」画法 —— 封面几乎铺满，外圈只留窄黑胶沿。
///
/// 旧版标签只占 62%、周围大片黑盘，在浅色页面上像空洞；现在封面是主角。
class _Vinyl extends StatefulWidget {
  const _Vinyl({
    required this.coverUrl,
    required this.size,
    required this.accent,
    required this.kugo,
    required this.onTap,
    this.isCurrent = false,
    this.ghost = false,
  });

  final String coverUrl;
  final double size;
  final Color accent;
  final KugoTheme kugo;
  final VoidCallback onTap;
  final bool isCurrent;
  final bool ghost;

  @override
  State<_Vinyl> createState() => _VinylState();
}

class _VinylState extends State<_Vinyl> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final kugo = widget.kugo;
    final size = widget.size;
    final rim = math.max(5.0, size * 0.045);

    if (widget.ghost) {
      return SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kugo.isLight
                ? kugo.surfaceElevated
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: kugo.textTertiary.withValues(alpha: 0.28),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: kugo.isLight ? 0.05 : 0.22),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(
            Icons.album_outlined,
            size: size * 0.26,
            color: kugo.textTertiary.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    final accent = widget.accent;
    final hasAccent = widget.isCurrent && accent != Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: size,
          height: size,
          transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
          transformAlignment: Alignment.center,
          padding: EdgeInsets.all(rim),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF1C1C22), Color(0xFF08080C)],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: hasAccent
                    ? accent.withValues(alpha: _hovered ? 0.48 : 0.40)
                    : Colors.black.withValues(
                        alpha: kugo.isLight
                            ? (_hovered ? 0.20 : 0.14)
                            : (_hovered ? 0.48 : 0.38),
                      ),
                blurRadius: hasAccent ? 42 : 30,
                spreadRadius: hasAccent ? 2 : 0,
                offset: Offset(0, _hovered ? 16 : 14),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 先铺盘面密纹，封面盖在上面 —— 纹路只从窄沿露出来。
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _RimGroovePainter(rim: rim)),
                ),
              ),
              ClipOval(
                child: SizedBox(
                  width: size - rim * 2,
                  height: size - rim * 2,
                  child: CoverBox(
                    seed: widget.coverUrl,
                    size: size - rim * 2,
                    radius: 999,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 盘面沿上的细密纹（封面之下的底层绘制）。
class _RimGroovePainter extends CustomPainter {
  const _RimGroovePainter({required this.rim});

  final double rim;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    // 从盘缘往内画几圈，刚好落在 rim 带内；封面盖住内圈。
    for (var i = 0; i < 4; i++) {
      final r = outer - 1.2 - i * (rim / 4);
      if (r <= outer - rim) break;
      paint.color = Colors.white.withValues(alpha: 0.07 - i * 0.01);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RimGroovePainter oldDelegate) =>
      oldDelegate.rim != rim;
}

/// 10 根跳动频谱条（EchoMusic `radio-bars`）。
///
/// 每根有各自的基准高度（照 EchoMusic 的 CSS 逐根给定），波动只是叠加在上面，
/// 所以看起来是"音响在跳"而不是整齐的正弦波。
class _Spectrum extends StatelessWidget {
  const _Spectrum({
    required this.bars,
    required this.active,
    this.compact = false,
  });

  static const List<double> _baseHeights = [
    11, 17, 8, 19, 13, 18, 9, 14, 8, 15,
  ];

  final AnimationController bars;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bars,
      builder: (context, _) {
        final scale = compact ? 0.78 : 1.0;
        final barWidth = compact ? 2.0 : 2.5;
        final barGap = compact ? 2.0 : 3.0;
        return SizedBox(
          height: compact ? 20 : 26,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 窄卡 footer 会把频谱压扁：只画放得下的条，避免 RenderFlex 溢出。
              final maxBars = constraints.maxWidth.isFinite
                  ? math.max(
                      0,
                      (constraints.maxWidth / (barWidth + barGap)).floor(),
                    )
                  : _baseHeights.length;
              final count = math.min(maxBars, _baseHeights.length);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < count; i++)
                    Container(
                      width: barWidth,
                      margin: EdgeInsets.only(right: barGap),
                      height: (active
                              ? _baseHeights[i] +
                                  _baseHeights[i] *
                                      0.6 *
                                      (0.5 +
                                          0.5 *
                                              math.sin(
                                                (bars.value * 2 * math.pi) +
                                                    i * 0.7,
                                              ))
                              : _baseHeights[i] * 0.55) *
                          scale,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: active ? 0.75 : 0.30,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// 卡内 footer 的小圆钮（不喜欢 / 红心）：半透明玻璃底，禁用时淡出。
class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
    this.size = 40,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Icon(icon, size: size * 0.45, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// 卡内 footer 的主播键：主题色实心 + 同色光晕；加载中换成转环。
class _CardPlayButton extends StatelessWidget {
  const _CardPlayButton({
    required this.loading,
    required this.isPlaying,
    required this.onTap,
    this.size = 48,
  });

  final bool loading;
  final bool isPlaying;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kugo.primary,
          boxShadow: [
            BoxShadow(
              color: kugo.primary.withValues(alpha: 0.35),
              blurRadius: size * 0.55,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Center(
          child: loading
              ? SizedBox(
                  width: size * 0.38,
                  height: size * 0.38,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: size * 0.5,
                  color: Colors.white,
                ),
        ),
      ),
    );
  }
}

/// 信息 chip：时长 / 音质 / 语种 / 相似度（EchoMusic `fm-now-info-chip`）。
class FmInfoChips extends StatelessWidget {
  const FmInfoChips({
    super.key,
    required this.kugo,
    this.track,
    this.center = true,
  });

  final KugoTheme kugo;
  final Track? track;

  /// 面板里左对齐，移动端正中。
  final bool center;

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null) return const SizedBox.shrink();
    final items = <String>[
      if (t.durationMs > 0) t.durationLabel,
      if (t.quality.isNotEmpty) t.quality,
      if (t.language.isNotEmpty) t.language,
      if (t.similarDesc.isNotEmpty) '相似度${t.similarDesc}',
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      spacing: KugoSpacing.sm,
      runSpacing: KugoSpacing.xs,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: kugo.surfaceElevated,
              borderRadius: BorderRadius.circular(KugoRadius.chip),
              border: Border.all(color: kugo.divider),
            ),
            child: Text(
              item,
              style: kugo.caption.copyWith(
                color: kugo.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

/// 数据来源标注 —— 兜底模式必须让人看出来不是个性化推荐。
class FmSourceBadge extends StatelessWidget {
  const FmSourceBadge({
    super.key,
    required this.kugo,
    required this.fromServer,
    required this.gatewayError,
    required this.pool,
    required this.mode,
    this.textAlign = TextAlign.center,
  });

  final KugoTheme kugo;
  final bool fromServer;
  final String gatewayError;
  final FmSongPool pool;
  final FmMode mode;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final semantic = pool.semantic.isEmpty ? '' : ' · ${pool.semantic}';
    // 真接口成功 → 明确写出「私人 FM」；失败/回落才写关键词，且带上原因。
    final String text;
    if (fromServer) {
      text = '来源：酷狗私人 FM · ${pool.label}$semantic';
    } else if (gatewayError.isNotEmpty) {
      text = '来源：关键词检索 · $gatewayError';
    } else {
      text = '来源：关键词检索（${pool.reasonLabel}，非个性化）';
    }
    return Text(
      text,
      textAlign: textAlign,
      maxLines: 2,
      style: kugo.caption.copyWith(color: kugo.textTertiary, fontSize: 11),
    );
  }
}

/// 胶囊分段开关：歌池轴（页面抬头，浅色面）/ 模式轴（电台卡内，深色面）共用。
class FmCapsuleSwitch<T> extends StatelessWidget {
  const FmCapsuleSwitch({
    super.key,
    required this.kugo,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.compact = false,
    this.onDarkSurface = false,
  });

  final KugoTheme kugo;
  final List<T> values;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool compact;

  /// true = 放在深色面上（电台卡内）：选中态用白色玻璃片。
  /// false = 放在页面浅色面上（抬头）：选中态用主题主色实心。
  final bool onDarkSurface;

  @override
  Widget build(BuildContext context) {
    final background = onDarkSurface
        ? Colors.white.withValues(alpha: 0.14)
        : kugo.surfaceElevated.withValues(alpha: 0.9);
    final foreground = onDarkSurface ? Colors.white70 : kugo.textSecondary;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(KugoRadius.chip),
        border: Border.all(
          color: onDarkSurface
              ? Colors.white.withValues(alpha: 0.06)
              : kugo.divider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in values)
            GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 14,
                  vertical: compact ? 5 : 7,
                ),
                decoration: BoxDecoration(
                  color: value == selected
                      ? (onDarkSurface
                            ? Colors.white.withValues(alpha: 0.22)
                            : kugo.primary)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(KugoRadius.chip),
                ),
                child: Text(
                  labelOf(value),
                  style: kugo.caption.copyWith(
                    color: value == selected
                        ? (onDarkSurface ? Colors.white : kugo.onAccent)
                        : foreground,
                    fontWeight: value == selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontSize: compact ? 11 : 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
