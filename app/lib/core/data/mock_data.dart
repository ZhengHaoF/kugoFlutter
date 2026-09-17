import '../models/track.dart';

/// Phase 1 fixtures — no network. Covers use solid-color placeholders via [CoverBox].
abstract final class MockData {
  static const heroPlaylists = [
    PlaylistBrief(
      id: 'hero1',
      name: '此刻推荐',
      description: '根据你的口味推荐',
      coverUrl: 'mock://hero1',
      trackCount: 28,
      playCountLabel: '1 / 5',
    ),
    PlaylistBrief(
      id: 'hero2',
      name: '夜航电台',
      description: '深夜通勤专用',
      coverUrl: 'mock://hero2',
      trackCount: 36,
      playCountLabel: '2 / 5',
    ),
    PlaylistBrief(
      id: 'hero3',
      name: '城市漫游',
      description: '走路带风的节拍',
      coverUrl: 'mock://hero3',
      trackCount: 24,
      playCountLabel: '3 / 5',
    ),
  ];

  static const dailyTracks = [
    Track(
      id: 't1',
      name: '天真有邪',
      artist: '林宥嘉',
      album: '今日营业中',
      coverUrl: 'mock://t1',
      durationMs: 282000,
    ),
    Track(
      id: 't2',
      name: '理想三旬',
      artist: '陈鸿宇',
      album: '浓烟下的诗歌电台',
      coverUrl: 'mock://t2',
      durationMs: 264000,
    ),
    Track(
      id: 't3',
      name: '夜空中最亮的星',
      artist: '逃跑计划',
      album: '世界',
      coverUrl: 'mock://t3',
      durationMs: 252000,
      quality: 'Hi-Res',
    ),
    Track(
      id: 't4',
      name: '说好不哭',
      artist: '周杰伦',
      album: '说好不哭',
      coverUrl: 'mock://t4',
      durationMs: 218000,
      isVip: true,
    ),
    Track(
      id: 't5',
      name: '孤勇者',
      artist: '陈奕迅',
      album: '孤勇者',
      coverUrl: 'mock://t5',
      durationMs: 256000,
    ),
  ];

  static const recommendPlaylists = [
    PlaylistBrief(
      id: 'p1',
      name: '华语私人订制',
      coverUrl: 'mock://p1',
      trackCount: 50,
      playCountLabel: '128.4万',
    ),
    PlaylistBrief(
      id: 'p2',
      name: '民谣与诗',
      coverUrl: 'mock://p2',
      trackCount: 40,
      playCountLabel: '86.2万',
    ),
    PlaylistBrief(
      id: 'p3',
      name: '电子夜行',
      coverUrl: 'mock://p3',
      trackCount: 32,
      playCountLabel: '45.1万',
    ),
    PlaylistBrief(
      id: 'p4',
      name: '国风新声',
      coverUrl: 'mock://p4',
      trackCount: 36,
      playCountLabel: '62.8万',
    ),
  ];

  static const hotSearch = ['周杰伦', '陈奕迅', '民谣', '说唱'];

  static const rankings = [
    PlaylistBrief(
      id: 'r1',
      name: '飙升榜',
      coverUrl: 'mock://r1',
      trackCount: 100,
      playCountLabel: '实时',
    ),
    PlaylistBrief(
      id: 'r2',
      name: '新歌榜',
      coverUrl: 'mock://r2',
      trackCount: 100,
      playCountLabel: '每日',
    ),
    PlaylistBrief(
      id: 'r3',
      name: '热歌榜',
      coverUrl: 'mock://r3',
      trackCount: 100,
      playCountLabel: '每周',
    ),
  ];

  static const categories = ['流行', '摇滚', '电子', '国风', '轻音乐', '现场'];

  static const mockLyrics = [
    LyricLine(timeMs: 0, text: '夜空中最亮的星'),
    LyricLine(timeMs: 4000, text: '能否听清'),
    LyricLine(timeMs: 8000, text: '那仰望的人'),
    LyricLine(timeMs: 12000, text: '心底的孤独和叹息'),
    LyricLine(timeMs: 18000, text: '夜空中最亮的星'),
    LyricLine(timeMs: 22000, text: '能否记起'),
    LyricLine(timeMs: 26000, text: '曾与我同行'),
    LyricLine(timeMs: 30000, text: '消失在风里的身影'),
    LyricLine(timeMs: 36000, text: '我祈祷拥有一颗透明的心灵'),
    LyricLine(timeMs: 42000, text: '和会流泪的眼睛'),
    LyricLine(timeMs: 48000, text: '给我再去相信的勇气'),
    LyricLine(timeMs: 54000, text: '越过谎言去拥抱你'),
  ];
}
