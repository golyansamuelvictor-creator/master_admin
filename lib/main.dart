// ignore_for_file: deprecated_member_use, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

// Import your screens
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/add_account_screen.dart';

// --- THEME MANAGER ---
// This ValueNotifier holds the current theme state (light, dark, or system)
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://bbottkhzcpzjsufeyryv.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJib3R0a2h6Y3B6anN1ZmV5cnl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzNTg1NTEsImV4cCI6MjA4NDkzNDU1MX0.EwHg23bzbS27WB6-F4lvp1VI2kZ3YmnENVw-OkvSsHk',
  );

  runApp(const MasterAdminApp());
}

class MasterAdminApp extends StatelessWidget {
  const MasterAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color pPurple = Color(0xFF4A148C);

    // We wrap the entire app in a ValueListenableBuilder
    // When themeNotifier.value changes, this entire block rebuilds
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'Master Administration',
          debugShowCheckedModeBanner: false,
          
          // 1. LIGHT THEME CONFIG
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(seedColor: pPurple, brightness: Brightness.light),
            textTheme: GoogleFonts.merriweatherTextTheme(ThemeData.light().textTheme),
            scaffoldBackgroundColor: const Color(0xFFFBFBFE),
          ),

          // 2. DARK THEME CONFIG
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(seedColor: pPurple, brightness: Brightness.dark),
            textTheme: GoogleFonts.merriweatherTextTheme(ThemeData.dark().textTheme),
            scaffoldBackgroundColor: const Color(0xFF121212), // Professional deep dark
          ),

          // 3. CURRENT THEME MODE
          themeMode: currentMode,

          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'US')],
          
          routes: {
            '/home': (context) => const HomeScreen(),
            '/auth': (context) => const AuthScreen(),
            '/add-account': (context) => const AddAccountScreen(),
          },
          home: const AuthWrapper(),
        );
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF4A148C))));
        }

        final session = snapshot.data?.session;

        if (session == null) {
          return const AuthScreen();
        }

        return FutureBuilder(
          future: Supabase.instance.client
              .from('profiles')
              .select('full_name') 
              .eq('id', session.user.id)
              .maybeSingle(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF4A148C))));
            }

            final data = profileSnapshot.data;

            if (data == null || data['full_name'] == null || data['full_name'].toString().isEmpty) {
              return const AddAccountScreen();
            }

            return const HomeScreen();
          },
        );
      },
    );
  }
}