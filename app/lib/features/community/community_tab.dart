import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/feed_models.dart';
import '../../core/scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../feed/social.dart';
import 'proposals.dart';

/// CBM-01: Community tab. Phase 1 shows the committee board and its
/// announcements; wallet, resources, communal services, projects and maps are hidden.
class CommunityTab extends StatefulWidget {
  const CommunityTab({super.key});
  @override
  State<CommunityTab> createState() => CommunityTabState();
}

class CommunityTabState extends State<CommunityTab> {
  Map<String, dynamic>? _c;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final r = await context.api.get('/community');
      if (mounted) setState(() => _c = r);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return const Center(child: CircularProgressIndicator());
    final com = c['community'];
    final showProposals = c['proposalsTab'] == true;
    return Column(children: [
      ListTile(
        leading: const CircleAvatar(backgroundColor: KColors.surfaceSubtle, child: Icon(Icons.apartment_outlined, color: KColors.selected)),
        title: Text(com['name'], style: KText.paragraphMediumLarge),
        subtitle: Text(com['location'], style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
        trailing: IconButton(tooltip: 'Share community', icon: const Icon(Icons.share_outlined), onPressed: () => showShareCommunity(context, com['code'], c['shareLink'])),
      ),
      // VOT-01.5: Proposals tab for committee members only.
      if (showProposals)
        Row(children: [
          for (final (i, label) in ['Hub', 'Proposals'].indexed)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _tab = i),
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == i ? KColors.textPrimary : KColors.borderDefault, width: _tab == i ? 2 : 1))),
                  child: Text(label, style: KText.labelSemibold.copyWith(color: _tab == i ? KColors.textPrimary : KColors.textSecondary)),
                ),
              ),
            ),
        ]),
      Expanded(child: showProposals && _tab == 1 ? const ProposalsList() : RefreshIndicator(onRefresh: refresh, child: _Hub(c: c, onChanged: refresh))),
    ]);
  }
}

class _Hub extends StatelessWidget {
  const _Hub({required this.c, required this.onChanged});
  final Map<String, dynamic> c;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final board = c['board'];
    final ann = List<Map<String, dynamic>>.from(c['announcements'] ?? []);
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      if (c['tierUp'] != null)
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: KColors.brandSubtle, borderRadius: BorderRadius.circular(KRadius.md), border: Border.all(color: KColors.brand)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Welcome to Tier ${c['tierUp']['tier']}!', style: KText.headingXSmall),
            const SizedBox(height: 4),
            Text(
              c['me']['isChair'] == true
                  ? 'Congratulations! Your community just got bigger. This means your community now has additional committee seats that only you can activate.'
                  : 'Your community just got bigger and unlocked additional committee seats you can apply to.',
              style: KText.paragraphMedium,
            ),
            const SizedBox(height: 8),
            LinkText(c['me']['isChair'] == true ? 'Activate board seats' : 'View board seats', onTap: () async {
              await context.push(c['me']['isChair'] == true ? '/board/manage' : '/board');
              onChanged();
            }),
          ]),
        ),
      if (board == null)
        // CBM-02.1
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Column(children: [
            const CircleImage('assets/images/committee_empty.png', size: 220),
            const SizedBox(height: 20),
            Text('Take a leap to improve your community', style: KText.headingSmall, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('Become the first committee member.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
            const SizedBox(height: 20),
            SizedBox(width: 200, child: KeysButton('Create committee', onPressed: () async {
              await context.push('/board/join', extra: {'create': true});
              onChanged();
            })),
          ]),
        )
      else ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(children: [
            Text('Committee board', style: KText.headingXSmall),
            const Spacer(),
            TextButton(onPressed: () async {
              await context.push('/board');
              onChanged();
            }, child: const Text('View all', style: TextStyle(color: KColors.textLink))),
          ]),
        ),
        SizedBox(
          height: 92,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final p in List<Map<String, dynamic>>.from(board['preview']))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(children: [
                  Avatar(p['photoUrl'], size: 56),
                  const SizedBox(height: 6),
                  Text(p['isYou'] == true ? 'You' : PersonRef(p).firstName, style: KText.paragraphSmall),
                ]),
              ),
          ]),
        ),
        if (c['me']['role'] == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: KeysButton('Join the committee', variant: ButtonVariant.outline, onPressed: () async {
              await context.push('/board');
              onChanged();
            }),
          ),
      ],
      if (ann.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 8), child: Text('Committee announcements', style: KText.headingXSmall)),
        SizedBox(
          height: 170,
          child: PageView(
            controller: PageController(viewportFraction: 0.9),
            children: [for (final a in ann) _AnnouncementCard(a: a, me: c['me'])],
          ),
        ),
        if (ann.length > 1) Center(child: Text('Swipe to view more', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary))),
      ],
    ]);
  }
}

/// CBM-18: New member, Role change, Board exit, Member removal.
class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.a, required this.me});
  final Map<String, dynamic> a;
  final Map<String, dynamic> me;
  @override
  Widget build(BuildContext context) {
    final vacancy = a['type'] == 'board_exit' || a['type'] == 'member_removal';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: BorderRadius.circular(KRadius.md), border: Border.all(color: KColors.borderDefault)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: vacancy ? const Color(0xFFFDECEA) : const Color(0xFFDDF2F0), borderRadius: BorderRadius.circular(4)),
          child: Text(a['label'], style: KText.paragraphMediumSmall.copyWith(color: vacancy ? KColors.error : KColors.selected)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Avatar(a['subject']?['photoUrl'], size: 36),
          const SizedBox(width: 10),
          Expanded(child: Text(a['text'], style: KText.paragraphMedium, maxLines: 3, overflow: TextOverflow.ellipsis)),
        ]),
        const Spacer(),
        Row(children: [
          if (a['reason'] != null)
            LinkText('View reason', onTap: () => showModalBottomSheet(
                  context: context,
                  builder: (c) => Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), child: Text(a['reason'], style: KText.paragraphLarge)),
                )),
          const Spacer(),
          // CBM-18.2: residents apply, members reassign.
          if (vacancy)
            LinkText(me['isCommittee'] == true ? 'Reassign to this role' : (me['role'] == null ? 'Apply for this role' : ''), onTap: () => context.push('/board')),
        ]),
      ]),
    );
  }
}

/// CBM-03: community code and link.
Future<void> showShareCommunity(BuildContext context, String code, String link) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bring your neighbors closer', style: KText.headingSmall),
          const SizedBox(height: 16),
          Center(child: Text(code.split('').join(' '), style: KText.headingMedium.copyWith(letterSpacing: 4))),
          const SizedBox(height: 16),
          Text('Community link', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
          Text(link, style: KText.paragraphMediumLarge),
          const SizedBox(height: 16),
          Text('How to join via code', style: KText.paragraphMediumLarge),
          Text('Download Keys, enter your home address and type this code in "Community code".', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 12),
          Text('How to join via link', style: KText.paragraphMediumLarge),
          Text('Open the link on your phone. Keys opens and finds the community for you.', style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: KeysButton('Copy link', variant: ButtonVariant.secondary, onPressed: () async {
              await context.deps.sharer.copy(link);
              if (c.mounted) showToast(c, 'Link copied');
            })),
            const SizedBox(width: 12),
            Expanded(child: KeysButton('Share', onPressed: () => context.deps.sharer.share("Hey! I'm using the Keys app to stay connected to our community. Download it and join us! $link"))),
          ]),
        ]),
      ),
    );
