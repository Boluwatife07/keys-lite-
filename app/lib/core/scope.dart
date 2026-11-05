import 'package:flutter/widgets.dart';
import 'api.dart';
import 'realtime.dart';
import 'services.dart';
import 'session.dart';

/// Everything screens need, provided once at the top of the tree. Tests
/// build it with fakes.
class Deps {
  Deps({required this.api, required this.session, required this.media, required this.social, required this.cards, required this.sharer, required this.store, this.videoLength, this.recorder, Realtime? realtime}) : realtime = realtime ?? NoRealtime();
  final ApiClient api;
  final Session session;
  final MediaPicker media;
  final SocialAuth social;
  final CardVerifier cards;
  final Sharer sharer;
  final LocalStore store;
  /// Reads a picked video's length (FED-04.3). Null skips the client check; the server re-checks.
  final Future<Duration?> Function(PickedFile file)? videoLength;
  /// Voice notes; null hides the microphone.
  final VoiceRecorder? recorder;
  final Realtime realtime;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.deps, required super.child});
  final Deps deps;
  static Deps of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.deps;
  @override
  bool updateShouldNotify(AppScope old) => old.deps != deps;
}

extension DepsX on BuildContext {
  Deps get deps => AppScope.of(this);
  ApiClient get api => AppScope.of(this).api;
  Session get session => AppScope.of(this).session;
}
