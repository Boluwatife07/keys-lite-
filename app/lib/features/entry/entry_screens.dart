import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
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
    return Scaffold(
      backgroundColor: KColors.brand,
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              Spacer(),
              KeysLogo(height: 44),
              Spacer(),
              Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text('Unlock your community', style: KText.paragraphMediumSmall),
              ),
            ],
          ),
        ),
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
    // Figma 1300:188993 and siblings. The photos carry the top fade.
    const grey50 = Color(0xFFF3F3F3);
    return Scaffold(
      backgroundColor: const Color(0xFF171717),
      body: Stack(
        children: [
          PageView.builder(
            controller: _page,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => Image.asset(slides[i].image, fit: BoxFit.cover, alignment: Alignment.topCenter, width: double.infinity, height: double.infinity),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      for (var i = 0; i < slides.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(child: Container(height: 3, color: i <= _i ? Colors.white : const Color(0xFF4B4B4B))),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Semantics(
                      button: true,
                      child: InkWell(
                        onTap: _done,
                        borderRadius: BorderRadius.circular(KRadius.pill),
                        child: const SizedBox(
                          height: 36,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Center(widthFactor: 1, child: Text('Skip', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white))),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 257), child: Text(slides[_i].title, style: KText.headingMedium.copyWith(color: grey50))),
                      const SizedBox(height: 7),
                      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 297), child: Text(slides[_i].body, style: KText.paragraphLarge.copyWith(color: grey50))),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
                  child: KeysButton(_i == slides.length - 1 ? 'Done' : 'Next', variant: ButtonVariant.light, onPressed: _next),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ONB-03: resident or vendor. Phase 1 has no language picker (ONB-04.1).
class ChooseAccountScreen extends StatelessWidget {
  const ChooseAccountScreen({super.key});
  @override
  Widget build(BuildContext context) {
    Widget option(String asset, String title, String body, VoidCallback onTap) => Semantics(
      container: true,
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KRadius.md),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: KColors.surfaceDefault,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: KColors.borderDefault),
          ),
          child: Row(
            children: [
              CircleImage(asset, size: 80),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: KText.paragraphMediumLarge),
                      const SizedBox(height: 2),
                      Text(body, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Icon(PhosphorIconsRegular.caretRight, size: 24, color: KColors.textPrimary),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: kPageGradient),
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        // Figma 4479:15581: header row for the language picker (not in Phase 1).
                        const SizedBox(height: 72),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const KeysLogo(height: 48),
                                const SizedBox(height: 48),
                                Text('Unlock your community', style: KText.headingMedium),
                                const SizedBox(height: 8),
                                Text('Choose how you will use the Keys app.', style: KText.paragraphLarge.copyWith(color: KColors.textSecondary)),
                                const SizedBox(height: 28),
                                option('assets/images/choose_resident.png', 'I’m a resident', 'Get closer with your neighbourhood and manage your community.', () => context.go('/auth/email')),
                                const SizedBox(height: 16),
                                option('assets/images/choose_vendor.png', 'I’m a vendor', 'Manage your bookings and connect with the communities you serve.', () => context.push('/vendor')),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
