import 'dart:ui';

/// 2D side-view projection (the room is seen from the side, like a
/// comic panel). World coordinates: x = 0..14.6 units along the room,
/// y (depth) = 0..1.6 units toward the viewer (a narrow floor band).
/// Kept the class name `Iso` so the rest of the code stays unchanged.
class Iso {
  static const double sceneW = 960;
  static const double sceneH = 640;

  static const double unit = 60; // 1 world unit in px (horizontal)
  static const double depthUnit = 80; // 1 depth unit in px (vertical)
  static const double originX = 40;
  static const double floorY = 462; // where the floor band starts
  static const double wallTop = 90; // top of the back wall

  /// World -> scene coordinates (anchor = feet / object base on the floor).
  static Offset toScene(double x, double d) =>
      Offset(originX + x * unit, floorY + d * depthUnit);

  static Offset offsetToScene(Offset g) => toScene(g.dx, g.dy);

  /// Scene -> world coordinates.
  static Offset toGrid(Offset scene) => Offset(
      (scene.dx - originX) / unit, (scene.dy - floorY) / depthUnit);

  /// Depth for z-sorting: things lower on the screen are drawn later.
  static double depth(Offset g) => g.dy;
}
