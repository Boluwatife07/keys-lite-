import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/flow.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';

/// ONB-01: "Unlock your community" splash, then route.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.hold = const Duration(milliseconds: 1200)});
  final Duration hold;
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final d = context.deps;
    await Future.wait([d.session.restore(), Future.delayed(widget.hold)]);
    if (!mounted) return;
    if (d.session.signedIn) {
      await goToCurrentStep(context);
    } else if (await d.store.carouselSeen()) {
      // ONB-02.3: returning device skips the carousel.
      if (mounted) context.go('/auth/email');
    } else {
      if (mounted) context.go('/intro');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: KColors.brand,
      body: SafeArea(
        child: Column(children: [
          Spacer(),
          KeysLogo(height: 56),
          Spacer(),
          Padding(padding: EdgeInsets.only(bottom: 24), child: Text('Unlock your community', style: KText.paragraphMediumSmall)),
        ]),
      ),
    );
  }
}

class _Slide {
  const _Slide(this.title, this.body, this.image);
  final String title;
  final String body;
  final String image;
}

/// ONB-02: four-slide intro.
class IntroCarousel extends StatefulWidget {
  const IntroCarousel({super.key});
  static const slides = [
    _Slide('Stay informed and never miss a beat', 'Connect with neighbours, exchange news, and keep up with all the latest developments.', 'assets/images/carousel_1.jpg'),
    _Slide('Book services digitally', 'Manage your building services digitally and connect with local small business.', 'assets/images/carousel_2.jpg'),
    _Slide('Join resident committees and clubs', 'Effortlessly organise events, join clubs or support local initiatives.', 'assets/images/carousel_3.jpg'),
    _Slide('Contribute to your neighbourhood', 'Vote on important issues and have your say on local decisions, projects and services.', 'assets/images/carousel_4.jpg'),
  ];
  @override
  State<IntroCarousel> createState() => _IntroCarouselState();
}

class _IntroCarouselState extends State<IntroCarousel> {
  final _page = PageController();
  int _i = 0;

  Future<void> _done() async {
    await context.deps.store.setCarouselSeen();
    if (mounted) context.go('/choose');
  }

  void _next() {
    if (_i == IntroCarousel.slides.length - 1) {
      _done();
    } else {
      _page.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    const slides = IntroCarousel.slides;
    return Scaffold(
      backgroundColor: const Color(0xFF1B1F23),
      body: Stack(children: [
        PageView.builder(
          controller: _page,
          itemCount: slides.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => Stack(fit: StackFit.expand, children: [
            Positioned.fill(top: MediaQuery.sizeOf(context).height * 0.3, child: Image.asset(slides[i].image, fit: BoxFit.cover, alignment: Alignment.topCenter)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.31, 0.5], colors: [Color(0xFF1B1F23), Color(0x001B1F23)]),
              ),
            ),
          ]),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: List.generate(slides.length, (i) => Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(color: i <= _i ? Colors.white : Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                  ))),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _done, child: const Text('Skip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
              ),
              const SizedBox(height: 32),
              Text(slides[_i].title, style: KText.headingMedium.copyWith(color: Colors.white)),
              const SizedBox(height: 12),
              Text(slides[_i].body, style: KText.paragraphLarge.copyWith(color: Colors.white)),
              const Spacer(),
              KeysButton(_i == slides.length - 1 ? 'Done' : 'Next', variant: ButtonVariant.light, onPressed: _next),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// ONB-03: resident or vendor. Phase 1 has no language picker (ONB-04.1).
class ChooseAccountScreen extends StatelessWidget {
  const ChooseAccountScreen({super.key});
  @override
  Widget build(BuildContext context) {
    Widget option(String asset, String title, String body, VoidCallback onTap) => Semantics(
          button: true,
          label: title,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(KRadius.md),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: BorderRadius.circular(KRadius.md), border: Border.all(color: KColors.borderDefault)),
              child: Row(children: [
                CircleImage(asset, size: 80),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: KText.paragraphMediumLarge),
                    const SizedBox(height: 4),
                    Text(body, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: KColors.textSecondary),
              ]),
            ),
          ),
        );
    return KeysScaffold(
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 72),
        const KeysLogo(height: 40),
        const SizedBox(height: 40),
        const Intro(title: 'Unlock your community', body: 'Choose how you will use the Keys app.'),
        const SizedBox(height: 24),
        option('assets/images/choose_resident.png', 'I\'m a resident', 'Get closer with your neighbourhood and manage your community.', () => context.go('/auth/email')),
        const SizedBox(height: 16),
        option('assets/images/choose_vendor.png', 'I\'m a vendor', 'Manage your bookings and connect with the communities you serve.', () => context.push('/vendor')),
      ]),
    );
  }
}

/// ONB-03.2: vendor onboarding is a separate Money lane card.
class VendorEntryScreen extends StatelessWidget {
  const VendorEntryScreen({super.key});
  @override
  Widget build(BuildContext context) => const KeysScaffold(
        header: KeysHeader(),
        body: Intro(title: 'Vendor accounts are coming soon', body: 'Vendor sign-up opens with the Keys services release. For now, Keys is open to residents.'),
      );
}
