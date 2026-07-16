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
  bool _musicStarted = false;

  /// Ragtime playlist (both pieces are public domain), played in a loop.
  static const List<String> _playlist = [
    'kitten_on_the_keys',
    'the_entertainer',
  ];
  int _track = 0;

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

  void _onSettingsChanged() => _applyMusic();

  Future<void> _applyMusic() async {
    final shouldPlay = _musicWanted && settings.musicOn;
    try {
      if (shouldPlay) {
        if (_music == null) {
          _music = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
          _music!.onPlayerComplete.listen((_) {
            // next track in the playlist
            _track = (_track + 1) % _playlist.length;
            _musicStarted = false;
            if (_musicWanted && settings.musicOn) {
              _musicStarted = true;
              _playCurrentTrack();
            }
          });
        }
        if (_musicStarted) {
          await _music!.resume();
        } else {
          _musicStarted = true;
          await _playCurrentTrack();
        }
      } else {
        await _music?.pause();
      }
    } catch (_) {}
  }

  Future<void> _playCurrentTrack() async {
    try {
      await _music?.play(AssetSource('audio/${_playlist[_track]}.wav'),
          volume: 0.45);
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
