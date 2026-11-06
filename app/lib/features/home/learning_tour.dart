import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/phosphor.dart';
import '../../theme/tokens.dart';

class TourKeys {
  final compose = GlobalKey(debugLabel: 'compose');
  final tabs = GlobalKey(debugLabel: 'tabs');
  final calendar = GlobalKey(debugLabel: 'calendar');
  final community = GlobalKey(debugLabel: 'community');
  final clubs = GlobalKey(debugLabel: 'clubs');
  final services = GlobalKey(debugLabel: 'services');
  final events = GlobalKey(debugLabel: 'events');
  final profile = GlobalKey(debugLabel: 'profile');
}

class TourStep {
  const TourStep(this.title, this.body, this.target, {this.preview});
  final String title;
  final String body;
  final GlobalKey Function(TourKeys k) target;
  /// Sample card from the Figma tour frame, shown under the copy.
  final String? preview;
}

/// LRN-02: eight steps. Copy for steps 2, 3, 4 drops later-phase items
/// (News, scheduled posts, projects/resources/budgets) and needs design sign-off.
final kTourSteps = <TourStep>[
  TourStep('Share what\'s on your mind', 'Tap the icon to post on the feed — anyone in your community can join in.', (k) => k.compose),
  TourStep('Feed and Updates', 'See what neighbours are sharing in the Feed, and official news from your committee in Updates.', (k) => k.tabs, preview: 'assets/images/tour_feed.png'),
  TourStep('Your Calendar', 'Track upcoming events and community moments in one place.', (k) => k.calendar),
  TourStep('Your Community', 'Meet your committee board, apply for a role and take part in community proposals.', (k) => k.community, preview: 'assets/images/tour_community.png'),
  TourStep('Clubs', 'Clubs are where shared interests come alive. Join an existing group, create your own, or use a template to get started in minutes.', (k) => k.clubs, preview: 'assets/images/tour_clubs.png'),
  TourStep('Services', 'Your shortcut to reliable services. Explore recommended vendors, read community reviews, and book what you need without the hassle.', (k) => k.services, preview: 'assets/images/tour_services.png'),
  TourStep('Events', "Your go-to for what's happening nearby. Browse community events, track the ones you've joined, or create something new.", (k) => k.events, preview: 'assets/images/tour_events.png'),
  TourStep('Your Profile', 'Everything about you, in one place. Your posts, your events, your bookings — all at a glance.', (k) => k.profile),
];

/// LRN-01: guided tour over Home. Next / Back / Skip; ends with [onDone].
class LearningTour extends StatefulWidget {
  const LearningTour({super.key, required this.keys, required this.onDone});
  final TourKeys keys;
  final void Function(String outcome) onDone;
  @override
  State<LearningTour> createState() => _LearningTourState();
}

class _LearningTourState extends State<LearningTour> {
  int _i = 0;

  Rect? _target() {
    final ctx = kTourSteps[_i].target(widget.keys).currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return (box.localToGlobal(Offset.zero) & box.size).inflate(6);
  }

  Widget _button(String label, VoidCallback onTap, {bool primary = false, bool outline = false}) => Semantics(
        button: true,
        child: Material(
          color: primary ? KColors.surfaceInverted : Colors.transparent,
          shape: StadiumBorder(side: outline ? BorderSide(color: KColors.borderStrong) : BorderSide.none),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: SizedBox(
              height: 36,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(widthFactor: 1, child: Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, height: 1, color: primary ? KColors.textInverse : KColors.textPrimary))),
              ),
            ),
          ),
        ),
      );

  // Figma "Onboarding Overlay": 50% scrim, yellow-ringed cut-out, white
  // card (radius 12, 16 padding) with step, title, copy, sample, buttons.
  @override
  Widget build(BuildContext context) {
    final step = kTourSteps[_i];
    final rect = _target();
    final size = MediaQuery.sizeOf(context);
    final below = rect == null || rect.center.dy < size.height / 2;
    final last = _i == kTourSteps.length - 1;
    // Card widths per step from the Figma frames.
    const widths = [320.0, 341.0, 280.0, 342.0, 342.0, 330.0, 280.0, 280.0];
    final width = math.min(widths[_i], size.width - 32);
    return Material(
      type: MaterialType.transparency,
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _Scrim(rect, radius: _i == kTourSteps.length - 1 ? 19 : (_i == 1 ? 8 : 12)))),
        Positioned(
          left: _i == 0 ? null : 26,
          right: _i == 0 ? 20 : null,
          top: below ? (rect?.bottom ?? size.height / 3) + 24 : null,
          bottom: below ? null : size.height - rect.top + 12,
          child: Container(
            width: width,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KColors.surfaceDefault,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 16)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 20,
                child: Row(children: [
                  Text('Step ${_i + 1} of ${kTourSteps.length}', style: KText.paragraphSmall.copyWith(fontWeight: FontWeight.w500, height: 1, color: KColors.textSecondary)),
                  const Spacer(),
                  Semantics(button: true, label: 'Close tour', child: InkResponse(radius: 16, onTap: () => widget.onDone('skipped'), child: Icon(PhosphorIconsRegular.x, size: 20, color: KColors.iconDefault))),
                ]),
              ),
              const SizedBox(height: 8),
              Text(step.title, style: KText.headingXSmall.copyWith(height: 26 / 18, letterSpacing: -0.2)),
              const SizedBox(height: 8),
              Text(step.body, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
              const SizedBox(height: 8),
              if (step.preview != null) ...[
                ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.asset(step.preview!, width: double.infinity, fit: BoxFit.fitWidth)),
                const SizedBox(height: 8),
              ] else
                const SizedBox(height: 4),
              Row(children: [
                _button('Skip', () => widget.onDone('skipped')),
                const Spacer(),
                if (_i > 0) ...[_button('Back', () => setState(() => _i--), outline: true), const SizedBox(width: 8)],
                _button(last ? 'Finish' : 'Next', () => last ? widget.onDone('completed') : setState(() => _i++), primary: true),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Scrim extends CustomPainter {
  _Scrim(this.hole, {this.radius = 12});
  final Rect? hole;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()..addRect(Offset.zero & size);
    final rr = hole == null ? null : RRect.fromRectAndRadius(hole!, Radius.circular(radius));
    if (rr != null) p.addRRect(rr);
    p.fillType = PathFillType.evenOdd;
    canvas.drawPath(p, Paint()..color = const Color(0x80171717));
    if (rr != null) {
      canvas.drawRRect(rr, Paint()
        ..color = const Color(0xFFFFD12A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_Scrim old) => old.hole != hole || old.radius != radius;
}
