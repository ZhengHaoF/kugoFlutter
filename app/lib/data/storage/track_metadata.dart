import 'dart:convert';

import '../../core/models/audio_quality.dart';
import '../../core/models/cloud_models.dart';
import '../../core/models/track.dart';

/// Versioned, non-secret metadata. Never persist resolved/signed media URLs.
String encodeTrackMetadata(Track track) {
  final cloud = track.cloudAudioSource;
  return jsonEncode({
    'version': 1,
    'artistId': track.artistId,
    'availableQualities': track.availableQualities.map((q) => q.name).toList(),
    'relateGoods': [
      for (final good in track.relateGoods)
        {'hash': good.hash, 'quality': good.quality, 'level': good.level},
    ],
    'qualityCatalogComplete': track.qualityCatalogComplete,
    'recDesc': track.recDesc,
    'similarDesc': track.similarDesc,
    'language': track.language,
    'cloudFileId': track.cloudFileId,
    if (cloud != null)
      'cloudAudioSource': {
        'hash': cloud.hash,
        'cloudFileId': cloud.cloudFileId,
        'hashStd': cloud.hashStd,
        'audioId': cloud.audioId,
        'albumAudioId': cloud.albumAudioId,
        'bitrate': cloud.bitrate,
        'size': cloud.size,
        'ext': cloud.ext,
        'name': cloud.name,
        'matchBy': cloud.matchBy?.name,
      },
  });
}

Track decodeTrackMetadata(Track base, String raw) {
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    String text(Map m, String key) => m[key]?.toString() ?? '';
    int? number(Map m, String key) => (m[key] as num?)?.toInt();
    final c = map['cloudAudioSource'];
    return base.copyWith(
      artistId: text(map, 'artistId'),
      availableQualities: {
        for (final name in (map['availableQualities'] as List? ?? const []))
          for (final quality in AppQuality.values)
            if (quality.name == name) quality,
      },
      relateGoods: [
        for (final good
            in (map['relateGoods'] as List? ?? const []).whereType<Map>())
          RelateGood(
            hash: text(good, 'hash'),
            quality: text(good, 'quality'),
            level: number(good, 'level'),
          ),
      ],
      qualityCatalogComplete: map['qualityCatalogComplete'] == true,
      recDesc: text(map, 'recDesc'),
      similarDesc: text(map, 'similarDesc'),
      language: text(map, 'language'),
      cloudFileId: text(map, 'cloudFileId'),
      cloudAudioSource: c is Map
          ? CloudAudioSource(
              hash: text(c, 'hash'),
              cloudFileId: text(c, 'cloudFileId'),
              hashStd: text(c, 'hashStd'),
              audioId: text(c, 'audioId'),
              albumAudioId: text(c, 'albumAudioId'),
              bitrate: number(c, 'bitrate'),
              size: number(c, 'size'),
              ext: text(c, 'ext'),
              name: text(c, 'name'),
              matchBy: CloudMatchBy.values
                  .where((value) => value.name == c['matchBy'])
                  .firstOrNull,
            )
          : null,
    );
  } catch (_) {
    // A corrupt/future optional payload must not hide a playable legacy row.
    return base;
  }
}
