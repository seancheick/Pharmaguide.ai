import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';

/// Premium search field with animated focus ring and icon.
///
/// Use [readOnly] + [onTap] to make it a "tap to open search screen" launcher
/// (the most common pattern on the home screen), or omit both for a real
/// text input.
class PGSearchField extends StatefulWidget {
  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool autofocus;
  final Widget? leading;
  final Widget? trailing;

  const PGSearchField({
    super.key,
    this.hintText = 'Search supplements…',
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.readOnly = false,
    this.autofocus = false,
    this.leading,
    this.trailing,
  });

  @override
  State<PGSearchField> createState() => _PGSearchFieldState();
}

class _PGSearchFieldState extends State<PGSearchField> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final container = AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.standard,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color: _focused ? scheme.primary : scheme.outlineVariant,
          width: _focused ? 1.4 : 0.8,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 2),
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: Row(
        children: [
          const SizedBox(width: AppTheme.space16),
          widget.leading ??
              Icon(
                Icons.search_rounded,
                size: 20,
                color: _focused ? scheme.primary : scheme.onSurfaceVariant,
              ),
          const SizedBox(width: AppTheme.space12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              readOnly: widget.readOnly,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              onTap: widget.onTap,
              style: theme.textTheme.bodyLarge,
              cursorColor: scheme.primary,
              cursorWidth: 1.6,
              cursorRadius: const Radius.circular(2),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                filled: false,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                hintText: widget.hintText,
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: AppTheme.space8),
            widget.trailing!,
            const SizedBox(width: AppTheme.space12),
          ] else
            const SizedBox(width: AppTheme.space16),
        ],
      ),
    );

    // Read-only launcher path: wrap with PGPressable so the whole surface
    // gets the iOS press feel — a 0.99 micro-scale + spring release. No
    // haptic on tap-down because the destination search screen owns the
    // entry haptic; firing one here would double-tap the user. The
    // micro-scale is intentionally subtle (0.99 vs the 0.96 default for
    // standalone cards) — the search field is top chrome, not a content
    // card, so it should compress just enough to register as live.
    if (widget.readOnly && widget.onTap != null) {
      return PGPressable(
        onTap: widget.onTap,
        haptic: false,
        pressedScale: 0.99,
        child: container,
      );
    }

    return container;
  }
}
