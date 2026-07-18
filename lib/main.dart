import 'package:flutter/material.dart';

import 'core/settings.dart';
import 'core/sound_manager.dart';
import 'core/strings.dart';
import 'core/version.dart';
import 'screens/game_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  await settings.load();
  runApp(CatCareApp(settings: settings));
}

class CatCareApp extends StatefulWidget {
  const CatCareApp({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<CatCareApp> createState() => _CatCareAppState();
}

class _CatCareAppState extends State<CatCareApp> {
  late final SoundManager sound = SoundManager(widget.settings);

  @override
  void initState() {
    super.initState();
    // background ragtime plays in the menu as well as in the game
    sound.musicWanted(true);
  }

  @override
  void dispose() {
    sound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, _) => MaterialApp(
        title: L10n.t('appTitle'),
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE8A45C)),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected)
                    ? const Color(0xFFE8A45C)
                    : null),
          ),
        ),
        home: MenuScreen(settings: widget.settings, sound: sound),
      ),
    );
  }
}

// ============================================================== MENU

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key, required this.settings, required this.sound});
  final AppSettings settings;
  final SoundManager sound;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF7E8CE), Color(0xFFE8A45C), Color(0xFFE8C49A)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🐈🐱', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE09A8C),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: const Color(0xFF5C4632), width: 4),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0xFF5C4632), offset: Offset(6, 6)),
                      ],
                    ),
                    child: Text(
                      L10n.t('appTitle'),
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2,
                        shadows: [
                          Shadow(
                              color: Color(0xFF5C4632),
                              offset: Offset(3, 3)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(L10n.t('subtitle'),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5C4632))),
                  const SizedBox(height: 36),
                  _menuButton(context, L10n.t('menuPlay'),
                      const Color(0xFF8FB573), () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            GameScreen(settings: settings, sound: sound)));
                  }, big: true),
                  _menuButton(context, L10n.t('menuSettings'),
                      const Color(0xFFAEC9E0), () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SettingsScreen(settings: settings)));
                  }),
                  _menuButton(context, L10n.t('menuHelp'),
                      const Color(0xFFF2CE7E), () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const HelpScreen()));
                  }),
                  const SizedBox(height: 22),
                  const Text(
                    'build $appBuild',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0x995C4632)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuButton(
      BuildContext context, String text, Color color, VoidCallback onTap,
      {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: () {
          // every menu tap doubles as the browser's audio-unlock gesture
          sound.userGesture();
          onTap();
        },
        child: Container(
          width: 260,
          padding: EdgeInsets.symmetric(vertical: big ? 18 : 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF5C4632), width: 3.5),
            boxShadow: const [
              BoxShadow(color: Color(0xFF5C4632), offset: Offset(4, 4)),
            ],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: big ? 24 : 17,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF5C4632)),
          ),
        ),
      ),
    );
  }
}

// ============================================================ SETTINGS

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Scaffold(
        backgroundColor: const Color(0xFFFFF9EC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFE8A45C),
          title: Text(L10n.t('settingsTitle'),
              style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              secondary: const Text('🔔', style: TextStyle(fontSize: 24)),
              title: Text(L10n.t('sfx'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              value: settings.sfxOn,
              onChanged: (v) => settings.sfxOn = v,
            ),
            SwitchListTile(
              secondary: const Text('🎹', style: TextStyle(fontSize: 24)),
              title: Text(L10n.t('musicTitle'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(L10n.t('musicName')),
              value: settings.musicOn,
              onChanged: (v) => settings.musicOn = v,
            ),
            const Divider(),
            ListTile(
              leading: const Text('🌍', style: TextStyle(fontSize: 24)),
              title: Text(L10n.t('langTitle'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final entry in L10n.languages.entries)
              RadioListTile<String>(
                title: Text('${entry.value.$1}  ${entry.value.$2}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                value: entry.key,
                groupValue: settings.lang,
                onChanged: (v) => settings.lang = v!,
              ),
          ],
        ),
      ),
    );
  }
}

// ================================================================ HELP

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9EC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2CE7E),
        title: Text(L10n.t('helpTitle'),
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(
          L10n.t('helpBody'),
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
      ),
    );
  }
}
