import 'dart:async';
import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';

// Progress per step, matching the bar in the design.
class P {
  static const address = 0.2; // Figma: 72 of 360
  static const match = 0.5; // Figma: 180 of 360
  static const create = 0.5;
  static const homeType = 0.5;
  static const building = 0.6;
  static const live = 0.65;
  static const profile = 0.75;
  static const verify = 0.85;
  static const invite = 0.95;
}

Future<void> _showMatch(BuildContext context, Map<String, dynamic> r, {bool replace = false}) async {
  final m = MatchResult(Map<String, dynamic>.from(r['match']));
  if (replace) {
    context.pushReplacement('/onboarding/match', extra: m);
  } else {
    context.push('/onboarding/match', extra: m);
  }
}

/// ONB-11 / ONB-12: home address with suggestions, optional community code.
class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key});
  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> with Busy {
  final _address = TextEditingController();
  late final _code = TextEditingController(text: context.session.pendingCommunityCode);
  List<Map<String, dynamic>> _suggestions = [];
  Map<String, dynamic>? _picked;
  String? _addressError;
  String? _codeError;
  Timer? _debounce;
  final _sessionToken = DateTime.now().microsecondsSinceEpoch.toString();

  void _onType(String v) {
    _picked = null;
    _addressError = null;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (v.trim().length < 3) return setState(() => _suggestions = []);
      try {
        final r = await context.api.get('/addresses/autocomplete', query: {'q': v.trim(), 'session': _sessionToken});
        if (mounted) setState(() => _suggestions = List<Map<String, dynamic>>.from(r['suggestions']));
      } catch (_) {}
    });
    setState(() {});
  }

  void _pick(Map<String, dynamic> s) {
    setState(() {
      _picked = s;
      _address.text = '${s['primary']}, ${s['secondary']}';
      _suggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _continue() async {
    if (_picked == null) return setState(() => _addressError = 'Address not found. Please use a valid address.');
    final session = context.session;
    await run(() async {
      final r = await session.api.post('/onboarding/address', {
        'placeId': _picked!['placeId'],
        'sessionToken': _sessionToken,
        if (_code.text.trim().isNotEmpty) 'communityCode': _code.text.trim(),
      });
      session.pendingCommunityCode = null;
      await session.refresh();
      if (mounted) await _showMatch(context, r);
    }, onError: (e) {
      if (e is! ApiException) return;
      setState(() {
        if (e.code == 'INVALID_COMMUNITY_CODE') {
          _codeError = e.message;
        } else if (e.code == 'ADDRESS_NOT_FOUND') {
          _addressError = e.message;
        } else {
          showToast(context, e.message);
        }
      });
    });
  }

  Widget _suggestionList() => Container(
        // Figma "menu_list": white card, radius 16, soft shadow, 8 top inset.
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: KColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 4))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: [
            for (final s in _suggestions)
              InkWell(
                onTap: () => _pick(s),
                child: Container(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: KColors.borderDefault))),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: KColors.surfaceSubtle, shape: BoxShape.circle),
                      child: Icon(PhosphorIconsFill.mapPin, size: 20, color: KColors.iconDefault),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s['primary'], style: KText.paragraphMedium),
                          const SizedBox(height: 2),
                          Text(s['secondary'], style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final showList = _suggestions.isNotEmpty;
    // Figma 1300:185508 (default) and 1300:185546 (suggestions).
    return KeysScaffold(
      gradient: false,
      header: KeysHeader(
        progress: P.address,
        onBack: () async {
          await context.session.logout();
          if (context.mounted) context.go('/auth/email');
        },
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Intro(small: true, overline: 'Home address', title: "What's your home address?", body: 'Enter your home address to find your community. Kindly provide your community code if you have one.'),
        const SizedBox(height: 36),
        // The suggestion card floats over the code field, 16 below the address.
        Stack(clipBehavior: Clip.none, children: [
          Column(children: [
            KeysTextField(
              label: 'Home address',
              controller: _address,
              hint: 'Enter your home address',
              prefixIcon: PhosphorIconsRegular.magnifyingGlass,
              error: _addressError,
              onChanged: _onType,
              fieldKey: const Key('address-field'),
              suffix: _picked != null ? Icon(PhosphorIconsFill.checkCircle, color: KColors.success, size: 20) : null,
            ),
            const SizedBox(height: 32),
            KeysTextField(
              label: 'Community code',
              labelNote: ' (Optional)',
              controller: _code,
              hint: 'Enter your community code',
              prefixIcon: PhosphorIconsRegular.key,
              error: _codeError,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() => _codeError = null),
              fieldKey: const Key('code-field-community'),
            ),
          ]),
          if (showList) Positioned(top: 92, left: 0, right: 0, child: _suggestionList()),
        ]),
        if (showList) SizedBox(height: (_suggestions.length * 57.0 + 8 + 16 - 76).clamp(0, double.infinity)),
      ]),
      // Inactive while suggestions are open; a typed address that was not
      // picked is refused with an error on Continue (ONB-11.3).
      bottom: KeysButton('Continue', loading: busy, onPressed: _address.text.trim().isEmpty || (showList && _picked == null) ? null : _continue),
    );
  }
}

/// Community card used on the match screens.
class CommunityHero extends StatelessWidget {
  const CommunityHero(this.c, {super.key, this.badge = MarkBadge.check});
  final CommunityCard c;
  final MarkBadge? badge;
  @override
  Widget build(BuildContext context) {
    // Figma 1300:185679: code pill, 32, image, 32, type + name + counts.
    return Column(children: [
      if (c.json['code'] != null) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(16)),
          child: Text(c.json['code'] as String, style: TextStyle(fontFamily: 'GeistMono', fontWeight: FontWeight.w500, fontSize: 14, height: 18 / 14, letterSpacing: 5, color: KColors.textPrimary)),
        ),
        const SizedBox(height: 32),
      ],
      CircleImage(c.image, size: 140, badge: badge),
      const SizedBox(height: 32),
      Text(c.typeLabel, style: KText.overline),
      const SizedBox(height: 4),
      Text(c.name, style: KText.headingSmall, textAlign: TextAlign.center),
      if (c.residents != null) ...[const SizedBox(height: 8), Counts(c)],
    ]);
  }
}

/// Figma "Community card" (pick your community): icon disc, teal type
/// label, name, counts; selected shows a 2pt teal outline and a teal disc.
class CommunityPickCard extends StatelessWidget {
  const CommunityPickCard(this.c, {super.key, required this.selected, required this.onTap});
  final CommunityCard c;
  final bool selected;
  final VoidCallback onTap;
  static const teal = Color(0xFF008080);

  @override
  Widget build(BuildContext context) {
    final icon = switch (c.type) {
      'development' => PhosphorIconsRegular.tree,
      'building' => PhosphorIconsRegular.buildings,
      _ => PhosphorIconsRegular.houseLine,
    };
    final small = KText.paragraphSmall.copyWith(color: KColors.textSecondary);
    return Semantics(
      button: true,
      selected: selected,
      label: '${c.typeLabel} ${c.name}',
      child: Material(
        color: KColors.surfaceDefault,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: selected ? teal : KColors.surfaceSubtle, width: selected ? 2 : 1)),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? teal : KColors.surfaceSubtle),
                child: Icon(icon, size: 22, color: selected ? Colors.white : teal),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.typeLabel, style: KText.overline.copyWith(color: teal)),
                    const SizedBox(height: 8),
                    Text(c.name, style: KText.paragraphMediumLarge),
                    // Counts show only past 500 residents (CommunityCard).
                    if (c.residents != null) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        Text('${formatCount(c.residents!)} residents', style: small),
                        Container(width: 1, height: 10, margin: const EdgeInsets.symmetric(horizontal: 12), color: KColors.borderDefault),
                        Text('${formatCount(c.committee ?? 0)} committee', style: small),
                      ]),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class Counts extends StatelessWidget {
  const Counts(this.c, {super.key});
  final CommunityCard c;
  @override
  Widget build(BuildContext context) {
    final s = KText.paragraphMedium.copyWith(color: KColors.textSecondary);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(PhosphorIconsRegular.users, size: 18, color: KColors.textSecondary),
      const SizedBox(width: 8),
      Text('${formatCount(c.residents!)} residents', style: s),
      Container(width: 1, height: 10, margin: const EdgeInsets.symmetric(horizontal: 12), color: KColors.borderDefault),
      Text('${formatCount(c.committee ?? 0)} committee', style: s),
      if (c.distanceKm != null) ...[
        Container(width: 1, height: 10, margin: const EdgeInsets.symmetric(horizontal: 12), color: KColors.borderDefault),
        Text('${c.distanceKm}km away', style: s),
      ],
    ]);
  }
}

/// ONB-12 / ONB-13: every outcome of community matching.
class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key, required this.result});
  final MatchResult result;
  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> with Busy {
  String? _selected;

  Future<void> _join(CommunityCard c) async {
    await run(() async {
      final r = await context.api.post('/onboarding/join', {'communityId': c.id});
      if (!mounted) return;
      if (r['onboardingStep'] == 'profile') {
        context.go('/onboarding/live', extra: {'screen': r['screen'], 'name': r['name']});
      } else {
        context.go('/onboarding/home-type');
      }
    });
  }

  Future<void> _proceedWithAddress() async {
    await run(() async {
      context.session.pendingCommunityCode = null;
      final r = await context.api.post('/onboarding/match', {});
      if (mounted) await _showMatch(context, r, replace: true);
    });
  }

  void _notMine() => context.push('/onboarding/area');

  String _foundBody(CommunityCard c) {
    final street = context.session.me?.address?['street'] ?? 'your street';
    if (widget.result.kind == 'code_parent') {
      return 'Your address is on ${c.name}. ${widget.result.codedName} is a building in this community but your address isn\'t eligible for it.';
    }
    return switch (c.type) {
      'development' => 'Your address is within ${c.name}\'s territory. Join to connect with your neighbours and access community updates, events, and local services.',
      'building' => 'Your address is on the same street as ${c.name}. Join to connect with residents in your building, stay informed, and be part of your local community.',
      _ => 'Your address is on $street. Join to connect with your neighbours, stay informed on local updates, and help shape your community.',
    };
  }

  String _ineligibleBody(CommunityCard c) => switch (c.type) {
        'development' => 'Your street is not within ${c.name}\'s area. You can continue with your own address to find or create the community for your street.',
        'building' => 'Your address is not on the street ${c.name} is on. You can continue with your own address to find or create the community for your area.',
        _ => 'Your address is not on ${c.name}. You can continue with your own address to find or create the community for your street.',
      };

  static const _pad = EdgeInsets.fromLTRB(16, 20, 16, 36);

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final header = KeysHeader(progress: P.match);
    switch (r.kind) {
      case 'none':
        final street = context.session.me?.address?['street'] ?? 'your street';
        // Figma 1300:185969: the pioneer block sits centred in the space left.
        return KeysScaffold(
          gradient: false,
          fill: true,
          header: header,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
          body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Intro(small: true, overline: 'Community matching', title: "Your area isn't on Keys yet", body: 'No one has set up a community for $street yet.'),
            const SizedBox(height: 36),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 180,
                    height: 180,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFCCE6E6)),
                    child: Image.asset('assets/images/pioneer_star.png', fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 32),
                  Text('Be the first', textAlign: TextAlign.center, style: KText.headingSmall),
                  const SizedBox(height: 4),
                  Text("As the community's pioneer, you get to create the community and invite your neighbors.", textAlign: TextAlign.center, style: KText.paragraphLarge.copyWith(color: KColors.textSecondary)),
                ]),
              ),
            ),
          ]),
          bottom: KeysButton('Create my community', onPressed: () => context.push('/onboarding/area')),
        );
      case 'multiple':
        final list = r.communities;
        final chosen = list.where((c) => c.id == _selected).firstOrNull;
        // Figma 1300:185936.
        return KeysScaffold(
          gradient: false,
          header: header,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Intro(small: true, overline: 'Community matching', title: 'Pick your community', body: 'Your address is associated with the communities below. Please choose the one that best reflects your actual living area.'),
            const SizedBox(height: 36),
            for (final c in list) ...[
              CommunityPickCard(c, selected: c.id == _selected, onTap: () => setState(() => _selected = c.id)),
              const SizedBox(height: 16),
            ],
          ]),
          bottom: ButtonStack([
            KeysButton('Join community', loading: busy, onPressed: chosen == null ? null : () => _join(chosen)),
            KeysButton('My community is not listed', variant: ButtonVariant.secondary, onPressed: _notMine),
          ]),
        );
      case 'code_ineligible':
        final c = r.communities.first;
        return KeysScaffold(
          gradient: false,
          header: header,
          padding: _pad,
          body: Column(children: [
            Intro(small: true, overline: 'Community matching', title: "You're not eligible for this community", body: _ineligibleBody(c)),
            const SizedBox(height: 36),
            CommunityHero(c, badge: MarkBadge.cross),
          ]),
          bottom: KeysButton('Proceed with my address', loading: busy, onPressed: _proceedWithAddress),
        );
      default: // single, code_match, code_parent
        final c = r.communities.first;
        return KeysScaffold(
          gradient: false,
          header: header,
          padding: _pad,
          body: Column(children: [
            Intro(small: true, overline: 'Community matching', title: 'We found your community', body: _foundBody(c)),
            const SizedBox(height: 36),
            CommunityHero(c),
          ]),
          bottom: ButtonStack([
            KeysButton(r.kind == 'code_parent' ? 'Join ${c.name}' : 'Join community', loading: busy, onPressed: () => _join(c)),
            KeysButton('Not my community', variant: ButtonVariant.secondary, onPressed: _notMine),
          ]),
        );
    }
  }
}

/// ONB-14: "What kind of area do you live in?"
class AreaKindScreen extends StatefulWidget {
  const AreaKindScreen({super.key});
  @override
  State<AreaKindScreen> createState() => _AreaKindScreenState();
}

class _AreaKindScreenState extends State<AreaKindScreen> {
  String? _kind;
  @override
  // Figma 1300:185987.
  Widget build(BuildContext context) => KeysScaffold(
        gradient: false,
        header: const KeysHeader(progress: P.create),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(small: true, overline: 'Start something new', title: 'What kind of area do you live in?', body: 'Select the community type that best describes where your home is.'),
          const SizedBox(height: 36),
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: ChoiceCard(
                asset: 'assets/images/community_street.png',
                title: 'Residential street',
                subtitle: 'On a public street • Non-gated community',
                selected: _kind == 'street',
                onTap: () => setState(() => _kind = 'street'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ChoiceCard(
                asset: 'assets/images/community_development.png',
                title: 'Development',
                subtitle: 'Private land • Managed community • Estate',
                selected: _kind == 'development',
                onTap: () => setState(() => _kind = 'development'),
              ),
            ),
          ])),
        ]),
        // ONB-14.2: inactive until a type is chosen.
        bottom: KeysButton('Proceed', onPressed: _kind == null ? null : () => context.push(_kind == 'street' ? '/onboarding/street' : '/onboarding/development')),
      );
}

/// ONB-15: confirm and create the street community.
class ConfirmStreetScreen extends StatefulWidget {
  const ConfirmStreetScreen({super.key});
  @override
  State<ConfirmStreetScreen> createState() => _ConfirmStreetScreenState();
}

class _ConfirmStreetScreenState extends State<ConfirmStreetScreen> with Busy {
  Future<void> _create() async {
    await run(() async {
      await context.api.post('/onboarding/street');
      if (mounted) context.go('/onboarding/home-type');
    }, onError: (e) async {
      // ONB-15.3: someone else created it first; offer to join theirs.
      if (e is ApiException && e.code == 'STREET_COMMUNITY_EXISTS') {
        final c = CommunityCard(Map<String, dynamic>.from(e.data['community']));
        context.pushReplacement('/onboarding/match', extra: MatchResult({'kind': 'single', 'communities': [c.json]}));
      } else if (e is ApiException) {
        showToast(context, e.message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final street = context.session.me?.address?['street'] ?? '';
    // Figma 1300:186003: street hero centred under the intro.
    return KeysScaffold(
      gradient: false,
      fill: true,
      header: const KeysHeader(progress: P.create),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Intro(small: true, overline: 'Pioneering a street', title: 'Confirm your street', body: 'The community will be anchored to this street. Neighbours with matching addresses will be able to find and join it.'),
        const SizedBox(height: 36),
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircleImage('assets/images/community_street.png', size: 180),
              const SizedBox(height: 32),
              Text('STREET COMMUNITY', style: KText.overline, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(street, style: KText.headingSmall, textAlign: TextAlign.center),
            ]),
          ),
        ),
      ]),
      bottom: KeysButton('Create community', loading: busy, onPressed: _create),
    );
  }
}

/// ONB-18: name the development, then the similar-name check.
class DevelopmentNameScreen extends StatefulWidget {
  const DevelopmentNameScreen({super.key});
  @override
  State<DevelopmentNameScreen> createState() => _DevelopmentNameScreenState();
}

class _DevelopmentNameScreenState extends State<DevelopmentNameScreen> with Busy {
  final _name = TextEditingController();
  Future<void> _proceed() async {
    await run(() async {
      final r = await context.api.post('/onboarding/development/check', {'name': _name.text.trim()});
      final similar = List<Map<String, dynamic>>.from(r['similar']);
      if (!mounted) return;
      if (similar.isEmpty) {
        context.push('/onboarding/development/shape', extra: _name.text.trim());
      } else {
        context.push('/onboarding/development/similar', extra: {'name': _name.text.trim(), 'similar': similar});
      }
    });
  }

  @override
  // Figma 1300:188171.
  Widget build(BuildContext context) => KeysScaffold(
        gradient: false,
        header: const KeysHeader(progress: P.create),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(small: true, overline: 'Pioneering a development', title: 'Name your development', body: "Use the official name of your development. If you're not sure, check your tenancy agreement or documents from your managing agent."),
          const SizedBox(height: 36),
          KeysTextField(
            label: 'Development name',
            hint: 'Enter name of your development',
            prefixIcon: PhosphorIconsRegular.tree,
            controller: _name,
            maxLength: 60,
            showCount: false,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
        ]),
        bottom: KeysButton('Proceed', loading: busy, onPressed: _name.text.trim().isEmpty ? null : _proceed),
      );
}

/// ONB-19.1 / ONB-19.4
class SimilarDevelopmentsScreen extends StatelessWidget {
  const SimilarDevelopmentsScreen({super.key, required this.name, required this.similar});
  final String name;
  final List<Map<String, dynamic>> similar;

  Future<void> _confirmCreate(BuildContext context) async {
    final go = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Are you sure?', style: KText.headingSmall),
          const SizedBox(height: 8),
          Text('A development with a similar name already exists nearby. Only create a new one if yours is a separate development.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 24),
          KeysButton('Create new development', onPressed: () => Navigator.pop(c, true)),
          const SizedBox(height: 12),
          KeysButton('Go back', variant: ButtonVariant.secondary, onPressed: () => Navigator.pop(c, false)),
        ]),
      ),
    );
    if (go == true && context.mounted) context.push('/onboarding/development/shape', extra: name);
  }

  // Figma 1573:19454.
  @override
  Widget build(BuildContext context) => KeysScaffold(
        gradient: false,
        header: const KeysHeader(progress: P.create),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // This frame's label is Inter Regular 10 with 3pt tracking.
          Text('DEVELOPMENT NAME CHECK', style: TextStyle(fontFamily: 'Inter', fontSize: 10, height: 28 / 10, letterSpacing: 3, color: KColors.textPrimary)),
          const SizedBox(height: 12),
          Text('Developments with a similar name already exists nearby', style: KText.headingSmall),
          const SizedBox(height: 8),
          Text('If this is the same development, joining it is the correct choice your street will be added to the existing community.', style: KText.paragraphLarge.copyWith(color: KColors.textSecondary)),
          for (final s in similar.map(CommunityCard.new)) ...[
            const SizedBox(height: 20),
            SimilarDevelopmentCard(s, onTap: () => context.push('/onboarding/development/join', extra: s.id)),
          ],
          const SizedBox(height: 20),
          Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 1), color: KColors.borderDefault),
          const SizedBox(height: 20),
          Text('This is a different development', style: KText.headingXSmall.copyWith(height: 26 / 18, letterSpacing: -0.2)),
          const SizedBox(height: 8),
          Text("If you're certain this is a separate development that happens to share a similar name, you can proceed to create your community.", style: KText.paragraphLarge.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 20),
          KeysButton('Continue with creation', variant: ButtonVariant.outline, onPressed: () => _confirmCreate(context)),
        ]),
      );
}

/// Figma "Community cards" on the name check: orange disc with a tree,
/// name, counts (over 500 residents only), distance tag, caret.
class SimilarDevelopmentCard extends StatelessWidget {
  const SimilarDevelopmentCard(this.c, {super.key, required this.onTap});
  final CommunityCard c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final small = KText.paragraphSmall.copyWith(color: KColors.textSecondary);
    return Material(
      color: KColors.surfaceDefault,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: KColors.borderDefault, width: 2)),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFF8327)),
              child: const Icon(PhosphorIconsRegular.tree, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: KText.paragraphMediumLarge),
                if (c.residents != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Text('${formatCount(c.residents!)} residents', style: small),
                    Container(width: 1, height: 10, margin: const EdgeInsets.symmetric(horizontal: 12), color: KColors.borderDefault),
                    Flexible(child: Text('${formatCount(c.committee ?? 0)} committee members', style: small, overflow: TextOverflow.ellipsis)),
                  ]),
                ],
                if (c.distanceKm != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(color: const Color(0xFFFFEDE0), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(PhosphorIconsFill.mapPin, size: 12, color: Color(0xFFAA571A)),
                      const SizedBox(width: 4),
                      Text('${c.distanceKm}km away', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w500, height: 1.5, color: Color(0xFFAA571A))),
                    ]),
                  ),
                ],
              ]),
            ),
            const SizedBox(width: 20),
            Icon(PhosphorIconsRegular.caretRight, size: 20, color: KColors.iconDefault),
          ]),
        ),
      ),
    );
  }
}

/// ONB-19.2 / ONB-19.3: add your street to an existing development, no vote.
class JoinDevelopmentScreen extends StatefulWidget {
  const JoinDevelopmentScreen({super.key, required this.developmentId});
  final String developmentId;
  @override
  State<JoinDevelopmentScreen> createState() => _JoinDevelopmentScreenState();
}

class _JoinDevelopmentScreenState extends State<JoinDevelopmentScreen> with Busy {
  Map<String, dynamic>? _p;
  @override
  void initState() {
    super.initState();
    context.api.get('/onboarding/development/${widget.developmentId}/join-preview').then((r) => mounted ? setState(() => _p = r) : null);
  }

  Future<void> _join() async {
    await run(() async {
      await context.api.post('/onboarding/development/${widget.developmentId}/join');
      if (mounted) context.go('/onboarding/home-type');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(label, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary))),
            Expanded(child: Text(value, style: KText.paragraphMediumLarge.copyWith(fontSize: 14))),
          ]),
        );
    return KeysScaffold(
      header: const KeysHeader(progress: P.create),
      body: p == null
          ? const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Intro(
                overline: 'Join existing development',
                title: 'Add your street to ${p['development']['name']}',
                body: 'Joining this community will add your street ${p['yourStreet']} to ${p['development']['name']}.',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: BorderRadius.circular(KRadius.md), border: Border.all(color: KColors.borderDefault)),
                child: Column(children: [
                  row('Your street', p['yourStreet']),
                  Divider(color: KColors.borderDefault, height: 1),
                  row('Development', p['development']['name']),
                  Divider(color: KColors.borderDefault, height: 1),
                  row('Current streets', (p['streets'] as List).join('\n')),
                ]),
              ),
            ]),
      bottom: KeysButton('Join development', loading: busy, onPressed: p == null ? null : _join),
    );
  }
}

/// ONB-20: add up to 5 directly connected streets, or skip.
class ShapeDevelopmentScreen extends StatefulWidget {
  const ShapeDevelopmentScreen({super.key, required this.name});
  final String name;
  @override
  State<ShapeDevelopmentScreen> createState() => _ShapeDevelopmentScreenState();
}

class _ShapeDevelopmentScreenState extends State<ShapeDevelopmentScreen> with Busy {
  Map<String, dynamic>? _data;
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    context.api.get('/onboarding/development/connected-streets').then((r) => mounted ? setState(() => _data = r) : null);
  }

  int get _max => (_data?['max'] as int?) ?? 5;

  Future<void> _create({bool skip = false}) async {
    await run(() async {
      await context.api.post('/onboarding/development', {'name': widget.name, 'streetKeys': skip ? [] : _picked.toList()});
      if (mounted) context.go('/onboarding/home-type');
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final full = _picked.length >= _max;
    return KeysScaffold(
      header: const KeysHeader(progress: P.create),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Copy updated: committee street-adding is Phase 2 (Design vs PRD ONB-D4).
        const Intro(overline: 'Pioneering a development', title: 'Shape your development', body: 'Add the streets in your development so their residents can join this development community. You can skip this step.'),
        const SizedBox(height: 16),
        if (d == null)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
        else ...[
          Text('Your street', style: KText.overline),
          const SizedBox(height: 8),
          _StreetRow(name: d['yourStreet']['name'], trailing: Icon(PhosphorIconsRegular.lock, size: 18, color: KColors.textSecondary)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: Text('Connected streets', style: KText.overline)),
            Text('${_picked.length}/$_max', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          ]),
          const SizedBox(height: 4),
          Text('Only streets directly connected to your street are shown.', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 8),
          for (final s in List<Map<String, dynamic>>.from(d['streets']))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _StreetRow(
                name: s['name'],
                sub: s['hasStreetCommunity'] == true ? 'Has its own street community. It will stay linked to both.' : null,
                trailing: _picked.contains(s['key'])
                    ? IconButton(tooltip: 'Remove ${s['name']}', icon: Icon(PhosphorIconsFill.checkCircle, color: KColors.selected), onPressed: () => setState(() => _picked.remove(s['key'])))
                    : IconButton(
                        tooltip: 'Add ${s['name']}',
                        icon: Icon(PhosphorIconsRegular.plusCircle, color: full ? KColors.textTertiary : KColors.textPrimary),
                        onPressed: full ? null : () => setState(() => _picked.add(s['key'])),
                      ),
              ),
            ),
          if (full) Padding(padding: const EdgeInsets.only(top: 4), child: ErrorLine('Maximum of $_max streets can be linked')),
        ],
      ]),
      bottom: ButtonStack([
        KeysButton('Create development', loading: busy, onPressed: d == null ? null : () => _create()),
        KeysButton('Skip', variant: ButtonVariant.ghost, onPressed: busy || d == null ? null : () => _create(skip: true)),
      ]),
    );
  }
}

class _StreetRow extends StatelessWidget {
  const _StreetRow({required this.name, this.sub, required this.trailing});
  final String name;
  final String? sub;
  final Widget trailing;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: BorderRadius.circular(KRadius.sm), border: Border.all(color: KColors.borderDefault)),
        child: Row(children: [
          Icon(PhosphorIconsRegular.signpost, size: 20, color: KColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: KText.paragraphMediumLarge.copyWith(fontSize: 15)),
              if (sub != null) Text(sub!, style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
            ]),
          ),
          SizedBox(height: 44, child: Center(child: trailing)),
        ]),
      );
}

/// ONB-16: house or building.
class HomeTypeScreen extends StatefulWidget {
  const HomeTypeScreen({super.key});
  @override
  State<HomeTypeScreen> createState() => _HomeTypeScreenState();
}

class _HomeTypeScreenState extends State<HomeTypeScreen> with Busy {
  String? _type;
  Future<void> _proceed() async {
    await run(() async {
      final r = await context.api.post('/onboarding/home-type', {'type': _type});
      if (!mounted) return;
      if (_type == 'house') {
        context.go('/onboarding/live', extra: {'screen': r['screen'], 'name': r['name']});
      } else {
        final buildings = List<Map<String, dynamic>>.from(r['buildings']);
        context.push(buildings.isEmpty ? '/onboarding/building/name' : '/onboarding/building/pick', extra: buildings);
      }
    });
  }

  @override
  Widget build(BuildContext context) => KeysScaffold(
        header: KeysHeader(progress: P.homeType, showBack: false),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(overline: 'Your home', title: 'What type of home do you live in?', body: 'This helps us connect you with the right neighbours on Keys.'),
          const SizedBox(height: 24),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: ChoiceCard(asset: 'assets/images/home_house.png', title: 'House', subtitle: 'Bungalow • Detached house • Semi detached • Townhouse', selected: _type == 'house', onTap: () => setState(() => _type = 'house'))),
            const SizedBox(width: 16),
            Expanded(child: ChoiceCard(asset: 'assets/images/community_building.png', title: 'Building', subtitle: 'Apartment • Maisonette • Duplex • Loft • High rise', selected: _type == 'building', onTap: () => setState(() => _type = 'building'))),
          ]),
        ]),
        bottom: KeysButton('Proceed', loading: busy, onPressed: _type == null ? null : _proceed),
      );
}

/// ONB-17.4: pick an existing building on your street.
class PickBuildingScreen extends StatefulWidget {
  const PickBuildingScreen({super.key, required this.buildings});
  final List<Map<String, dynamic>> buildings;
  @override
  State<PickBuildingScreen> createState() => _PickBuildingScreenState();
}

class _PickBuildingScreenState extends State<PickBuildingScreen> with Busy {
  String? _id;
  Future<void> _join() async {
    await run(() async {
      final r = await context.api.post('/onboarding/building/$_id/join');
      if (mounted) context.go('/onboarding/live', extra: {'screen': r['screen'], 'name': r['name']});
    });
  }

  @override
  Widget build(BuildContext context) => KeysScaffold(
        header: const KeysHeader(progress: P.building),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(overline: 'Your home', title: 'Pick your building', body: 'This helps us connect you with the right neighbours on Keys.'),
          const SizedBox(height: 24),
          for (final b in widget.buildings) ...[
            OptionTile(
              title: b['name'],
              subtitle: b['residents'] != null ? '${formatCount(b['residents'])} residents' : null,
              leading: const CircleImage('assets/images/community_building.png', size: 48),
              selected: _id == b['id'],
              onTap: () => setState(() => _id = b['id']),
            ),
            const SizedBox(height: 12),
          ],
        ]),
        bottom: ButtonStack([
          KeysButton('Proceed', loading: busy, onPressed: _id == null ? null : _join),
          KeysButton("My building isn't listed", variant: ButtonVariant.secondary, onPressed: () => context.push('/onboarding/building/name')),
        ]),
      );
}

/// ONB-17.1 - ONB-17.3: name a new building.
class NameBuildingScreen extends StatefulWidget {
  const NameBuildingScreen({super.key});
  @override
  State<NameBuildingScreen> createState() => _NameBuildingScreenState();
}

class _NameBuildingScreenState extends State<NameBuildingScreen> with Busy {
  final _name = TextEditingController();
  String? _error;
  Future<void> _create() async {
    await run(() async {
      final r = await context.api.post('/onboarding/building', {'name': _name.text.trim()});
      if (mounted) context.go('/onboarding/live', extra: {'screen': r['screen'], 'name': r['name'], 'building': true});
    }, onError: (e) => setState(() => _error = e is ApiException ? e.message : 'Something went wrong.'));
  }

  @override
  Widget build(BuildContext context) => KeysScaffold(
        header: const KeysHeader(progress: P.building),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Intro(overline: 'Pioneering a building', title: 'Name your building', body: "Use the official name of your building. If you're not sure, check your tenancy agreement or documents from your managing agent."),
          const SizedBox(height: 24),
          KeysTextField(label: 'Building name', controller: _name, maxLength: 60, error: _error, textCapitalization: TextCapitalization.words, onChanged: (_) => setState(() => _error = null)),
        ]),
        bottom: KeysButton('Create building', loading: busy, onPressed: _name.text.trim().isEmpty ? null : _create),
      );
}

/// ONB-21: "[Name] is live." or "Welcome to [Community]".
class CommunityLiveScreen extends StatelessWidget {
  const CommunityLiveScreen({super.key, required this.screen, required this.name, this.building = false});
  final String screen; // live | welcome
  final String name;
  final bool building;
  @override
  Widget build(BuildContext context) {
    final live = screen == 'live';
    return KeysScaffold(
      header: const KeysHeader(progress: P.live, showBack: false),
      body: Column(children: [
        const SizedBox(height: 24),
        Text(live ? '$name is live.' : 'Welcome to $name', style: KText.headingMedium.copyWith(fontSize: 32, height: 40 / 32), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(
          live && !building
              ? "You're the first. Others on your street will be able to join as they sign up."
              : 'Say hello to your neighbours, follow local projects, help shape what happens next',
          textAlign: TextAlign.center,
          style: KText.paragraphMedium.copyWith(color: KColors.textSecondary),
        ),
        const SizedBox(height: 40),
        CircleImage(building ? 'assets/images/community_building.png' : 'assets/images/community_live_street.png', size: 270),
      ]),
      bottom: KeysButton('Enter community', onPressed: () => context.go('/onboarding/profile')),
    );
  }
}
