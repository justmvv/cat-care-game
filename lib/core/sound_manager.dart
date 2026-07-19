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

  /// Enables/disables the background-music desire (menu + game).
  void musicWanted(bool wanted) {
    _musicWanted = wanted;
    _applyMusic();
  }

  bool _pausedByGame = false;

  /// True only once REAL playback progress has been observed. Browsers
  /// can silently reject play() outside a user gesture while the player
  /// still claims to be "playing", so position progress is the only
  /// trustworthy signal.
  bool _musicStarted = false;
  DateTime _lastKick = DateTime.fromMillisecondsSinceEpoch(0);

  /// Live diagnostics shown in the UI while the music is not audible:
  /// 'starting' -> 'started?' -> 'playing', or 'ERR…: <cause>'.
  String musicStatus = 'off';

  Future<void> _startMusicFresh() async {
    try {
      _music?.dispose();
    } catch (_) {}
    _musicStarted = false;
    musicStatus = 'starting';
    try {
      final p = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
      _music = p;
      p.onPositionChanged.listen((pos) {
        if (pos > Duration.zero) {
          _musicStarted = true;
          musicStatus = 'playing';
        }
      });
      // no awaits before play(): a user-activation must survive
      p.play(AssetSource('audio/ragtime_medley.wav'), volume: 0.45).then(
        (_) {
          if (musicStatus == 'starting') musicStatus = 'started?';
        },
        onError: (Object e) {
          // medley missing/undecodable? fall back to the original track
          // that shipped with every build since day one
          musicStatus = 'ERR1: $e';
          try {
            p
                .play(AssetSource('audio/kitten_on_the_keys.wav'),
                    volume: 0.45)
                .then((_) {}, onError: (Object e2) {
              musicStatus = 'ERR2: $e2';
            });
          } catch (e2) {
            musicStatus = 'ERR2b: $e2';
          }
        },
      );
    } catch (e) {
      musicStatus = 'ERR0: $e';
    }
  }

  /// Call from any real user gesture (tap). While the music has never
  /// ACTUALLY started, every tap (throttled) restarts it from scratch
  /// inside the gesture call stack — self-healing on every platform.
  /// Once playback truly runs, taps never touch it again.
  void userGesture() {
    if (_musicStarted) return;
    if (!(_musicWanted && settings.musicOn)) return;
    if (_pausedByGame) return;
    final now = DateTime.now();
    if (now.difference(_lastKick).inMilliseconds < 2000) return;
    _lastKick = now;
    _startMusicFresh();
  }

  void _onSettingsChanged() => _applyMusic();

  /// Both ragtime pieces live in one looping medley file — a native
  /// loop never depends on flaky "track completed" events.
  ///
  /// IMPORTANT: resume() on a player whose play() was silently blocked
  /// by the browser is a no-op forever. So until playback has REALLY
  /// started, always start from scratch instead of resuming.
  Future<void> _applyMusic() async {
    final shouldPlay = _musicWanted && settings.musicOn;
    try {
      if (shouldPlay) {
        if (_music == null || !_musicStarted) {
          await _startMusicFresh();
        } else {
          await _music!.resume();
        }
      } else {
        await _music?.pause();
      }
    } catch (_) {}
  }

  void pauseAll() {
    _pausedByGame = true;
    try {
      _music?.pause();
    } catch (_) {}
  }

  void resumeAll() {
    _pausedByGame = false;
    _applyMusic();
  }

  void dispose() {
    settings.removeListener(_onSettingsChanged);
    _music?.dispose();
    _music = null;
  }
}
