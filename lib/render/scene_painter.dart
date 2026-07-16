import 'dart:math';

import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../game/game_controller.dart';
import '../game/models.dart';
import 'iso.dart';

/// Soft pastel comic renderer, 2D side view: the room is one big comic
/// panel seen from the side. Warm cream palette, thin brown outlines,
/// cats with big glossy eyes and blush.
class ScenePainter extends CustomPainter {
  ScenePainter(this.game, this.t) : super(repaint: game);

  final GameController game;
  final double t; // continuous animation time (seconds)

  // ------------------------------------------------------------- palette
  static const ink = Color(0xFF6B5138);
  static const page = Color(0xFFF5E9D3);
  static const catBase = Color(0xFFFDF8F0);
  static const blushC = Color(0x59F2A0A0);
  static const innerEar = Color(0xFFF2C4C4);

  static final Paint _ink = Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  Paint _fill(Color c) => Paint()..color = c;

  Path _poly(List<Offset> pts) {
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final pt in pts.skip(1)) {
      p.lineTo(pt.dx, pt.dy);
    }
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, _fill(page));
    _drawWall(canvas);
    _drawFloor(canvas);

    // ---- z-sorted entities (sorted by depth = distance to viewer) ----------
    final entities = <(double, void Function())>[
      (0.30, () => _drawLamp(canvas)),
      (Iso.depth(RoomLayout.sofa.grid), () => _drawSofa(canvas)),
      (Iso.depth(RoomLayout.table.grid), () => _drawTable(canvas)),
      (Iso.depth(RoomLayout.post.grid), () => _drawPost(canvas)),
      (Iso.depth(RoomLayout.toys.grid), () => _drawToys(canvas)),
      (Iso.depth(RoomLayout.bowl.grid), () => _drawBowls(canvas)),
      (Iso.depth(RoomLayout.litter.grid), () => _drawLitter(canvas)),
      for (final item in game.fallenItems)
        (Iso.depth(item.pos), () => _drawFallenItem(canvas, item)),
      for (final c in game.cats) (_catDepth(c), () => _drawCat(canvas, c)),
      if (game.boxPresent)
        (Iso.depth(RoomLayout.boxSpot.grid) + 0.01, () => _drawBox(canvas)),
      (_actorDepth(game.owner.pos, 0.03), () => _drawOwner(canvas)),
    ];
    entities.sort((a, b) => a.$1.compareTo(b.$1));
    for (final e in entities) {
      e.$2();
    }

    if (game.flyActive) _drawFly(canvas);
    _drawDayTint(canvas, size);

    // comic panel frame
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(5, 5, size.width - 10, size.height - 10),
            const Radius.circular(20)),
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);

    for (final c in game.cats) {
      _drawBubble(canvas, c);
    }
    for (final f in game.fx) {
      _drawFx(canvas, f);
    }
    _drawParticles(canvas);

    // pointer arrows above objects relevant to active tasks
    for (final task in game.activeTasks) {
      final anchor = game.taskAnchor(task);
      if (anchor == null) continue;
      _drawMarker(canvas, Iso.offsetToScene(anchor),
          urgent: task.type == TaskType.stopMischief);
    }

    // tap feedback: expanding ring where the owner is heading
    if (game.tapMark != null && game.elapsed < game.tapMarkUntil) {
      final k =
          (1 - (game.tapMarkUntil - game.elapsed) / 0.6).clamp(0.0, 1.0);
      canvas.drawOval(
          Rect.fromCenter(
              center: game.tapMark!,
              width: 26 + k * 44,
              height: 12 + k * 20),
          Paint()
            ..color = const Color(0xFF8FB573).withOpacity((1 - k) * 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5);
    }
  }

  /// Actors standing on / inside a furniture footprint draw just in
  /// front of that furniture but still behind anyone closer to the
  /// viewer (fixes cats vanishing behind the sofa and overlapping the
  /// owner while perched).
  double _actorDepth(Offset pos, double bias) {
    for (final r in GameController.solids) {
      if (r.contains(pos)) return r.bottom + bias;
    }
    return Iso.depth(pos);
  }

  double _catDepth(Cat c) {
    if (c.state == CatState.inBox) return Iso.depth(c.pos) - 0.02;
    return _actorDepth(c.pos, 0.02);
  }

  // ------------------------------------------------------------- markers

  void _drawMarker(Canvas canvas, Offset at, {bool urgent = false}) {
    final color =
        urgent ? const Color(0xFFD97B6C) : const Color(0xFFE8A45C);
    final pulse = 0.8 + sin(t * 5) * 0.2;
    canvas.drawOval(
        Rect.fromCenter(center: at, width: 96 * pulse, height: 34 * pulse),
        Paint()
          ..color = color.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5);
    final tip = at - Offset(0, 128 + sin(t * 5) * 8);
    final arrow = _poly([
      tip,
      tip + const Offset(-14, -20),
      tip + const Offset(-6, -20),
      tip + const Offset(-6, -38),
      tip + const Offset(6, -38),
      tip + const Offset(6, -20),
      tip + const Offset(14, -20),
    ]);
    canvas.drawPath(arrow, _fill(color));
    canvas.drawPath(arrow, _ink);
  }

  // ------------------------------------------------------------- room

  Color get _skyColor {
    if (game.stormActive) return const Color(0xFF8A93A8);
    return switch (game.phase) {
      GamePhase.morning => const Color(0xFFFFE8C4),
      GamePhase.day => const Color(0xFFC8E4F0),
      GamePhase.evening => const Color(0xFFF5C89E),
      GamePhase.night => const Color(0xFF6B7BA8),
    };
  }

  void _drawWall(Canvas canvas) {
    // back wall
    final wall = Rect.fromLTRB(0, Iso.wallTop, Iso.sceneW, Iso.floorY);
    canvas.drawRect(wall, _fill(const Color(0xFFF2E4C4)));
    // gentle wallpaper dots
    final dot = _fill(const Color(0x1A8B6F52));
    int row = 0;
    for (double y = Iso.wallTop + 24; y < Iso.floorY - 24; y += 52) {
      final shift = row.isEven ? 0.0 : 28.0;
      for (double x = 30 + shift; x < Iso.sceneW; x += 56) {
        canvas.drawCircle(Offset(x, y), 5, dot);
      }
      row++;
    }
    // ceiling line
    canvas.drawLine(Offset(0, Iso.wallTop), Offset(Iso.sceneW, Iso.wallTop),
        Paint()
          ..color = ink
          ..strokeWidth = 3);
    // skirting board
    final skirt = Rect.fromLTRB(0, Iso.floorY - 12, Iso.sceneW, Iso.floorY);
    canvas.drawRect(skirt, _fill(const Color(0xFFE2D3AE)));
    canvas.drawLine(Offset(0, Iso.floorY - 12),
        Offset(Iso.sceneW, Iso.floorY - 12),
        Paint()
          ..color = ink
          ..strokeWidth = 2);

    _drawWindow(canvas);
    _drawDoor(canvas);
    _drawWallDecor(canvas);
    _drawWallScratches(canvas);
  }

  void _drawWindow(Canvas canvas) {
    final win = Rect.fromLTRB(104, 150, 268, 330);
    canvas.drawRect(win, _fill(_skyColor));

    // sun / moon
    if (!game.stormActive) {
      final mid = win.center;
      if (game.phase == GamePhase.night) {
        canvas.drawCircle(mid + const Offset(28, -40), 14,
            _fill(const Color(0xFFF7F2DC)));
        canvas.drawCircle(mid + const Offset(34, -43), 11, _fill(_skyColor));
      } else {
        canvas.drawCircle(mid + const Offset(30, -42), 14,
            _fill(const Color(0xFFF7DC94)));
      }
    }

    // birds
    if (game.birdsActive && !game.stormActive) {
      final flap = sin(t * 10) * 4;
      final bp = Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 3; i++) {
        final base = win.center +
            Offset(-40.0 + i * 34 + sin(t * 1.3 + i) * 12,
                -10.0 + i * 22 + cos(t * 1.7 + i) * 8);
        canvas.drawLine(base, base + Offset(-9, -5 - flap), bp);
        canvas.drawLine(base, base + Offset(9, -5 + flap), bp);
      }
    }

    // storm: rain + lightning
    if (game.stormActive) {
      final rain = Paint()
        ..color = const Color(0xAAC9DEF0)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 22; i++) {
        final rx = win.left + 6 + (i * 37 + t * 160) % (win.width - 12);
        final ry = win.top + 6 + ((i * 53 + t * 260) % (win.height - 24));
        canvas.drawLine(Offset(rx, ry), Offset(rx - 4, ry + 14), rain);
      }
      final phase = (game.elapsed - game.stormStart) % 7;
      if (phase < 0.35) {
        canvas.drawRect(win, _fill(const Color(0x8CFFFFFF)));
        final bolt = _poly([
          win.center + const Offset(-8, -70),
          win.center + const Offset(6, -22),
          win.center + const Offset(-4, -22),
          win.center + const Offset(12, 40),
          win.center + const Offset(-2, -6),
          win.center + const Offset(8, -6),
        ]);
        canvas.drawPath(bolt, _fill(const Color(0xFFF7DC94)));
        canvas.drawPath(bolt, _ink..strokeWidth = 1.8);
        _ink.strokeWidth = 2.5;
      }
    }

    // frame + cross bars
    canvas.drawRect(win, _ink..strokeWidth = 3.5);
    _ink.strokeWidth = 2.5;
    canvas.drawLine(Offset(win.center.dx, win.top),
        Offset(win.center.dx, win.bottom), _ink);
    canvas.drawLine(Offset(win.left, win.center.dy),
        Offset(win.right, win.center.dy), _ink);
    // window sill
    final sill = RRect.fromRectAndRadius(
        Rect.fromLTWH(win.left - 12, win.bottom, win.width + 24, 12),
        const Radius.circular(4));
    canvas.drawRRect(sill, _fill(const Color(0xFFE2D3AE)));
    canvas.drawRRect(sill, _ink);
    // flower pot on the sill (until a cat knocks it off…)
    if (game.flowerOnSill) {
      final px = win.left + 26;
      final py = win.bottom;
      final pot = _poly([
        Offset(px - 12, py - 2), Offset(px + 12, py - 2),
        Offset(px + 8, py - 20), Offset(px - 8, py - 20),
      ]);
      canvas.drawPath(pot, _fill(const Color(0xFFD98B6C)));
      canvas.drawPath(pot, _ink..strokeWidth = 1.8);
      _ink.strokeWidth = 2.5;
      canvas.drawLine(Offset(px, py - 20), Offset(px, py - 38),
          Paint()
            ..color = const Color(0xFF8FB573)
            ..strokeWidth = 2.5);
      canvas.drawCircle(Offset(px - 5, py - 36), 4,
          _fill(const Color(0xFF8FB573)));
      canvas.drawCircle(Offset(px, py - 44), 6,
          _fill(const Color(0xFFF2AFC1)));
      canvas.drawCircle(Offset(px, py - 44), 2.5,
          _fill(const Color(0xFFF2CE7E)));
    }
    // curtains — dusty pink, on a rod
    canvas.drawLine(Offset(win.left - 22, win.top - 14),
        Offset(win.right + 22, win.top - 14),
        Paint()
          ..color = ink
          ..strokeWidth = 4);
    for (final side in [-1, 1]) {
      final cx = side < 0 ? win.left - 4 : win.right + 4;
      final cur = Path()
        ..moveTo(cx, win.top - 12)
        ..quadraticBezierTo(cx + side * 26, win.center.dy,
            cx + side * 14, win.bottom + 10)
        ..lineTo(cx + side * 30, win.bottom + 10)
        ..quadraticBezierTo(cx + side * 34, win.center.dy - 30,
            cx + side * 20, win.top - 12)
        ..close();
      canvas.drawPath(cur, _fill(const Color(0xFFE8B4B8)));
      canvas.drawPath(cur, _ink);
    }
  }

  void _drawDoor(Canvas canvas) {
    final door = Rect.fromLTRB(682, 296, 766, Iso.floorY - 12);
    canvas.drawRect(door, _fill(const Color(0xFFBE9060)));
    canvas.drawRect(door.deflate(10),
        _ink..strokeWidth = 1.8);
    canvas.drawRect(
        Rect.fromLTRB(door.left + 16, door.top + 60, door.right - 16,
            door.bottom - 16),
        _ink);
    _ink.strokeWidth = 2.5;
    canvas.drawCircle(Offset(door.left + 12, door.center.dy + 10), 4.5,
        _fill(const Color(0xFFF2CE7E)));
    canvas.drawRect(door, _ink..strokeWidth = 3);
    _ink.strokeWidth = 2.5;
    // doormat
    final mat = Rect.fromCenter(
        center: Offset(door.center.dx, Iso.floorY + 26), width: 96, height: 22);
    canvas.drawOval(mat, _fill(const Color(0xFFC4A272)));
    canvas.drawOval(mat, _ink..strokeWidth = 1.8);
    _ink.strokeWidth = 2.5;
  }

  void _drawWallDecor(Canvas canvas) {
    // a small framed cat portrait between sofa and door
    final frame = Rect.fromCenter(
        center: const Offset(560, 210), width: 70, height: 84);
    canvas.drawRect(frame, _fill(const Color(0xFFFFFDF5)));
    canvas.drawRect(frame, _ink..strokeWidth = 4);
    _ink.strokeWidth = 2.5;
    // tiny cat silhouette
    final cx = frame.center;
    canvas.drawCircle(cx + const Offset(0, 8), 14,
        _fill(const Color(0xFFB8B2C9)));
    canvas.drawCircle(cx + const Offset(0, -12), 10,
        _fill(const Color(0xFFB8B2C9)));
    canvas.drawPath(
        _poly([
          cx + const Offset(-9, -18),
          cx + const Offset(-11, -28),
          cx + const Offset(-3, -21),
        ]),
        _fill(const Color(0xFFB8B2C9)));
    canvas.drawPath(
        _poly([
          cx + const Offset(9, -18),
          cx + const Offset(11, -28),
          cx + const Offset(3, -21),
        ]),
        _fill(const Color(0xFFB8B2C9)));
  }

  void _drawWallScratches(Canvas canvas) {
    if (game.wallScratch <= 0) return;
    final base = Iso.toScene(RoomLayout.wallpaper.dx, 0) -
        const Offset(0, 0); // wall point
    final p = Paint()
      ..color = const Color(0xFFFFFDF5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < game.wallScratch * 3; i++) {
      final a = Offset(base.dx - 26 + (i % 3) * 20,
          Iso.floorY - 96.0 + (i ~/ 3) * 10);
      canvas.drawLine(a, a + const Offset(6, 38), p);
    }
  }

  void _drawFloor(Canvas canvas) {
    final floor =
        Rect.fromLTRB(0, Iso.floorY, Iso.sceneW, Iso.sceneH);
    canvas.drawRect(floor, _fill(const Color(0xFFE3C495)));
    // planks
    final line = Paint()
      ..color = const Color(0x40A6835A)
      ..strokeWidth = 1.5;
    for (double y = Iso.floorY + 34; y < Iso.sceneH; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(Iso.sceneW, y), line);
    }
    for (int row = 0; row < 6; row++) {
      final y0 = Iso.floorY + row * 34.0;
      for (double x = (row.isEven ? 60 : 160);
          x < Iso.sceneW;
          x += 200) {
        canvas.drawLine(Offset(x, y0), Offset(x, min(y0 + 34, Iso.sceneH)),
            line);
      }
    }
    canvas.drawLine(Offset(0, Iso.floorY), Offset(Iso.sceneW, Iso.floorY),
        Paint()
          ..color = ink
          ..strokeWidth = 3);
    // rug — dusty rose
    final rugC = Iso.offsetToScene(RoomLayout.rug.grid);
    final rug = Rect.fromCenter(center: rugC, width: 230, height: 62);
    canvas.drawOval(rug, _fill(const Color(0xFFE8C4C4)));
    canvas.drawOval(rug.deflate(12), _fill(const Color(0xFFF5DEDE)));
    canvas.drawOval(rug, _ink);
  }

  void _drawDayTint(Canvas canvas, Size size) {
    Color tint = switch (game.phase) {
      GamePhase.morning => const Color(0x14F7DC94),
      GamePhase.day => const Color(0x00000000),
      GamePhase.evening => const Color(0x26E8A45C),
      GamePhase.night => const Color(0x4D4A4468),
    };
    if (game.stormActive && game.phase != GamePhase.night) {
      tint = const Color(0x2E5A637E); // gloomy storm light
    }
    if (tint.alpha != 0) {
      canvas.drawRect(Offset.zero & size, _fill(tint));
    }
    if (game.phase == GamePhase.night && !game.lampFallen) {
      final lampTop = Iso.toScene(14.0, 0.3) - const Offset(0, 120);
      final glow = Paint()
        ..shader = RadialGradient(colors: [
          const Color(0x66F7DC94),
          const Color(0x00F7DC94),
        ]).createShader(Rect.fromCircle(center: lampTop, radius: 200));
      canvas.drawCircle(lampTop, 200, glow);
    }
  }

  // ------------------------------------------------------------- furniture

  void _drawSofa(Canvas canvas) {
    final c = Iso.offsetToScene(RoomLayout.sofa.grid);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    final body = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-95, -66, 190, 66), const Radius.circular(18));
    final back = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-95, -108, 190, 56), const Radius.circular(18));
    canvas.drawRRect(back, _fill(const Color(0xFFB9A3D8)));
    canvas.drawRRect(back, _ink);
    canvas.drawRRect(body, _fill(const Color(0xFFC9B6E4)));
    canvas.drawRRect(body, _ink);
    for (int i = 0; i < 2; i++) {
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(-88 + i * 92.0, -62, 84, 40),
          const Radius.circular(14));
      canvas.drawRRect(r, _fill(const Color(0xFFDCCCEF)));
      canvas.drawRRect(r, _ink..strokeWidth = 1.8);
      _ink.strokeWidth = 2.5;
    }
    for (final dx in [-95.0, 61.0]) {
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(dx, -84, 34, 84), const Radius.circular(16));
      canvas.drawRRect(r, _fill(const Color(0xFFB9A3D8)));
      canvas.drawRRect(r, _ink);
    }
    // little feet
    for (final dx in [-84.0, 72.0]) {
      canvas.drawRect(Rect.fromLTWH(dx, 0, 12, 8),
          _fill(const Color(0xFF8B6F52)));
    }
    // scratches
    final sp = Paint()
      ..color = const Color(0xFFF7F2E8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < game.sofaScratch * 3; i++) {
      final x = -86.0 + (i % 3) * 9 + (i ~/ 3) * 26;
      canvas.drawLine(Offset(x, -48), Offset(x + 5, -16), sp);
    }
    canvas.restore();
  }

  void _drawTable(Canvas canvas) {
    final c = Iso.offsetToScene(RoomLayout.table.grid);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    // legs
    final leg = _fill(const Color(0xFFA97E4E));
    for (final x in const [-66.0, 56.0]) {
      canvas.drawRect(Rect.fromLTWH(x, -74, 10, 74), leg);
      canvas.drawRect(Rect.fromLTWH(x, -74, 10, 74), _ink..strokeWidth = 1.8);
    }
    _ink.strokeWidth = 2.5;
    // top
    final top = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-82, -86, 164, 14), const Radius.circular(5));
    canvas.drawRRect(top, _fill(const Color(0xFFC89B66)));
    canvas.drawRRect(top, _ink);

    // items on the table
    if (game.tableItems.contains('vase')) {
      _drawVase(canvas, const Offset(-40, -86), broken: false);
    }
    if (game.tableItems.contains('cup')) {
      final cup = RRect.fromRectAndRadius(
          const Rect.fromLTWH(8, -104, 22, 18), const Radius.circular(4));
      canvas.drawRRect(cup, _fill(const Color(0xFFD97B6C)));
      canvas.drawRRect(cup, _ink..strokeWidth = 1.8);
      canvas.drawArc(const Rect.fromLTWH(28, -100, 12, 12), -1.4, 2.8, false,
          _ink);
      _ink.strokeWidth = 2.5;
    }
    if (game.tableItems.contains('book')) {
      final r = const Rect.fromLTWH(42, -96, 36, 10);
      canvas.drawRect(r, _fill(const Color(0xFF8FB573)));
      canvas.drawRect(r, _ink..strokeWidth = 1.8);
      _ink.strokeWidth = 2.5;
    }
    canvas.restore();
  }

  void _drawVase(Canvas canvas, Offset at, {required bool broken}) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (!broken) {
      final vase = Path()
        ..moveTo(-9, 0)
        ..quadraticBezierTo(-16, -14, -7, -26)
        ..lineTo(7, -26)
        ..quadraticBezierTo(16, -14, 9, 0)
        ..close();
      canvas.drawPath(vase, _fill(const Color(0xFF9BB8D9)));
      canvas.drawPath(vase, _ink..strokeWidth = 1.8);
      _ink.strokeWidth = 2.5;
      canvas.drawLine(const Offset(0, -26), const Offset(0, -40),
          Paint()
            ..color = const Color(0xFF8FB573)
            ..strokeWidth = 2.5);
      canvas.drawCircle(const Offset(0, -44), 6, _fill(const Color(0xFFF2AFC1)));
    } else {
      final shard = _fill(const Color(0xFF9BB8D9));
      canvas.drawPath(
          _poly(const [Offset(-14, 0), Offset(-4, -12), Offset(2, 0)]), shard);
      canvas.drawPath(
          _poly(const [Offset(4, 0), Offset(12, -9), Offset(18, 0)]), shard);
      canvas.drawPath(
          _poly(const [Offset(-2, -2), Offset(6, -14), Offset(10, -4)]), shard);
    }
    canvas.restore();
  }

  void _drawPost(Canvas canvas) {
    final c = Iso.offsetToScene(RoomLayout.post.grid);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 66, height: 22),
        _fill(const Color(0xFFA97E4E)));
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 66, height: 22),
        _ink);
    final pole = Rect.fromLTWH(-11, -104, 22, 100);
    canvas.drawRect(pole, _fill(const Color(0xFFE8D4B0)));
    final rope = Paint()
      ..color = const Color(0xFFC4A272)
      ..strokeWidth = 3;
    for (double y = -98; y < -8; y += 9) {
      canvas.drawLine(Offset(-11, y), Offset(11, y + 4), rope);
    }
    canvas.drawRect(pole, _ink);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, -108), width: 58, height: 20),
        _fill(const Color(0xFFA97E4E)));
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, -108), width: 58, height: 20),
        _ink);
    // dangling toy
    canvas.drawLine(const Offset(20, -104), Offset(24, -76 + sin(t * 2) * 4),
        Paint()
          ..color = ink
          ..strokeWidth = 1.6);
    canvas.drawCircle(Offset(24, -72 + sin(t * 2) * 4), 6,
        _fill(const Color(0xFFD97B6C)));
    canvas.restore();
  }

  void _drawToys(Canvas canvas) {
    final c = Iso.offsetToScene(RoomLayout.toys.grid);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    final basket = Path()
      ..moveTo(-34, -36)
      ..lineTo(34, -36)
      ..lineTo(27, 0)
      ..lineTo(-27, 0)
      ..close();
    canvas.drawPath(basket, _fill(const Color(0xFFD9B584)));
    final weave = Paint()
      ..color = const Color(0x668B6F52)
      ..strokeWidth = 2;
    for (double y = -30; y < -2; y += 8) {
      canvas.drawLine(Offset(-31 + (y + 30) * 0.2, y),
          Offset(31 - (y + 30) * 0.2, y), weave);
    }
    canvas.drawPath(basket, _ink);
    canvas.drawCircle(const Offset(-12, -40), 11, _fill(const Color(0xFFD97B6C)));
    canvas.drawCircle(const Offset(-12, -40), 11, _ink..strokeWidth = 1.8);
    _ink.strokeWidth = 2.5;
    canvas.drawLine(const Offset(12, -38), const Offset(30, -68),
        Paint()
          ..color = const Color(0xFFA97E4E)
          ..strokeWidth = 3.5);
    canvas.drawCircle(const Offset(30, -70), 6, _fill(const Color(0xFFF2CE7E)));
    canvas.restore();
  }

  void _drawBowls(Canvas canvas) {
    final c = Iso.offsetToScene(RoomLayout.bowl.grid);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    void bowl(Offset at, Color color, {bool food = false, bool water = false}) {
      final body = _poly([
        at + const Offset(-23, -18),
        at + const Offset(23, -18),
        at + const Offset(17, 0),
        at + const Offset(-17, 0),
      ]);
      canvas.drawPath(body, _fill(color));
      canvas.drawPath(body, _ink);
      if (food) {
        canvas.drawOval(
            Rect.fromCenter(
                center: at - const Offset(0, 19), width: 38, height: 12),
            _fill(const Color(0xFFA97E4E)));
      }
      if (water) {
        canvas.drawOval(
            Rect.fromCenter(
                center: at - const Offset(0, 18), width: 38, height: 10),
            _fill(const Color(0xFFC9DEF0)));
      }
    }

    bowl(const Offset(-30, 0), const Color(0xFFD97B6C),
        food: game.foodInBowl > 0);
    bowl(const Offset(28, 6), const Color(0xFF9BB8D9), water: true);
    canvas.restore();
  }

  void _drawLitter(Canvas canvas) {
    final c = Iso.offsetToScene(RoomLayout.litter.grid);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    final tray = _poly(const [
      Offset(-44, -30), Offset(44, -30), Offset(38, 0), Offset(-38, 0),
    ]);
    canvas.drawPath(tray, _fill(const Color(0xFFA8C9C6)));
    canvas.drawPath(tray, _ink);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, -30), width: 82, height: 14),
        _fill(const Color(0xFFF2EAD4)));
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, -30), width: 82, height: 14),
        _ink..strokeWidth = 1.8);
    _ink.strokeWidth = 2.5;
    if (game.litterDirt > 45) {
      final dirt = _fill(const Color(0xFF8B6F52));
      canvas.drawCircle(const Offset(-16, -30), 4, dirt);
      canvas.drawCircle(const Offset(12, -32), 3.5, dirt);
      if (game.litterDirt > 70) {
        canvas.drawCircle(const Offset(0, -28), 4, dirt);
        final stink = Paint()
          ..color = const Color(0xAAA8B98A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;
        for (int i = -1; i <= 1; i++) {
          final x = i * 14.0;
          final ph = t * 3 + i;
          final path = Path()..moveTo(x, -38);
          path.quadraticBezierTo(x + sin(ph) * 6, -54, x, -66);
          canvas.drawPath(path, stink);
        }
      }
    }
    canvas.restore();
  }

  void _drawLamp(Canvas canvas) {
    final c = Iso.toScene(14.0, 0.3);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (game.lampFallen) canvas.rotate(-1.25); // toppled over
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 46, height: 14),
        _fill(const Color(0xFF8B6F52)));
    canvas.drawLine(const Offset(0, -4), const Offset(0, -106),
        Paint()
          ..color = ink
          ..strokeWidth = 3.5);
    final shade = _poly(const [
      Offset(-27, -106), Offset(27, -106), Offset(17, -140), Offset(-17, -140),
    ]);
    canvas.drawPath(shade,
        _fill(game.phase == GamePhase.night && !game.lampFallen
            ? const Color(0xFFF7DC94)
            : const Color(0xFFF2CE7E)));
    canvas.drawPath(shade, _ink);
    canvas.restore();
  }

  void _drawBox(Canvas canvas) {
    final c = Iso.offsetToScene(RoomLayout.boxSpot.grid);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    final body = Rect.fromCenter(
        center: const Offset(0, -28), width: 92, height: 56);
    canvas.drawRect(body, _fill(const Color(0xFFD9B584)));
    canvas.drawRect(body, _ink);
    // open flaps
    final flapL = _poly(const [
      Offset(-46, -56), Offset(-4, -56), Offset(-22, -84), Offset(-62, -80),
    ]);
    final flapR = _poly(const [
      Offset(46, -56), Offset(4, -56), Offset(22, -84), Offset(62, -80),
    ]);
    canvas.drawPath(flapL, _fill(const Color(0xFFE3C495)));
    canvas.drawPath(flapR, _fill(const Color(0xFFC89B66)));
    canvas.drawPath(flapL, _ink);
    canvas.drawPath(flapR, _ink);
    // "this side up" arrow doodle
    canvas.drawLine(const Offset(-14, -18), const Offset(-14, -38),
        _ink..strokeWidth = 1.8);
    canvas.drawLine(const Offset(-14, -38), const Offset(-20, -30), _ink);
    canvas.drawLine(const Offset(-14, -38), const Offset(-8, -30), _ink);
    _ink.strokeWidth = 2.5;
    canvas.restore();
  }

  void _drawFallenItem(Canvas canvas, FallenItem item) {
    final c = Iso.offsetToScene(item.pos);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    switch (item.kind) {
      case 'vase':
        _drawVase(canvas, Offset.zero, broken: true);
        break;
      case 'cup':
        canvas.save();
        canvas.rotate(1.3);
        final cup = RRect.fromRectAndRadius(
            const Rect.fromLTWH(-11, -16, 22, 16), const Radius.circular(4));
        canvas.drawRRect(cup, _fill(const Color(0xFFD97B6C)));
        canvas.drawRRect(cup, _ink..strokeWidth = 1.8);
        _ink.strokeWidth = 2.5;
        canvas.restore();
        break;
      case 'book':
        final r = Rect.fromCenter(center: const Offset(0, -6),
            width: 38, height: 12);
        canvas.drawRect(r, _fill(const Color(0xFF8FB573)));
        canvas.drawRect(r, _ink..strokeWidth = 1.8);
        _ink.strokeWidth = 2.5;
        break;
      case 'flower':
        // tipped pot, spilled soil and the flower
        canvas.save();
        canvas.rotate(1.2);
        final pot = _poly(const [
          Offset(-11, 0), Offset(11, 0), Offset(8, -18), Offset(-8, -18),
        ]);
        canvas.drawPath(pot, _fill(const Color(0xFFD98B6C)));
        canvas.drawPath(pot, _ink..strokeWidth = 1.8);
        _ink.strokeWidth = 2.5;
        canvas.restore();
        canvas.drawOval(
            Rect.fromCenter(
                center: const Offset(16, -2), width: 34, height: 10),
            _fill(const Color(0xFF8B6F52)));
        canvas.drawLine(const Offset(26, -4), const Offset(38, -12),
            Paint()
              ..color = const Color(0xFF8FB573)
              ..strokeWidth = 2.5);
        canvas.drawCircle(const Offset(40, -14), 5,
            _fill(const Color(0xFFF2AFC1)));
        break;
      case 'puddle':
        // the "accident" next to a dirty litter box
        final puddle = Rect.fromCenter(
            center: const Offset(0, -2), width: 42, height: 14);
        canvas.drawOval(puddle, _fill(const Color(0xAAF2E28A)));
        canvas.drawOval(
            puddle,
            Paint()
              ..color = const Color(0xFFC9B45C)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
        // shine
        canvas.drawOval(
            Rect.fromCenter(
                center: const Offset(-8, -4), width: 10, height: 4),
            _fill(const Color(0x66FFFFFF)));
        break;
    }
    canvas.restore();
  }

  // ------------------------------------------------------------------ fly

  Offset get _flyPos => Offset(
      430 + sin(t * 1.1) * 230,
      330 + sin(t * 2.3) * 70 + cos(t * 3.7) * 30);

  void _drawFly(Canvas canvas) {
    final p = _flyPos;
    // erratic mini-jitter
    final jp = p + Offset(sin(t * 21) * 4, cos(t * 27) * 4);
    canvas.drawOval(Rect.fromCenter(center: jp, width: 9, height: 7),
        _fill(const Color(0xFF4A3628)));
    final wing = _fill(const Color(0x88C9DEF0));
    final flap = sin(t * 40) * 3;
    canvas.drawOval(
        Rect.fromCenter(
            center: jp + Offset(-4, -5 + flap), width: 8, height: 5),
        wing);
    canvas.drawOval(
        Rect.fromCenter(
            center: jp + Offset(4, -5 - flap), width: 8, height: 5),
        wing);
    // buzz trail
    final trail = Paint()
      ..color = const Color(0x338B6F52)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..moveTo(jp.dx - 14, jp.dy + 6);
    path.quadraticBezierTo(jp.dx - 22, jp.dy + 2, jp.dx - 26, jp.dy + 10);
    canvas.drawPath(path, trail);
  }

  // ------------------------------------------------------------------ actors

  void _drawShadow(Canvas canvas, Offset at, double w) {
    canvas.drawOval(
        Rect.fromCenter(
            center: at + const Offset(0, 4), width: w, height: w * 0.22),
        _fill(const Color(0x268B6F52)));
  }

  /// Draws fur patches clipped inside [body].
  void _patches(Canvas canvas, Path body, Color patchC, List<Rect> spots) {
    canvas.save();
    canvas.clipPath(body);
    for (final r in spots) {
      canvas.drawOval(r, _fill(patchC));
    }
    canvas.restore();
  }

  void _drawCat(Canvas canvas, Cat cat) {
    final floorP = Iso.offsetToScene(cat.pos);
    final p = floorP - Offset(0, cat.lift);
    final scale = cat.isKitten ? 0.72 : 1.0;
    final patchC =
        cat.isKitten ? const Color(0xFFF0A868) : const Color(0xFFB8B2C9);
    final darkC =
        cat.isKitten ? const Color(0xFFE0904E) : const Color(0xFFA39CBB);

    if (cat.state == CatState.inBox) {
      canvas.save();
      canvas.translate(p.dx, p.dy - 74 * scale);
      canvas.scale(scale);
      _drawCatHead(canvas, patchC, darkC, cat,
          mouthOpen: false, eyesClosed: false, happy: true);
      canvas.restore();
      return;
    }

    // shadow stays on the floor and shrinks while the cat is up high
    _drawShadow(canvas, floorP, 70 * scale * (1 - cat.lift / 500));

    canvas.save();
    canvas.translate(p.dx, p.dy);
    if (cat.state == CatState.hiding) {
      // constant trembling + a visible flinch right after a thunderclap
      final flinch = (1 - cat.stateT / 0.6).clamp(0.0, 1.0);
      canvas.translate(
          sin(t * 30) * (1.5 + flinch * 4), -flinch * 12);
      canvas.scale(1.0, 0.92); // crouched low
    }
    if (cat.facingLeft) canvas.scale(-1, 1);
    canvas.scale(scale);

    final jumping = cat.state == CatState.jumping;
    final playing = cat.state == CatState.playing;
    // while playing: running toward the toy = run pose,
    // close to the toy = pouncing (rearing up, swiping paws)
    final chasing = playing &&
        cat.target != null &&
        (cat.pos - cat.target!).distance > 0.35;
    final pouncing = playing && !chasing;
    final walking = cat.state == CatState.walking ||
        cat.state == CatState.zoomies ||
        jumping ||
        chasing;
    final sleeping = cat.state == CatState.sleeping;
    final yowl = cat.state == CatState.yowling;
    final mischief = cat.state == CatState.mischief ||
        cat.state == CatState.mischiefWarning ||
        cat.state == CatState.usingPost ||
        pouncing;
    final eating = cat.state == CatState.eating ||
        cat.state == CatState.usingLitter;

    if (cat.state == CatState.zoomies) {
      final sl = Paint()
        ..color = const Color(0x808B6F52)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 3; i++) {
        canvas.drawLine(Offset(-46, -18.0 - i * 10),
            Offset(-76, -18.0 - i * 10), sl);
      }
    }

    if (sleeping) {
      final body = Path()
        ..addOval(Rect.fromCenter(
            center: const Offset(0, -18), width: 74, height: 44));
      canvas.drawPath(body, _fill(catBase));
      _patches(canvas, body, patchC, [
        Rect.fromCenter(center: const Offset(8, -28), width: 46, height: 26),
        Rect.fromCenter(center: const Offset(-22, -16), width: 24, height: 18),
      ]);
      canvas.drawPath(body, _ink);
      final tail = Path()
        ..moveTo(28, -12)
        ..quadraticBezierTo(44, -26, 22, -34);
      canvas.drawPath(
          tail,
          Paint()
            ..color = darkC
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round);
      canvas.save();
      canvas.translate(-16, -30);
      canvas.scale(0.9);
      _drawCatHead(canvas, patchC, darkC, cat,
          mouthOpen: false, eyesClosed: true, happy: false);
      canvas.restore();
      canvas.restore();
      return;
    }

    if (mischief) {
      // little excited hops while pouncing at the toy
      if (pouncing) canvas.translate(0, -(sin(t * 11).abs()) * 9);
      final body = Path()
        ..addOval(Rect.fromCenter(
            center: const Offset(0, -30), width: 40, height: 66));
      canvas.drawPath(body, _fill(catBase));
      _patches(canvas, body, patchC, [
        Rect.fromCenter(center: const Offset(-6, -44), width: 30, height: 34),
      ]);
      canvas.drawPath(body, _ink);
      final ph = sin(t * 14) * 5;
      final paw = _fill(catBase);
      canvas.drawOval(Rect.fromCenter(
              center: Offset(14, -58 + ph), width: 14, height: 22), paw);
      canvas.drawOval(Rect.fromCenter(
              center: Offset(-2, -58 - ph), width: 14, height: 22), paw);
      canvas.save();
      canvas.translate(6, -76);
      canvas.scale(0.95);
      _drawCatHead(canvas, patchC, darkC, cat,
          mouthOpen: false, eyesClosed: false, happy: true);
      canvas.restore();
      canvas.restore();
      return;
    }

    // ---- standard sitting / walking body ----
    final tailWag = sin(t * (yowl ? 12 : 3) + cat.id) * (yowl ? 14 : 8);
    final tail = Path()
      ..moveTo(-26, -16)
      ..quadraticBezierTo(-52, -30 + tailWag, -44, -58 + tailWag);
    canvas.drawPath(
        tail,
        Paint()
          ..color = darkC
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round);

    if (walking) {
      if (jumping) {
        // aerial pose: body tilts up while rising, down while landing
        final k = (cat.stateT / 0.38).clamp(0.0, 1.0);
        final rising = cat.perchLift >= cat.jumpFromLift;
        canvas.rotate((k < 0.55 ? -0.22 : 0.1) * (rising ? 1 : -0.6));
      }
      // legs: splayed in flight, trotting on the ground
      final legPh = jumping ? 8.0 : sin(t * 10) * 6;
      final leg = _fill(catBase);
      for (int i = 0; i < 4; i++) {
        final x = -20.0 + i * 13;
        final dy = jumping
            ? (i < 2 ? 5.0 : -6.0) // front paws forward, hind legs back
            : (i % 2 == 0 ? legPh : -legPh);
        canvas.drawRect(Rect.fromLTWH(x, -12 + dy * 0.4, 9, 14), leg);
      }
      final body = Path()
        ..addOval(Rect.fromCenter(
            center: const Offset(0, -26), width: 70, height: 40));
      canvas.drawPath(body, _fill(catBase));
      _patches(canvas, body, patchC, [
        Rect.fromCenter(center: const Offset(-4, -36), width: 52, height: 26),
        Rect.fromCenter(center: const Offset(24, -22), width: 20, height: 16),
      ]);
      canvas.drawPath(body, _ink);
      canvas.save();
      canvas.translate(26, -40 + (eating ? 14 : 0));
      _drawCatHead(canvas, patchC, darkC, cat,
          mouthOpen: yowl, eyesClosed: false, happy: false);
      canvas.restore();
    } else {
      final body = Path()
        ..moveTo(-24, -4)
        ..quadraticBezierTo(-30, -44, 0, -50)
        ..quadraticBezierTo(30, -44, 24, -4)
        ..close();
      canvas.drawPath(body, _fill(catBase));
      _patches(canvas, body, patchC, [
        Rect.fromCenter(center: const Offset(-12, -36), width: 34, height: 30),
        Rect.fromCenter(center: const Offset(18, -14), width: 22, height: 20),
      ]);
      canvas.drawPath(body, _ink);
      canvas.drawOval(Rect.fromCenter(
              center: const Offset(-8, -6), width: 14, height: 12),
          _fill(catBase));
      canvas.drawOval(Rect.fromCenter(
              center: const Offset(8, -6), width: 14, height: 12),
          _fill(catBase));
      canvas.drawOval(
          Rect.fromCenter(center: const Offset(-8, -6), width: 14, height: 12),
          _ink..strokeWidth = 1.6);
      canvas.drawOval(
          Rect.fromCenter(center: const Offset(8, -6), width: 14, height: 12),
          _ink);
      _ink.strokeWidth = 2.5;
      final headDown = eating ? 18.0 : 0.0;
      final happy = cat.state == CatState.petted ||
          cat.state == CatState.playing;
      canvas.save();
      canvas.translate(0, -62 + headDown);
      _drawCatHead(canvas, patchC, darkC, cat,
          mouthOpen: yowl,
          eyesClosed: cat.state == CatState.petted || eating,
          happy: happy,
          scared: cat.state == CatState.hiding);
      canvas.restore();
      if (yowl) {
        final mark = Paint()
          ..color = const Color(0xFFD97B6C)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        for (int i = 0; i < 3; i++) {
          final a = -0.6 + i * 0.6;
          final from = Offset(cos(a) * 44, -74 + sin(a) * 20);
          canvas.drawLine(
              from, from + Offset(cos(a) * 10, sin(a) * 10 - 6), mark);
        }
      }
    }
    canvas.restore();
  }

  void _drawCatHead(Canvas canvas, Color patchC, Color darkC, Cat cat,
      {required bool mouthOpen,
      required bool eyesClosed,
      required bool happy,
      bool scared = false}) {
    // frightened cats flatten their ears back
    if (scared) {
      canvas.save();
      canvas.translate(0, 5);
      canvas.scale(1.06, 0.62);
    }
    final earL = Path()
      ..moveTo(-20, -10)
      ..quadraticBezierTo(-30, -30, -21, -33)
      ..quadraticBezierTo(-12, -31, -5, -21)
      ..close();
    final earR = Path()
      ..moveTo(20, -10)
      ..quadraticBezierTo(30, -30, 21, -33)
      ..quadraticBezierTo(12, -31, 5, -21)
      ..close();
    canvas.drawPath(earL, _fill(patchC));
    canvas.drawPath(earR, _fill(catBase));
    canvas.drawPath(earL, _ink);
    canvas.drawPath(earR, _ink);
    canvas.drawPath(
        _poly(const [Offset(-17, -15), Offset(-21, -27), Offset(-10, -20)]),
        _fill(innerEar));
    canvas.drawPath(
        _poly(const [Offset(17, -15), Offset(21, -27), Offset(10, -20)]),
        _fill(innerEar));
    if (scared) canvas.restore(); // end of flattened-ears transform
    final head = Path()
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: 24));
    canvas.drawPath(head, _fill(catBase));
    canvas.save();
    canvas.clipPath(head);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(-13, -14), width: 34, height: 30),
        _fill(patchC));
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(16, -20), width: 18, height: 16),
        _fill(patchC));
    canvas.restore();
    canvas.drawPath(head, _ink);

    if (scared) {
      // wide frightened eyes: whites showing, tiny pupils
      canvas.drawCircle(const Offset(-9, -3), 8.5, _fill(Colors.white));
      canvas.drawCircle(const Offset(9, -3), 8.5, _fill(Colors.white));
      canvas.drawCircle(
          const Offset(-9, -3), 8.5, _ink..strokeWidth = 1.6);
      canvas.drawCircle(const Offset(9, -3), 8.5, _ink);
      _ink.strokeWidth = 2.5;
      canvas.drawCircle(
          const Offset(-8, -1), 2.6, _fill(const Color(0xFF4A3628)));
      canvas.drawCircle(
          const Offset(10, -1), 2.6, _fill(const Color(0xFF4A3628)));
    } else if (eyesClosed || happy) {
      final ep = Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
          Rect.fromCenter(center: const Offset(-9, -3), width: 13, height: 11),
          happy ? 3.4 : 0.2, 2.6, false, ep);
      canvas.drawArc(
          Rect.fromCenter(center: const Offset(9, -3), width: 13, height: 11),
          happy ? 3.4 : 0.2, 2.6, false, ep);
    } else {
      final r = cat.isKitten ? 8.0 : 7.0;
      final eye = _fill(const Color(0xFF4A3628));
      canvas.drawCircle(const Offset(-9, -3), r, eye);
      canvas.drawCircle(const Offset(9, -3), r, eye);
      canvas.drawCircle(const Offset(-6.8, -5.4), 2.4, _fill(Colors.white));
      canvas.drawCircle(const Offset(11.2, -5.4), 2.4, _fill(Colors.white));
      canvas.drawCircle(const Offset(-11, -0.4), 1.2, _fill(Colors.white70));
      canvas.drawCircle(const Offset(7, -0.4), 1.2, _fill(Colors.white70));
    }
    if (!scared) {
      // rosy cheeks only when the cat is calm
      canvas.drawOval(
          Rect.fromCenter(center: const Offset(-16, 6), width: 10, height: 6),
          _fill(blushC));
      canvas.drawOval(
          Rect.fromCenter(center: const Offset(16, 6), width: 10, height: 6),
          _fill(blushC));
    }
    canvas.drawPath(
        _poly(const [Offset(-3, 5), Offset(3, 5), Offset(0, 9)]),
        _fill(const Color(0xFFE89A9A)));
    if (mouthOpen) {
      canvas.drawOval(Rect.fromCenter(
              center: const Offset(0, 15), width: 14, height: 12),
          _fill(const Color(0xFFCC7A73)));
      canvas.drawOval(
          Rect.fromCenter(center: const Offset(0, 15), width: 14, height: 12),
          _ink..strokeWidth = 1.8);
      _ink.strokeWidth = 2.5;
    } else if (scared) {
      // small anxious frown + a sweat drop
      final mp = Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
          Rect.fromCenter(center: const Offset(0, 17), width: 11, height: 7),
          3.34, 2.6, false, mp);
      canvas.drawCircle(
          const Offset(24, -18), 4, _fill(const Color(0xFFC9DEF0)));
      canvas.drawPath(
          _poly(const [Offset(21, -20), Offset(24, -27), Offset(27, -20)]),
          _fill(const Color(0xFFC9DEF0)));
    } else {
      final mp = Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
          Rect.fromCenter(center: const Offset(-4, 11), width: 8, height: 6),
          0.2, 2.6, false, mp);
      canvas.drawArc(
          Rect.fromCenter(center: const Offset(4, 11), width: 8, height: 6),
          0.2, 2.6, false, mp);
    }
    final wp = Paint()
      ..color = const Color(0x998B7355)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    for (int i = -1; i <= 1; i++) {
      canvas.drawLine(
          Offset(-14, 6.0 + i * 4), Offset(-32, 4.0 + i * 6), wp);
      canvas.drawLine(Offset(14, 6.0 + i * 4), Offset(32, 4.0 + i * 6), wp);
    }
  }

  void _drawOwner(Canvas canvas) {
    final o = game.owner;
    final p = Iso.offsetToScene(o.pos);
    _drawShadow(canvas, p, 56);
    canvas.save();
    canvas.translate(p.dx, p.dy);
    if (o.facingLeft) canvas.scale(-1, 1);

    final walking = o.state == OwnerState.walking;
    final acting = o.state == OwnerState.acting;
    final jobKind = o.job?.kind ?? '';
    // gentle gait: slow leg swing + tiny body bob
    final legPh = walking ? sin(t * 7) * 8 : 0.0;
    final bob = walking ? -(sin(t * 14).abs()) * 1.6 : 0.0;
    canvas.translate(0, bob);

    // legs
    final legPaint = _fill(const Color(0xFF9BAFC9));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(-13, -34 + legPh * 0.3, 11, 34),
            const Radius.circular(5)),
        legPaint);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(2, -34 - legPh * 0.3, 11, 34),
            const Radius.circular(5)),
        legPaint);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(-13, -34 + legPh * 0.3, 11, 34),
            const Radius.circular(5)),
        _ink..strokeWidth = 1.8);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(2, -34 - legPh * 0.3, 11, 34),
            const Radius.circular(5)),
        _ink);
    _ink.strokeWidth = 2.5;
    // shoes
    canvas.drawOval(Rect.fromCenter(
            center: Offset(-7, -1 + legPh * 0.3), width: 20, height: 10),
        _fill(const Color(0xFF8B6F52)));
    canvas.drawOval(Rect.fromCenter(
            center: Offset(8, -1 - legPh * 0.3), width: 20, height: 10),
        _fill(const Color(0xFF8B6F52)));

    // --- far arm (behind the torso), smooth curved swing -------------------
    final swing = walking ? sin(t * 7) * 5 : 0.0;
    final farHand = Offset(-24 - swing * 0.4, -42 + swing);
    final armFar = Paint()
      ..color = const Color(0xFF93B274)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(-13, -66)
          ..quadraticBezierTo(-24, -58, farHand.dx, farHand.dy),
        armFar);
    canvas.drawCircle(farHand, 5.5, _fill(const Color(0xFFF5D9BC)));

    // torso
    final torso = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-19, -76, 38, 46), const Radius.circular(12));
    canvas.drawRRect(torso, _fill(const Color(0xFFA8C686)));
    canvas.drawRRect(torso, _ink);
    // collar
    canvas.drawLine(const Offset(-8, -76), const Offset(0, -70),
        _ink..strokeWidth = 1.8);
    canvas.drawLine(const Offset(8, -76), const Offset(0, -70), _ink);
    _ink.strokeWidth = 2.5;

    // --- near arm ------------------------------------------------------------
    final armNear = Paint()
      ..color = const Color(0xFFA8C686)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    if (acting) {
      // steady raised arm with a soft bob, holding the right tool
      final hb = sin(t * 6) * 2;
      final hand = Offset(27, -80 + hb);
      canvas.drawPath(
          Path()
            ..moveTo(13, -68)
            ..quadraticBezierTo(26, -74, hand.dx, hand.dy),
          armNear);
      canvas.drawCircle(hand, 6, _fill(const Color(0xFFF5D9BC)));
      _drawTool(canvas, hand, jobKind);
    } else {
      final hand = Offset(24 + swing * 0.4, -42 - swing);
      canvas.drawPath(
          Path()
            ..moveTo(13, -66)
            ..quadraticBezierTo(24, -58, hand.dx, hand.dy),
          armNear);
      canvas.drawCircle(hand, 6, _fill(const Color(0xFFF5D9BC)));
    }

    // head
    canvas.drawCircle(const Offset(0, -94), 19, _fill(const Color(0xFFF5D9BC)));
    canvas.drawCircle(const Offset(0, -94), 19, _ink);
    final hair = Path()
      ..moveTo(-19, -98)
      ..quadraticBezierTo(-14, -120, 6, -114)
      ..quadraticBezierTo(20, -110, 19, -96)
      ..quadraticBezierTo(6, -106, -19, -98)
      ..close();
    canvas.drawPath(hair, _fill(const Color(0xFF8B6F52)));
    canvas.drawPath(hair, _ink..strokeWidth = 1.8);
    _ink.strokeWidth = 2.5;
    canvas.drawCircle(const Offset(-6, -95), 2.2, _fill(ink));
    canvas.drawCircle(const Offset(7, -95), 2.2, _fill(ink));
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(-12, -88), width: 8, height: 5),
        _fill(blushC));
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(13, -88), width: 8, height: 5),
        _fill(blushC));
    final smile = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        Rect.fromCenter(center: const Offset(1, -88), width: 12, height: 8),
        0.3, 2.4, false, smile);
    canvas.restore();
  }

  /// A small tool in the owner's hand, depending on the current action.
  void _drawTool(Canvas canvas, Offset hand, String jobKind) {
    switch (jobKind) {
      case 'feed':
        // red food pouch
        final pouch = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: hand + const Offset(6, -12), width: 16, height: 20),
            const Radius.circular(4));
        canvas.drawRRect(pouch, _fill(const Color(0xFFD97B6C)));
        canvas.drawRRect(pouch, _ink..strokeWidth = 1.8);
        _ink.strokeWidth = 2.5;
        break;
      case 'scoop':
      case 'pickup':
        // litter scoop
        canvas.drawLine(hand, hand + const Offset(10, -16),
            Paint()
              ..color = ink
              ..strokeWidth = 3);
        canvas.drawPath(
            _poly([
              hand + const Offset(6, -24),
              hand + const Offset(20, -20),
              hand + const Offset(16, -10),
              hand + const Offset(8, -14),
            ]),
            _fill(const Color(0xFFA8C9C6)));
        break;
      case 'playPickup':
      case 'playSession':
        // teaser wand, waving side to side with a dangling star
        final sway = sin(t * 5) * 8;
        final tip = hand + Offset(14 + sway, -24);
        canvas.drawLine(hand, tip,
            Paint()
              ..color = const Color(0xFFA97E4E)
              ..strokeWidth = 3);
        // string + star swinging with a lag
        final star = tip + Offset(sin(t * 5 - 0.9) * 7, 14);
        canvas.drawLine(tip, star,
            Paint()
              ..color = ink
              ..strokeWidth = 1.6);
        canvas.drawCircle(star, 6, _fill(const Color(0xFFF2CE7E)));
        canvas.drawCircle(star, 6, _ink..strokeWidth = 1.8);
        _ink.strokeWidth = 2.5;
        break;
      default:
        break;
    }
  }

  // -------------------------------------------------------------- bubbles/fx

  void _drawBubble(Canvas canvas, Cat cat) {
    if (cat.bubble == BubbleIcon.none) return;
    final p = Iso.offsetToScene(cat.pos) -
        Offset(0, cat.lift + (cat.isKitten ? 92 : 112));
    final pulse = cat.bubble == BubbleIcon.exclaim ||
            cat.bubble == BubbleIcon.angry
        ? 1.0 + sin(t * 10) * 0.08
        : 1.0;
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.scale(pulse);

    final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 52, height: 44),
        const Radius.circular(14));
    final tailPath = _poly(const [
      Offset(-6, 20), Offset(6, 20), Offset(0, 34),
    ]);
    canvas.drawPath(tailPath, _fill(const Color(0xFFFFFDF5)));
    canvas.drawRRect(rect, _fill(const Color(0xFFFFFDF5)));
    canvas.drawRRect(rect, _ink);
    canvas.drawPath(tailPath, _ink..strokeWidth = 1.8);
    _ink.strokeWidth = 2.5;

    switch (cat.bubble) {
      case BubbleIcon.food:
        canvas.drawOval(
            Rect.fromCenter(center: const Offset(0, 4), width: 30, height: 14),
            _fill(const Color(0xFFD97B6C)));
        canvas.drawOval(
            Rect.fromCenter(center: const Offset(0, 0), width: 22, height: 10),
            _fill(const Color(0xFFA97E4E)));
        break;
      case BubbleIcon.play:
        canvas.drawCircle(
            const Offset(0, 0), 11, _fill(const Color(0xFFD97B6C)));
        final yarn = Paint()
          ..color = const Color(0xFFFFFDF5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawArc(Rect.fromCircle(center: const Offset(0, 0), radius: 7),
            0, 3, false, yarn);
        canvas.drawArc(Rect.fromCircle(center: const Offset(0, 0), radius: 4),
            2, 3, false, yarn);
        break;
      case BubbleIcon.litter:
        canvas.drawPath(
            _poly(const [
              Offset(-16, 6), Offset(16, 6), Offset(12, -6), Offset(-12, -6),
            ]),
            _fill(const Color(0xFFA8C9C6)));
        break;
      case BubbleIcon.angry:
        _text(canvas, '💢', const Offset(0, 0), 20, center: true);
        break;
      case BubbleIcon.heart:
        _text(canvas, '❤', const Offset(0, 0), 20, center: true,
            color: const Color(0xFFD97B6C));
        break;
      case BubbleIcon.bird:
        final bp = Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(0, 2), const Offset(-9, -4), bp);
        canvas.drawLine(const Offset(0, 2), const Offset(9, -4), bp);
        canvas.drawLine(const Offset(-4, 8), const Offset(-13, 2), bp);
        canvas.drawLine(const Offset(-4, 8), const Offset(5, 2), bp);
        break;
      case BubbleIcon.exclaim:
        _text(canvas, '!', const Offset(0, 0), 26, center: true,
            color: const Color(0xFFD97B6C), bold: true);
        break;
      case BubbleIcon.zzz:
        _text(canvas, 'Z z', const Offset(0, 0), 16, center: true,
            color: const Color(0xFF9BAFC9), bold: true);
        break;
      case BubbleIcon.box:
        canvas.drawRect(Rect.fromCenter(
                center: const Offset(0, 0), width: 22, height: 16),
            _fill(const Color(0xFFD9B584)));
        canvas.drawRect(
            Rect.fromCenter(center: const Offset(0, 0), width: 22, height: 16),
            _ink..strokeWidth = 1.8);
        _ink.strokeWidth = 2.5;
        break;
      case BubbleIcon.none:
        break;
    }
    canvas.restore();
  }

  void _drawParticles(Canvas canvas) {
    for (final p in game.particles) {
      final life = (p.until - game.elapsed).clamp(0.0, 1.5);
      final fade = (life / 1.2).clamp(0.0, 1.0);
      if (p.kind == 'heart') {
        _text(canvas, '❤', p.pos, 13,
            center: true,
            color: const Color(0xFFD97B6C).withOpacity(fade));
      } else {
        canvas.drawCircle(
            p.pos,
            4 + (1 - fade) * 6,
            _fill(const Color(0xFFC4A272)
                .withOpacity(0.4 * fade)));
      }
    }
  }

  void _drawFx(Canvas canvas, FxText f) {
    final text = L10n.t(f.textKey);
    final fade = ((f.until - game.elapsed) / 1.8).clamp(0.0, 1.0);
    final rise = (1 - fade) * 18;
    canvas.save();
    canvas.translate(f.scenePos.dx, f.scenePos.dy - rise);
    canvas.rotate(f.big ? -0.08 : -0.04);

    if (f.big) {
      final burst = Path();
      const spikes = 10;
      final rOut = 30.0 + text.length * 5.5;
      for (int i = 0; i < spikes * 2; i++) {
        final r = i.isEven ? rOut : rOut * 0.62;
        final a = i * pi / spikes;
        final pt = Offset(cos(a) * r * 1.35, sin(a) * r * 0.72);
        if (i == 0) {
          burst.moveTo(pt.dx, pt.dy);
        } else {
          burst.lineTo(pt.dx, pt.dy);
        }
      }
      burst.close();
      canvas.drawPath(
          burst, _fill(const Color(0xFFF2CE7E).withOpacity(fade)));
      canvas.drawPath(
          burst,
          Paint()
            ..color = const Color(0xFFD97B6C).withOpacity(fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
    _text(canvas, text, Offset.zero, f.big ? 24 : 17,
        center: true,
        color: (f.big ? const Color(0xFFA34F42) : const Color(0xFFFFFDF5))
            .withOpacity(fade),
        bold: true,
        stroke: !f.big);
    canvas.restore();
  }

  void _text(Canvas canvas, String s, Offset at, double size,
      {bool center = false,
      Color color = ink,
      bool bold = false,
      bool stroke = false}) {
    if (stroke) {
      final tpS = TextPainter(
        text: TextSpan(
            text: s,
            style: TextStyle(
              fontSize: size,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 4
                ..color = ink,
            )),
        textDirection: TextDirection.ltr,
      )..layout();
      tpS.paint(canvas,
          center ? at - Offset(tpS.width / 2, tpS.height / 2) : at);
    }
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: size,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  @override
  bool shouldRepaint(covariant ScenePainter old) => true;
}
