// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kugo_db.dart';

// ignore_for_file: type=lint
class $QueueTracksTable extends QueueTracks
    with TableInfo<$QueueTracksTable, QueueTrack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueTracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverUrlMeta = const VerificationMeta(
    'coverUrl',
  );
  @override
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
    'cover_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hashMeta = const VerificationMeta('hash');
  @override
  late final GeneratedColumn<String> hash = GeneratedColumn<String>(
    'hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumIdMeta = const VerificationMeta(
    'albumId',
  );
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
    'album_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mixSongIdMeta = const VerificationMeta(
    'mixSongId',
  );
  @override
  late final GeneratedColumn<String> mixSongId = GeneratedColumn<String>(
    'mix_song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _qualityMeta = const VerificationMeta(
    'quality',
  );
  @override
  late final GeneratedColumn<String> quality = GeneratedColumn<String>(
    'quality',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isVipMeta = const VerificationMeta('isVip');
  @override
  late final GeneratedColumn<bool> isVip = GeneratedColumn<bool>(
    'is_vip',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_vip" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    position,
    trackId,
    name,
    artist,
    album,
    coverUrl,
    durationMs,
    hash,
    albumId,
    mixSongId,
    quality,
    isVip,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queue_tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueueTrack> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    } else if (isInserting) {
      context.missing(_artistMeta);
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    } else if (isInserting) {
      context.missing(_albumMeta);
    }
    if (data.containsKey('cover_url')) {
      context.handle(
        _coverUrlMeta,
        coverUrl.isAcceptableOrUnknown(data['cover_url']!, _coverUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_coverUrlMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('hash')) {
      context.handle(
        _hashMeta,
        hash.isAcceptableOrUnknown(data['hash']!, _hashMeta),
      );
    } else if (isInserting) {
      context.missing(_hashMeta);
    }
    if (data.containsKey('album_id')) {
      context.handle(
        _albumIdMeta,
        albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta),
      );
    } else if (isInserting) {
      context.missing(_albumIdMeta);
    }
    if (data.containsKey('mix_song_id')) {
      context.handle(
        _mixSongIdMeta,
        mixSongId.isAcceptableOrUnknown(data['mix_song_id']!, _mixSongIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mixSongIdMeta);
    }
    if (data.containsKey('quality')) {
      context.handle(
        _qualityMeta,
        quality.isAcceptableOrUnknown(data['quality']!, _qualityMeta),
      );
    } else if (isInserting) {
      context.missing(_qualityMeta);
    }
    if (data.containsKey('is_vip')) {
      context.handle(
        _isVipMeta,
        isVip.isAcceptableOrUnknown(data['is_vip']!, _isVipMeta),
      );
    } else if (isInserting) {
      context.missing(_isVipMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {position};
  @override
  QueueTrack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueTrack(
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      )!,
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      )!,
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_url'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      hash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hash'],
      )!,
      albumId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_id'],
      )!,
      mixSongId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mix_song_id'],
      )!,
      quality: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quality'],
      )!,
      isVip: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_vip'],
      )!,
    );
  }

  @override
  $QueueTracksTable createAlias(String alias) {
    return $QueueTracksTable(attachedDatabase, alias);
  }
}

class QueueTrack extends DataClass implements Insertable<QueueTrack> {
  final int position;
  final String trackId;
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
  const QueueTrack({
    required this.position,
    required this.trackId,
    required this.name,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.durationMs,
    required this.hash,
    required this.albumId,
    required this.mixSongId,
    required this.quality,
    required this.isVip,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['position'] = Variable<int>(position);
    map['track_id'] = Variable<String>(trackId);
    map['name'] = Variable<String>(name);
    map['artist'] = Variable<String>(artist);
    map['album'] = Variable<String>(album);
    map['cover_url'] = Variable<String>(coverUrl);
    map['duration_ms'] = Variable<int>(durationMs);
    map['hash'] = Variable<String>(hash);
    map['album_id'] = Variable<String>(albumId);
    map['mix_song_id'] = Variable<String>(mixSongId);
    map['quality'] = Variable<String>(quality);
    map['is_vip'] = Variable<bool>(isVip);
    return map;
  }

  QueueTracksCompanion toCompanion(bool nullToAbsent) {
    return QueueTracksCompanion(
      position: Value(position),
      trackId: Value(trackId),
      name: Value(name),
      artist: Value(artist),
      album: Value(album),
      coverUrl: Value(coverUrl),
      durationMs: Value(durationMs),
      hash: Value(hash),
      albumId: Value(albumId),
      mixSongId: Value(mixSongId),
      quality: Value(quality),
      isVip: Value(isVip),
    );
  }

  factory QueueTrack.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueTrack(
      position: serializer.fromJson<int>(json['position']),
      trackId: serializer.fromJson<String>(json['trackId']),
      name: serializer.fromJson<String>(json['name']),
      artist: serializer.fromJson<String>(json['artist']),
      album: serializer.fromJson<String>(json['album']),
      coverUrl: serializer.fromJson<String>(json['coverUrl']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      hash: serializer.fromJson<String>(json['hash']),
      albumId: serializer.fromJson<String>(json['albumId']),
      mixSongId: serializer.fromJson<String>(json['mixSongId']),
      quality: serializer.fromJson<String>(json['quality']),
      isVip: serializer.fromJson<bool>(json['isVip']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'position': serializer.toJson<int>(position),
      'trackId': serializer.toJson<String>(trackId),
      'name': serializer.toJson<String>(name),
      'artist': serializer.toJson<String>(artist),
      'album': serializer.toJson<String>(album),
      'coverUrl': serializer.toJson<String>(coverUrl),
      'durationMs': serializer.toJson<int>(durationMs),
      'hash': serializer.toJson<String>(hash),
      'albumId': serializer.toJson<String>(albumId),
      'mixSongId': serializer.toJson<String>(mixSongId),
      'quality': serializer.toJson<String>(quality),
      'isVip': serializer.toJson<bool>(isVip),
    };
  }

  QueueTrack copyWith({
    int? position,
    String? trackId,
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
  }) => QueueTrack(
    position: position ?? this.position,
    trackId: trackId ?? this.trackId,
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
  QueueTrack copyWithCompanion(QueueTracksCompanion data) {
    return QueueTrack(
      position: data.position.present ? data.position.value : this.position,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      name: data.name.present ? data.name.value : this.name,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      hash: data.hash.present ? data.hash.value : this.hash,
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      mixSongId: data.mixSongId.present ? data.mixSongId.value : this.mixSongId,
      quality: data.quality.present ? data.quality.value : this.quality,
      isVip: data.isVip.present ? data.isVip.value : this.isVip,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueueTrack(')
          ..write('position: $position, ')
          ..write('trackId: $trackId, ')
          ..write('name: $name, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('durationMs: $durationMs, ')
          ..write('hash: $hash, ')
          ..write('albumId: $albumId, ')
          ..write('mixSongId: $mixSongId, ')
          ..write('quality: $quality, ')
          ..write('isVip: $isVip')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    position,
    trackId,
    name,
    artist,
    album,
    coverUrl,
    durationMs,
    hash,
    albumId,
    mixSongId,
    quality,
    isVip,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueueTrack &&
          other.position == this.position &&
          other.trackId == this.trackId &&
          other.name == this.name &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.coverUrl == this.coverUrl &&
          other.durationMs == this.durationMs &&
          other.hash == this.hash &&
          other.albumId == this.albumId &&
          other.mixSongId == this.mixSongId &&
          other.quality == this.quality &&
          other.isVip == this.isVip);
}

class QueueTracksCompanion extends UpdateCompanion<QueueTrack> {
  final Value<int> position;
  final Value<String> trackId;
  final Value<String> name;
  final Value<String> artist;
  final Value<String> album;
  final Value<String> coverUrl;
  final Value<int> durationMs;
  final Value<String> hash;
  final Value<String> albumId;
  final Value<String> mixSongId;
  final Value<String> quality;
  final Value<bool> isVip;
  const QueueTracksCompanion({
    this.position = const Value.absent(),
    this.trackId = const Value.absent(),
    this.name = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.hash = const Value.absent(),
    this.albumId = const Value.absent(),
    this.mixSongId = const Value.absent(),
    this.quality = const Value.absent(),
    this.isVip = const Value.absent(),
  });
  QueueTracksCompanion.insert({
    this.position = const Value.absent(),
    required String trackId,
    required String name,
    required String artist,
    required String album,
    required String coverUrl,
    required int durationMs,
    required String hash,
    required String albumId,
    required String mixSongId,
    required String quality,
    required bool isVip,
  }) : trackId = Value(trackId),
       name = Value(name),
       artist = Value(artist),
       album = Value(album),
       coverUrl = Value(coverUrl),
       durationMs = Value(durationMs),
       hash = Value(hash),
       albumId = Value(albumId),
       mixSongId = Value(mixSongId),
       quality = Value(quality),
       isVip = Value(isVip);
  static Insertable<QueueTrack> custom({
    Expression<int>? position,
    Expression<String>? trackId,
    Expression<String>? name,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<String>? coverUrl,
    Expression<int>? durationMs,
    Expression<String>? hash,
    Expression<String>? albumId,
    Expression<String>? mixSongId,
    Expression<String>? quality,
    Expression<bool>? isVip,
  }) {
    return RawValuesInsertable({
      if (position != null) 'position': position,
      if (trackId != null) 'track_id': trackId,
      if (name != null) 'name': name,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (durationMs != null) 'duration_ms': durationMs,
      if (hash != null) 'hash': hash,
      if (albumId != null) 'album_id': albumId,
      if (mixSongId != null) 'mix_song_id': mixSongId,
      if (quality != null) 'quality': quality,
      if (isVip != null) 'is_vip': isVip,
    });
  }

  QueueTracksCompanion copyWith({
    Value<int>? position,
    Value<String>? trackId,
    Value<String>? name,
    Value<String>? artist,
    Value<String>? album,
    Value<String>? coverUrl,
    Value<int>? durationMs,
    Value<String>? hash,
    Value<String>? albumId,
    Value<String>? mixSongId,
    Value<String>? quality,
    Value<bool>? isVip,
  }) {
    return QueueTracksCompanion(
      position: position ?? this.position,
      trackId: trackId ?? this.trackId,
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

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (hash.present) {
      map['hash'] = Variable<String>(hash.value);
    }
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (mixSongId.present) {
      map['mix_song_id'] = Variable<String>(mixSongId.value);
    }
    if (quality.present) {
      map['quality'] = Variable<String>(quality.value);
    }
    if (isVip.present) {
      map['is_vip'] = Variable<bool>(isVip.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueueTracksCompanion(')
          ..write('position: $position, ')
          ..write('trackId: $trackId, ')
          ..write('name: $name, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('durationMs: $durationMs, ')
          ..write('hash: $hash, ')
          ..write('albumId: $albumId, ')
          ..write('mixSongId: $mixSongId, ')
          ..write('quality: $quality, ')
          ..write('isVip: $isVip')
          ..write(')'))
        .toString();
  }
}

class $QueueMetaTable extends QueueMeta
    with TableInfo<$QueueMetaTable, QueueMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currentIndexMeta = const VerificationMeta(
    'currentIndex',
  );
  @override
  late final GeneratedColumn<int> currentIndex = GeneratedColumn<int>(
    'current_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, currentIndex, mode];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queue_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueueMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('current_index')) {
      context.handle(
        _currentIndexMeta,
        currentIndex.isAcceptableOrUnknown(
          data['current_index']!,
          _currentIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentIndexMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QueueMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueMetaData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      currentIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_index'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
    );
  }

  @override
  $QueueMetaTable createAlias(String alias) {
    return $QueueMetaTable(attachedDatabase, alias);
  }
}

class QueueMetaData extends DataClass implements Insertable<QueueMetaData> {
  final int id;
  final int currentIndex;
  final String mode;
  const QueueMetaData({
    required this.id,
    required this.currentIndex,
    required this.mode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['current_index'] = Variable<int>(currentIndex);
    map['mode'] = Variable<String>(mode);
    return map;
  }

  QueueMetaCompanion toCompanion(bool nullToAbsent) {
    return QueueMetaCompanion(
      id: Value(id),
      currentIndex: Value(currentIndex),
      mode: Value(mode),
    );
  }

  factory QueueMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueMetaData(
      id: serializer.fromJson<int>(json['id']),
      currentIndex: serializer.fromJson<int>(json['currentIndex']),
      mode: serializer.fromJson<String>(json['mode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'currentIndex': serializer.toJson<int>(currentIndex),
      'mode': serializer.toJson<String>(mode),
    };
  }

  QueueMetaData copyWith({int? id, int? currentIndex, String? mode}) =>
      QueueMetaData(
        id: id ?? this.id,
        currentIndex: currentIndex ?? this.currentIndex,
        mode: mode ?? this.mode,
      );
  QueueMetaData copyWithCompanion(QueueMetaCompanion data) {
    return QueueMetaData(
      id: data.id.present ? data.id.value : this.id,
      currentIndex: data.currentIndex.present
          ? data.currentIndex.value
          : this.currentIndex,
      mode: data.mode.present ? data.mode.value : this.mode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueueMetaData(')
          ..write('id: $id, ')
          ..write('currentIndex: $currentIndex, ')
          ..write('mode: $mode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, currentIndex, mode);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueueMetaData &&
          other.id == this.id &&
          other.currentIndex == this.currentIndex &&
          other.mode == this.mode);
}

class QueueMetaCompanion extends UpdateCompanion<QueueMetaData> {
  final Value<int> id;
  final Value<int> currentIndex;
  final Value<String> mode;
  const QueueMetaCompanion({
    this.id = const Value.absent(),
    this.currentIndex = const Value.absent(),
    this.mode = const Value.absent(),
  });
  QueueMetaCompanion.insert({
    this.id = const Value.absent(),
    required int currentIndex,
    required String mode,
  }) : currentIndex = Value(currentIndex),
       mode = Value(mode);
  static Insertable<QueueMetaData> custom({
    Expression<int>? id,
    Expression<int>? currentIndex,
    Expression<String>? mode,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (currentIndex != null) 'current_index': currentIndex,
      if (mode != null) 'mode': mode,
    });
  }

  QueueMetaCompanion copyWith({
    Value<int>? id,
    Value<int>? currentIndex,
    Value<String>? mode,
  }) {
    return QueueMetaCompanion(
      id: id ?? this.id,
      currentIndex: currentIndex ?? this.currentIndex,
      mode: mode ?? this.mode,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (currentIndex.present) {
      map['current_index'] = Variable<int>(currentIndex.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueueMetaCompanion(')
          ..write('id: $id, ')
          ..write('currentIndex: $currentIndex, ')
          ..write('mode: $mode')
          ..write(')'))
        .toString();
  }
}

class $HistoryTracksTable extends HistoryTracks
    with TableInfo<$HistoryTracksTable, HistoryTrack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryTracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playedAtMeta = const VerificationMeta(
    'playedAt',
  );
  @override
  late final GeneratedColumn<int> playedAt = GeneratedColumn<int>(
    'played_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverUrlMeta = const VerificationMeta(
    'coverUrl',
  );
  @override
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
    'cover_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hashMeta = const VerificationMeta('hash');
  @override
  late final GeneratedColumn<String> hash = GeneratedColumn<String>(
    'hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumIdMeta = const VerificationMeta(
    'albumId',
  );
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
    'album_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mixSongIdMeta = const VerificationMeta(
    'mixSongId',
  );
  @override
  late final GeneratedColumn<String> mixSongId = GeneratedColumn<String>(
    'mix_song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _qualityMeta = const VerificationMeta(
    'quality',
  );
  @override
  late final GeneratedColumn<String> quality = GeneratedColumn<String>(
    'quality',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isVipMeta = const VerificationMeta('isVip');
  @override
  late final GeneratedColumn<bool> isVip = GeneratedColumn<bool>(
    'is_vip',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_vip" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    playedAt,
    trackId,
    name,
    artist,
    album,
    coverUrl,
    durationMs,
    hash,
    albumId,
    mixSongId,
    quality,
    isVip,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history_tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryTrack> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('played_at')) {
      context.handle(
        _playedAtMeta,
        playedAt.isAcceptableOrUnknown(data['played_at']!, _playedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_playedAtMeta);
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    } else if (isInserting) {
      context.missing(_artistMeta);
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    } else if (isInserting) {
      context.missing(_albumMeta);
    }
    if (data.containsKey('cover_url')) {
      context.handle(
        _coverUrlMeta,
        coverUrl.isAcceptableOrUnknown(data['cover_url']!, _coverUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_coverUrlMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('hash')) {
      context.handle(
        _hashMeta,
        hash.isAcceptableOrUnknown(data['hash']!, _hashMeta),
      );
    } else if (isInserting) {
      context.missing(_hashMeta);
    }
    if (data.containsKey('album_id')) {
      context.handle(
        _albumIdMeta,
        albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta),
      );
    } else if (isInserting) {
      context.missing(_albumIdMeta);
    }
    if (data.containsKey('mix_song_id')) {
      context.handle(
        _mixSongIdMeta,
        mixSongId.isAcceptableOrUnknown(data['mix_song_id']!, _mixSongIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mixSongIdMeta);
    }
    if (data.containsKey('quality')) {
      context.handle(
        _qualityMeta,
        quality.isAcceptableOrUnknown(data['quality']!, _qualityMeta),
      );
    } else if (isInserting) {
      context.missing(_qualityMeta);
    }
    if (data.containsKey('is_vip')) {
      context.handle(
        _isVipMeta,
        isVip.isAcceptableOrUnknown(data['is_vip']!, _isVipMeta),
      );
    } else if (isInserting) {
      context.missing(_isVipMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {playedAt, trackId};
  @override
  HistoryTrack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryTrack(
      playedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}played_at'],
      )!,
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      )!,
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      )!,
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_url'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      hash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hash'],
      )!,
      albumId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_id'],
      )!,
      mixSongId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mix_song_id'],
      )!,
      quality: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quality'],
      )!,
      isVip: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_vip'],
      )!,
    );
  }

  @override
  $HistoryTracksTable createAlias(String alias) {
    return $HistoryTracksTable(attachedDatabase, alias);
  }
}

class HistoryTrack extends DataClass implements Insertable<HistoryTrack> {
  final int playedAt;
  final String trackId;
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
  const HistoryTrack({
    required this.playedAt,
    required this.trackId,
    required this.name,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.durationMs,
    required this.hash,
    required this.albumId,
    required this.mixSongId,
    required this.quality,
    required this.isVip,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['played_at'] = Variable<int>(playedAt);
    map['track_id'] = Variable<String>(trackId);
    map['name'] = Variable<String>(name);
    map['artist'] = Variable<String>(artist);
    map['album'] = Variable<String>(album);
    map['cover_url'] = Variable<String>(coverUrl);
    map['duration_ms'] = Variable<int>(durationMs);
    map['hash'] = Variable<String>(hash);
    map['album_id'] = Variable<String>(albumId);
    map['mix_song_id'] = Variable<String>(mixSongId);
    map['quality'] = Variable<String>(quality);
    map['is_vip'] = Variable<bool>(isVip);
    return map;
  }

  HistoryTracksCompanion toCompanion(bool nullToAbsent) {
    return HistoryTracksCompanion(
      playedAt: Value(playedAt),
      trackId: Value(trackId),
      name: Value(name),
      artist: Value(artist),
      album: Value(album),
      coverUrl: Value(coverUrl),
      durationMs: Value(durationMs),
      hash: Value(hash),
      albumId: Value(albumId),
      mixSongId: Value(mixSongId),
      quality: Value(quality),
      isVip: Value(isVip),
    );
  }

  factory HistoryTrack.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryTrack(
      playedAt: serializer.fromJson<int>(json['playedAt']),
      trackId: serializer.fromJson<String>(json['trackId']),
      name: serializer.fromJson<String>(json['name']),
      artist: serializer.fromJson<String>(json['artist']),
      album: serializer.fromJson<String>(json['album']),
      coverUrl: serializer.fromJson<String>(json['coverUrl']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      hash: serializer.fromJson<String>(json['hash']),
      albumId: serializer.fromJson<String>(json['albumId']),
      mixSongId: serializer.fromJson<String>(json['mixSongId']),
      quality: serializer.fromJson<String>(json['quality']),
      isVip: serializer.fromJson<bool>(json['isVip']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playedAt': serializer.toJson<int>(playedAt),
      'trackId': serializer.toJson<String>(trackId),
      'name': serializer.toJson<String>(name),
      'artist': serializer.toJson<String>(artist),
      'album': serializer.toJson<String>(album),
      'coverUrl': serializer.toJson<String>(coverUrl),
      'durationMs': serializer.toJson<int>(durationMs),
      'hash': serializer.toJson<String>(hash),
      'albumId': serializer.toJson<String>(albumId),
      'mixSongId': serializer.toJson<String>(mixSongId),
      'quality': serializer.toJson<String>(quality),
      'isVip': serializer.toJson<bool>(isVip),
    };
  }

  HistoryTrack copyWith({
    int? playedAt,
    String? trackId,
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
  }) => HistoryTrack(
    playedAt: playedAt ?? this.playedAt,
    trackId: trackId ?? this.trackId,
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
  HistoryTrack copyWithCompanion(HistoryTracksCompanion data) {
    return HistoryTrack(
      playedAt: data.playedAt.present ? data.playedAt.value : this.playedAt,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      name: data.name.present ? data.name.value : this.name,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      hash: data.hash.present ? data.hash.value : this.hash,
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      mixSongId: data.mixSongId.present ? data.mixSongId.value : this.mixSongId,
      quality: data.quality.present ? data.quality.value : this.quality,
      isVip: data.isVip.present ? data.isVip.value : this.isVip,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryTrack(')
          ..write('playedAt: $playedAt, ')
          ..write('trackId: $trackId, ')
          ..write('name: $name, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('durationMs: $durationMs, ')
          ..write('hash: $hash, ')
          ..write('albumId: $albumId, ')
          ..write('mixSongId: $mixSongId, ')
          ..write('quality: $quality, ')
          ..write('isVip: $isVip')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    playedAt,
    trackId,
    name,
    artist,
    album,
    coverUrl,
    durationMs,
    hash,
    albumId,
    mixSongId,
    quality,
    isVip,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryTrack &&
          other.playedAt == this.playedAt &&
          other.trackId == this.trackId &&
          other.name == this.name &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.coverUrl == this.coverUrl &&
          other.durationMs == this.durationMs &&
          other.hash == this.hash &&
          other.albumId == this.albumId &&
          other.mixSongId == this.mixSongId &&
          other.quality == this.quality &&
          other.isVip == this.isVip);
}

class HistoryTracksCompanion extends UpdateCompanion<HistoryTrack> {
  final Value<int> playedAt;
  final Value<String> trackId;
  final Value<String> name;
  final Value<String> artist;
  final Value<String> album;
  final Value<String> coverUrl;
  final Value<int> durationMs;
  final Value<String> hash;
  final Value<String> albumId;
  final Value<String> mixSongId;
  final Value<String> quality;
  final Value<bool> isVip;
  final Value<int> rowid;
  const HistoryTracksCompanion({
    this.playedAt = const Value.absent(),
    this.trackId = const Value.absent(),
    this.name = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.hash = const Value.absent(),
    this.albumId = const Value.absent(),
    this.mixSongId = const Value.absent(),
    this.quality = const Value.absent(),
    this.isVip = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HistoryTracksCompanion.insert({
    required int playedAt,
    required String trackId,
    required String name,
    required String artist,
    required String album,
    required String coverUrl,
    required int durationMs,
    required String hash,
    required String albumId,
    required String mixSongId,
    required String quality,
    required bool isVip,
    this.rowid = const Value.absent(),
  }) : playedAt = Value(playedAt),
       trackId = Value(trackId),
       name = Value(name),
       artist = Value(artist),
       album = Value(album),
       coverUrl = Value(coverUrl),
       durationMs = Value(durationMs),
       hash = Value(hash),
       albumId = Value(albumId),
       mixSongId = Value(mixSongId),
       quality = Value(quality),
       isVip = Value(isVip);
  static Insertable<HistoryTrack> custom({
    Expression<int>? playedAt,
    Expression<String>? trackId,
    Expression<String>? name,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<String>? coverUrl,
    Expression<int>? durationMs,
    Expression<String>? hash,
    Expression<String>? albumId,
    Expression<String>? mixSongId,
    Expression<String>? quality,
    Expression<bool>? isVip,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (playedAt != null) 'played_at': playedAt,
      if (trackId != null) 'track_id': trackId,
      if (name != null) 'name': name,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (durationMs != null) 'duration_ms': durationMs,
      if (hash != null) 'hash': hash,
      if (albumId != null) 'album_id': albumId,
      if (mixSongId != null) 'mix_song_id': mixSongId,
      if (quality != null) 'quality': quality,
      if (isVip != null) 'is_vip': isVip,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HistoryTracksCompanion copyWith({
    Value<int>? playedAt,
    Value<String>? trackId,
    Value<String>? name,
    Value<String>? artist,
    Value<String>? album,
    Value<String>? coverUrl,
    Value<int>? durationMs,
    Value<String>? hash,
    Value<String>? albumId,
    Value<String>? mixSongId,
    Value<String>? quality,
    Value<bool>? isVip,
    Value<int>? rowid,
  }) {
    return HistoryTracksCompanion(
      playedAt: playedAt ?? this.playedAt,
      trackId: trackId ?? this.trackId,
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
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playedAt.present) {
      map['played_at'] = Variable<int>(playedAt.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (hash.present) {
      map['hash'] = Variable<String>(hash.value);
    }
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (mixSongId.present) {
      map['mix_song_id'] = Variable<String>(mixSongId.value);
    }
    if (quality.present) {
      map['quality'] = Variable<String>(quality.value);
    }
    if (isVip.present) {
      map['is_vip'] = Variable<bool>(isVip.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryTracksCompanion(')
          ..write('playedAt: $playedAt, ')
          ..write('trackId: $trackId, ')
          ..write('name: $name, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('durationMs: $durationMs, ')
          ..write('hash: $hash, ')
          ..write('albumId: $albumId, ')
          ..write('mixSongId: $mixSongId, ')
          ..write('quality: $quality, ')
          ..write('isVip: $isVip, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$KugoDb extends GeneratedDatabase {
  _$KugoDb(QueryExecutor e) : super(e);
  $KugoDbManager get managers => $KugoDbManager(this);
  late final $QueueTracksTable queueTracks = $QueueTracksTable(this);
  late final $QueueMetaTable queueMeta = $QueueMetaTable(this);
  late final $HistoryTracksTable historyTracks = $HistoryTracksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    queueTracks,
    queueMeta,
    historyTracks,
  ];
}

typedef $$QueueTracksTableCreateCompanionBuilder =
    QueueTracksCompanion Function({
      Value<int> position,
      required String trackId,
      required String name,
      required String artist,
      required String album,
      required String coverUrl,
      required int durationMs,
      required String hash,
      required String albumId,
      required String mixSongId,
      required String quality,
      required bool isVip,
    });
typedef $$QueueTracksTableUpdateCompanionBuilder =
    QueueTracksCompanion Function({
      Value<int> position,
      Value<String> trackId,
      Value<String> name,
      Value<String> artist,
      Value<String> album,
      Value<String> coverUrl,
      Value<int> durationMs,
      Value<String> hash,
      Value<String> albumId,
      Value<String> mixSongId,
      Value<String> quality,
      Value<bool> isVip,
    });

class $$QueueTracksTableFilterComposer
    extends Composer<_$KugoDb, $QueueTracksTable> {
  $$QueueTracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mixSongId => $composableBuilder(
    column: $table.mixSongId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVip => $composableBuilder(
    column: $table.isVip,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QueueTracksTableOrderingComposer
    extends Composer<_$KugoDb, $QueueTracksTable> {
  $$QueueTracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mixSongId => $composableBuilder(
    column: $table.mixSongId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVip => $composableBuilder(
    column: $table.isVip,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QueueTracksTableAnnotationComposer
    extends Composer<_$KugoDb, $QueueTracksTable> {
  $$QueueTracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get coverUrl =>
      $composableBuilder(column: $table.coverUrl, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hash =>
      $composableBuilder(column: $table.hash, builder: (column) => column);

  GeneratedColumn<String> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<String> get mixSongId =>
      $composableBuilder(column: $table.mixSongId, builder: (column) => column);

  GeneratedColumn<String> get quality =>
      $composableBuilder(column: $table.quality, builder: (column) => column);

  GeneratedColumn<bool> get isVip =>
      $composableBuilder(column: $table.isVip, builder: (column) => column);
}

class $$QueueTracksTableTableManager
    extends
        RootTableManager<
          _$KugoDb,
          $QueueTracksTable,
          QueueTrack,
          $$QueueTracksTableFilterComposer,
          $$QueueTracksTableOrderingComposer,
          $$QueueTracksTableAnnotationComposer,
          $$QueueTracksTableCreateCompanionBuilder,
          $$QueueTracksTableUpdateCompanionBuilder,
          (QueueTrack, BaseReferences<_$KugoDb, $QueueTracksTable, QueueTrack>),
          QueueTrack,
          PrefetchHooks Function()
        > {
  $$QueueTracksTableTableManager(_$KugoDb db, $QueueTracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueueTracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueueTracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueTracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> position = const Value.absent(),
                Value<String> trackId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String> album = const Value.absent(),
                Value<String> coverUrl = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String> hash = const Value.absent(),
                Value<String> albumId = const Value.absent(),
                Value<String> mixSongId = const Value.absent(),
                Value<String> quality = const Value.absent(),
                Value<bool> isVip = const Value.absent(),
              }) => QueueTracksCompanion(
                position: position,
                trackId: trackId,
                name: name,
                artist: artist,
                album: album,
                coverUrl: coverUrl,
                durationMs: durationMs,
                hash: hash,
                albumId: albumId,
                mixSongId: mixSongId,
                quality: quality,
                isVip: isVip,
              ),
          createCompanionCallback:
              ({
                Value<int> position = const Value.absent(),
                required String trackId,
                required String name,
                required String artist,
                required String album,
                required String coverUrl,
                required int durationMs,
                required String hash,
                required String albumId,
                required String mixSongId,
                required String quality,
                required bool isVip,
              }) => QueueTracksCompanion.insert(
                position: position,
                trackId: trackId,
                name: name,
                artist: artist,
                album: album,
                coverUrl: coverUrl,
                durationMs: durationMs,
                hash: hash,
                albumId: albumId,
                mixSongId: mixSongId,
                quality: quality,
                isVip: isVip,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$QueueTracksTable, QueueTrack>(table),
                  BaseReferences<_$KugoDb, $QueueTracksTable, QueueTrack>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QueueTracksTableProcessedTableManager =
    ProcessedTableManager<
      _$KugoDb,
      $QueueTracksTable,
      QueueTrack,
      $$QueueTracksTableFilterComposer,
      $$QueueTracksTableOrderingComposer,
      $$QueueTracksTableAnnotationComposer,
      $$QueueTracksTableCreateCompanionBuilder,
      $$QueueTracksTableUpdateCompanionBuilder,
      (QueueTrack, BaseReferences<_$KugoDb, $QueueTracksTable, QueueTrack>),
      QueueTrack,
      PrefetchHooks Function()
    >;
typedef $$QueueMetaTableCreateCompanionBuilder =
    QueueMetaCompanion Function({
      Value<int> id,
      required int currentIndex,
      required String mode,
    });
typedef $$QueueMetaTableUpdateCompanionBuilder =
    QueueMetaCompanion Function({
      Value<int> id,
      Value<int> currentIndex,
      Value<String> mode,
    });

class $$QueueMetaTableFilterComposer
    extends Composer<_$KugoDb, $QueueMetaTable> {
  $$QueueMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentIndex => $composableBuilder(
    column: $table.currentIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QueueMetaTableOrderingComposer
    extends Composer<_$KugoDb, $QueueMetaTable> {
  $$QueueMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentIndex => $composableBuilder(
    column: $table.currentIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QueueMetaTableAnnotationComposer
    extends Composer<_$KugoDb, $QueueMetaTable> {
  $$QueueMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get currentIndex => $composableBuilder(
    column: $table.currentIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);
}

class $$QueueMetaTableTableManager
    extends
        RootTableManager<
          _$KugoDb,
          $QueueMetaTable,
          QueueMetaData,
          $$QueueMetaTableFilterComposer,
          $$QueueMetaTableOrderingComposer,
          $$QueueMetaTableAnnotationComposer,
          $$QueueMetaTableCreateCompanionBuilder,
          $$QueueMetaTableUpdateCompanionBuilder,
          (
            QueueMetaData,
            BaseReferences<_$KugoDb, $QueueMetaTable, QueueMetaData>,
          ),
          QueueMetaData,
          PrefetchHooks Function()
        > {
  $$QueueMetaTableTableManager(_$KugoDb db, $QueueMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueueMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueueMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> currentIndex = const Value.absent(),
                Value<String> mode = const Value.absent(),
              }) => QueueMetaCompanion(
                id: id,
                currentIndex: currentIndex,
                mode: mode,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int currentIndex,
                required String mode,
              }) => QueueMetaCompanion.insert(
                id: id,
                currentIndex: currentIndex,
                mode: mode,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$QueueMetaTable, QueueMetaData>(table),
                  BaseReferences<_$KugoDb, $QueueMetaTable, QueueMetaData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QueueMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$KugoDb,
      $QueueMetaTable,
      QueueMetaData,
      $$QueueMetaTableFilterComposer,
      $$QueueMetaTableOrderingComposer,
      $$QueueMetaTableAnnotationComposer,
      $$QueueMetaTableCreateCompanionBuilder,
      $$QueueMetaTableUpdateCompanionBuilder,
      (QueueMetaData, BaseReferences<_$KugoDb, $QueueMetaTable, QueueMetaData>),
      QueueMetaData,
      PrefetchHooks Function()
    >;
typedef $$HistoryTracksTableCreateCompanionBuilder =
    HistoryTracksCompanion Function({
      required int playedAt,
      required String trackId,
      required String name,
      required String artist,
      required String album,
      required String coverUrl,
      required int durationMs,
      required String hash,
      required String albumId,
      required String mixSongId,
      required String quality,
      required bool isVip,
      Value<int> rowid,
    });
typedef $$HistoryTracksTableUpdateCompanionBuilder =
    HistoryTracksCompanion Function({
      Value<int> playedAt,
      Value<String> trackId,
      Value<String> name,
      Value<String> artist,
      Value<String> album,
      Value<String> coverUrl,
      Value<int> durationMs,
      Value<String> hash,
      Value<String> albumId,
      Value<String> mixSongId,
      Value<String> quality,
      Value<bool> isVip,
      Value<int> rowid,
    });

class $$HistoryTracksTableFilterComposer
    extends Composer<_$KugoDb, $HistoryTracksTable> {
  $$HistoryTracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mixSongId => $composableBuilder(
    column: $table.mixSongId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVip => $composableBuilder(
    column: $table.isVip,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HistoryTracksTableOrderingComposer
    extends Composer<_$KugoDb, $HistoryTracksTable> {
  $$HistoryTracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mixSongId => $composableBuilder(
    column: $table.mixSongId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVip => $composableBuilder(
    column: $table.isVip,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HistoryTracksTableAnnotationComposer
    extends Composer<_$KugoDb, $HistoryTracksTable> {
  $$HistoryTracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get playedAt =>
      $composableBuilder(column: $table.playedAt, builder: (column) => column);

  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get coverUrl =>
      $composableBuilder(column: $table.coverUrl, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hash =>
      $composableBuilder(column: $table.hash, builder: (column) => column);

  GeneratedColumn<String> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<String> get mixSongId =>
      $composableBuilder(column: $table.mixSongId, builder: (column) => column);

  GeneratedColumn<String> get quality =>
      $composableBuilder(column: $table.quality, builder: (column) => column);

  GeneratedColumn<bool> get isVip =>
      $composableBuilder(column: $table.isVip, builder: (column) => column);
}

class $$HistoryTracksTableTableManager
    extends
        RootTableManager<
          _$KugoDb,
          $HistoryTracksTable,
          HistoryTrack,
          $$HistoryTracksTableFilterComposer,
          $$HistoryTracksTableOrderingComposer,
          $$HistoryTracksTableAnnotationComposer,
          $$HistoryTracksTableCreateCompanionBuilder,
          $$HistoryTracksTableUpdateCompanionBuilder,
          (
            HistoryTrack,
            BaseReferences<_$KugoDb, $HistoryTracksTable, HistoryTrack>,
          ),
          HistoryTrack,
          PrefetchHooks Function()
        > {
  $$HistoryTracksTableTableManager(_$KugoDb db, $HistoryTracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoryTracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoryTracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryTracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> playedAt = const Value.absent(),
                Value<String> trackId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String> album = const Value.absent(),
                Value<String> coverUrl = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String> hash = const Value.absent(),
                Value<String> albumId = const Value.absent(),
                Value<String> mixSongId = const Value.absent(),
                Value<String> quality = const Value.absent(),
                Value<bool> isVip = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoryTracksCompanion(
                playedAt: playedAt,
                trackId: trackId,
                name: name,
                artist: artist,
                album: album,
                coverUrl: coverUrl,
                durationMs: durationMs,
                hash: hash,
                albumId: albumId,
                mixSongId: mixSongId,
                quality: quality,
                isVip: isVip,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int playedAt,
                required String trackId,
                required String name,
                required String artist,
                required String album,
                required String coverUrl,
                required int durationMs,
                required String hash,
                required String albumId,
                required String mixSongId,
                required String quality,
                required bool isVip,
                Value<int> rowid = const Value.absent(),
              }) => HistoryTracksCompanion.insert(
                playedAt: playedAt,
                trackId: trackId,
                name: name,
                artist: artist,
                album: album,
                coverUrl: coverUrl,
                durationMs: durationMs,
                hash: hash,
                albumId: albumId,
                mixSongId: mixSongId,
                quality: quality,
                isVip: isVip,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HistoryTracksTable, HistoryTrack>(table),
                  BaseReferences<_$KugoDb, $HistoryTracksTable, HistoryTrack>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HistoryTracksTableProcessedTableManager =
    ProcessedTableManager<
      _$KugoDb,
      $HistoryTracksTable,
      HistoryTrack,
      $$HistoryTracksTableFilterComposer,
      $$HistoryTracksTableOrderingComposer,
      $$HistoryTracksTableAnnotationComposer,
      $$HistoryTracksTableCreateCompanionBuilder,
      $$HistoryTracksTableUpdateCompanionBuilder,
      (
        HistoryTrack,
        BaseReferences<_$KugoDb, $HistoryTracksTable, HistoryTrack>,
      ),
      HistoryTrack,
      PrefetchHooks Function()
    >;

class $KugoDbManager {
  final _$KugoDb _db;
  $KugoDbManager(this._db);
  $$QueueTracksTableTableManager get queueTracks =>
      $$QueueTracksTableTableManager(_db, _db.queueTracks);
  $$QueueMetaTableTableManager get queueMeta =>
      $$QueueMetaTableTableManager(_db, _db.queueMeta);
  $$HistoryTracksTableTableManager get historyTracks =>
      $$HistoryTracksTableTableManager(_db, _db.historyTracks);
}
