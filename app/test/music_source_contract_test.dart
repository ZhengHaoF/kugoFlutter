import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/core/source/quality_map.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/core/models/audio_quality.dart';

class _FakeSource implements MusicSource {
  _FakeSource(this.platform);

  @override
  final MusicPlatform platform;

  @override
  Future<List<Track>> searchSongs(String keyword, {int page = 1, int pageSize = 30}) async =>
      const [];

  @override
  Future<PlayUrlResult> resolvePlayUrl(Track track, {AppQuality? preferred}) async =>
      const PlayUrlResult(url: 'https://example.com/a.mp3');

  @override
  Future<LyricPayload> fetchLyric(Track track) async => LyricPayload.empty;
}

void main() {
  test('musicIdentity is platform:id', () {
    expect(musicIdentity(MusicPlatform.kugou, '42'), 'kugou:42');
    expect(musicIdentity(MusicPlatform.netease, '99'), 'netease:99');
  });

  test('Track.identityKey uses platform and id', () {
    const t = Track(
      id: 'mix1',
      name: 'n',
      artist: 'a',
      album: 'al',
      coverUrl: '',
      durationMs: 1,
    );
    expect(t.identityKey, 'kugou:mix1');
  });

  test('MusicSourceRegistry.of / capability / anyHas', () {
    final kg = _FakeSource(MusicPlatform.kugou);
    final registry = MusicSourceRegistry([kg]);
    expect(registry.of(MusicPlatform.kugou), kg);
    expect(registry.supports(MusicPlatform.netease), isFalse);
    expect(registry.anyHas<MusicSource>(), isTrue);
    expect(
      () => registry.of(MusicPlatform.netease),
      throwsA(isA<StateError>()),
    );
  });

  test('kugou quality candidates degrade downward', () {
    expect(
      SourceQualityMap.kugouCandidates(AppQuality.hiRes),
      ['hires', 'flac', '320', '128'],
    );
  });
}
