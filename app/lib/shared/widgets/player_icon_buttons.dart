import 'package:flutter/material.dart';

/// 播放 / 暂停的形态过渡。
///
/// 三处播放器（迷你条 / 桌面底栏 / 全屏播放页）原本都是 IconData 硬切换，
/// 点一下图标「跳变」。这里用 [AnimatedIcons.play_pause] 让播放箭头真的
/// 变形到暂停条：progress 0 = 播放、1 = 暂停。
///
/// 状态由外部给（[playing]），切换时 forward/reverse，冷启动已播的场合直接
/// 落在终点，不会先闪一个播放箭头。
class PlayPauseIcon extends StatefulWidget {
  const PlayPauseIcon({
    super.key,
    required this.playing,
    this.size = 28,
    this.color,
    this.duration = const Duration(milliseconds: 220),
  });

  final bool playing;
  final double size;
  final Color? color;
  final Duration duration;

  @override
  State<PlayPauseIcon> createState() => _PlayPauseIconState();
}

class _PlayPauseIconState extends State<PlayPauseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.playing ? 1.0 : 0.0,
    duration: widget.duration,
  );

  @override
  void didUpdateWidget(covariant PlayPauseIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing == widget.playing) return;
    if (widget.playing) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedIcon(
      icon: AnimatedIcons.play_pause,
      progress: _controller,
      size: widget.size,
      color: widget.color,
    );
  }
}

/// 喜欢的红心按钮：点下去有一下回弹（easeOutBack），不再是颜色瞬变。
///
/// [liked] 变化时报错——既覆盖本页点击（状态从 Riverpod 回来），也覆盖别的
/// 页面改了收藏、回到本页时的一致性。
class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.liked,
    required this.onToggle,
    this.size = 22,
    this.activeColor,
    this.inactiveColor,
    this.tooltip,
    this.padding = EdgeInsets.zero,
    this.constraints = const BoxConstraints(minWidth: 40, minHeight: 40),
  });

  final bool liked;
  final VoidCallback onToggle;
  final double size;

  /// 不传则用各自播放器原来的色（播放页是 0xFFE87A90，桌面底栏是 redAccent）。
  final Color? activeColor;
  final Color? inactiveColor;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final BoxConstraints constraints;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1.0,
  );

  late final Animation<double> _scale = _controller.drive(
    Tween<double>(begin: 0.82, end: 1.0).chain(
      CurveTween(curve: Curves.easeOutBack),
    ),
  );

  bool _lastLiked = false;

  @override
  void initState() {
    super.initState();
    _lastLiked = widget.liked;
  }

  @override
  void didUpdateWidget(covariant LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastLiked == widget.liked) return;
    _lastLiked = widget.liked;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: IconButton(
        padding: widget.padding,
        constraints: widget.constraints,
        tooltip: widget.tooltip ?? (widget.liked ? '取消喜欢' : '喜欢'),
        onPressed: widget.onToggle,
        icon: Icon(
          widget.liked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          size: widget.size,
          color: widget.liked ? widget.activeColor : widget.inactiveColor,
        ),
      ),
    );
  }
}
