import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/scope.dart';
import '../features/feed/social.dart' show Avatar;
import '../theme/phosphor.dart';
import '../theme/tokens.dart';

/// Figma tab page header (Events, Clubs): 36pt avatar, centred title,
/// 28pt action icon on the right.
class TabPageHeader extends StatelessWidget {
  const TabPageHeader(this.title, {super.key, required this.actionIcon, required this.actionLabel, required this.onAction});
  final String title;
  final IconData actionIcon;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Stack(alignment: Alignment.center, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => context.push('/profile'),
                  child: Semantics(button: true, label: 'Profile', child: Avatar(context.session.me?.photoUrl, size: 36)),
                ),
              ),
              Text(title, style: KText.paragraphLarge.copyWith(fontSize: 18, fontWeight: FontWeight.w600, height: 24 / 18)),
              Align(
                alignment: Alignment.centerRight,
                child: Semantics(
                  button: true,
                  label: actionLabel,
                  child: Tooltip(
                    message: actionLabel,
                    child: InkResponse(onTap: onAction, radius: 22, child: Icon(actionIcon, size: 28, color: KColors.iconDefault)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// Figma tabs: 48pt row, 14pt labels (semibold when selected), 3pt rounded
/// black indicator inset 8pt, 1pt grey divider.
class KeysTabs extends StatelessWidget implements PreferredSizeWidget {
  const KeysTabs({super.key, required this.controller, required this.labels});
  final TabController controller;
  final List<String> labels;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) => TabBar(
        controller: controller,
        labelColor: KColors.textPrimary,
        unselectedLabelColor: KColors.textSecondary,
        labelStyle: KText.paragraphMedium.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: KText.paragraphMedium,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(width: 3, color: KColors.textPrimary),
          borderRadius: BorderRadius.circular(2),
          insets: const EdgeInsets.symmetric(horizontal: 8),
        ),
        dividerColor: KColors.borderDefault,
        dividerHeight: 1,
        overlayColor: WidgetStatePropertyAll(KColors.surfaceSubtle),
        tabs: [for (final l in labels) Tab(height: 48, text: l)],
      );
}

/// Figma "FAB Button": 52pt yellow disc, 28pt icon, two soft shadows.
class KeysFab extends StatelessWidget {
  const KeysFab({super.key, required this.label, required this.onTap, this.icon = PhosphorIconsRegular.plus});
  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 5, offset: Offset(0, 1)), BoxShadow(color: Color(0x24000000), blurRadius: 10, offset: Offset(0, 2))],
            ),
            child: Material(
              color: KColors.brand,
              shape: const CircleBorder(),
              child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Icon(icon, size: 28, color: const Color(0xFF171717))),
            ),
          ),
        ),
      );
}
