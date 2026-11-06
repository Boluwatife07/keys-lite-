import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:keys_lite/theme/phosphor.dart';
import 'package:flutter/services.dart';
import '../core/api.dart';
import '../theme/tokens.dart';
export 'keys_logo.dart';
export 'street_map.dart';
export 'brand_marks.dart';
export 'nav_icons.dart';

// ---------------------------------------------------------------- layout

/// Standard onboarding page: back + progress header, scrolling body, pinned
/// buttons at the bottom, white to brand-subtle background.
class KeysScaffold extends StatelessWidget {
  const KeysScaffold({super.key, this.header, required this.body, this.bottom, this.gradient = true, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16), this.fill = false});
  /// Body is at least as tall as the space, so it can use Expanded/Spacer
  /// (e.g. a block centred under the intro). Still scrolls when it overflows.
  final bool fill;
  final Widget? header;
  final Widget body;
  final Widget? bottom;
  final bool gradient;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient ? kPageGradient : null, color: gradient ? null : KColors.surfaceDefault),
        // Transparent Material so list rows and buttons keep their ink ripple.
        child: Material(type: MaterialType.transparency, child: SafeArea(
          child: Column(
            children: [
              ?header,
              Expanded(
                child: fill
                    ? LayoutBuilder(
                        builder: (context, box) => SingleChildScrollView(
                          padding: padding,
                          child: ConstrainedBox(constraints: BoxConstraints(minHeight: box.maxHeight - padding.vertical), child: IntrinsicHeight(child: body)),
                        ),
                      )
                    : SingleChildScrollView(padding: padding, child: body),
              ),
              // Figma pins the bottom action 12 below the content and right on the
              // home indicator; without a bottom inset keep a 16 margin.
              if (bottom != null) Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.viewPaddingOf(context).bottom > 0 ? 0 : 16), child: bottom!),
            ],
          ),
        )),
      ),
    );
  }
}

class KeysHeader extends StatelessWidget {
  const KeysHeader({super.key, this.onBack, this.progress, this.showBack = true, this.trailing, this.leading});
  /// Replaces the back caret (e.g. a close X).
  final Widget? leading;
  final VoidCallback? onBack;
  final double? progress;
  final bool showBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // Figma "Page Header": 48 high, 16 side padding, 26pt back caret.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 48,
            child: Row(children: [
              ?leading,
              if (leading == null && showBack)
                Semantics(
                  button: true,
                  label: 'Back',
                  child: InkResponse(
                    key: const Key('back'),
                    radius: 22,
                    onTap: onBack ?? () => Navigator.of(context).maybePop(),
                    child: Icon(PhosphorIconsRegular.caretLeft, size: 26, color: KColors.iconDefault),
                  ),
                ),
              const Spacer(),
              ?trailing,
            ]),
          ),
          if (progress != null) Padding(padding: const EdgeInsets.fromLTRB(0, 12, 0, 13), child: ProgressBar(value: progress!)),
        ],
      ),
    );
  }
}

/// Figma "Page Header": 48 high, 16 side padding, 26px back caret, 16 gap,
/// title Inter SemiBold 18 / -0.2.
class PageHeader extends StatelessWidget implements PreferredSizeWidget {
  const PageHeader(this.title, {super.key, this.actions = const [], this.onBack, this.showBack = true, this.bottomBorder = false});
  final String title;
  final bool bottomBorder;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final bool showBack;
  static const titleStyle = TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w600, height: 1, letterSpacing: -0.2);

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) => Material(
        color: KColors.surfaceDefault,
        shape: bottomBorder ? Border(bottom: BorderSide(color: KColors.borderSubtle, width: 0.5)) : null,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                if (showBack) ...[
                  Semantics(
                    button: true,
                    label: 'Back',
                    child: InkResponse(
                      key: const Key('back'),
                      radius: 22,
                      onTap: onBack ?? () => Navigator.of(context).maybePop(),
                      child: Icon(PhosphorIconsRegular.caretLeft, size: 26, color: KColors.iconDefault),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle.copyWith(color: KColors.textPrimary))),
                ...actions,
              ]),
            ),
          ),
        ),
      );
}

/// In-page back caret (26) in an 8pt vertical band, as on the auth screens.
class BackRow extends StatelessWidget {
  const BackRow({super.key, this.onBack});
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Semantics(
          button: true,
          label: 'Back',
          child: InkResponse(
            key: const Key('back'),
            radius: 22,
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
            child: Icon(PhosphorIconsRegular.caretLeft, size: 26, color: KColors.iconDefault),
          ),
        ),
      );
}

/// "or" between two 1pt rules, inset 16 from the content edges.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: Container(height: 1, color: KColors.borderDefault)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: KText.paragraphMediumSmall)),
          Expanded(child: Container(height: 1, color: KColors.borderDefault)),
        ]),
      );
}

/// Figma "Onboaring progress": 8pt bar on a surface/subtle track; the fill
/// runs orange 500 to orange 200 to brand subtle to brand.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value});
  final double value;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Progress',
      value: '${(value * 100).round()}%',
      child: Container(
        height: 8,
        decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(KRadius.pill)),
        alignment: Alignment.centerLeft,
        child: LayoutBuilder(
          builder: (_, c) => Container(
            width: (c.maxWidth * value.clamp(0, 1)).clamp(18, c.maxWidth),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(
                colors: [Color(0xFFFF8327), Color(0xFFFF8327), Color(0xFFFFC79E), Color(0xFFFFE37F), Color(0xFFFFD12A)],
                stops: [0, 0.139, 0.404, 0.831, 1],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Intro extends StatelessWidget {
  const Intro({super.key, this.overline, required this.title, this.body, this.center = false, this.small = false});
  /// Heading/Small with 12pt gaps, as on the onboarding form steps.
  final bool small;
  final String? overline;
  final String title;
  final String? body;
  final bool center;
  @override
  Widget build(BuildContext context) {
    final align = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (overline != null) ...[Text(overline!.toUpperCase(), style: KText.overline, textAlign: align), SizedBox(height: small ? 12 : 8)],
        Text(title, style: small ? KText.headingSmall : KText.headingMedium, textAlign: align),
        if (body != null) ...[const SizedBox(height: 12), Text(body!, style: KText.paragraphLarge.copyWith(color: KColors.textSecondary), textAlign: align)],
      ],
    );
  }
}

// ---------------------------------------------------------------- buttons

enum ButtonVariant { primary, secondary, outline, ghost, light }

class KeysButton extends StatelessWidget {
  const KeysButton(this.label, {super.key, required this.onPressed, this.variant = ButtonVariant.primary, this.loading = false, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final bool loading;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final (bg, fg, border) = switch (variant) {
      ButtonVariant.primary => (enabled || loading) ? (KColors.surfaceInverted, KColors.textInverse, null) : (KColors.surfaceSubtle, KColors.textDisabled, null),
      ButtonVariant.secondary => (KColors.surfaceMuted, enabled ? KColors.textPrimary : KColors.textTertiary, null),
      ButtonVariant.outline => (Colors.transparent, enabled ? KColors.textPrimary : KColors.textTertiary, KColors.borderStrong),
      ButtonVariant.ghost => (Colors.transparent, enabled ? KColors.textPrimary : KColors.textTertiary, null),
      // Always white: used on photos and camera views in both themes.
      ButtonVariant.light => (Colors.white, const Color(0xFF292929), null),
    };
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: Material(
          color: bg,
          shape: StadiumBorder(side: border == null ? BorderSide.none : BorderSide(color: border)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[icon!, const SizedBox(width: 8)],
                      Flexible(child: ExcludeSemantics(child: Text(label, overflow: TextOverflow.ellipsis, style: KText.labelSemibold.copyWith(color: fg)))),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

class ButtonStack extends StatelessWidget {
  const ButtonStack(this.children, {super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 10), children[i]],
      ]);
}

class LinkText extends StatelessWidget {
  const LinkText(this.text, {super.key, required this.onTap, this.style});
  final String text;
  final VoidCallback? onTap;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(text, style: (style ?? KText.paragraphMedium).copyWith(color: onTap == null ? KColors.textTertiary : KColors.textPrimary, fontWeight: FontWeight.w600)),
        ),
      );
}

// ---------------------------------------------------------------- inputs

class KeysTextField extends StatefulWidget {
  const KeysTextField({
    super.key,
    this.label,
    required this.controller,
    this.hint,
    this.hintColor,
    this.prefixIcon,
    this.showCount = true,
    this.labelNote,
    this.error,
    this.obscure = false,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.onChanged,
    this.autofocus = false,
    this.suffix,
    this.textCapitalization = TextCapitalization.none,
    this.fieldKey,
    this.inputFormatters,
    this.autofillHints,
    this.enabled = true,
  });
  final String? label;
  final TextEditingController controller;
  final String? hint;
  final Color? hintColor;
  /// Leading 24pt icon inside the field, 8 before the text.
  final IconData? prefixIcon;
  /// Shows "n/max" by the label when [maxLength] is set.
  final bool showCount;
  /// Grey text after the label, e.g. " (Optional)".
  final String? labelNote;
  final String? error;
  final bool obscure;
  final int? maxLength;
  final int maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final Widget? suffix;
  final TextCapitalization textCapitalization;
  final Key? fieldKey;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool enabled;

  @override
  State<KeysTextField> createState() => _KeysTextFieldState();
}

class _KeysTextFieldState extends State<KeysTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null || (widget.maxLength != null && widget.showCount))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              // Figma "Input element/Heading": a 20pt row whose 24pt text hangs from the bottom.
              if (widget.label != null) Expanded(child: SizedBox(height: 20, child: OverflowBox(maxHeight: 24, alignment: Alignment.bottomLeft, child: Text.rich(TextSpan(text: widget.label!, children: [if (widget.labelNote != null) TextSpan(text: widget.labelNote, style: TextStyle(color: KColors.textSecondary))]), style: KText.paragraphMediumLarge)))),
              if (widget.maxLength != null && widget.showCount)
                ValueListenableBuilder(
                  valueListenable: widget.controller,
                  builder: (_, v, _) => Text('${v.text.characters.length}/${widget.maxLength}', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                ),
            ]),
          ),
        Container(
          decoration: BoxDecoration(
            // Figma error state: white fill under a 2pt red border.
            color: hasError ? KColors.surfaceDefault : widget.enabled ? KColors.surfaceSubtle : KColors.surfaceMuted,
            borderRadius: BorderRadius.circular(KRadius.sm),
          ),
          // Drawn on top so the border never changes the 48pt field height.
          foregroundDecoration: hasError ? BoxDecoration(borderRadius: BorderRadius.circular(KRadius.sm), border: Border.all(color: KColors.error, width: 2)) : null,
          padding: const EdgeInsets.only(left: 12, right: 8),
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(children: [
            if (widget.prefixIcon != null) ...[Icon(widget.prefixIcon, size: 24, color: KColors.iconDefault), const SizedBox(width: 8)],
            Expanded(
              child: TextField(
                key: widget.fieldKey,
                controller: widget.controller,
                enabled: widget.enabled,
                obscureText: _hidden,
                maxLines: widget.obscure ? 1 : widget.maxLines,
                minLines: widget.minLines ?? 1,
                autofocus: widget.autofocus,
                keyboardType: widget.keyboardType,
                textCapitalization: widget.textCapitalization,
                autofillHints: widget.autofillHints,
                inputFormatters: [
                  if (widget.maxLength != null) LengthLimitingTextInputFormatter(widget.maxLength),
                  ...?widget.inputFormatters,
                ],
                onChanged: widget.onChanged,
                style: KText.paragraphLarge,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: KText.paragraphLarge.copyWith(color: widget.hintColor ?? KColors.textPlaceholder),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (widget.obscure)
              Semantics(
                button: true,
                label: _hidden ? 'Show password' : 'Hide password',
                child: InkResponse(
                  radius: 20,
                  onTap: () => setState(() => _hidden = !_hidden),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(_hidden ? PhosphorIconsRegular.eyeSlash : PhosphorIconsRegular.eye, size: 24, color: KColors.iconDefault),
                  ),
                ),
              ),
            if (widget.suffix != null) widget.suffix!,
          ]),
        ),
        if (hasError) Padding(padding: const EdgeInsets.only(top: 10), child: FieldHint(widget.error!)),
      ],
    );
  }
}

/// Figma input "Hint" in its error colour: Inter 12/16, no icon.
/// Figma "Control buttons / Radio button / Small".
class KRadio extends StatelessWidget {
  const KRadio({super.key, required this.selected});
  final bool selected;
  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 24,
        child: Center(
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? KColors.textPrimary : KColors.borderStrong, width: 1.5)),
            alignment: Alignment.center,
            child: selected ? Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: KColors.textPrimary)) : null,
          ),
        ),
      );
}

/// Figma "Control buttons / Checkbox / Small": 18pt box in a 24pt slot.
class KCheckbox extends StatelessWidget {
  const KCheckbox({super.key, required this.value, this.enabled = true});
  final bool value;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final on = enabled ? KColors.textPrimary : KColors.surfaceMuted;
    return SizedBox.square(
      dimension: 24,
      child: Center(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: value ? on : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: value ? on : (enabled ? KColors.borderStrong : KColors.surfaceMuted), width: 1.5),
          ),
          child: value ? Icon(PhosphorIconsBold.check, size: 12, color: enabled ? KColors.textInverse : KColors.surfaceDefault) : null,
        ),
      ),
    );
  }
}

/// A page drawn as a Figma bottom sheet over the screen that opened it:
/// 75% black scrim, grabber, 18pt title with a close X, scrolling content
/// and a bottom action bar. Route it with an opaque: false page.
class KeysSheetPage extends StatelessWidget {
  const KeysSheetPage({super.key, this.title, required this.child, required this.bottom, this.onClose, this.contentPadding = const EdgeInsets.fromLTRB(20, 8, 20, 20)});
  final String? title;
  final Widget child;
  final Widget bottom;
  final VoidCallback? onClose;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    final close = onClose ?? () => Navigator.of(context).maybePop();
    return Material(
      color: Colors.black.withValues(alpha: 0.75),
      child: Column(children: [
        Expanded(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: close, child: const SizedBox.expand())),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - MediaQuery.paddingOf(context).top - 24),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: KColors.surfaceDefault, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 8),
              Container(width: 48, height: 4, decoration: BoxDecoration(color: KColors.surfaceSubtle, borderRadius: BorderRadius.circular(100))),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Text(title ?? '', style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w500, height: 1, letterSpacing: -0.2, color: KColors.textPrimary)),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close',
                    child: InkResponse(radius: 20, onTap: close, child: SizedBox.square(dimension: 36, child: Icon(PhosphorIconsRegular.x, size: 20, color: KColors.iconDefault))),
                  ),
                ]),
              ),
              Flexible(child: SingleChildScrollView(padding: contentPadding, child: child)),
              Container(
                decoration: BoxDecoration(color: KColors.surfaceDefault, border: Border(top: BorderSide(color: KColors.borderDefault))),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: SafeArea(top: false, child: bottom),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Red ring with a cross, the pair of [SuccessMark] (Figma "Failed").
class FailMark extends StatelessWidget {
  const FailMark({super.key, this.size = 120});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: KColors.error, width: size / 20)),
        child: Icon(PhosphorIconsBold.x, size: size * 0.45, color: KColors.error),
      );
}

/// Rounded rectangle with a dashed outline (upload areas).
class DashedBox extends StatelessWidget {
  const DashedBox({super.key, required this.child, this.color, this.radius = 16});
  final Widget child;
  final Color? color;
  final double radius;
  @override
  Widget build(BuildContext context) => CustomPaint(foregroundPainter: _DashPainter(color ?? KColors.textSecondary, radius), child: child);
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color, this.radius);
  final Color color;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 8) {
        canvas.drawPath(m.extractPath(d, (d + 4).clamp(0, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// Figma "Success icon": 120pt green ring with a double tick.
class SuccessMark extends StatelessWidget {
  const SuccessMark({super.key, this.size = 120});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: KColors.success, width: size / 20)),
        child: Icon(PhosphorIconsBold.checks, size: size * 0.4, color: KColors.success),
      );
}

class FieldHint extends StatelessWidget {
  const FieldHint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(liveRegion: true, child: Text(text, style: KText.paragraphSmall.copyWith(color: KColors.error)));
}

class ErrorLine extends StatelessWidget {
  const ErrorLine(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: EdgeInsets.only(top: 1), child: Icon(PhosphorIconsRegular.warningCircle, size: 16, color: KColors.error)),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: KText.paragraphSmall.copyWith(color: KColors.error, fontSize: 13, height: 18 / 13))),
        ]),
      );
}

/// Six single-digit boxes (ONB-07, ONB-10). Calls [onCompleted] when the 6th
/// digit is typed.
class CodeInput extends StatefulWidget {
  const CodeInput({super.key, required this.onCompleted, this.error, this.length = 6, this.controller});
  final ValueChanged<String> onCompleted;
  final String? error;
  final int length;
  final TextEditingController? controller;
  @override
  State<CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<CodeInput> {
  late final TextEditingController _c = widget.controller ?? TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;
    return Column(children: [
      SizedBox(
        height: 48,
        child: Stack(children: [
          // The six boxes only draw; the transparent field on top owns the
          // keyboard, paste, one-time-code autofill and screen readers.
          IgnorePointer(
            child: ValueListenableBuilder(
              valueListenable: _c,
              builder: (_, v, _) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.length, (i) {
                  final ch = i < v.text.length ? v.text[i] : '';
                  final active = i == v.text.length && _focus.hasFocus;
                  // Figma "Code input": 48 square, radius 12, surface/subtle.
                  return Container(
                    width: 48,
                    height: 48,
                    margin: EdgeInsets.only(left: i == 0 ? 0 : 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: KColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(KRadius.md),
                      border: Border.all(color: hasError ? KColors.error : active ? KColors.borderStrong : Colors.transparent),
                    ),
                    child: Text(ch, style: KText.paragraphMediumLarge.copyWith(fontSize: 18)),
                  );
                }),
              ),
            ),
          ),
          Positioned.fill(
            child: Semantics(
              label: 'Verification code',
              child: TextField(
                key: const Key('code-field'),
                controller: _c,
                focusNode: _focus,
                autofocus: true,
                showCursor: false,
                enableInteractiveSelection: false,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                style: const TextStyle(color: Colors.transparent, fontSize: 1),
                decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(widget.length)],
                onTap: () => setState(() {}),
                onChanged: (v) {
                  setState(() {});
                  if (v.length == widget.length) widget.onCompleted(v);
                },
              ),
            ),
          ),
        ]),
      ),
      if (hasError) Padding(padding: const EdgeInsets.only(top: 12), child: ErrorLine(widget.error!)),
    ]);
  }
}

/// Live password rules (ONB-08.2, ONB-10.3).
class PasswordRules extends StatelessWidget {
  const PasswordRules({super.key, required this.password, this.showErrors = false, this.large = false});
  /// 14pt rules in text/secondary, as on the reset-password screen.
  final bool large;
  final String password;
  static const rules = ['Between 8-15 characters', 'Contain letters and numbers', 'At least one special character'];
  static List<bool> check(String p) => [
        p.length >= 8 && p.length <= 15,
        RegExp('[A-Za-z]').hasMatch(p) && RegExp(r'\d').hasMatch(p),
        RegExp(r'[^A-Za-z0-9]').hasMatch(p),
      ];
  static bool ok(String p) => check(p).every((e) => e);

  /// After a failed submit, unmet rules turn red with a cross.
  final bool showErrors;

  @override
  Widget build(BuildContext context) {
    final c = check(password);
    // Figma "Password requirement": 11pt icon, 5 gap, Inter 12/16.
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(rules.length, (i) {
          final pass = c[i];
          final fail = showErrors && !pass;
          final color = pass ? KColors.success : fail ? KColors.error : large ? KColors.textSecondary : KColors.textPlaceholder;
          return Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 5, left: large ? 16 : 0),
            child: Row(children: [
              SizedBox.square(
                dimension: 11,
                child: Center(
                  child: pass
                      ? Icon(PhosphorIconsBold.check, size: 11, color: color)
                      : fail
                          ? Icon(PhosphorIconsRegular.x, size: 11, color: color)
                          : Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 0.8))),
                ),
              ),
              const SizedBox(width: 5),
              Text(rules[i], style: (large ? KText.paragraphMedium : KText.paragraphSmall).copyWith(color: color)),
            ]),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------- media

enum MarkBadge { check, cross }

class CircleImage extends StatelessWidget {
  const CircleImage(this.asset, {super.key, this.size = 140, this.badge});
  final String asset;
  final double size;
  final MarkBadge? badge;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        ClipOval(child: Image.asset(asset, width: size, height: size, fit: BoxFit.cover)),
        // Figma "Approved": 72pt white disc (for a 140 image) holding a 60pt
        // filled check or cross, 14 past the top-right edge.
        if (badge != null)
          Positioned(
            right: -size * 0.1,
            top: -size * 0.1,
            child: Container(
              width: size * 72 / 140,
              height: size * 72 / 140,
              decoration: BoxDecoration(color: KColors.surfaceDefault, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(badge == MarkBadge.check ? PhosphorIconsFill.checkCircle : PhosphorIconsFill.xCircle, color: badge == MarkBadge.check ? KColors.success : KColors.error, size: size * 60 / 140),
            ),
          ),
      ]),
    );
  }
}

/// Square-ish card with a round illustration (area kind, home type).
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({super.key, required this.asset, required this.title, required this.subtitle, required this.selected, required this.onTap});
  final String asset;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      selected: selected,
      button: true,
      label: '$title. $subtitle',
      // Figma card (1300:185987): radius 16, padding 16, 120 image, 20 gap,
      // Inter Medium 16 title, 12/16 placeholder-grey description.
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: KColors.surfaceDefault,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? const Color(0xFF008080) : KColors.surfaceSubtle, width: selected ? 2 : 1),
          ),
          child: ExcludeSemantics(
            child: Column(children: [
              ClipOval(child: Image.asset(asset, width: 120, height: 120, fit: BoxFit.cover)),
              const SizedBox(height: 20),
              Text(title, textAlign: TextAlign.center, style: KText.paragraphMediumLarge),
              const SizedBox(height: 2),
              Text(subtitle, textAlign: TextAlign.center, style: KText.paragraphSmall.copyWith(color: KColors.textPlaceholder)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Row option with a radio mark (community list, building list).
class OptionTile extends StatelessWidget {
  const OptionTile({super.key, required this.title, this.subtitle, this.leading, required this.selected, required this.onTap, this.overline});
  final String title;
  final String? subtitle;
  final String? overline;
  final Widget? leading;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(KRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: KColors.surfaceDefault,
            borderRadius: BorderRadius.circular(KRadius.md),
            border: Border.all(color: selected ? KColors.selected : KColors.borderDefault, width: selected ? 2 : 1),
          ),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (overline != null) Text(overline!, style: KText.overline),
                Text(title, style: KText.paragraphMediumLarge),
                if (subtitle != null) Text(subtitle!, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary)),
              ]),
            ),
            Icon(selected ? PhosphorIconsFill.radioButton : PhosphorIconsRegular.circle, color: selected ? KColors.selected : KColors.textTertiary),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- feedback

void showToast(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, textColor: KColors.brand, onPressed: onAction ?? () {}),
      duration: const Duration(seconds: 3),
    ));
}

/// The KEYS wordmark, exported from Figma.
/// Google "G" mark drawn in code (brand asset could not be exported).
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key, this.size = 20});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _GPainter());
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final stroke = s.width * 0.2;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s.width - stroke, s.height - stroke);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, -math.pi * 0.25, -math.pi * 0.5, false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, -math.pi * 0.75, -math.pi * 0.5, false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, math.pi * 0.75, -math.pi * 0.75, false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, 0, math.pi * 0.25 * -1 + math.pi * 0.25, false, p(const Color(0xFF4285F4)));
    canvas.drawArc(rect, 0, math.pi * 0.25, false, p(const Color(0xFF4285F4)));
    canvas.drawLine(Offset(s.width / 2, s.height / 2), Offset(s.width - stroke / 2, s.height / 2), p(const Color(0xFF4285F4))..strokeWidth = stroke * 0.9);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Runs an async action with a busy flag and maps API errors to a message.
mixin Busy<T extends StatefulWidget> on State<T> {
  bool busy = false;
  Future<R?> run<R>(Future<R> Function() fn, {void Function(Object e)? onError}) async {
    if (busy) return null;
    setState(() => busy = true);
    try {
      return await fn();
    } catch (e) {
      if (onError != null) {
        onError(e);
      } else if (mounted) {
        showToast(context, e is ApiException ? e.message : 'Something went wrong. Please try again.');
      }
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}


/// Figma iOS "Switch": 60x36 here (track #E8E8E8 off, surface-inverted on),
/// white knob with the design's two shadows.
class KSwitch extends StatelessWidget {
  const KSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        enabled: onChanged != null,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 60,
            height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: value ? KColors.surfaceInverted : KColors.surfaceMuted, borderRadius: BorderRadius.circular(18)),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: KColors.isDark && value ? KColors.staticBlack : KColors.staticWhite,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x33171717), width: 0.5),
                  boxShadow: const [
                    BoxShadow(color: Color(0x26000000), offset: Offset(0, 3), blurRadius: 8),
                    BoxShadow(color: Color(0x29000000), offset: Offset(0, 1), blurRadius: 1),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
