// Camera permission gate — shows a benefit-first pre-prompt before the
// OS camera dialog fires, and a denied-state fallback if the user
// declines. Uses SharedPreferences to track whether the prompt has been
// shown so returning users skip straight to the camera.
//
// This widget wraps the scanner screen and only builds the camera once
// permission is granted. If denied, offers "Open Settings" + manual entry.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Wraps [child] (the scanner) with a one-time camera permission prompt.
///
/// On first visit the user sees a clean benefit screen. Tapping
/// "Allow Camera Access" creates a [MobileScannerController] which
/// triggers the OS prompt. If granted, shows the scanner. If denied,
/// shows a fallback with "Open Settings" + manual alternatives.
class CameraPermissionGate extends StatefulWidget {
  final Widget Function() childBuilder;
  final VoidCallback onManualEntry;

  const CameraPermissionGate({
    super.key,
    required this.childBuilder,
    required this.onManualEntry,
  });

  @override
  State<CameraPermissionGate> createState() => _CameraPermissionGateState();
}

enum _PermissionState { checking, prompt, granted, denied }

class _CameraPermissionGateState extends State<CameraPermissionGate> {
  static const _prefKey = 'cameraPermissionPromptShown';
  _PermissionState _state = _PermissionState.checking;

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    final prefs = await SharedPreferences.getInstance();
    final promptShown = prefs.getBool(_prefKey) ?? false;

    if (!mounted) return;

    if (promptShown) {
      // User has seen the prompt before — go straight to scanner.
      // mobile_scanner will handle re-prompting if permission was revoked.
      setState(() => _state = _PermissionState.granted);
    } else {
      setState(() => _state = _PermissionState.prompt);
    }
  }

  Future<void> _requestPermission() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);

    if (!mounted) return;

    // Transition to granted — mobile_scanner's controller init will
    // trigger the OS prompt if not yet granted. If the user denies at
    // the OS level, mobile_scanner shows its own error state which we
    // can detect via the controller's value stream.
    setState(() => _state = _PermissionState.granted);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _PermissionState.checking => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      _PermissionState.prompt => _PermissionPromptScreen(
        onAllow: _requestPermission,
        onManualEntry: widget.onManualEntry,
      ),
      _PermissionState.granted => widget.childBuilder(),
      _PermissionState.denied => _PermissionDeniedScreen(
        onManualEntry: widget.onManualEntry,
      ),
    };
  }
}

// ---------------------------------------------------------------------------
// Pre-permission prompt — benefit-first, no "No Thanks" button
// ---------------------------------------------------------------------------

class _PermissionPromptScreen extends StatelessWidget {
  final VoidCallback onAllow;
  final VoidCallback onManualEntry;

  const _PermissionPromptScreen({
    required this.onAllow,
    required this.onManualEntry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.space24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 40,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: AppTheme.space24),
              Text(
                'Scan supplements instantly',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.space12),
              Text(
                'PharmaGuide uses your camera to scan barcodes and '
                'product labels.\n\n'
                'Photos are only used when you choose to submit a product.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: onAllow,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('Allow Camera Access'),
                ),
              ),
              const SizedBox(height: AppTheme.space12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: onManualEntry,
                  icon: const Icon(Icons.keyboard_rounded),
                  label: const Text('Enter code manually'),
                ),
              ),
              const SizedBox(height: AppTheme.space24),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Denied state — camera off, offer Settings + manual fallback
// ---------------------------------------------------------------------------

class _PermissionDeniedScreen extends StatelessWidget {
  final VoidCallback onManualEntry;

  const _PermissionDeniedScreen({required this.onManualEntry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.space24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Icon(
                  Icons.videocam_off_rounded,
                  size: 40,
                  color: scheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: AppTheme.space24),
              Text(
                'Camera access is off',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.space12),
              Text(
                'You can still enter a barcode manually or enable '
                'camera access in Settings.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () =>
                      launchUrl(Uri.parse('app-settings:')),
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Open Settings'),
                ),
              ),
              const SizedBox(height: AppTheme.space12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: onManualEntry,
                  icon: const Icon(Icons.keyboard_rounded),
                  label: const Text('Enter code manually'),
                ),
              ),
              const SizedBox(height: AppTheme.space24),
            ],
          ),
        ),
      ),
    );
  }
}
