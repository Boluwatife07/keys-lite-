/// Feed, comment and poll models parsed from the API.
class PersonRef {
  PersonRef(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'];
  String get name => json['name'] ?? '';
  String get firstName => json['firstName'] ?? name.split(' ').first;
  String? get photoUrl => json['photoUrl'];
  bool get verified => json['verified'] == true;
  String? get role => json['role'];
  bool get isCommittee => role != null && role != 'Champion';
}

class PollOption {
  PollOption(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'];
  String get text => json['text'];
  String? get imageUrl => json['imageUrl'];
  int? get votes => json['votes'];
  int? get percent => json['percent'];
  bool get winner => json['winner'] == true;
}

class Poll {
  Poll(this.json);
  final Map<String, dynamic> json;
  String get question => json['question'];
  String? get promise => json['promise'];
  bool get multi => json['multi'] == true;
  DateTime get closesAt => DateTime.parse(json['closesAt']).toLocal();
  bool get closed => json['closed'] == true;
  int get totalVotes => json['totalVotes'] ?? 0;
  List<String>? get myVote => (json['myVote'] as List?)?.cast<String>();
  bool get canVote => json['canVote'] == true;
  bool get resultsVisible => json['resultsVisible'] == true;
  List<PollOption> get options => (json['options'] as List).map((e) => PollOption(Map<String, dynamic>.from(e))).toList();
}

class Post {
  Post(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'];
  bool get isPoll => json['kind'] == 'poll';
  PersonRef get author => PersonRef(Map<String, dynamic>.from(json['author']));
  String get text => json['text'] ?? '';
  List<Map<String, dynamic>> get mentions => List<Map<String, dynamic>>.from(json['mentions'] ?? []);
  String get attachment => json['attachment'] ?? 'none';
  List<String> get photos => ((json['photos'] as List?) ?? []).map((e) => e['url'] as String).toList();
  Map<String, dynamic>? get video => json['video'];
  Map<String, dynamic>? get document => json['document'];
  Map<String, dynamic>? get link => json['link'];
  Poll? get poll => json['poll'] == null ? null : Poll(Map<String, dynamic>.from(json['poll']));
  int get likeCount => json['likeCount'] ?? 0;
  int get commentCount => json['commentCount'] ?? 0;
  bool get likedByMe => json['likedByMe'] == true;
  bool get isMine => json['isMine'] == true;
  DateTime get createdAt => DateTime.parse(json['createdAt']).toLocal();
  bool get edited => json['editedAt'] != null;
  String get shareLink => json['shareLink'];
}

class Comment {
  Comment(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'];
  String? get parentId => json['parentId'];
  bool get deleted => json['deleted'] == true;
  PersonRef? get author => json['author'] == null ? null : PersonRef(Map<String, dynamic>.from(json['author']));
  String get text => json['text'] ?? '';
  String? get imageUrl => json['imageUrl'];
  List<Map<String, dynamic>> get mentions => List<Map<String, dynamic>>.from(json['mentions'] ?? []);
  int get likeCount => json['likeCount'] ?? 0;
  bool get likedByMe => json['likedByMe'] == true;
  int get replyCount => json['replyCount'] ?? 0;
  bool get isMine => json['isMine'] == true;
  bool get edited => json['editedAt'] != null;
  DateTime get createdAt => DateTime.parse(json['createdAt']).toLocal();
}

/// "10m ago", "2h ago", "3d ago", then a date.
String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 60) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${m[t.month - 1]}';
}

/// "23hours left" style from the design, for open polls.
String timeLeft(DateTime closes, {DateTime? now}) {
  final d = closes.difference(now ?? DateTime.now());
  if (d.isNegative) return 'Closed';
  if (d.inDays >= 1) return '${d.inDays}${d.inDays == 1 ? 'day' : 'days'} left';
  if (d.inHours >= 1) return '${d.inHours}${d.inHours == 1 ? 'hour' : 'hours'} left';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes}mins left';
}

String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';
