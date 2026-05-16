import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Deep link Supabase posts magic-link confirmations to. Must match
/// the URL scheme registered in Info.plist (iOS) + the intent-filter
/// in AndroidManifest.xml (Android). Phase 9.1b wires the redirect
/// handler; this sheet just hands the value to Supabase.
const String kAuthRedirectUrl = 'pharmaguide://auth/callback';

/// Opens the email magic-link sheet. Returns once the sheet is
/// dismissed.
///
/// **2026-05-16 (Sentry PHARMAGUIDE-W fix)**: `useRootNavigator: true`
/// anchors the sheet on the `MaterialApp.router` root navigator. The
/// previous form passed the GoRoute pageBuilder's context directly to
/// `showModalBottomSheet`, and on iOS 26.5 (iPhone 16 Pro) that
/// context's `Navigator.of` resolution returned null inside Flutter's
/// `Navigator.of` lookup, triggering `Null check operator used on a
/// null value`. Routing through the root navigator side-steps the
/// timing race and is the documented Flutter pattern for sheets
/// invoked from a router-level callback (see Flutter SDK
/// `bottom_sheet.dart` doc on `useRootNavigator`).
Future<void> showMagicLinkSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (ctx) => const MagicLinkSheet(),
  );
}

/// Email magic-link sheet — single email field + "Send magic link"
/// CTA + success morph. Calls `supabase.auth.signInWithOtp()` with
/// the [kAuthRedirectUrl] deep link.
///
/// Production wires the deep-link side of the round trip in Phase
/// 9.1b. For now, success state lands once Supabase confirms the
/// email send; the actual sign-in completes when the user taps the
/// link in their inbox.
class MagicLinkSheet extends StatefulWidget {
  const MagicLinkSheet({super.key});

  @override
  State<MagicLinkSheet> createState() => _MagicLinkSheetState();
}

enum _SheetState { editing, sending, sent, error }

class _MagicLinkSheetState extends State<MagicLinkSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  _SheetState _state = _SheetState.editing;
  String? _errorMessage;

  // Simple RFC-style email regex — Supabase will validate properly,
  // this is just to keep the obvious typos out of the network call.
  static final _emailRegex = RegExp(r'^[\w\.\-+]+@([\w\-]+\.)+[\w\-]{2,}$');

  @override
  void initState() {
    super.initState();
    // Autofocus once the sheet animation settles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isValidEmail =>
      _emailRegex.hasMatch(_controller.text.trim());

  Future<void> _send() async {
    final email = _controller.text.trim();
    if (!_emailRegex.hasMatch(email)) {
      setState(() {
        _state = _SheetState.error;
        _errorMessage = "That doesn't look like a complete email.";
      });
      return;
    }

    // Skip the network when Supabase isn't configured — surface a
    // friendly inline state instead of letting the SDK fail in a
    // confusing way during early dev / placeholder builds.
    if (SupabaseConfig.isPlaceholder) {
      setState(() {
        _state = _SheetState.error;
        _errorMessage =
            'Supabase is not configured in this build. Run with the '
            'real .env to test the magic link round trip.';
      });
      return;
    }

    setState(() {
      _state = _SheetState.sending;
      _errorMessage = null;
    });

    try {
      await supabase.auth.signInWithOtp(
        email: email,
        emailRedirectTo: kAuthRedirectUrl,
      );
      unawaited(HapticFeedback.lightImpact());
      if (!mounted) return;
      setState(() => _state = _SheetState.sent);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _SheetState.error;
        _errorMessage = _friendlyAuthMessage(e);
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _SheetState.error;
        _errorMessage =
            "We couldn't reach the network. Check your connection and "
            "try again.";
      });
    }
  }

  String _friendlyAuthMessage(AuthException e) {
    // Supabase rate-limits magic links per email; surface that
    // calmly instead of the raw error code.
    final msg = e.message.toLowerCase();
    if (msg.contains('rate') || msg.contains('too many')) {
      return 'Too many requests. Wait a minute and try again.';
    }
    if (msg.contains('invalid') && msg.contains('email')) {
      return "That email address isn't valid.";
    }
    return 'Something went wrong. Try again in a moment.';
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      // Lift the sheet above the on-screen keyboard so the field
      // stays visible while the user types.
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: V2Colors.bg,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
          boxShadow: V2Shadows.lg,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              V2Spacing.space24,
              V2Spacing.space12,
              V2Spacing.space24,
              V2Spacing.space24,
            ),
            child: AnimatedSize(
              duration: V2Motion.base,
              curve: V2Motion.emphasized,
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle.
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: V2Colors.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: V2Spacing.space16),
                  if (_state == _SheetState.sent)
                    _SentBody(email: _controller.text.trim())
                  else
                    _EditBody(
                      controller: _controller,
                      focusNode: _focusNode,
                      isValid: _isValidEmail,
                      isSending: _state == _SheetState.sending,
                      errorMessage: _errorMessage,
                      onChanged: () {
                        // Always rebuild so the "Send magic link" button
                        // can flip from disabled → enabled as the user
                        // types a valid address (parent owns isValid;
                        // without a setState here the button stays
                        // greyed out until something else triggers a
                        // rebuild). Also clears the error state on edit.
                        setState(() {
                          if (_state == _SheetState.error) {
                            _state = _SheetState.editing;
                            _errorMessage = null;
                          }
                        });
                      },
                      onSubmit: _send,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditBody extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isValid;
  final bool isSending;
  final String? errorMessage;
  final VoidCallback onChanged;
  final Future<void> Function() onSubmit;

  const _EditBody({
    required this.controller,
    required this.focusNode,
    required this.isValid,
    required this.isSending,
    required this.errorMessage,
    required this.onChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Continue with email',
          style: V2Typography.titleSm(color: V2Colors.fg),
        ),
        const SizedBox(height: V2Spacing.space8),
        Text(
          "We'll send you a one-tap sign-in link — no password needed.",
          style: V2Typography.body(color: V2Colors.fgMuted),
        ),
        const SizedBox(height: V2Spacing.space24),
        _EmailField(
          controller: controller,
          focusNode: focusNode,
          enabled: !isSending,
          hasError: errorMessage != null,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmit(),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: V2Spacing.space8),
          Text(
            errorMessage!,
            style: V2Typography.bodySm(color: V2Colors.caution),
          ),
        ],
        const SizedBox(height: V2Spacing.space16),
        PGPillButton(
          label: isSending ? 'Sending…' : 'Send magic link',
          icon: isSending ? null : Icons.send_rounded,
          expand: true,
          onPressed: (isSending || !isValid) ? null : onSubmit,
        ),
      ],
    );
  }
}

class _EmailField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool hasError;
  final VoidCallback onChanged;
  final ValueChanged<String> onSubmitted;

  const _EmailField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hasError,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        hasError ? V2Colors.caution.withValues(alpha: 0.45) : V2Colors.outline;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.send,
      style: V2Typography.body(color: V2Colors.fg),
      cursorColor: V2Colors.accent,
      onChanged: (_) => onChanged(),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: 'you@email.com',
        hintStyle: V2Typography.body(color: V2Colors.fgSubtle),
        filled: true,
        fillColor: V2Colors.surface,
        prefixIcon: const Icon(
          Icons.mail_outline_rounded,
          color: V2Colors.fgMuted,
          size: 20,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.space16,
          vertical: V2Spacing.space12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          borderSide: BorderSide(
            color: hasError ? V2Colors.caution : V2Colors.accent,
            width: 1.3,
          ),
        ),
      ),
    );
  }
}

class _SentBody extends StatelessWidget {
  final String email;
  const _SentBody({required this.email});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: V2Colors.safe.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(
                color: V2Colors.safe.withValues(alpha: 0.22),
                width: 0.8,
              ),
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              color: V2Colors.safe,
              size: 34,
            ),
          ),
        ),
        const SizedBox(height: V2Spacing.space16),
        Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: V2Typography.titleSm(color: V2Colors.fg),
        ),
        const SizedBox(height: V2Spacing.space8),
        Text(
          'We sent a sign-in link to $email. Tap the link to come back '
          'and finish signing in. It expires in 1 hour.',
          textAlign: TextAlign.center,
          style: V2Typography.body(color: V2Colors.fgMuted),
        ),
        const SizedBox(height: V2Spacing.space24),
        PGPillButton(
          label: 'Done',
          variant: PGPillVariant.secondary,
          expand: true,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
