import 'package:flutter/foundation.dart';
import 'api.dart';
import 'models.dart';
import 'services.dart';

/// Holds the signed-in user. Screens read [me] and call [refresh] after a
/// step changes it.
class Session extends ChangeNotifier {
  Session(this.api, this.store);
  final ApiClient api;
  final LocalStore store;
  Me? me;
  bool restored = false;
  /// Community code from an invite link opened before sign-up (ONB-24.4).
  String? pendingCommunityCode;

  bool get signedIn => api.token != null && me != null;

  Future<void> restore() async {
    api.token = await store.readToken();
    if (api.token != null) {
      try {
        await refresh();
      } on ApiException catch (e) {
        if (e.status == 401) await _clear();
      }
    }
    restored = true;
    notifyListeners();
  }

  Future<void> signIn(String token) async {
    api.token = token;
    await store.writeToken(token);
    await refresh();
  }

  Future<Me> refresh() async {
    me = Me(await api.get('/me'));
    notifyListeners();
    return me!;
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } catch (_) {}
    await _clear();
  }

  Future<void> _clear() async {
    api.token = null;
    me = null;
    await store.writeToken(null);
    notifyListeners();
  }
}
