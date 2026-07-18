import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/settings.dart';
import '../core/sound_manager.dart';
import '../core/strings.dart';
import '../game/game_controller.dart';
import '../game/models.dart';
import '../render/iso.dart';
import '../render/scene_painter.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.settings, required this.sound});

  final AppSettings settings;
  final SoundManager sound;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final GameController game;
  late final Ticker _ticker;
  double _lastT = 0;
  double _animT = 0;

  @override
  void initState() {
    super.initState();
    game = GameController(widget.sound);
    widget.sound.musicWanted(true);
    _ticker = createTicker((elapsed) {
      final now = elapsed.inMicroseconds / 1e6;
      final dt = (now - _lastT).clamp(0.0, 0.1);
      _lastT = now;
      _animT = now;
      game.update(dt);
      if (mounted) setState(() {});
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.sound.musicWanted(false);
    game.dispose();
    super.dispose();
  }

  static const _comicShadow = [
    Shadow(color: Color(0xFF5C4632), offset: Offset(2, 2), blurRadius: 0),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5E9D3),
      // any tap counts as a user gesture: retries music if the browser
      // blocked autoplay (web autoplay policy)
      body: Listener(
        onPointerDown: (_) => widget.sound.userGesture(),
        child: Stack(
        children: [
          // ------------------------------------------------ scene
          Positioned.fill(
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: Iso.sceneW,
                  height: Iso.sceneH,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => game.handleTap(d.localPosition),
                    child: CustomPaint(
                      painter: ScenePainter(game, _animT),
                      size: const Size(Iso.sceneW, Iso.sceneH),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ------------------------------------------------ HUD
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  // scales down as one piece on narrow screens, so the
                  // buttons on the right are never clipped off-screen
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _clockCard(),
                          const SizedBox(width: 8),
                          _catChip(game.cats[0]),
                          const SizedBox(width: 6),
                          _catChip(game.cats[1]),
                          const SizedBox(width: 16),
                          _scoreCard(),
                          const SizedBox(width: 8),
                          _roundButton(
                              widget.settings.sfxOn
                                  ? Icons.volume_up
                                  : Icons.volume_off,
                              () => widget.settings.sfxOn =
                                  !widget.settings.sfxOn),
                          const SizedBox(width: 6),
                          _roundButton(
                              widget.settings.musicOn
                                  ? Icons.music_note
                                  : Icons.music_off,
                              () => widget.settings.musicOn =
                                  !widget.settings.musicOn),
                          const SizedBox(width: 6),
                          _roundTextButton(
                              game.timeScale == 2.0 ? '2×' : '1×',
                              game.toggleSpeed,
                              highlighted: game.timeScale == 2.0),
                          const SizedBox(width: 6),
                          _roundButton(
                              game.status == GameStatus.paused
                                  ? Icons.play_arrow
                                  : Icons.pause,
                              _togglePause),
                          const SizedBox(width: 6),
                          _roundButton(Icons.home,
                              () => Navigator.of(context).pop()),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 250),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final t in game.activeTasks) _taskCard(t),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (game.tipVisible) _tipBanner(),
                ],
              ),
            ),
          ),
          if (game.status == GameStatus.ready) _introOverlay(),
          if (game.status == GameStatus.paused) _pausedOverlay(),
          if (game.status == GameStatus.finished) _resultOverlay(),
        ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ HUD widgets

  Widget _card({required Widget child, Color color = const Color(0xFFFFFDF5)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF5C4632), width: 2.5),
        boxShadow: const [
          BoxShadow(color: Color(0xFF5C4632), offset: Offset(3, 3)),
        ],
      ),
      child: child,
    );
  }

  Widget _clockCard() {
    final phaseKey = switch (game.phase) {
      GamePhase.morning => 'phase_morning',
      GamePhase.day => 'phase_day',
      GamePhase.evening => 'phase_evening',
      GamePhase.night => 'phase_night',
    };
    final phaseEmoji = switch (game.phase) {
      GamePhase.morning => '🌅',
      GamePhase.day => '☀️',
      GamePhase.evening => '🌇',
      GamePhase.night => '🌙',
    };
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$phaseEmoji ${game.clockString} · ${L10n.t(phaseKey)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 4),
          SizedBox(
            width: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: game.elapsed / GameController.dayLength,
                minHeight: 7,
                backgroundColor: const Color(0xFFEDE3D0),
                valueColor:
                    const AlwaysStoppedAnimation(Color(0xFFE8A45C)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _catChip(Cat cat) {
    final moodColor = cat.mood > 60
        ? const Color(0xFF8FB573)
        : cat.mood > 30
            ? const Color(0xFFE8A45C)
            : const Color(0xFFD97B6C);
    String? urgent;
    if (cat.hunger > 70) urgent = '🍗';
    if (cat.play > 75) urgent = '🧶';
    if (cat.attention > 85) urgent = '💗';
    if (cat.state == CatState.yowling) urgent = '😾';
    return _card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
              '${cat.isKitten ? '🐱' : '🐈'} ${L10n.t(cat.nameKey)}'
              '${urgent != null ? ' $urgent' : ''}',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 3),
          SizedBox(
            width: 90,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: cat.mood / 100,
                minHeight: 6,
                backgroundColor: const Color(0xFFEDE3D0),
                valueColor: AlwaysStoppedAnimation(moodColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreCard() => _card(
        color: const Color(0xFFF2CE7E),
        child: Text('⭐ ${game.score}',
            style:
                const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
      );

  Widget _roundButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Color(0xFFFFFDF5),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF5C4632), width: 2.5),
          boxShadow: const [
            BoxShadow(color: Color(0xFF5C4632), offset: Offset(2, 2)),
          ],
        ),
        child: Icon(icon, size: 22, color: const Color(0xFF5C4632)),
      ),
    );
  }

  /// Round HUD button with text (used for the 1×/2× speed toggle).
  Widget _roundTextButton(String label, VoidCallback onTap,
      {bool highlighted = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: highlighted
              ? const Color(0xFFF2CE7E)
              : const Color(0xFFFFFDF5),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF5C4632), width: 2.5),
          boxShadow: const [
            BoxShadow(color: Color(0xFF5C4632), offset: Offset(2, 2)),
          ],
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF5C4632))),
      ),
    );
  }

  String _taskEmoji(TaskType t) => switch (t) {
        TaskType.feed => '🍗',
        TaskType.cleanLitter => '🧹',
        TaskType.play => '🧶',
        TaskType.attention => '💗',
        TaskType.stopMischief => '⚠️',
        TaskType.openDoor => '🚪',
        TaskType.closeDoor => '🌬️',
        TaskType.findToy => '🐭',
      };

  Widget _taskCard(TaskItem t) {
    final total = t.deadline - t.createdAt;
    final left = (t.deadline - game.elapsed).clamp(0.0, total);
    final frac = total > 0 ? left / total : 0.0;
    final urgentColor = frac < 0.3
        ? const Color(0xFFD97B6C)
        : frac < 0.6
            ? const Color(0xFFE8A45C)
            : const Color(0xFF8FB573);
    String title = L10n.t(t.titleKey);
    if (t.type == TaskType.attention && t.catId != null) {
      title = '$title ${L10n.t(game.cats[t.catId!].nameKey)}';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () => game.performTask(t),
        child: _card(
          child: Row(
            children: [
              Text(_taskEmoji(t.type), style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 12)),
                    Text('👆 ${L10n.t(_taskHint(t.type))}',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF8B7355))),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 5,
                        backgroundColor: const Color(0xFFEDE3D0),
                        valueColor: AlwaysStoppedAnimation(urgentColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _taskHint(TaskType t) => switch (t) {
        TaskType.feed => 'hint_feed',
        TaskType.cleanLitter => 'hint_litter',
        TaskType.play => 'hint_play',
        TaskType.attention => 'hint_attention',
        TaskType.stopMischief => 'hint_mischief',
        TaskType.openDoor => 'hint_door',
        TaskType.closeDoor => 'hint_door',
        TaskType.findToy => 'hint_toy',
      };

  Widget _tipBanner() {
    return _card(
      color: const Color(0xFFF7EDD8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('💡', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(L10n.t(game.tipKey!),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- overlays

  Widget _overlayShell(List<Widget> children) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xAA6B5138),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9EC),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF5C4632), width: 4),
              boxShadow: const [
                BoxShadow(color: Color(0xFF5C4632), offset: Offset(6, 6)),
              ],
            ),
            // scrolls on small screens instead of overflowing
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _comicButton(String text, VoidCallback onTap,
      {Color color = const Color(0xFFE8A45C)}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF5C4632), width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0xFF5C4632), offset: Offset(3, 3)),
            ],
          ),
          child: Text(text,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF5C4632))),
        ),
      ),
    );
  }

  Widget _introOverlay() {
    return _overlayShell([
      const Text('🐈🐱', style: TextStyle(fontSize: 40)),
      const SizedBox(height: 8),
      Text(L10n.t('appTitle'),
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Color(0xFFD97B6C),
              shadows: _comicShadow)),
      const SizedBox(height: 12),
      Text(L10n.t('intro_text'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7EDD8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF5C4632), width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.t('howto_title'),
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 13)),
            const SizedBox(height: 4),
            for (final k in const [
              'howto_feed',
              'howto_litter',
              'howto_play',
              'howto_cat',
              'howto_task',
            ])
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(L10n.t(k),
                    style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _comicButton(L10n.t('start'), game.start),
    ]);
  }

  void _togglePause() {
    if (game.status == GameStatus.paused) {
      game.resume();
    } else {
      game.pause();
    }
  }

  /// Minimal pause veil: no dialog — tap anywhere to resume.
  Widget _pausedOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: game.resume,
        child: Container(
          color: const Color(0x996B5138),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 34, vertical: 22),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9EC),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: const Color(0xFF5C4632), width: 4),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0xFF5C4632), offset: Offset(5, 5)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.pause_circle_filled,
                      size: 44, color: Color(0xFFE8A45C)),
                  const SizedBox(height: 6),
                  Text(L10n.t('pauseTitle'),
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('▶ ${L10n.t('resume')}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8B7355))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultOverlay() {
    final starsText =
        List.generate(3, (i) => i < game.stars ? '★' : '☆').join(' ');
    return _overlayShell([
      Text(game.won ? L10n.t('result_win') : L10n.t('result_lose'),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: game.won
                  ? const Color(0xFF8FB573)
                  : const Color(0xFFD97B6C),
              shadows: _comicShadow)),
      const SizedBox(height: 6),
      Text(starsText,
          style: const TextStyle(
              fontSize: 40, color: Color(0xFFE8A45C))),
      Text(L10n.t('win_${game.stars}'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      _statRow(L10n.t('result_done'), '${game.tasksDone}'),
      _statRow(L10n.t('result_failed'), '${game.tasksFailed}'),
      _statRow(L10n.t('result_damage'), '${game.damage}'),
      _statRow(L10n.t('scoreLabel'), '${game.score}'),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(L10n.t('result_learned'),
            style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 14)),
      ),
      const SizedBox(height: 4),
      for (int i = 1; i <= 5; i++)
        Align(
          alignment: Alignment.centerLeft,
          child: Text('🐾 ${L10n.t('learned_$i')}',
              style: const TextStyle(fontSize: 13)),
        ),
      const SizedBox(height: 14),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _comicButton(L10n.t('play_again'), game.restart),
          const SizedBox(width: 10),
          _comicButton(L10n.t('quitToMenu'),
              () => Navigator.of(context).pop(),
              color: const Color(0xFFAEC9E0)),
        ],
      ),
    ]);
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(value,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
