import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/likes/likes_controller.dart';

Track _t(String id) => Track(
      id: id,
      name: id,
      artist: 'a',
      album: '',
      coverUrl: 'mock://$id',
      durationMs: 1000,
      hash: 'h$id',
    );

void main() {
  test('like toggle adds and removes', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(likesProvider.notifier);

    expect(n.isLiked('a'), isFalse);
    await n.toggle(_t('a'));
    expect(n.isLiked('a'), isTrue);
    await n.toggle(_t('a'));
    expect(n.isLiked('a'), isFalse);
  });

  test('like is idempotent', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(likesProvider.notifier);
    await n.like(_t('b'));
    await n.like(_t('b'));
    expect(c.read(likesProvider).length, 1);
  });
}
