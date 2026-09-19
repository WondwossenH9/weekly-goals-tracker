import "package:flutter/material.dart";
import "package:flutter_dotenv/flutter_dotenv.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "app.dart";
import "data/remote/supabase_service.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loads SUPABASE_URL / SUPABASE_ANON_KEY from .env (copy .env.example ->
  // .env and fill in your project values — see README).
  await dotenv.load(fileName: ".env");

  await SupabaseService.initialize(
    url: dotenv.get("SUPABASE_URL"),
    anonKey: dotenv.get("SUPABASE_ANON_KEY"),
  );

  runApp(const ProviderScope(child: WeeklyGoalsApp()));
}
