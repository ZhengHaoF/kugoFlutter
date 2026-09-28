import 'track.dart';

/// One style tag under a group tab (EchoMusic `tag_info[].child[]`).
class StyleTag {
  const StyleTag({
    required this.id,
    required this.name,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final bool isDefault;
}

/// Style recommend tag group (EchoMusic `tag_info[]`).
class StyleTagGroup {
  const StyleTagGroup({required this.name, required this.child});

  final String name;
  final List<StyleTag> child;
}

/// Style-recommend section payload for the hub page.
class StyleRecommendResult {
  const StyleRecommendResult({
    this.tracks = const [],
    this.groups = const [],
    this.error = '',
    this.needLogin = false,
  });

  final List<Track> tracks;
  final List<StyleTagGroup> groups;
  final String error;
  final bool needLogin;

  bool get isEmpty => tracks.isEmpty && groups.isEmpty;
}
