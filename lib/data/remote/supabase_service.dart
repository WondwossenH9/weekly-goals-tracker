import "package:supabase_flutter/supabase_flutter.dart";

/// Thin wrapper around the Supabase client so the rest of the app never
/// imports supabase_flutter directly — makes it easy to fake in tests and
/// keeps auth + table access in one place.
class SupabaseService {
  SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(url: url, anonKey: anonKey);
  }

  User? get currentUser => client.auth.currentUser;
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  /// Passwordless sign-in: Supabase emails the user a magic link, which
  /// deep-links back into the app (see README for the redirect URL setup
  /// required in the Supabase dashboard + Android manifest).
  Future<void> sendMagicLink(String email) {
    return client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: "io.supabase.weeklygoals://login-callback/",
    );
  }

  Future<void> signOut() => client.auth.signOut();
}
