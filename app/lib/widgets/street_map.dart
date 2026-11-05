import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/scope.dart';
import '../theme/phosphor.dart';
import '../theme/tokens.dart';

/// One street on the map.
class MapStreet {
  const MapStreet({required this.lat, required this.lng, this.active = true});
  final double lat;
  final double lng;
  final bool active;
}

/// Figma "Shape your development" map: a muted basemap with a teal house
/// pin per street. The basemap comes from the server (Google Static Maps);
/// without a Maps key it is drawn here as a simple street sketch.
class StreetMap extends StatelessWidget {
  const StreetMap({super.key, required this.streets, this.height = 197});
  final List<MapStreet> streets;
  final double height;

  static const _tile = 256.0;
  static const _pad = 28.0;

  static double _x(double lng) => (lng + 180) / 360;
  static double _y(double lat) {
    final s = math.sin(lat * math.pi / 180).clamp(-0.9999, 0.9999);
    return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
  }

  static double _lat(double y) => (2 * math.atan(math.exp((0.5 - y) * 2 * math.pi)) - math.pi / 2) * 180 / math.pi;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = height;
      if (streets.isEmpty) {
        return ClipRRect(borderRadius: BorderRadius.circular(8), child: CustomPaint(size: Size(w, h), painter: _SketchPainter(const [], dark: KColors.palette.brightness == Brightness.dark)));
      }
      // Fit every street in the box (Web Mercator, as the static map uses).
      final xs = streets.map((s) => _x(s.lng)).toList(), ys = streets.map((s) => _y(s.lat)).toList();
      final minX = xs.reduce(math.min), maxX = xs.reduce(math.max), minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
      final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
      var zoom = 17;
      while (zoom > 3) {
        final scale = _tile * math.pow(2, zoom);
        if ((maxX - minX) * scale <= w - _pad * 2 && (maxY - minY) * scale <= h - _pad * 2) break;
        zoom--;
      }
      final scale = _tile * math.pow(2, zoom);
      Offset at(MapStreet s) => Offset(w / 2 + (_x(s.lng) - cx) * scale, h / 2 + (_y(s.lat) - cy) * scale);
      final points = [for (final s in streets) at(s)];
      final api = context.api;
      final url = api.absolute('/maps/static?lat=${_lat(cy).toStringAsFixed(6)}&lng=${(cx * 360 - 180).toStringAsFixed(6)}&zoom=$zoom&w=${w.round().clamp(50, 640)}&h=${h.round().clamp(50, 640)}');
      final sketch = CustomPaint(size: Size(w, h), painter: _SketchPainter(points, dark: KColors.palette.brightness == Brightness.dark));
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(children: [
            Positioned.fill(child: sketch),
            Positioned.fill(
              child: Image.network(
                url,
                headers: {if (api.token != null) 'authorization': 'Bearer ${api.token}'},
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
                frameBuilder: (_, child, frame, _) => frame == null ? const SizedBox.shrink() : child,
              ),
            ),
            for (var i = 0; i < streets.length; i++) Positioned(left: points[i].dx - 17, top: points[i].dy - 17, child: _Pin(active: streets[i].active)),
          ]),
        ),
      );
    });
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x29000000), blurRadius: 4, offset: Offset(0, 1))]),
        child: Container(
          decoration: BoxDecoration(shape: BoxShape.circle, color: active ? const Color(0xFF008080) : const Color(0xFFA6A6A6)),
          child: const Icon(PhosphorIconsFill.houseLine, size: 15, color: Colors.white),
        ),
      );
}

/// Light-grey blocks with white roads from your street to each other street.
class _SketchPainter extends CustomPainter {
  _SketchPainter(this.points, {required this.dark});
  final List<Offset> points;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = dark ? const Color(0xFF242424) : const Color(0xFFEDEDED));
    final block = Paint()..color = dark ? const Color(0xFF2E2E2E) : const Color(0xFFE2E2E2);
    final rnd = math.Random(7);
    for (var i = 0; i < 14; i++) {
      final r = Rect.fromLTWH(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height, 30 + rnd.nextDouble() * 60, 20 + rnd.nextDouble() * 40);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), block);
    }
    if (points.isEmpty) return;
    final edge = Paint()
      ..color = dark ? const Color(0xFF3A3A3A) : const Color(0xFFD6D6D6)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final road = Paint()
      ..color = dark ? const Color(0xFF4B4B4B) : Colors.white
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    for (final p in points.skip(1)) {
      canvas.drawLine(points.first, p, edge);
    }
    for (final p in points.skip(1)) {
      canvas.drawLine(points.first, p, road);
    }
  }

  @override
  bool shouldRepaint(_SketchPainter old) => old.points != points || old.dark != dark;
}
