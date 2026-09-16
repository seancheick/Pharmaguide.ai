import 'dart:async';
import 'package:pharmaguide/core/navigation/root_navigator_key.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
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
  // Sentry PHARMAGUIDE-15: router-level callers can hand us a context
  // that is deactivated or above the Navigator. Fall back to the root
  // navigator key's live context rather than crashing.
  var hostContext = context;
  if (!hostContext.mounted ||
      Navigator.maybeOf(hostContext, rootNavigator: true) == null) {
    final rootContext = rootNavigatorKey.currentContext;
    if (rootContext == null) return Future<void>.value();
    hostContext = rootContext;
  }
  return showModalBottomSheet<void>(
    context: hostContext,
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
/// The email carries both a link and a one-time code. Tapping the link
/// only works on the device running the app, so the sent state also
/// takes the code (`verifyOTP`) for emails opened on a laptop or other
/// phone. Either path emits `signedIn`, which the app's auth listener
/// turns into navigation.
class MagicLinkSheet extends StatefulWidget {
  const MagicLinkSheet({super.key, this.sendLink, this.verifyCode});

  /// Sends the sign-in email. Null uses Supabase `signInWithOtp`.
  final Future<void> Function(String email)? sendLink;

  /// Exchanges the emailed code for a session. Null uses Supabase
  /// `verifyOTP`.
  final Future<void> Function(String email, String code)? verifyCode;

  @override
  State<MagicLinkSheet> createState() => _MagicLinkSheetState();
}

enum _SheetState { editing, sending, sent, error }

class _MagicLinkSheetState extends State<MagicLinkSheet> {
  final _controller = TextEditingController();
  final _codeController = TextEditingController();
  final _focusNode = FocusNode();
  _SheetState _state = _SheetState.editing;
  String? _errorMessage;
  bool _isVerifying = false;
  String? _codeError;

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
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isValidEmail => _emailRegex.hasMatch(_controller.text.trim());

  // Supabase email OTPs are 6 digits by default and configurable up to 10.
  static final _codeRegex = RegExp(r'^\d{6,10}$');

  String get _code => _codeController.text.replaceAll(RegExp(r'\s'), '');

  bool get _isValidCode => _codeRegex.hasMatch(_code);

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
    if (widget.sendLink == null && SupabaseConfig.isPlaceholder) {
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
      final sendLink = widget.sendLink;
      if (sendLink != null) {
        await sendLink(email);
      } else {
        await supabase.auth.signInWithOtp(
          email: email,
          emailRedirectTo: kAuthRedirectUrl,
        );
      }
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

  Future<void> _verify() async {
    if (!_isValidCode || _isVerifying) return;
    final email = _controller.text.trim();
    final code = _code;
    setState(() {
      _isVerifying = true;
      _codeError = null;
    });
    try {
      final verifyCode = widget.verifyCode;
      if (verifyCode != null) {
        await verifyCode(email, code);
      } else {
        await supabase.auth.verifyOTP(
          email: email,
          token: code,
          type: OtpType.email,
        );
      }
      unawaited(HapticFeedback.lightImpact());
      if (!mounted) return;
      setState(() => _isVerifying = false);
      await Navigator.of(context).maybePop();
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      setState(() {
        _isVerifying = false;
        _codeError = (msg.contains('rate') || msg.contains('too many'))
            ? 'Too many requests. Wait a minute and try again.'
            : 'That code is wrong or has expired. Check the latest email.';
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _codeError =
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
        decoration: BoxDecoration(
          color: context.v2.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                        color: context.v2.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: V2Spacing.space16),
                  if (_state == _SheetState.sent)
                    _SentBody(
                      email: _controller.text.trim(),
                      codeController: _codeController,
                      isCodeValid: _isValidCode,
                      isVerifying: _isVerifying,
                      codeError: _codeError,
                      onCodeChanged: () => setState(() => _codeError = null),
                      onVerify: _verify,
                    )
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
          style: V2Typography.titleSm(color: context.v2.fg),
        ),
        const SizedBox(height: V2Spacing.space8),
        Text(
          "We'll send you a one-tap sign-in link — no password needed.",
          style: V2Typography.body(color: context.v2.fgMuted),
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
            style: V2Typography.bodySm(color: context.v2.caution),
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
    final borderColor = hasError
        ? context.v2.caution.withValues(alpha: 0.45)
        : context.v2.outline;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.send,
      style: V2Typography.body(color: context.v2.fg),
      cursorColor: context.v2.accent,
      onChanged: (_) => onChanged(),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: 'you@email.com',
        hintStyle: V2Typography.body(color: context.v2.fgSubtle),
        filled: true,
        fillColor: context.v2.surface,
        prefixIcon: Icon(
          Icons.mail_outline_rounded,
          color: context.v2.fgMuted,
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
            color: hasError ? context.v2.caution : context.v2.accent,
            width: 1.3,
          ),
        ),
      ),
    );
  }
}

class _SentBody extends StatelessWidget {
  final String email;
  final TextEditingController codeController;
  final bool isCodeValid;
  final bool isVerifying;
  final String? codeError;
  final VoidCallback onCodeChanged;
  final Future<void> Function() onVerify;

  const _SentBody({
    required this.email,
    required this.codeController,
    required this.isCodeValid,
    required this.isVerifying,
    required this.codeError,
    required this.onCodeChanged,
    required this.onVerify,
  });

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
              color: context.v2.safe.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(
                color: context.v2.safe.withValues(alpha: 0.22),
                width: 0.8,
              ),
            ),
            child: Icon(
              Icons.mark_email_read_rounded,
              color: context.v2.safe,
              size: 34,
            ),
          ),
        ),
        const SizedBox(height: V2Spacing.space16),
        Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: V2Typography.titleSm(color: context.v2.fg),
        ),
        const SizedBox(height: V2Spacing.space8),
        Text(
          'We sent a sign-in link and code to $email. Tap the link on '
          'this phone, or enter the code below if you opened the email '
          'somewhere else. Both expire in 1 hour.',
          textAlign: TextAlign.center,
          style: V2Typography.body(color: context.v2.fgMuted),
        ),
        const SizedBox(height: V2Spacing.space24),
        _CodeField(
          controller: codeController,
          enabled: !isVerifying,
          hasError: codeError != null,
          onChanged: onCodeChanged,
          onSubmitted: (_) => onVerify(),
        ),
        if (codeError != null) ...[
          const SizedBox(height: V2Spacing.space8),
          Text(
            codeError!,
            textAlign: TextAlign.center,
            style: V2Typography.bodySm(color: context.v2.caution),
          ),
        ],
        const SizedBox(height: V2Spacing.space16),
        PGPillButton(
          label: isVerifying ? 'Verifying…' : 'Verify code',
          expand: true,
          onPressed: (isVerifying || !isCodeValid) ? null : onVerify,
        ),
        const SizedBox(height: V2Spacing.space12),
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

class _CodeField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool hasError;
  final VoidCallback onChanged;
  final ValueChanged<String> onSubmitted;

  const _CodeField({
    required this.controller,
    required this.enabled,
    required this.hasError,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? context.v2.caution.withValues(alpha: 0.45)
        : context.v2.outline;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          borderSide: BorderSide(color: color, width: width),
        );
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      autocorrect: false,
      enableSuggestions: false,
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      maxLength: 12,
      style: V2Typography.titleSm(color: context.v2.fg),
      cursorColor: context.v2.accent,
      onChanged: (_) => onChanged(),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: 'Code from email',
        hintStyle: V2Typography.body(color: context.v2.fgSubtle),
        counterText: '',
        filled: true,
        fillColor: context.v2.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.space16,
          vertical: V2Spacing.space12,
        ),
        border: border(borderColor),
        enabledBorder: border(borderColor),
        focusedBorder: border(
          hasError ? context.v2.caution : context.v2.accent,
          1.3,
        ),
      ),
    );
  }
}
