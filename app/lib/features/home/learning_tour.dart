import 'package:flutter/material.dart';
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
  const TourStep(this.title, this.body, this.target);
  final String title;
  final String body;
  final GlobalKey Function(TourKeys k) target;
}

/// LRN-02: eight steps. Copy for steps 2, 3, 4 drops later-phase items
/// (News, scheduled posts, projects/resources/budgets) and needs design sign-off.
final kTourSteps = <TourStep>[
  TourStep('Share what\'s on your mind', 'Tap the icon to post on the feed — anyone in your community can join in.', (k) => k.compose),
  TourStep('Feed and Updates', 'See what neighbours are sharing in the Feed, and official news from your committee in Updates.', (k) => k.tabs),
  TourStep('Your Calendar', 'Track upcoming events and community moments in one place.', (k) => k.calendar),
  TourStep('Your Community', 'Meet your committee board, apply for a role and take part in community proposals.', (k) => k.community),
  TourStep('Clubs', 'Clubs are where shared interests come alive. Join an existing group, create your own, or use a template to get started in minutes.', (k) => k.clubs),
  TourStep('Services', 'Your shortcut to reliable services. Explore recommended vendors, read community reviews, and book what you need without the hassle.', (k) => k.services),
  TourStep('Events', "Your go-to for what's happening nearby. Browse community events, track the ones you've joined, or create something new.", (k) => k.events),
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

  @override
  Widget build(BuildContext context) {
    final step = kTourSteps[_i];
    final rect = _target();
    final size = MediaQuery.sizeOf(context);
    final below = rect == null || rect.center.dy < size.height / 2;
    final last = _i == kTourSteps.length - 1;
    return Material(
      type: MaterialType.transparency,
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _Scrim(rect))),
        Positioned(
          left: 16,
          right: 16,
          top: below ? (rect?.bottom ?? size.height / 3) + 12 : null,
          bottom: below ? null : size.height - rect.top + 12,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: BorderRadius.circular(KRadius.lg)),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Step ${_i + 1} of ${kTourSteps.length}', style: KText.overline),
                const Spacer(),
                TextButton(onPressed: () => widget.onDone('skipped'), child: const Text('Skip')),
              ]),
              Text(step.title, style: KText.headingXSmall),
              const SizedBox(height: 6),
              Text(step.body, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
              const SizedBox(height: 16),
              Row(children: [
                if (_i > 0) OutlinedButton(onPressed: () => setState(() => _i--), style: OutlinedButton.styleFrom(shape: const StadiumBorder()), child: const Text('Back')),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: KColors.surfaceInverted, shape: const StadiumBorder()),
                  onPressed: () => last ? widget.onDone('completed') : setState(() => _i++),
                  child: Text(last ? 'Finish' : 'Next'),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Scrim extends CustomPainter {
  _Scrim(this.hole);
  final Rect? hole;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()..addRect(Offset.zero & size);
    if (hole != null) p.addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(12)));
    p.fillType = PathFillType.evenOdd;
    canvas.drawPath(p, Paint()..color = KColors.scrim);
  }

  @override
  bool shouldRepaint(_Scrim old) => old.hole != hole;
}
