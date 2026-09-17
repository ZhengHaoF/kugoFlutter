class Track {
  const Track({
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.durationMs,
    this.hash = '',
    this.albumId = '',
    this.mixSongId = '',
    this.quality = 'SQ',
    this.isVip = false,
  });

  final String id;
  final String name;
  final String artist;
  final String album;
  final String coverUrl;
  final int durationMs;
  final String hash;
  final String albumId;
  final String mixSongId;
  final String quality;
  final bool isVip;

  String get durationLabel {
    final total = Duration(milliseconds: durationMs);
    final m = total.inMinutes.toString().padLeft(2, '0');
    final s = (total.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get hasHash => hash.trim().isNotEmpty;

  Track copyWith({
    String? id,
    String? name,
    String? artist,
    String? album,
    String? coverUrl,
    int? durationMs,
    String? hash,
    String? albumId,
    String? mixSongId,
    String? quality,
    bool? isVip,
  }) {
    return Track(
      id: id ?? this.id,
      name: name ?? this.name,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      coverUrl: coverUrl ?? this.coverUrl,
      durationMs: durationMs ?? this.durationMs,
      hash: hash ?? this.hash,
      albumId: albumId ?? this.albumId,
      mixSongId: mixSongId ?? this.mixSongId,
      quality: quality ?? this.quality,
      isVip: isVip ?? this.isVip,
    );
  }
}

class PlaylistBrief {
  const PlaylistBrief({
    required this.id,
    required this.name,
    required this.coverUrl,
    this.description = '',
    this.trackCount = 0,
    this.playCountLabel = '',
  });

  final String id;
  final String name;
  final String coverUrl;
  final String description;
  final int trackCount;
  final String playCountLabel;
}

class LyricLine {
  const LyricLine({required this.timeMs, required this.text});

  final int timeMs;
  final String text;
}

class ResolvedAudio {
  const ResolvedAudio({
    required this.url,
    this.backupUrls = const [],
    this.quality = '128k',
  });

  final String url;
  final List<String> backupUrls;
  final String quality;

  List<String> get allUrls => [url, ...backupUrls];
}
