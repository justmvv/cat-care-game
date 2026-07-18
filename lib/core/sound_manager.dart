import 'package:audioplayers/audioplayers.dart';

import 'settings.dart';

/// Plays SFX (WAV assets) and loops background music.
/// Respects [AppSettings]: SFX toggle and music toggle (music off by default).
class SoundManager {
  SoundManager(this.settings) {
    settings.addListener(_onSettingsChanged);
  }

  final AppSettings settings;

  AudioPlayer? _music;
  bool _musicWanted = false;

  /// Minimal interval (seconds) between repeats of the same sound.
  static const Map<String, double> _cooldowns = {
    'meow': 1.2,
    'meow_kitten': 1.2,
    'yowl': 2.5,
    'purr': 1.5,
    'scratch': 0.8,
    'chirp': 2.0,
  };
  final Map<String, int> _lastPlayed = {};

  /// SFX use short-lived independent players so they can never be
  /// affected by the music player's state (pause/stop/track change).
  Future<void> sfx(String name) async {
    if (!settings.sfxOn) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cd = ((_cooldowns[name] ?? 0.15) * 1000).round();
    if (now - (_lastPlayed[name] ?? -100000) < cd) return;
    _lastPlayed[name] = now;
    try {
      final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      player.onPlayerComplete.listen((_) => player.dispose());
      await player.play(AssetSource('audio/$name.wav'), volume: 0.9);
    } catch (_) {}
  }

  /// Called when the game screen opens: starts music if enabled in settings.
  void musicWanted(bool wanted) {
    _musicWanted = wanted;
    _applyMusic();
  }

  /// Call from any real user gesture (tap). Browsers block audio
  /// autoplay until the user interacts — this retries the music then.
  void userGesture() {
    if (!(_musicWanted && settings.musicOn)) return;
    try {
      if (_music == null || _music!.state != PlayerState.playing) {
        _music?.dispose();
        _music = null;
        _applyMusic();
      }
    } catch (_) {}
  }

  void _onSettingsChanged() => _applyMusic();

  /// Both ragtime pieces live in one looping medley file — a native
  /// loop never depends on flaky "track completed" events.
  Future<void> _applyMusic() async {
    final shouldPlay = _musicWanted && settings.musicOn;
    try {
      if (shouldPlay) {
        if (_music == null) {
          _music = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
          await _music!
              .play(AssetSource('audio/ragtime_medley.wav'), volume: 0.45);
        } else {
          await _music!.resume();
        }
      } else {
        await _music?.pause();
      }
    } catch (_) {}
  }

  void pauseAll() {
    try {
      _music?.pause();
    } catch (_) {}
  }

  void resumeAll() => _applyMusic();

  void dispose() {
    settings.removeListener(_onSettingsChanged);
    _music?.dispose();
    _music = null;
  }
}
