import 'dart:ui';

/// ------------------------------------------------------------------ enums

enum GamePhase { morning, day, evening, night }

enum CatState {
  idle,
  walking,
  eating,
  begging, // sits and asks (food / play / attention)
  playing, // play session with the owner
  mischiefWarning, // "!" — can still be stopped
  mischief, // actively damaging
  watchingBirds,
  yowling,
  sleeping,
  inBox,
  zoomies,
  usingLitter,
  usingPost,
  petted,
  hiding, // scared by the thunderstorm
  perched, // sitting up on furniture / the windowsill
  jumping, // ballistic hop up onto / down from a perch
}

enum SpotId { bowl, litter, table, sofa, post, toys, window, door, rug, box }

enum TaskType {
  feed,
  cleanLitter,
  play,
  attention,
  stopMischief,
  openDoor,
  closeDoor,
  findToy,
}

enum BubbleIcon { food, play, litter, angry, heart, bird, exclaim, zzz, box, none }

enum MischiefTarget { sofa, wallpaper, table, flower, lamp, curtain }

/// ------------------------------------------------------------------ world

class Spot {
  const Spot(this.id, this.gx, this.gy, this.radius);
  final SpotId id;
  final double gx, gy, radius;
  Offset get grid => Offset(gx, gy);
}

/// Static room layout (side view: x = 0..14.6 along the room,
/// y = depth 0..1.6 toward the viewer).
class RoomLayout {
  static const bowl = Spot(SpotId.bowl, 1.6, 1.10, 0.8);
  static const window = Spot(SpotId.window, 2.4, 0.50, 1.1); // approach point
  static const toys = Spot(SpotId.toys, 3.4, 1.25, 0.8);
  static const table = Spot(SpotId.table, 5.6, 0.50, 1.2);
  static const boxSpot = Spot(SpotId.box, 6.4, 1.25, 0.8);
  static const rug = Spot(SpotId.rug, 7.2, 1.05, 1.2);
  static const sofa = Spot(SpotId.sofa, 9.0, 0.75, 1.5);
  static const door = Spot(SpotId.door, 11.4, 0.50, 0.9); // approach point
  static const post = Spot(SpotId.post, 12.4, 0.85, 0.7);
  static const litter = Spot(SpotId.litter, 13.5, 1.15, 0.9);
  static const wallpaper = Offset(10.2, 0.35); // mischief point on the wall

  static const List<Spot> all = [
    bowl, litter, table, sofa, post, toys, window, door, rug,
  ];
}

/// ------------------------------------------------------------------ actors

class Cat {
  Cat({
    required this.id,
    required this.nameKey,
    required this.isKitten,
    required this.pos,
  });

  final int id;
  final String nameKey; // 'cat_adult' | 'cat_kitten'
  final bool isKitten;

  Offset pos; // grid coords
  Offset? target;
  CatState state = CatState.idle;
  double stateT = 0; // seconds in current state
  bool facingLeft = false;

  /// Needs, 0 (fine) .. 100 (critical).
  double hunger = 35;
  double play = 30;
  double attention = 20;

  double mood = 80; // 0..100

  BubbleIcon bubble = BubbleIcon.none;
  double bubbleUntil = 0;

  /// Vertical lift in scene px while sitting on furniture/windowsill.
  double lift = 0;
  double perchLift = 0; // target lift of the current perch
  double jumpFromLift = 0; // lift at the moment the jump started
  int curtainSide = 0; // 0 = left curtain, 1 = right (climbing mischief)

  MischiefTarget? mischiefTarget;
  CatState afterWalk = CatState.idle;
  double nextLitterAt = -1; // game time when the cat wants the litter box
  double nextDecisionAt = 0;

  double get worstNeed =>
      [hunger, play, attention].reduce((a, b) => a > b ? a : b);
}

enum OwnerState { idle, walking, acting }

class Owner {
  Offset pos = const Offset(4.5, 5.2);
  OwnerState state = OwnerState.idle;
  bool facingLeft = false;
  OwnerJob? job;
  double actT = 0;
}

class OwnerJob {
  OwnerJob({
    required this.kind,
    required this.target,
    required this.duration,
    this.cat,
    this.item,
  });

  /// kinds: feed, scoop, playPickup, playSession, pet, openDoor,
  ///        fetchToy, pickup, usePost
  final String kind;
  final Offset target; // grid
  final double duration;
  final Cat? cat;
  final FallenItem? item;
}

/// ------------------------------------------------------------------ stuff

class FallenItem {
  FallenItem(this.kind, this.pos, {this.broken = false});
  final String kind; // vase | cup | book
  final Offset pos; // grid
  final bool broken;
}

class TaskItem {
  TaskItem({
    required this.type,
    required this.createdAt,
    required this.deadline,
    this.catId,
  });

  final TaskType type;
  final double createdAt;
  final double deadline; // absolute game time
  final int? catId;
  bool done = false;
  bool failed = false;

  bool get active => !done && !failed;

  String get titleKey => switch (type) {
        TaskType.feed => 'task_feed',
        TaskType.cleanLitter => 'task_litter',
        TaskType.play => 'task_play',
        TaskType.attention => 'task_attention',
        TaskType.stopMischief => 'task_mischief',
        TaskType.openDoor => 'task_door',
        TaskType.closeDoor => 'task_close',
        TaskType.findToy => 'task_toy',
      };
}

/// Comic onomatopoeia floating in the scene ("CRASH!", "MEOW!").
class FxText {
  FxText(this.textKey, this.scenePos, this.until, {this.big = false});
  final String textKey;
  final Offset scenePos; // screen (scene) coords
  final double until; // game time
  final bool big;
}

class ScriptedEvent {
  ScriptedEvent(this.time, this.run);
  final double time;
  final void Function() run;
  bool fired = false;
}

/// Tiny visual particle (hearts when petting, dust while scratching).
class Particle {
  Particle(this.kind, this.pos, this.vel, this.until);
  final String kind; // heart | dust
  Offset pos; // scene coords
  final Offset vel; // px/sec
  final double until; // game time
}
