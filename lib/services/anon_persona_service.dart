import 'package:flutter/foundation.dart';

/// Holds the current user's chosen anon persona photo — the image they set
/// specifically to represent their anonymous identity, distinct from (and
/// never derived from) their real profile photo. Same local-state-only
/// fidelity as the rest of this app's profile data (see _profileName/
/// _profileScore in profile_screen.dart) — no `users` table column for this
/// yet, matching CurrentUserService's stopgap note about onboarding.
class AnonPersonaService extends ChangeNotifier {
  AnonPersonaService._();
  static final instance = AnonPersonaService._();

  String? _photoUrl;
  String? get photoUrl => _photoUrl;

  void setPhoto(String? url) {
    _photoUrl = url;
    notifyListeners();
  }
}
