import 'package:comerune/data/auth/user_session_store.dart';

class InMemoryUserSessionStore implements UserSessionStore {
  String _session = '';

  @override
  Future<String> load() async => _session;

  @override
  Future<void> save(String userSession) async {
    _session = userSession;
  }

  @override
  Future<void> clear() async {
    _session = '';
  }
}
