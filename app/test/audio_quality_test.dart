import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/mappers.dart';
import 'package:kugo/core/models/audio_quality.dart';
import 'package:kugo/core/models/track.dart';

void main() {
  group('AudioQualityUtil', () {
    test('parse quality tokens', () {
      expect(AudioQualityUtil.parseQualityToken('128'), AppQuality.standard);
      expect(AudioQualityUtil.parseQualityToken('320'), AppQuality.hq);
      expect(AudioQualityUtil.parseQualityToken('flac'), AppQuality.sq);
      expect(AudioQualityUtil.parseQualityToken('hires'), AppQuality.hiRes);
      expect(AudioQualityUtil.parseQualityToken('hi-res'), AppQuality.hiRes);
      expect(AudioQualityUtil.parseQualityToken('unknown'), isNull);
    });

    test('parse levels like EchoMusic', () {
      expect(AudioQualityUtil.parseQualityLevel(4), AppQuality.hq);
      expect(AudioQualityUtil.parseQualityLevel(5), AppQuality.sq);
      expect(AudioQualityUtil.parseQualityLevel(6), AppQuality.hiRes);
    });

    test('candidates go preferred → downward', () {
      expect(
        AudioQualityUtil.resolveCandidates(
          preferred: AppQuality.hiRes,
          available: const {},
          compatibilityMode: true,
        ),
        [
          AppQuality.hiRes,
          AppQuality.sq,
          AppQuality.hq,
          AppQuality.standard,
        ],
      );
    });

    test('unknown availability does not filter options', () {
      expect(
        AudioQualityUtil.hasQuality(const {}, AppQuality.hiRes),
        isTrue,
      );
    });

    test('known availability filters missing tiers', () {
      final available = {AppQuality.standard, AppQuality.hq};
      expect(
        AudioQualityUtil.hasQuality(available, AppQuality.hq),
        isTrue,
      );
      expect(
        AudioQualityUtil.hasQuality(available, AppQuality.sq),
        isFalse,
      );
      expect(
        AudioQualityUtil.resolveCandidates(
          preferred: AppQuality.hiRes,
          available: available,
          compatibilityMode: true,
        ),
        [AppQuality.hq, AppQuality.standard],
      );
    });

    test('inferred catalog keeps hiRes tryable', () {
      final available = {AppQuality.standard, AppQuality.hq, AppQuality.sq};
      expect(
        AudioQualityUtil.hasQuality(
          available,
          AppQuality.hiRes,
          catalogComplete: false,
        ),
        isTrue,
      );
      expect(
        AudioQualityUtil.hasQuality(
          available,
          AppQuality.hiRes,
          catalogComplete: true,
        ),
        isFalse,
      );
    });

    test('buildRelateGoods from mobile search shape', () {
      final goods = AudioQualityUtil.buildRelateGoods({
        'hash': 'aaa',
        '320hash': 'bbb',
        'sqhash': 'ccc',
        'extra': {
          '128hash': 'aaa',
          '320hash': 'bbb',
          'sqhash': 'ccc',
        },
      });
      final available = AudioQualityUtil.availableFromGoods(goods);
      expect(available, containsAll([AppQuality.standard, AppQuality.hq, AppQuality.sq]));
      expect(available.contains(AppQuality.hiRes), isFalse);
    });
  });

  group('mapMobileSearchSong quality', () {
    test('fills availableQualities from 320hash/sqhash', () {
      final track = mapMobileSearchSong({
        'hash': 'b3a52a7a958bf0aed0ebfba2e9a818b7',
        'songname': '晴天',
        'singername': '周杰伦',
        'album_name': '叶惠美',
        'duration': 269,
        'album_id': '966846',
        'album_audio_id': 32100650,
        '320hash': '1b56126a8a03924f1dd066259c095cbc',
        'sqhash': '0a69169202de95aaf24a9944ccf0730d',
        'privilege': 10,
        'pay_type': 3,
      });
      expect(track.availableQualities, contains(AppQuality.hq));
      expect(track.availableQualities, contains(AppQuality.sq));
      expect(track.isVip, isTrue);
      expect(track.quality, 'SQ');
    });

    test('free song without sq still has standard+hq', () {
      final track = mapMobileSearchSong({
        'hash': 'abc',
        'songname': 'x',
        'singername': 'y',
        'duration': 100,
        '320hash': 'def',
        'privilege': 0,
        'pay_type': 0,
      });
      expect(track.availableQualities, contains(AppQuality.standard));
      expect(track.availableQualities, contains(AppQuality.hq));
      expect(track.availableQualities.contains(AppQuality.sq), isFalse);
      expect(track.isVip, isFalse);
    });
  });

  group('Track quality helpers', () {
    test('withAvailableQualities sets display tag', () {
      const t = Track(
        id: '1',
        name: 'n',
        artist: 'a',
        album: 'al',
        coverUrl: 'u',
        durationMs: 1,
        hash: 'h',
      );
      final updated = t.withAvailableQualities({
        AppQuality.standard,
        AppQuality.hq,
        AppQuality.sq,
      });
      expect(updated.quality, 'SQ');
      expect(updated.qualityBadgeLabel, 'SQ');
    });

    test('quality known availability', () {
      const t = Track(
        id: '1',
        name: 'n',
        artist: 'a',
        album: 'al',
        coverUrl: 'u',
        durationMs: 1,
        availableQualities: {AppQuality.standard, AppQuality.hq},
        qualityCatalogComplete: true,
      );
      expect(t.qualityKnownAvailable(AppQuality.hq), isTrue);
      expect(t.qualityKnownAvailable(AppQuality.hiRes), isFalse);
      expect(t.qualityAvailabilityKnown, isTrue);

      const inferred = Track(
        id: '2',
        name: 'n',
        artist: 'a',
        album: 'al',
        coverUrl: 'u',
        durationMs: 1,
        availableQualities: {AppQuality.standard, AppQuality.hq},
        qualityCatalogComplete: false,
      );
      expect(inferred.qualityKnownAvailable(AppQuality.hiRes), isTrue);
    });
  });
}
