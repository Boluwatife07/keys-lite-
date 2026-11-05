/// Plain models parsed from API JSON.
class Me {
  Me(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'];
  String get email => json['email'];
  String get firstName => json['firstName'] ?? '';
  String get lastName => json['lastName'] ?? '';
  String get fullName => '$firstName $lastName'.trim();
  String get onboardingStep => json['onboardingStep'];
  String get verificationStatus => json['verificationStatus'];
  bool get isVerified => verificationStatus == 'verified';
  bool get underReview => verificationStatus == 'under_review';
  String? get photoUrl => json['photoUrl'];
  String? get bio => json['bio'];
  bool get showWelcomePrompt => json['showWelcomePrompt'] == true;
  bool get showLearning => json['showLearning'] == true;
  Map<String, dynamic>? get community => json['community'];
  String get communityName => community?['name'] ?? '';
  Map<String, dynamic>? get address => json['address'];
}

class CommunityCard {
  CommunityCard(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'];
  String get type => json['type'];
  String get typeLabel => json['typeLabel'];
  String get name => json['name'];
  String? get parentName => json['parentName'];
  int? get residents => json['residents'];
  int? get committee => json['committeeMembers'];
  double? get distanceKm => (json['distanceKm'] as num?)?.toDouble();
  String get image => switch (type) {
        'development' => 'assets/images/community_development.png',
        'building' => 'assets/images/community_building.png',
        _ => 'assets/images/community_street.png',
      };
}

/// Result of community matching (ONB-12, ONB-13).
class MatchResult {
  MatchResult(this.json);
  final Map<String, dynamic> json;
  String get kind => json['kind'];
  String? get codedName => json['codedName'];
  List<CommunityCard> get communities => ((json['communities'] as List?) ?? []).map((e) => CommunityCard(Map<String, dynamic>.from(e))).toList();
}

String formatCount(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
