import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_halo_background.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 camera permission gate — visual mirror of
/// `CameraPermissionGate._PermissionPromptScreen`.
///
/// Two states: prompt (first launch — benefit-first ask) and denied
/// (camera turned down — offer Settings + manual fallback).
///
/// v2 changes vs production:
///   - Cream bg with soft accent halo behind the icon well
///   - Icon well: 96pt rounded square with accent tint, layered shadow
///   - Newsreader serif headline (first-impression context allowed)
///   - Three calm benefit bullets between headline and primary CTA
///     (production has one paragraph blob — bullets scan faster)
///   - PGPillButton primary for "Allow Camera Access", secondary for
///     "Enter code manually"
///
/// Production wiring: replaces `_PermissionPromptScreen` /
/// `_PermissionDeniedScreen` builders in CameraPermissionGate; the
/// callback shape is identical.
class CameraPermissionV2Screen extends StatelessWidget {
  /// True → "denied" copy + "Open Settings" primary action.
  /// False → "first ask" copy + "Allow Camera Access" primary action.
  final bool denied;

  final VoidCallback onPrimaryAction;
  final VoidCallback onManualEntry;

  /// Optional close affordance (gallery preview wires this; production
  /// leaves it null — back-nav handled by GoRouter).
  final VoidCallback? onClose;

  const CameraPermissionV2Screen({
    super.key,
    this.denied = false,
    required this.onPrimaryAction,
    required this.onManualEntry,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final headline = denied
        ? 'Camera access is off'
        : 'Scan supplements\ninstantly';
    final body = denied
        ? "Without camera access, we can't read barcodes. "
            "Re-enable it in Settings, or enter codes by hand."
        : 'PharmaGuide uses your camera to read product barcodes. '
            'Nothing is stored unless you choose to submit a product.';
    final primaryLabel = denied ? 'Open Settings' : 'Allow camera access';
    final primaryIcon =
        denied ? Icons.settings_rounded : Icons.camera_alt_rounded;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: V2Colors.bg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: V2Colors.bg,
        body: PGHaloBackground(
          origin: const Alignment(0, -0.45),
          radius: 1.0,
          intensity: 0.05,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space24,
              ),
              child: Column(
                children: [
                  if (onClose != null)
                    Align(
                      alignment: Alignment.topRight,
                      child: _CloseChip(onTap: onClose!),
                    ),
                  const Spacer(flex: 2),
                  _IconWell(denied: denied),
                  const SizedBox(height: V2Spacing.space24),
                  PGEyebrow(
                    denied ? 'Permission needed' : 'Camera access',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: V2Spacing.space12),
                  Text(
                    headline,
                    textAlign: TextAlign.center,
                    style: V2Typography.displayXs(color: V2Colors.fg),
                  ),
                  const SizedBox(height: V2Spacing.space12),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: V2Spacing.space12,
                    ),
                    child: Text(
                      body,
                      textAlign: TextAlign.center,
                      style: V2Typography.body(color: V2Colors.fgMuted),
                    ),
                  ),
                  if (!denied) ...[
                    const SizedBox(height: V2Spacing.space24),
                    const _BenefitBullets(),
                  ],
                  const Spacer(flex: 3),
                  PGPillButton(
                    label: primaryLabel,
                    icon: primaryIcon,
                    expand: true,
                    onPressed: onPrimaryAction,
                  ),
                  const SizedBox(height: V2Spacing.space12),
                  PGPillButton(
                    label: 'Enter code manually',
                    icon: Icons.keyboard_rounded,
                    variant: PGPillVariant.secondary,
                    expand: true,
                    onPressed: onManualEntry,
                  ),
                  const SizedBox(height: V2Spacing.space24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconWell extends StatefulWidget {
  final bool denied;
  const _IconWell({required this.denied});

  @override
  State<_IconWell> createState() => _IconWellState();
}

class _IconWellState extends State<_IconWell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: V2Motion.slowest,
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.denied ? V2Colors.caution : V2Colors.accent;
    final tint = widget.denied
        ? V2Colors.caution.withValues(alpha: 0.12)
        : V2Colors.accentTint;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = V2Motion.spring.transform(_ctrl.value.clamp(0.0, 1.0));
        final scale = 0.85 + (t * 0.15);
        return Transform.scale(
          scale: scale,
          child: Opacity(opacity: _ctrl.value, child: child),
        );
      },
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(
            color: tone.withValues(alpha: 0.22),
            width: 0.8,
          ),
          boxShadow: V2Shadows.md,
        ),
        child: Icon(
          widget.denied
              ? Icons.no_photography_rounded
              : Icons.qr_code_scanner_rounded,
          color: tone,
          size: 42,
        ),
      ),
    );
  }
}

class _BenefitBullets extends StatelessWidget {
  const _BenefitBullets();

  static const _bullets = <(IconData, String)>[
    (Icons.bolt_rounded, 'Instant product recognition'),
    (Icons.shield_outlined, 'On-device match — no upload'),
    (Icons.medical_information_outlined, 'Personalized safety check'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (icon, label) in _bullets) ...[
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: V2Colors.accentTint,
                  borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 14, color: V2Colors.accent),
              ),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: Text(
                  label,
                  style: V2Typography.body(color: V2Colors.fg),
                ),
              ),
            ],
          ),
          if (label != _bullets.last.$2)
            const SizedBox(height: V2Spacing.space12),
        ],
      ],
    );
  }
}

class _CloseChip extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Colors.surface,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: V2Colors.outline),
          ),
          child: const Icon(
            Icons.close_rounded,
            color: V2Colors.fg,
            size: 18,
          ),
        ),
      ),
    );
  }
}

/// Gallery preview wrapper. Pass `?denied=1` query param to flip into
/// the denied state.
class CameraPermissionV2Preview extends StatelessWidget {
  final bool denied;
  const CameraPermissionV2Preview({super.key, this.denied = false});

  @override
  Widget build(BuildContext context) {
    return CameraPermissionV2Screen(
      denied: denied,
      onPrimaryAction: () => context.go('/dev/v2'),
      onManualEntry: () => context.go('/dev/v2'),
      onClose: () => context.go('/dev/v2'),
    );
  }
}
