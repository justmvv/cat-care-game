import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/sound_manager.dart';
import '../render/iso.dart';
import 'models.dart';

enum GameStatus { ready, running, paused, finished }

/// The whole game simulation: cat needs, scripted day events, mischief,
/// tasks, owner actions and scoring. One in-game day = 10 real minutes.
class GameController extends ChangeNotifier {
  GameController(this.sound) {
    _reset();
  }

  final SoundManager sound;
  final Random _rng = Random();

  static const double dayLength = 600; // seconds

  // --- state ---------------------------------------------------------------
  GameStatus status = GameStatus.ready;
  double elapsed = 0;

  late List<Cat> cats;
  final Owner owner = Owner();

  final List<TaskItem> tasks = [];
  final List<FxText> fx = [];
  late List<ScriptedEvent> _script;

  // room state
  double foodInBowl = 0; // 0..100
  double litterDirt = 20; // 0..100
  int sofaScratch = 0; // 0..3 (visual damage levels)
  int wallScratch = 0; // 0..3
  final List<String> tableItems = ['vase', 'cup', 'book'];
  final List<FallenItem> fallenItems = [];
  bool boxPresent = false;
  bool flowerOnSill = true; // a flower pot on the windowsill (until…)
  bool lampFallen = false; // the floor lamp got toppled
  bool curtainLeftTorn = false;
  bool curtainRightTorn = false;

  // --- the great escape ------------------------------------------------------
  bool doorOpen = false;
  int escapeStage = 0; // 0 calm, 1 cat bolting out, 2 panic/call/rescue
  int escapedCatId = -1;
  double _escapePhaseAt = 0;
  double carrierUntil = -1; // the pet carrier stays visible until then
  Offset? _panicTarget;

  bool get ownerPanicking =>
      escapeStage == 2 && elapsed - _escapePhaseAt < 5;
  bool get ownerCalling =>
      escapeStage == 2 && elapsed - _escapePhaseAt >= 5;
  bool isCatEscaped(Cat c) => escapeStage >= 2 && c.id == escapedCatId;
  double birdsUntil = -1;
  double zoomiesUntil = -1;
  double stormStart = -1;
  double stormUntil = -1;
  double flyUntil = -1;
  double _nextThunderAt = -1;
  final List<Particle> particles = [];

  // meta
  int score = 0;
  int tasksDone = 0;
  int tasksFailed = 0;
  int damage = 0;
  int stars = 0;
  bool won = false;

  String? tipKey;
  double tipUntil = 0;

  /// Tap feedback: a small ring shown where the owner is heading.
  Offset? tapMark;
  double tapMarkUntil = 0;

  bool get birdsActive => elapsed < birdsUntil;
  bool get zoomiesActive => elapsed < zoomiesUntil;
  bool get stormActive => elapsed < stormUntil;
  bool get flyActive => elapsed < flyUntil;

  GamePhase get phase {
    if (elapsed < 150) return GamePhase.morning;
    if (elapsed < 390) return GamePhase.day;
    if (elapsed < 540) return GamePhase.evening;
    return GamePhase.night;
  }

  /// Game clock: 08:00 .. 22:00 over 10 minutes.
  String get clockString {
    final minutes = 480 + (elapsed * 1.4).floor();
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  double get avgMood => cats.map((c) => c.mood).reduce((a, b) => a + b) / 2;
  List<TaskItem> get activeTasks => tasks.where((t) => t.active).toList();

  // --- lifecycle -----------------------------------------------------------

  void _reset() {
    elapsed = 0;
    status = GameStatus.ready;
    cats = [
      Cat(id: 0, nameKey: 'cat_adult', isKitten: false, pos: const Offset(4.5, 0.8))
        ..hunger = 55
        ..play = 30
        ..attention = 25,
      Cat(id: 1, nameKey: 'cat_kitten', isKitten: true, pos: const Offset(8.5, 1.2))
        ..hunger = 62
        ..play = 45
        ..attention = 35,
    ];
    owner
      ..pos = const Offset(7.2, 1.0)
      ..state = OwnerState.idle
      ..job = null;
    tasks.clear();
    fx.clear();
    foodInBowl = 0;
    litterDirt = 20;
    sofaScratch = 0;
    wallScratch = 0;
    tableItems
      ..clear()
      ..addAll(['vase', 'cup', 'book']);
    fallenItems.clear();
    boxPresent = false;
    flowerOnSill = true;
    lampFallen = false;
    curtainLeftTorn = false;
    curtainRightTorn = false;
    doorOpen = false;
    escapeStage = 0;
    escapedCatId = -1;
    carrierUntil = -1;
    _panicTarget = null;
    birdsUntil = -1;
    zoomiesUntil = -1;
    stormStart = -1;
    stormUntil = -1;
    flyUntil = -1;
    _nextThunderAt = -1;
    particles.clear();
    score = 0;
    tasksDone = tasksFailed = damage = stars = 0;
    won = false;
    tipKey = null;
    tapMark = null;
    _script = _buildScript();
  }

  void start() {
    if (status == GameStatus.ready) {
      status = GameStatus.running;
      _showTip('tip_feed');
      notifyListeners();
    }
  }

  void restart() {
    _reset();
    status = GameStatus.running;
    notifyListeners();
  }

  void pause() {
    if (status == GameStatus.running) {
      status = GameStatus.paused;
      sound.pauseAll();
      notifyListeners();
    }
  }

  void resume() {
    if (status == GameStatus.paused) {
      status = GameStatus.running;
      sound.resumeAll();
      notifyListeners();
    }
  }

  // --- scripted day (storyline) ---------------------------------------------

  List<ScriptedEvent> _buildScript() => [
        ScriptedEvent(110, () {
          birdsUntil = elapsed + 18;
          sound.sfx('chirp');
          _showTip('tip_birds');
        }),
        ScriptedEvent(175, () {
          sound.sfx('doorbell');
          _addFx('fx_ding', Iso.offsetToScene(RoomLayout.door.grid), big: true);
          _spawnTask(TaskType.openDoor, 30);
        }),
        ScriptedEvent(215, () {
          // the adult cat eyes the flower pot on the windowsill…
          if (flowerOnSill) {
            final c = cats[0];
            c.mischiefTarget = MischiefTarget.flower;
            _walkTo(c, const Offset(2.4, 0.35), CatState.mischiefWarning);
          }
        }),
        ScriptedEvent(260, () {
          // a fly gets in — free cat exercise!
          flyUntil = elapsed + 20;
          sound.sfx('buzz');
          _showTip('tip_fly');
          for (final c in cats) {
            if (c.state != CatState.sleeping && c.state != CatState.inBox) {
              c.state = CatState.zoomies;
              c.stateT = 0;
              c.target = null;
            }
          }
        }),
        ScriptedEvent(280, () {
          // the hunt is over: tired and happy
          for (final c in cats) {
            c.play = max(0, c.play - 15);
            c.mood = min(100, c.mood + 5);
          }
          sound.sfx('purr');
        }),
        ScriptedEvent(305, () {
          if (litterDirt > 40) _showTip('tip_litter');
        }),
        ScriptedEvent(380, () {
          // thunderstorm: cats hide, don't touch them — it's normal
          stormStart = elapsed;
          stormUntil = elapsed + 30;
          _nextThunderAt = elapsed;
          _showTip('tip_storm');
          for (final c in cats) {
            _walkTo(c, RoomLayout.table.grid + Offset(c.id * 1.2 - 0.6, 0.5),
                CatState.hiding);
            _bubble(c, BubbleIcon.exclaim, 8);
          }
        }),
        ScriptedEvent(320, () {
          // the kitten discovers that curtains make a great climbing wall
          final k = cats[1];
          if ((!curtainLeftTorn || !curtainRightTorn) &&
              k.state != CatState.sleeping &&
              k.state != CatState.inBox) {
            k.mischiefTarget = MischiefTarget.curtain;
            k.curtainSide = !curtainLeftTorn ? 0 : 1;
            _walkTo(
                k,
                k.curtainSide == 0
                    ? const Offset(1.0, 0.45)
                    : const Offset(3.85, 0.45),
                CatState.mischiefWarning);
          }
        }),
        ScriptedEvent(490, () {
          // a draught swings the door open — close it, or else…!
          doorOpen = true;
          sound.sfx('pop');
          _addFx('fx_ding',
              Iso.offsetToScene(RoomLayout.door.grid) - const Offset(0, 120),
              big: true);
          _spawnTask(TaskType.closeDoor, 18);
          _showTip('tip_door_open');
        }),
        ScriptedEvent(355, () {
          _spawnTask(TaskType.findToy, 45);
          final kitten = cats[1];
          kitten.target = RoomLayout.sofa.grid + const Offset(-0.8, 0.4);
          kitten.state = CatState.walking;
          kitten.afterWalk = CatState.begging;
          _bubble(kitten, BubbleIcon.play, 8);
          sound.sfx('meow_kitten');
        }),
        ScriptedEvent(430, () {
          zoomiesUntil = elapsed + 18;
          _showTip('tip_zoomies');
          for (final c in cats) {
            c.state = CatState.zoomies;
            c.stateT = 0;
          }
        }),
        ScriptedEvent(438, () {
          if (tableItems.contains('vase') && _rng.nextDouble() < 0.7) {
            cats[1].pos = RoomLayout.table.grid + const Offset(0.3, 0.3);
            _knockItem('vase');
          }
        }),
        ScriptedEvent(470, () {
          birdsUntil = elapsed + 12;
          sound.sfx('chirp');
        }),
        ScriptedEvent(560, () {
          _showTip('tip_sleep');
          for (final c in cats) {
            if (c.worstNeed < 70) {
              // curl up ON the sofa for the night
              c.perchLift = 50;
              _walkTo(c, Offset(8.5 + c.id * 0.9, 0.55), CatState.sleeping);
              c.afterWalk = CatState.sleeping;
            }
          }
        }),
        ScriptedEvent(575, () {
          // a short burst of night zoomies — classic cats
          zoomiesUntil = elapsed + 8;
          for (final c in cats) {
            if (c.state != CatState.sleeping) {
              c.state = CatState.zoomies;
              c.stateT = 0;
              c.target = null;
            }
          }
        }),
      ];

  // --- main update -----------------------------------------------------------

  void update(double dt) {
    if (status != GameStatus.running) return;
    if (dt > 0.1) dt = 0.1;
    elapsed += dt;

    for (final e in _script) {
      if (!e.fired && elapsed >= e.time) {
        e.fired = true;
        e.run();
      }
    }

    _updateNeeds(dt);
    _spawnNeedTasks();
    _expireTasks();
    for (final c in cats) {
      if (isCatEscaped(c)) continue; // she's out there somewhere…
      _updateCat(c, dt);
    }
    _updateOwner(dt);
    _updateEscape(dt);
    _updateMood(dt);

    fx.removeWhere((f) => elapsed > f.until);
    for (final c in cats) {
      if (elapsed > c.bubbleUntil) c.bubble = BubbleIcon.none;
    }

    // thunder rolls every ~7 s during the storm (synced with the flash)
    if (stormActive && elapsed >= _nextThunderAt) {
      _nextThunderAt = elapsed + 7;
      sound.sfx('thunder');
      _addFx('fx_boom',
          Iso.offsetToScene(RoomLayout.window.grid) - const Offset(0, 190),
          big: true);
      // hiding cats flinch at every thunderclap
      for (final c in cats) {
        if (c.state == CatState.hiding) {
          c.stateT = 0; // triggers the startle animation
          _bubble(c, BubbleIcon.exclaim, 2.5);
        }
      }
    }

    // particles
    for (final p in particles) {
      p.pos += p.vel * dt;
    }
    particles.removeWhere((p) => elapsed > p.until);

    if (elapsed >= dayLength) _finish();
    notifyListeners();
  }

  void _updateNeeds(double dt) {
    for (final c in cats) {
      final k = c.isKitten;
      c.hunger = min(100, c.hunger + dt * 100 / (k ? 190 : 230));
      c.play = min(100, c.play + dt * 100 / (k ? 160 : 260));
      c.attention = min(100, c.attention + dt * 100 / (k ? 280 : 320));
    }
  }

  void _updateMood(double dt) {
    for (final c in cats) {
      if (c.state == CatState.yowling) {
        c.mood = max(0, c.mood - 2.5 * dt);
      } else if (c.worstNeed > 80 || litterDirt > 85) {
        c.mood = max(0, c.mood - 1.2 * dt);
      } else if (c.worstNeed < 50) {
        c.mood = min(100, c.mood + 1.0 * dt);
      }
    }
  }

  // --- tasks -----------------------------------------------------------------

  bool _hasActive(TaskType t, [int? catId]) => tasks.any(
      (x) => x.active && x.type == t && (catId == null || x.catId == catId));

  TaskItem _spawnTask(TaskType type, double seconds, {int? catId}) {
    final t = TaskItem(
        type: type,
        createdAt: elapsed,
        deadline: elapsed + seconds,
        catId: catId);
    tasks.add(t);
    sound.sfx('pop');
    return t;
  }

  void _spawnNeedTasks() {
    if (cats.any((c) => c.hunger > 70) &&
        foodInBowl <= 0 &&
        !_hasActive(TaskType.feed)) {
      _spawnTask(TaskType.feed, 45);
    }
    if (litterDirt > 60 && !_hasActive(TaskType.cleanLitter)) {
      _spawnTask(TaskType.cleanLitter, 60);
    }
    if ((cats[0].play + cats[1].play) / 2 > 72 && !_hasActive(TaskType.play)) {
      _spawnTask(TaskType.play, 60);
    }
    for (final c in cats) {
      if (c.attention > 85 && !_hasActive(TaskType.attention, c.id)) {
        _spawnTask(TaskType.attention, 45, catId: c.id);
      }
    }
  }

  void _expireTasks() {
    for (final t in tasks) {
      if (t.active && elapsed > t.deadline) {
        t.failed = true;
        tasksFailed++;
        score -= 20;
        sound.sfx('fail');
        for (final c in cats) {
          c.mood = max(0, c.mood - 8);
        }
        // the door stayed open too long — a cat bolts!
        if (t.type == TaskType.closeDoor && doorOpen) _startEscape();
      }
    }
  }

  // --- the escape drama -------------------------------------------------------

  void _startEscape() {
    if (escapeStage != 0) return;
    final awake =
        cats.where((c) => c.state != CatState.sleeping).toList();
    final c = (awake.isEmpty ? cats : awake)[
        _rng.nextInt(awake.isEmpty ? cats.length : awake.length)];
    escapedCatId = c.id;
    escapeStage = 1;
    score -= 60;
    c.perchLift = 0;
    c.mischiefTarget = null;
    c.state = CatState.walking;
    c.afterWalk = CatState.idle;
    c.target = const Offset(15.3, 0.42); // out the open door!
    c.facingLeft = false;
  }

  void _updateEscape(double dt) {
    if (escapeStage == 1) {
      final c = cats[escapedCatId];
      if (c.pos.dx > 14.2) {
        escapeStage = 2; // gone. panic time.
        _escapePhaseAt = elapsed;
        owner.job = null;
        _showTip('tip_escape');
        sound.sfx('yowl');
      }
    } else if (escapeStage == 2) {
      if (elapsed - _escapePhaseAt > 13) {
        // the rescue service returns the grumpy runaway in a carrier
        escapeStage = 0;
        doorOpen = false;
        carrierUntil = elapsed + 10;
        final c = cats[escapedCatId];
        c.pos = const Offset(11.9, 0.85);
        _setIdle(c);
        c.mood = max(0, c.mood - 20);
        _bubble(c, BubbleIcon.angry, 7);
        sound.sfx('meow');
        _showTip('tip_return');
        escapedCatId = -1;
      }
    }
  }

  void _completeTask(TaskType type, {int? catId, int points = 50}) {
    for (final t in tasks) {
      if (t.active && t.type == type && (catId == null || t.catId == catId)) {
        t.done = true;
        tasksDone++;
        score += points;
        sound.sfx('success');
        return;
      }
    }
  }

  // --- cat AI ----------------------------------------------------------------

  void _updateCat(Cat c, double dt) {
    c.stateT += dt;

    // keep lift consistent with the state (the jump itself is ballistic
    // and sets the lift explicitly in the `jumping` case below)
    if (c.state != CatState.jumping) {
      final liftGoal = (c.state == CatState.perched ||
              c.state == CatState.watchingBirds ||
              (c.state == CatState.sleeping && c.perchLift > 0) ||
              // stays up on the table while reaching for an item
              ((c.state == CatState.mischiefWarning ||
                      c.state == CatState.mischief) &&
                  c.perchLift > 0))
          ? c.perchLift
          : 0.0;
      c.lift += (liftGoal - c.lift) * min(1.0, dt * 8);
    }

    switch (c.state) {
      case CatState.walking:
        _moveCat(c, dt, c.isKitten ? 3.2 : 2.7);
        if (c.target == null || (c.pos - c.target!).distance < 0.2) {
          final wantsPerch = c.perchLift > 0 &&
              (c.afterWalk == CatState.perched ||
                  c.afterWalk == CatState.watchingBirds ||
                  c.afterWalk == CatState.sleeping);
          c.target = null; // no stale targets (kept cats "playing" asleep)
          if (wantsPerch) {
            // real cats JUMP up — ballistic hop, then settle
            c.jumpFromLift = c.lift;
            c.state = CatState.jumping;
            c.stateT = 0;
          } else {
            c.state = c.afterWalk;
            c.stateT = 0;
            if (c.state == CatState.mischiefWarning) _onMischiefWarning(c);
            if (c.state == CatState.eating) sound.sfx('munch');
          }
        }
        break;

      case CatState.jumping:
        // parabolic arc: overshoot above the target height, then land
        final k = (c.stateT / 0.38).clamp(0.0, 1.0);
        c.lift = c.jumpFromLift +
            (c.perchLift - c.jumpFromLift) * k +
            sin(k * pi) * 30;
        if (k >= 1) {
          c.lift = c.perchLift;
          if (c.perchLift > 0) {
            c.state = c.afterWalk;
            c.stateT = 0;
          } else {
            _setIdle(c); // landed on the floor
          }
        }
        break;

      case CatState.eating:
        if (c.stateT > 4) {
          c.hunger = 0;
          foodInBowl = max(0, foodInBowl - 45);
          c.nextLitterAt = elapsed + 40 + _rng.nextDouble() * 60;
          c.mood = min(100, c.mood + 6);
          _setIdle(c);
        }
        break;

      case CatState.begging:
        // food has arrived — go eat
        if (c.hunger > 55 && foodInBowl > 0) {
          _walkTo(c, RoomLayout.bowl.grid + Offset(0.4 + c.id * 0.5, 0.3),
              CatState.eating);
          break;
        }
        if (c.stateT > 5 + _rng.nextDouble() * 2) {
          c.stateT = 0;
          sound.sfx(c.isKitten ? 'meow_kitten' : 'meow');
          _addFx('fx_meow', Iso.offsetToScene(c.pos) - const Offset(0, 70));
        }
        if (c.worstNeed < 55 && !_hasActive(TaskType.findToy)) _setIdle(c);
        break;

      case CatState.mischiefWarning:
        if (c.stateT > 4) {
          c.state = CatState.mischief;
          c.stateT = 0;
          sound.sfx('scratch');
        }
        break;

      case CatState.mischief:
        // dust puffs while scratching
        if (_rng.nextDouble() < dt * 6) {
          final sp = Iso.offsetToScene(c.pos) - const Offset(0, 34);
          particles.add(Particle(
              'dust',
              sp + Offset(_rng.nextDouble() * 24 - 12, 0),
              Offset(_rng.nextDouble() * 30 - 15, -20 - _rng.nextDouble() * 20),
              elapsed + 0.9));
        }
        if (c.mischiefTarget == MischiefTarget.table) {
          if (c.stateT > 2.5) _applyMischiefDamage(c);
        } else {
          if (c.stateT > 1 && c.stateT < 4.5) {
            // ongoing scratching sound handled by cooldown
            sound.sfx('scratch');
          }
          if (c.stateT > 4.5) _applyMischiefDamage(c);
        }
        break;

      case CatState.watchingBirds:
        if (!birdsActive || c.stateT > 16) _hopDown(c);
        break;

      case CatState.yowling:
        // food arrived — stop yelling and go eat (fixes the deadlock
        // where a starving cat could never calm down)
        if (c.hunger > 55 && foodInBowl > 0) {
          _walkTo(c, RoomLayout.bowl.grid + Offset(0.4 + c.id * 0.5, 0.3),
              CatState.eating);
          break;
        }
        if (c.stateT > 3.5) {
          c.stateT = 0;
          sound.sfx('yowl');
          _addFx('fx_yowl', Iso.offsetToScene(c.pos) - const Offset(0, 76),
              big: true);
        }
        if (c.worstNeed < 75 && litterDirt < 85) _setIdle(c);
        break;

      case CatState.sleeping:
        _bubble(c, BubbleIcon.zzz, 1);
        if (c.worstNeed > 85) _setIdle(c);
        break;

      case CatState.zoomies:
        _moveCat(c, dt, 6.5);
        if (c.target == null || (c.pos - c.target!).distance < 0.3) {
          c.target = _randomFloor();
        }
        if (!zoomiesActive && !flyActive) _setIdle(c);
        break;

      case CatState.hiding:
        // trembling under the table until the storm passes
        if (!stormActive) {
          c.mood = min(100, c.mood + 4);
          _setIdle(c);
        }
        break;

      case CatState.perched:
        // sitting on the table, the paw reaches for an item all by
        // itself… (classic cat physics)
        if (c.perchLift == 82 &&
            tableItems.isNotEmpty &&
            c.stateT > 4 &&
            _rng.nextDouble() < dt * 0.2) {
          c.mischiefTarget = MischiefTarget.table;
          c.state = CatState.mischiefWarning;
          c.stateT = 0;
          _onMischiefWarning(c);
          break;
        }
        // enjoying the view from up high, like real cats do
        if (c.stateT > 12 + c.id * 4 || c.worstNeed > 75) _hopDown(c);
        break;

      case CatState.usingLitter:
        if (c.stateT > 3.5) {
          if (litterDirt > 85) {
            // the box is too dirty — the cat refuses and has an
            // accident right next to it. Lesson: clean it in time!
            fallenItems.add(
                FallenItem('puddle', c.pos + const Offset(-0.5, 0.1)));
            score -= 20;
            c.mood = max(0, c.mood - 10);
            sound.sfx('fail');
            _addFx('fx_oops', Iso.offsetToScene(c.pos) - const Offset(0, 76),
                big: true);
            _showTip('tip_accident');
          } else {
            litterDirt = min(100, litterDirt + 30);
          }
          _setIdle(c);
        }
        break;

      case CatState.usingPost:
        if (c.stateT > 4) {
          c.play = max(0, c.play - 30);
          c.mood = min(100, c.mood + 6);
          sound.sfx('purr');
          _setIdle(c);
        }
        break;

      case CatState.petted:
        if (c.stateT > 2.5) _setIdle(c);
        break;

      case CatState.playing:
        // hop around the owner during a play session
        if (owner.job?.kind != 'playSession') _setIdle(c);
        break;

      case CatState.inBox:
        if (c.stateT > 25 || c.worstNeed > 80) _setIdle(c);
        break;

      case CatState.idle:
        if (elapsed >= c.nextDecisionAt) {
          c.nextDecisionAt = elapsed + 2.5 + _rng.nextDouble() * 3;
          _decide(c);
        }
        break;
    }
  }

  /// Hop down from a perch with a proper jump animation.
  void _hopDown(Cat c) {
    c.jumpFromLift = c.lift;
    c.perchLift = 0;
    c.state = CatState.jumping;
    c.stateT = 0;
  }

  void _setIdle(Cat c) {
    c.state = CatState.idle;
    c.stateT = 0;
    c.target = null;
    c.mischiefTarget = null;
    c.perchLift = 0; // lift animates back down
    c.nextDecisionAt = elapsed + 1 + _rng.nextDouble() * 2;
  }

  void _decide(Cat c) {
    // urgent: yowl when a need is critical
    if (c.worstNeed > 92) {
      c.state = CatState.yowling;
      c.stateT = 3.4; // yowl almost immediately
      _bubble(c, BubbleIcon.angry, 6);
      return;
    }
    // needs the litter box (a too-dirty box ends in an accident nearby!)
    if (c.nextLitterAt > 0 && elapsed >= c.nextLitterAt) {
      c.nextLitterAt = -1;
      _walkTo(c, RoomLayout.litter.grid + const Offset(-0.3, 0.3),
          CatState.usingLitter);
      _bubble(c, BubbleIcon.litter, 5);
      return;
    }
    // hungry and there is food
    if (c.hunger > 55 && foodInBowl > 0) {
      _walkTo(
          c,
          RoomLayout.bowl.grid + Offset(0.4 + c.id * 0.5, 0.3),
          CatState.eating);
      return;
    }
    // hungry, bowl empty -> beg at the bowl
    if (c.hunger > 70) {
      _walkTo(c, RoomLayout.bowl.grid + Offset(0.6 + c.id * 0.5, 0.6),
          CatState.begging);
      _bubble(c, BubbleIcon.food, 8);
      return;
    }
    // birds! — jump onto the windowsill for a better view
    if (birdsActive && _rng.nextDouble() < 0.8) {
      c.perchLift = 158;
      _walkTo(c, Offset(2.0 + c.id * 0.8, 0.42), CatState.watchingBirds);
      _bubble(c, BubbleIcon.bird, 6);
      return;
    }
    // the box!
    if (boxPresent &&
        c.isKitten &&
        _rng.nextDouble() < 0.4 &&
        !cats.any((o) => o.state == CatState.inBox)) {
      _walkTo(c, RoomLayout.boxSpot.grid, CatState.inBox);
      _bubble(c, BubbleIcon.box, 5);
      return;
    }
    // content cats love heights: jump on the sofa / windowsill / table
    if (c.worstNeed < 65 && _rng.nextDouble() < 0.22) {
      switch (_rng.nextInt(3)) {
        case 0: // sofa
          c.perchLift = 50;
          _walkTo(c, Offset(8.4 + c.id * 0.9, 0.55), CatState.perched);
          break;
        case 1: // windowsill
          c.perchLift = 158;
          _walkTo(c, Offset(2.0 + c.id * 0.8, 0.42), CatState.perched);
          break;
        default: // table edge (harmless sit — this time…)
          c.perchLift = 82;
          _walkTo(c, Offset(5.4 + c.id * 0.7, 0.45), CatState.perched);
      }
      return;
    }
    // moderately bored -> use the scratching post on its own
    if (c.play > 45 && c.play <= 70 && _rng.nextDouble() < 0.25) {
      _walkTo(c, RoomLayout.post.grid + const Offset(-0.4, 0.3),
          CatState.usingPost);
      return;
    }
    // bored -> mischief or beg for play
    if (c.play > 70) {
      if (_rng.nextDouble() < 0.55) {
        _startMischief(c);
      } else {
        _walkTo(c, RoomLayout.toys.grid + Offset(c.id * 0.7, -0.4),
            CatState.begging);
        _bubble(c, BubbleIcon.play, 8);
      }
      return;
    }
    // wants attention
    if (c.attention > 85) {
      _walkTo(c, owner.pos + Offset(0.7, c.id * 0.5), CatState.begging);
      _bubble(c, BubbleIcon.heart, 8);
      return;
    }
    // nap time (siesta window) or random wander
    if (elapsed > 240 && elapsed < 300 && c.worstNeed < 60) {
      _walkTo(c, RoomLayout.rug.grid + Offset(c.id * 1.0 - 0.5, 0.3),
          CatState.sleeping);
      return;
    }
    if (_rng.nextDouble() < 0.5) {
      _walkTo(c, _randomFloor(), CatState.idle);
    }
  }

  void _walkTo(Cat c, Offset target, CatState after) {
    c.target = Offset(
        target.dx.clamp(0.8, 13.8), target.dy.clamp(0.15, 1.55));
    c.state = CatState.walking;
    c.afterWalk = after;
    c.stateT = 0;
  }

  Offset _randomFloor() {
    for (int i = 0; i < 8; i++) {
      final p = Offset(
          1.0 + _rng.nextDouble() * 12.5, 0.2 + _rng.nextDouble() * 1.3);
      if (!solids.any((r) => r.inflate(0.1).contains(p))) return p;
    }
    return const Offset(7.2, 1.3); // rug area fallback
  }

  /// Solid furniture footprints (world coords): actors walk around
  /// them; the renderer also uses these for correct z-ordering.
  static const List<Rect> solids = [
    Rect.fromLTRB(7.5, 0.05, 10.5, 0.95), // sofa
    Rect.fromLTRB(4.7, 0.05, 6.5, 0.68), // table
    Rect.fromLTRB(12.15, 0.55, 12.65, 1.0), // scratching post
    Rect.fromLTRB(13.05, 0.8, 14.1, 1.32), // litter box
  ];

  /// One movement step toward [target] that walks AROUND solid
  /// furniture: if the direct step would enter a footprint, the actor
  /// smoothly detours along the front (viewer) side of the obstacle.
  Offset _stepToward(Offset pos, Offset target, double maxStep) {
    final d = target - pos;
    if (d.distance < 1e-6) return pos;
    var next =
        pos + (d.distance <= maxStep ? d : d / d.distance * maxStep);
    for (final r in solids) {
      if (r.contains(next) && !r.inflate(0.2).contains(target)) {
        final want = Offset(next.dx, r.bottom + 0.06);
        final dd = want - pos;
        next = dd.distance <= maxStep
            ? want
            : pos + dd / dd.distance * maxStep;
        break;
      }
    }
    return next;
  }

  void _moveCat(Cat c, double dt, double speed) {
    final t = c.target;
    if (t == null) return;
    final d = t - c.pos;
    if (d.distance < 0.01) return;
    c.pos = _stepToward(c.pos, t, speed * dt);
    if (d.dx.abs() > 0.05) c.facingLeft = d.dx < 0;
  }

  // --- mischief ---------------------------------------------------------------

  void _startMischief(Cat c) {
    final choices = <MischiefTarget>[
      MischiefTarget.sofa,
      MischiefTarget.sofa,
      MischiefTarget.wallpaper,
      if (tableItems.isNotEmpty) MischiefTarget.table,
      if (tableItems.isNotEmpty) MischiefTarget.table,
      if (flowerOnSill) MischiefTarget.flower,
      if (!lampFallen) MischiefTarget.lamp,
      // only the light kitten climbs curtains
      if (c.isKitten && (!curtainLeftTorn || !curtainRightTorn))
        MischiefTarget.curtain,
    ];
    c.mischiefTarget = choices[_rng.nextInt(choices.length)];
    if (c.mischiefTarget == MischiefTarget.curtain) {
      c.curtainSide = !curtainLeftTorn && !curtainRightTorn
          ? _rng.nextInt(2)
          : (!curtainLeftTorn ? 0 : 1);
    }
    final target = switch (c.mischiefTarget!) {
      MischiefTarget.sofa => RoomLayout.sofa.grid + const Offset(-1.0, 0.6),
      MischiefTarget.wallpaper => RoomLayout.wallpaper,
      MischiefTarget.table => RoomLayout.table.grid + const Offset(0.4, 0.4),
      MischiefTarget.flower => const Offset(2.4, 0.35),
      MischiefTarget.lamp => const Offset(13.5, 0.62),
      MischiefTarget.curtain => c.curtainSide == 0
          ? const Offset(1.0, 0.45)
          : const Offset(3.85, 0.45),
    };
    _walkTo(c, target, CatState.mischiefWarning);
  }

  void _onMischiefWarning(Cat c) {
    _bubble(c, BubbleIcon.exclaim, 9);
    _spawnTask(TaskType.stopMischief, 9.5, catId: c.id);
    sound.sfx(c.isKitten ? 'meow_kitten' : 'meow');
    // the kitten starts climbing UP the curtain
    if (c.mischiefTarget == MischiefTarget.curtain) c.perchLift = 120;
  }

  void _applyMischiefDamage(Cat c) {
    switch (c.mischiefTarget) {
      case MischiefTarget.table:
        if (tableItems.isNotEmpty) {
          _knockItem(tableItems[_rng.nextInt(tableItems.length)]);
        }
        break;
      case MischiefTarget.sofa:
        if (sofaScratch < 3) sofaScratch++;
        damage++;
        score -= 40;
        _addFx('fx_scratch', Iso.offsetToScene(c.pos) - const Offset(0, 60));
        break;
      case MischiefTarget.wallpaper:
        if (wallScratch < 3) wallScratch++;
        damage++;
        score -= 40;
        _addFx('fx_scratch', Iso.offsetToScene(c.pos) - const Offset(0, 60));
        break;
      case MischiefTarget.curtain:
        if (c.curtainSide == 0) {
          curtainLeftTorn = true;
        } else {
          curtainRightTorn = true;
        }
        fallenItems.add(FallenItem(
            'curtain',
            c.curtainSide == 0
                ? const Offset(1.0, 0.75)
                : const Offset(3.85, 0.75)));
        c.perchLift = 0; // the kitten tumbles down with its trophy
        damage++;
        score -= 40;
        sound.sfx('crash');
        _addFx('fx_crash', Iso.offsetToScene(c.pos) - const Offset(0, 130),
            big: true);
        _showTip('tip_curtain');
        break;
      case MischiefTarget.lamp:
        if (!lampFallen) {
          lampFallen = true;
          damage++;
          score -= 40;
          sound.sfx('crash');
          _addFx('fx_crash',
              Iso.toScene(13.6, 0.3) - const Offset(0, 60),
              big: true);
        }
        break;
      case MischiefTarget.flower:
        if (flowerOnSill) {
          flowerOnSill = false;
          final p = const Offset(2.7, 0.95);
          fallenItems.add(FallenItem('flower', p, broken: true));
          damage++;
          score -= 40;
          sound.sfx('crash');
          _addFx('fx_crash', Iso.offsetToScene(p) - const Offset(0, 40),
              big: true);
          _showTip('tip_flower');
        }
        break;
      case null:
        break;
    }
    // the deed is done; the cat is satisfied
    c.play = max(0, c.play - 20);
    _failMischiefTask(c.id);
    _setIdle(c);
  }

  void _knockItem(String kind) {
    tableItems.remove(kind);
    final p = RoomLayout.table.grid + const Offset(0.9, 0.6);
    fallenItems.add(FallenItem(kind, p, broken: kind == 'vase'));
    damage++;
    score -= 40;
    sound.sfx('crash');
    _addFx('fx_crash', Iso.offsetToScene(p) - const Offset(0, 40), big: true);
  }

  void _failMischiefTask(int catId) {
    for (final t in tasks) {
      if (t.active && t.type == TaskType.stopMischief && t.catId == catId) {
        t.failed = true;
        tasksFailed++;
      }
    }
  }

  // --- owner ------------------------------------------------------------------

  OwnerJob? _lastJob;

  void _updateOwner(double dt) {
    // during the escape the owner is beside himself: he runs around in
    // a panic, then stops to call the pet rescue service
    if (escapeStage == 2) {
      owner.job = null;
      _lastJob = null;
      if (ownerPanicking) {
        if (_panicTarget == null ||
            (owner.pos - _panicTarget!).distance < 0.3) {
          _panicTarget = _randomFloor();
        }
        owner.state = OwnerState.walking;
        final d = _panicTarget! - owner.pos;
        owner.pos = _stepToward(owner.pos, _panicTarget!, 5.2 * dt);
        if (d.dx.abs() > 0.05) owner.facingLeft = d.dx < 0;
      } else {
        // walk to the phone spot and make the call
        const spot = Offset(10.6, 0.8);
        final d = spot - owner.pos;
        if (d.distance > 0.25) {
          owner.state = OwnerState.walking;
          owner.pos = _stepToward(owner.pos, spot, 3.6 * dt);
          if (d.dx.abs() > 0.05) owner.facingLeft = d.dx < 0;
        } else {
          owner.state = OwnerState.acting;
        }
      }
      return;
    }
    final job = owner.job;
    if (job == null) {
      owner.state = OwnerState.idle;
      _lastJob = null;
      return;
    }
    // a new job replaced the old one mid-action: restart cleanly
    // + instant feedback (ring at the destination, soft pop)
    if (!identical(job, _lastJob)) {
      _lastJob = job;
      tapMark = Iso.offsetToScene(
          job.kind == 'pet' && job.cat != null ? job.cat!.pos : job.target);
      tapMarkUntil = elapsed + 0.6;
      if (job.kind != 'move' && job.kind != 'playSession') {
        sound.sfx('pop');
      }
      if (owner.state == OwnerState.acting) {
        owner.state = OwnerState.idle;
        owner.actT = 0;
      }
    }
    if (owner.state != OwnerState.acting) {
      // pet jobs follow the (possibly moving) cat
      final target = job.kind == 'pet' && job.cat != null
          ? job.cat!.pos + const Offset(0.5, 0.2)
          : job.target;
      final d = target - owner.pos;
      if (d.distance < 0.25) {
        owner.state = OwnerState.acting;
        owner.actT = 0;
        if (job.kind == 'pet' && job.cat != null) {
          job.cat!.state = CatState.petted;
          job.cat!.stateT = 0;
          job.cat!.target = null;
        }
      } else {
        owner.state = OwnerState.walking;
        owner.pos = _stepToward(owner.pos, target, 3.6 * dt);
        if (d.dx.abs() > 0.05) owner.facingLeft = d.dx < 0;
      }
      return;
    }
    owner.actT += dt;
    if (job.kind == 'playSession') {
      // cats chase the TIP of the teaser wand, pouncing around it
      final wand = owner.pos + Offset(owner.facingLeft ? -1.0 : 1.0, 0.1);
      Offset nearWand() =>
          wand +
          Offset(_rng.nextDouble() * 1.2 - 0.6,
              _rng.nextDouble() * 0.5 - 0.2);
      for (final c in cats) {
        if (isCatEscaped(c)) continue;
        // sleeping, hiding and boxed-in cats are left alone!
        if (c.state != CatState.playing &&
            c.state != CatState.sleeping &&
            c.state != CatState.hiding &&
            c.state != CatState.inBox) {
          c.state = CatState.playing;
          c.stateT = 0;
          c.target = nearWand();
        }
        if (c.state != CatState.playing) continue;
        _moveCat(c, dt, 4.2);
        // dart to a new spot after a short pounce at the current one
        if (c.target != null &&
            ((c.pos - c.target!).distance < 0.2 && c.stateT > 0.9)) {
          c.stateT = 0;
          c.target = nearWand();
        }
      }
    }
    if (owner.actT >= job.duration) {
      owner.job = null;
      owner.state = OwnerState.idle;
      _completeJob(job);
    }
  }

  void _completeJob(OwnerJob job) {
    switch (job.kind) {
      case 'feed':
        foodInBowl = 100;
        sound.sfx('pop');
        _completeTask(TaskType.feed);
        // hungry cats react right away instead of waiting to "decide"
        for (final c in cats) {
          if (isCatEscaped(c)) continue;
          if (c.hunger > 55 &&
              (c.state == CatState.idle ||
                  c.state == CatState.begging ||
                  c.state == CatState.yowling)) {
            _walkTo(c, RoomLayout.bowl.grid + Offset(0.4 + c.id * 0.5, 0.3),
                CatState.eating);
          }
        }
        break;
      case 'scoop':
        litterDirt = 0;
        sound.sfx('scoop');
        _completeTask(TaskType.cleanLitter);
        break;
      case 'playPickup':
        sound.sfx('jingle');
        owner.job = OwnerJob(
            kind: 'playSession', target: RoomLayout.rug.grid, duration: 7);
        break;
      case 'playSession':
        for (final c in cats) {
          if (c.state == CatState.playing) {
            c.play = 0;
            c.attention = max(0, c.attention - 25);
            c.mood = min(100, c.mood + 10);
            _spawnHearts(Iso.offsetToScene(c.pos) - const Offset(0, 50), 3);
            _setIdle(c);
          }
        }
        sound.sfx('purr');
        _completeTask(TaskType.play);
        break;
      case 'pet':
        final c = job.cat;
        if (c != null) {
          c.attention = 0;
          c.mood = min(100, c.mood + 8);
          _bubble(c, BubbleIcon.heart, 4);
          sound.sfx('purr');
          _addFx('fx_purr', Iso.offsetToScene(c.pos) - const Offset(0, 64));
          _spawnHearts(Iso.offsetToScene(c.pos) - const Offset(0, 55), 5);
          _completeTask(TaskType.attention, catId: c.id);
        }
        break;
      case 'openDoor':
        sound.sfx('pop');
        boxPresent = true;
        _completeTask(TaskType.openDoor);
        _showTip('tip_box');
        score += 10;
        final kitten = cats[1];
        if (kitten.state != CatState.yowling) {
          _walkTo(kitten, RoomLayout.boxSpot.grid, CatState.inBox);
          _bubble(kitten, BubbleIcon.box, 6);
        }
        break;
      case 'fetchToy':
        sound.sfx('jingle');
        final kitten = cats[1];
        kitten.play = max(0, kitten.play - 30);
        kitten.mood = min(100, kitten.mood + 8);
        _setIdle(kitten);
        _completeTask(TaskType.findToy);
        break;
      case 'fixLamp':
        lampFallen = false;
        score += 10;
        sound.sfx('pop');
        break;
      case 'closeDoor':
        doorOpen = false;
        sound.sfx('pop');
        _completeTask(TaskType.closeDoor);
        break;
      case 'pickup':
        final item = job.item;
        if (item != null) {
          fallenItems.remove(item);
          score += 10;
          sound.sfx('pop');
          if (item.broken) _showTip('tip_pickup');
        }
        break;
      case 'usePost':
        Cat? best;
        for (final c in cats) {
          if (c.play > 40 && (c.pos - RoomLayout.post.grid).distance < 3.5) {
            if (best == null || c.play > best.play) best = c;
          }
        }
        if (best != null) {
          _walkTo(best, RoomLayout.post.grid + const Offset(-0.4, 0.3),
              CatState.usingPost);
          score += 15;
        }
        _showTip('tip_post');
        break;
      case 'look':
        if (birdsActive) sound.sfx('chirp');
        break;
      default:
        break;
    }
  }

  // --- input ------------------------------------------------------------------

  void handleTap(Offset scenePos) {
    if (status != GameStatus.running) return;
    if (escapeStage != 0) return; // the drama plays itself out

    // 1) cats — hit box matches the sprite; a begging cat routes the tap
    // to what it actually asks for (feed / play), so taps always "work"
    for (final c in cats) {
      final sp = Iso.offsetToScene(c.pos) - Offset(0, c.lift);
      final s = c.isKitten ? 0.75 : 1.0;
      final dxOk = (scenePos.dx - sp.dx).abs() < 42 * s;
      final dyOk =
          scenePos.dy > sp.dy - 108 * s && scenePos.dy < sp.dy + 14;
      if (dxOk && dyOk) {
        if (c.state == CatState.mischiefWarning ||
            c.state == CatState.mischief) {
          _stopMischief(c);
        } else if (c.state == CatState.sleeping) {
          _showTip('tip_sleep');
        } else if (c.state == CatState.begging &&
            c.bubble == BubbleIcon.food) {
          owner.job = OwnerJob(
              kind: 'feed', target: RoomLayout.bowl.grid, duration: 1.5);
        } else if (c.state == CatState.begging &&
            c.bubble == BubbleIcon.play) {
          if (!_playChainRunning) {
            owner.job = OwnerJob(
                kind: 'playPickup',
                target: RoomLayout.toys.grid,
                duration: 0.8);
          }
        } else {
          owner.job = OwnerJob(
              kind: 'pet', target: c.pos, duration: 1.6, cat: c);
        }
        return;
      }
    }

    // 2) fallen items
    for (final item in fallenItems) {
      final sp = Iso.offsetToScene(item.pos);
      if ((scenePos - sp).distance < 42) {
        owner.job = OwnerJob(
            kind: 'pickup', target: item.pos, duration: 1.2, item: item);
        return;
      }
    }

    // 2b) toppled lamp: tap to set it upright
    if (lampFallen) {
      final lampP = Iso.toScene(14.0, 0.3);
      if ((scenePos - (lampP - const Offset(35, 40))).distance < 75) {
        owner.job = OwnerJob(
            kind: 'fixLamp',
            target: const Offset(13.4, 0.62),
            duration: 1.5);
        return;
      }
    }

    // 3) spots: side view — a tap anywhere in the object's vertical
    // column counts (furniture is tall), nearest column wins
    final g = Iso.toGrid(scenePos);
    Spot? hit;
    double bestD = 1e9;
    if (g.dy > -4.4 && g.dy < 2.0) {
      for (final s in RoomLayout.all) {
        final d = (g.dx - s.gx).abs();
        if (d < s.radius + 0.3 && d < bestD) {
          bestD = d;
          hit = s;
        }
      }
    }

    if (hit != null) {
      switch (hit.id) {
        case SpotId.bowl:
          owner.job = OwnerJob(kind: 'feed', target: hit.grid, duration: 1.5);
          break;
        case SpotId.litter:
          owner.job = OwnerJob(
              kind: 'scoop',
              target: hit.grid + const Offset(-0.6, 0.4),
              duration: 2.2);
          break;
        case SpotId.toys:
          if (!_playChainRunning) {
            owner.job =
                OwnerJob(kind: 'playPickup', target: hit.grid, duration: 0.8);
          }
          break;
        case SpotId.sofa:
          if (_hasActive(TaskType.findToy)) {
            owner.job = OwnerJob(
                kind: 'fetchToy',
                target: hit.grid + const Offset(-1.2, 0.5),
                duration: 2.0);
          }
          break;
        case SpotId.post:
          owner.job = OwnerJob(
              kind: 'usePost',
              target: hit.grid + const Offset(-0.7, 0.3),
              duration: 1.0);
          break;
        case SpotId.table:
          // just walk over to the table (mischief there is stopped
          // by tapping the cat itself)
          owner.job = OwnerJob(
              kind: 'move',
              target: hit.grid + const Offset(0.9, 0.9),
              duration: 0);
          break;
        case SpotId.window:
          owner.job = OwnerJob(kind: 'look', target: hit.grid, duration: 1.0);
          if (birdsActive) _showTip('tip_birds');
          break;
        case SpotId.door:
          if (doorOpen && _hasActive(TaskType.closeDoor)) {
            owner.job =
                OwnerJob(kind: 'closeDoor', target: hit.grid, duration: 1.0);
          } else if (_hasActive(TaskType.openDoor)) {
            owner.job =
                OwnerJob(kind: 'openDoor', target: hit.grid, duration: 1.2);
          } else {
            _showTip('tip_door_none');
          }
          break;
        case SpotId.rug:
        case SpotId.box:
          owner.job = OwnerJob(kind: 'move', target: hit.grid, duration: 0);
          break;
      }
      return;
    }

    // 4) plain floor: walk there
    if (g.dx > 0 && g.dx < 14.6 && g.dy > -0.4 && g.dy < 1.8) {
      owner.job = OwnerJob(
          kind: 'move',
          target: Offset(g.dx.clamp(0.8, 13.8), g.dy.clamp(0.15, 1.55)),
          duration: 0);
    }
  }

  void _stopMischief(Cat c) {
    sound.sfx('pop');
    _addFx('fx_no', Iso.offsetToScene(c.pos) - const Offset(0, 80), big: true);
    c.play = max(0, c.play - 10);
    _completeTask(TaskType.stopMischief, catId: c.id, points: 40);
    _showTip('tip_post');
    c.mischiefTarget = null;
    // the cat redirects its claws to the scratching post — as it should!
    _walkTo(c, RoomLayout.post.grid + const Offset(-0.4, 0.3),
        CatState.usingPost);
  }

  // --- task shortcuts (tap on a task card) ---------------------------------------

  /// Grid anchor of the object relevant to a task (for pointer arrows).
  Offset? taskAnchor(TaskItem t) => switch (t.type) {
        TaskType.feed => RoomLayout.bowl.grid,
        TaskType.cleanLitter => RoomLayout.litter.grid,
        TaskType.play => RoomLayout.toys.grid,
        TaskType.openDoor => RoomLayout.door.grid,
        TaskType.closeDoor => RoomLayout.door.grid,
        TaskType.findToy => RoomLayout.sofa.grid,
        TaskType.attention ||
        TaskType.stopMischief =>
          t.catId != null ? cats[t.catId!].pos : null,
      };

  /// True while the play-with-cats chain (pick up wand -> play) runs.
  bool get _playChainRunning =>
      owner.job?.kind == 'playPickup' || owner.job?.kind == 'playSession';

  /// Tapping a task card sends the owner to do the right thing.
  void performTask(TaskItem t) {
    if (status != GameStatus.running || !t.active) return;
    // don't restart the play chain if it is already in progress
    if (t.type == TaskType.play && _playChainRunning) return;
    switch (t.type) {
      case TaskType.feed:
        owner.job =
            OwnerJob(kind: 'feed', target: RoomLayout.bowl.grid, duration: 1.5);
        break;
      case TaskType.cleanLitter:
        owner.job = OwnerJob(
            kind: 'scoop',
            target: RoomLayout.litter.grid + const Offset(-0.6, 0.4),
            duration: 2.2);
        break;
      case TaskType.play:
        owner.job = OwnerJob(
            kind: 'playPickup', target: RoomLayout.toys.grid, duration: 0.8);
        break;
      case TaskType.attention:
        if (t.catId != null) {
          final c = cats[t.catId!];
          owner.job =
              OwnerJob(kind: 'pet', target: c.pos, duration: 1.6, cat: c);
        }
        break;
      case TaskType.stopMischief:
        if (t.catId != null) {
          final c = cats[t.catId!];
          if (c.state == CatState.mischiefWarning ||
              c.state == CatState.mischief) {
            _stopMischief(c);
          }
        }
        break;
      case TaskType.openDoor:
        owner.job = OwnerJob(
            kind: 'openDoor', target: RoomLayout.door.grid, duration: 1.2);
        break;
      case TaskType.closeDoor:
        owner.job = OwnerJob(
            kind: 'closeDoor', target: RoomLayout.door.grid, duration: 1.0);
        break;
      case TaskType.findToy:
        owner.job = OwnerJob(
            kind: 'fetchToy',
            target: RoomLayout.sofa.grid + const Offset(-1.2, 0.5),
            duration: 2.0);
        break;
    }
    sound.sfx('pop');
  }

  // --- helpers ------------------------------------------------------------------

  void _bubble(Cat c, BubbleIcon icon, double seconds) {
    c.bubble = icon;
    c.bubbleUntil = elapsed + seconds;
  }

  void _addFx(String key, Offset pos, {bool big = false}) {
    fx.add(FxText(key, pos, elapsed + 1.8, big: big));
  }

  void _spawnHearts(Offset sceneAt, int n) {
    for (int i = 0; i < n; i++) {
      particles.add(Particle(
          'heart',
          sceneAt + Offset(_rng.nextDouble() * 40 - 20, 0),
          Offset(_rng.nextDouble() * 20 - 10, -35 - _rng.nextDouble() * 25),
          elapsed + 1.2 + _rng.nextDouble() * 0.6));
    }
  }

  void _showTip(String key) {
    tipKey = key;
    tipUntil = elapsed + 6;
  }

  bool get tipVisible => tipKey != null && elapsed < tipUntil;

  void _finish() {
    status = GameStatus.finished;
    if (tasksFailed == 0 && damage == 0) {
      stars = 3;
    } else if (tasksFailed <= 1 && damage <= 2) {
      stars = 2;
    } else if (tasksFailed <= 3 && damage <= 4) {
      stars = 1;
    } else {
      stars = 0;
    }
    if (avgMood < 25 && stars > 1) stars = 1;
    won = stars >= 1;
    sound.sfx(won ? 'success' : 'fail');
  }
}
