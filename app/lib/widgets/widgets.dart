import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api.dart';
import '../theme/tokens.dart';

// ---------------------------------------------------------------- layout

/// Standard onboarding page: back + progress header, scrolling body, pinned
/// buttons at the bottom, white to brand-subtle background.
class KeysScaffold extends StatelessWidget {
  const KeysScaffold({super.key, this.header, required this.body, this.bottom, this.gradient = true, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16)});
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
              Expanded(child: SingleChildScrollView(padding: padding, child: body)),
              if (bottom != null) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: bottom!),
            ],
          ),
        )),
      ),
    );
  }
}

class KeysHeader extends StatelessWidget {
  const KeysHeader({super.key, this.onBack, this.progress, this.showBack = true, this.trailing});
  final VoidCallback? onBack;
  final double? progress;
  final bool showBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 44,
            child: Row(children: [
              if (showBack)
                IconButton(
                  key: const Key('back'),
                  tooltip: 'Back',
                  icon: const Icon(Icons.chevron_left, size: 30, color: KColors.iconDefault),
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                ),
              const Spacer(),
              ?trailing,
            ]),
          ),
          if (progress != null) Padding(padding: const EdgeInsets.fromLTRB(8, 8, 0, 8), child: ProgressBar(value: progress!)),
        ],
      ),
    );
  }
}

/// Onboarding progress: orange to yellow gradient on a light track.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value});
  final double value;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Progress',
      value: '${(value * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KRadius.pill),
        child: SizedBox(
          height: 6,
          child: Stack(children: [
            Container(color: KColors.borderDefault),
            FractionallySizedBox(
              widthFactor: value.clamp(0, 1),
              child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [KColors.progressStart, KColors.progressEnd]))),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Overline + heading + description block used at the top of most screens.
class Intro extends StatelessWidget {
  const Intro({super.key, this.overline, required this.title, this.body, this.center = false});
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
        if (overline != null) ...[Text(overline!.toUpperCase(), style: KText.overline, textAlign: align), const SizedBox(height: 8)],
        Text(title, style: KText.headingMedium, textAlign: align),
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
      ButtonVariant.primary => (enabled ? KColors.surfaceInverted : KColors.surfaceInverted.withValues(alpha: 0.25), KColors.textInverse, null),
      ButtonVariant.secondary => (KColors.surfaceMuted, enabled ? KColors.textPrimary : KColors.textTertiary, null),
      ButtonVariant.outline => (Colors.transparent, enabled ? KColors.textPrimary : KColors.textTertiary, KColors.borderStrong),
      ButtonVariant.ghost => (Colors.transparent, enabled ? KColors.textPrimary : KColors.textTertiary, null),
      ButtonVariant.light => (KColors.surfaceDefault, KColors.textPrimary, null),
    };
    return Semantics(
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
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
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
    this.error,
    this.obscure = false,
    this.maxLength,
    this.maxLines = 1,
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
  final String? error;
  final bool obscure;
  final int? maxLength;
  final int maxLines;
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
        if (widget.label != null || widget.maxLength != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              if (widget.label != null) Expanded(child: Text(widget.label!, style: KText.paragraphMediumLarge)),
              if (widget.maxLength != null)
                ValueListenableBuilder(
                  valueListenable: widget.controller,
                  builder: (_, v, _) => Text('${v.text.characters.length}/${widget.maxLength}', style: KText.paragraphSmall.copyWith(color: KColors.textSecondary)),
                ),
            ]),
          ),
        Container(
          decoration: BoxDecoration(
            color: widget.enabled ? KColors.surfaceSubtle : KColors.surfaceMuted,
            borderRadius: BorderRadius.circular(KRadius.sm),
            border: Border.all(color: hasError ? KColors.error : Colors.transparent),
          ),
          padding: const EdgeInsets.only(left: 12, right: 8),
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(children: [
            Expanded(
              child: TextField(
                key: widget.fieldKey,
                controller: widget.controller,
                enabled: widget.enabled,
                obscureText: _hidden,
                maxLines: widget.obscure ? 1 : widget.maxLines,
                minLines: 1,
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
                  hintStyle: KText.paragraphLarge.copyWith(color: KColors.textTertiary),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (widget.obscure)
              IconButton(
                tooltip: _hidden ? 'Show password' : 'Hide password',
                icon: Icon(_hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: KColors.textSecondary),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            if (widget.suffix != null) widget.suffix!,
          ]),
        ),
        if (hasError) Padding(padding: const EdgeInsets.only(top: 6), child: ErrorLine(widget.error!)),
      ],
    );
  }
}

class ErrorLine extends StatelessWidget {
  const ErrorLine(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.error_outline, size: 16, color: KColors.error)),
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
        height: 52,
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
                  return Container(
                    width: 46,
                    height: 52,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: KColors.surfaceDefault,
                      borderRadius: BorderRadius.circular(KRadius.sm),
                      border: Border.all(color: hasError ? KColors.error : active ? KColors.borderStrong : KColors.borderDefault),
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
  const PasswordRules({super.key, required this.password});
  final String password;
  static const rules = ['Between 8-15 characters', 'Contain letters and numbers', 'At least one special character'];
  static List<bool> check(String p) => [
        p.length >= 8 && p.length <= 15,
        RegExp('[A-Za-z]').hasMatch(p) && RegExp(r'\d').hasMatch(p),
        RegExp(r'[^A-Za-z0-9]').hasMatch(p),
      ];
  static bool ok(String p) => check(p).every((e) => e);

  @override
  Widget build(BuildContext context) {
    final c = check(password);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(rules.length, (i) {
        final pass = c[i];
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(pass ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: pass ? KColors.success : KColors.textTertiary),
            const SizedBox(width: 8),
            Text(rules[i], style: KText.paragraphSmall.copyWith(color: pass ? KColors.success : KColors.textSecondary, fontSize: 13)),
          ]),
        );
      }),
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
        if (badge != null)
          Positioned(
            right: -size * 0.06,
            top: -size * 0.02,
            child: Container(
              width: size * 0.43,
              height: size * 0.43,
              decoration: const BoxDecoration(color: KColors.surfaceDefault, shape: BoxShape.circle),
              padding: EdgeInsets.all(size * 0.04),
              child: Container(
                decoration: BoxDecoration(color: badge == MarkBadge.check ? KColors.success : KColors.error, shape: BoxShape.circle),
                child: Icon(badge == MarkBadge.check ? Icons.check_rounded : Icons.close_rounded, color: Colors.white, size: size * 0.24),
              ),
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
      selected: selected,
      button: true,
      label: '$title. $subtitle',
      child: InkWell(
        borderRadius: BorderRadius.circular(KRadius.md),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          decoration: BoxDecoration(
            color: KColors.surfaceDefault,
            borderRadius: BorderRadius.circular(KRadius.md),
            border: Border.all(color: selected ? KColors.selected : KColors.borderDefault, width: selected ? 2 : 1),
          ),
          child: ExcludeSemantics(
            child: Column(children: [
              ClipOval(child: Image.asset(asset, width: 110, height: 110, fit: BoxFit.cover)),
              const SizedBox(height: 14),
              Text(title, style: KText.paragraphMediumLarge.copyWith(fontSize: 17)),
              const SizedBox(height: 4),
              Text(subtitle, textAlign: TextAlign.center, style: KText.paragraphMedium.copyWith(color: KColors.textSecondary, fontSize: 13)),
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
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? KColors.selected : KColors.textTertiary),
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
class KeysLogo extends StatelessWidget {
  const KeysLogo({super.key, this.height = 28});
  final double height;
  @override
  Widget build(BuildContext context) => Semantics(label: 'Keys', child: Image.asset('assets/images/keys_logo.png', height: height));
}

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
