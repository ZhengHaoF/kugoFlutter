/// Extended account profile fields shown on 个人中心.
///
/// Sourced from KuGou `get_my_info` / `user/detail` (`extendsInfo.detail` +
/// `extendsInfo.vip.busi_vip`). Missing fields stay null / empty — the UI
/// renders placeholders rather than inventing zeros.
class UserProfileDetail {
  const UserProfileDetail({
    this.gender,
    this.signature = '',
    this.province = '',
    this.city = '',
    this.ipLocation = '',
    this.follows,
    this.fans,
    this.visitors,
    this.registerTime,
    this.listenSeconds,
    this.listenMinutes,
    this.grade,
    this.currentPoint,
    this.nextGrade,
    this.nextGradePoint,
    this.tvipActive = false,
    this.svipActive = false,
    this.tvipBegin,
    this.tvipEnd,
    this.svipBegin,
    this.svipEnd,
  });

  static const empty = UserProfileDetail();

  /// 0 女 · 1 男 · 2/null 保密
  final int? gender;
  final String signature;
  final String province;
  final String city;
  final String ipLocation;
  final int? follows;
  final int? fans;
  final int? visitors;

  /// Unix seconds.
  final int? registerTime;
  final int? listenSeconds;
  final int? listenMinutes;
  final int? grade;
  final int? currentPoint;
  final int? nextGrade;
  final int? nextGradePoint;

  final bool tvipActive;
  final bool svipActive;
  final Object? tvipBegin;
  final Object? tvipEnd;
  final Object? svipBegin;
  final Object? svipEnd;

  bool get hasSocialStats =>
      follows != null || fans != null || visitors != null || grade != null;

  bool get hasArchive =>
      gender != null ||
      registerTime != null ||
      listenSeconds != null ||
      listenMinutes != null ||
      province.isNotEmpty ||
      city.isNotEmpty;

  bool get hasMembershipInfo =>
      tvipActive || svipActive || tvipEnd != null || svipEnd != null;

  Map<String, Object?> toDetailMap() => {
        'gender': gender,
        'descri': signature,
        'signature': signature,
        'province': province,
        'city': city,
        'loc': ipLocation,
        'follows': follows,
        'fans': fans,
        'hvisitors': visitors,
        'rtime': registerTime,
        'd_sec': listenSeconds,
        'duration': listenMinutes,
        'p_grade': grade,
        'p_current_point': currentPoint,
        'p_next_grade': nextGrade,
        'p_next_grade_point': nextGradePoint,
      };

  UserProfileDetail merge(UserProfileDetail other) {
    return UserProfileDetail(
      gender: other.gender ?? gender,
      signature: other.signature.isNotEmpty ? other.signature : signature,
      province: other.province.isNotEmpty ? other.province : province,
      city: other.city.isNotEmpty ? other.city : city,
      ipLocation: other.ipLocation.isNotEmpty ? other.ipLocation : ipLocation,
      follows: other.follows ?? follows,
      fans: other.fans ?? fans,
      visitors: other.visitors ?? visitors,
      registerTime: other.registerTime ?? registerTime,
      listenSeconds: other.listenSeconds ?? listenSeconds,
      listenMinutes: other.listenMinutes ?? listenMinutes,
      grade: other.grade ?? grade,
      currentPoint: other.currentPoint ?? currentPoint,
      nextGrade: other.nextGrade ?? nextGrade,
      nextGradePoint: other.nextGradePoint ?? nextGradePoint,
      tvipActive: other.tvipActive || tvipActive,
      svipActive: other.svipActive || svipActive,
      tvipBegin: other.tvipBegin ?? tvipBegin,
      tvipEnd: other.tvipEnd ?? tvipEnd,
      svipBegin: other.svipBegin ?? svipBegin,
      svipEnd: other.svipEnd ?? svipEnd,
    );
  }

  Map<String, dynamic> toJson() => {
        'gender': gender,
        'signature': signature,
        'province': province,
        'city': city,
        'ipLocation': ipLocation,
        'follows': follows,
        'fans': fans,
        'visitors': visitors,
        'registerTime': registerTime,
        'listenSeconds': listenSeconds,
        'listenMinutes': listenMinutes,
        'grade': grade,
        'currentPoint': currentPoint,
        'nextGrade': nextGrade,
        'nextGradePoint': nextGradePoint,
        'tvipActive': tvipActive,
        'svipActive': svipActive,
        'tvipBegin': tvipBegin?.toString(),
        'tvipEnd': tvipEnd?.toString(),
        'svipBegin': svipBegin?.toString(),
        'svipEnd': svipEnd?.toString(),
      };

  static UserProfileDetail fromJson(Map<String, dynamic> json) {
    int? asInt(Object? v) =>
        v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    return UserProfileDetail(
      gender: asInt(json['gender']),
      signature: '${json['signature'] ?? ''}',
      province: '${json['province'] ?? ''}',
      city: '${json['city'] ?? ''}',
      ipLocation: '${json['ipLocation'] ?? ''}',
      follows: asInt(json['follows']),
      fans: asInt(json['fans']),
      visitors: asInt(json['visitors']),
      registerTime: asInt(json['registerTime']),
      listenSeconds: asInt(json['listenSeconds']),
      listenMinutes: asInt(json['listenMinutes']),
      grade: asInt(json['grade']),
      currentPoint: asInt(json['currentPoint']),
      nextGrade: asInt(json['nextGrade']),
      nextGradePoint: asInt(json['nextGradePoint']),
      tvipActive: json['tvipActive'] == true,
      svipActive: json['svipActive'] == true,
      tvipBegin: json['tvipBegin'],
      tvipEnd: json['tvipEnd'],
      svipBegin: json['svipBegin'],
      svipEnd: json['svipEnd'],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfileDetail &&
          gender == other.gender &&
          signature == other.signature &&
          province == other.province &&
          city == other.city &&
          ipLocation == other.ipLocation &&
          follows == other.follows &&
          fans == other.fans &&
          visitors == other.visitors &&
          registerTime == other.registerTime &&
          listenSeconds == other.listenSeconds &&
          listenMinutes == other.listenMinutes &&
          grade == other.grade &&
          currentPoint == other.currentPoint &&
          nextGrade == other.nextGrade &&
          nextGradePoint == other.nextGradePoint &&
          tvipActive == other.tvipActive &&
          svipActive == other.svipActive &&
          '${tvipBegin ?? ''}' == '${other.tvipBegin ?? ''}' &&
          '${tvipEnd ?? ''}' == '${other.tvipEnd ?? ''}' &&
          '${svipBegin ?? ''}' == '${other.svipBegin ?? ''}' &&
          '${svipEnd ?? ''}' == '${other.svipEnd ?? ''}';

  @override
  int get hashCode => Object.hashAll([
        gender,
        signature,
        province,
        city,
        ipLocation,
        follows,
        fans,
        visitors,
        registerTime,
        listenSeconds,
        listenMinutes,
        grade,
        currentPoint,
        nextGrade,
        nextGradePoint,
        tvipActive,
        svipActive,
        '${tvipBegin ?? ''}',
        '${tvipEnd ?? ''}',
        '${svipBegin ?? ''}',
        '${svipEnd ?? ''}',
      ]);
}

/// Snapshot returned by [LoginRepository.fetchMyInfo].
class MyProfile {
  const MyProfile({
    this.nickname = '用户',
    this.avatarUrl = '',
    this.isVip = false,
    this.userId = '',
    this.detail = UserProfileDetail.empty,
  });

  final String nickname;
  final String avatarUrl;
  final bool isVip;
  final String userId;
  final UserProfileDetail detail;
}
