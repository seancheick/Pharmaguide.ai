// Camera permission gate — shows a benefit-first pre-prompt before the
// OS camera dialog fires, and a denied-state fallback if the user
// declines. Uses SharedPreferences to track whether the prompt has been
// shown so returning users skip straight to the camera.
//
// This widget wraps the scanner screen and only builds the camera once
// permission is granted. If denied, offers "Open Settings" + manual entry.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/scanner/v2/camera_permission_v2_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

enum _PermissionState { checking, prompt, granted }

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
      _PermissionState.checking => const _CameraPermissionCheckingScreen(),
      // Phase 11.7j.1 — prompt + denied states use the v2 component
      // (same callback shape, cream surface + halo + serif headline).
      // Legacy `_PermissionPromptScreen` / `_PermissionDeniedScreen`
      // widgets have been deleted; the switch arms below delegate
      // directly to `CameraPermissionV2Screen`.
      _PermissionState.prompt => CameraPermissionV2Screen(
        denied: false,
        onPrimaryAction: _requestPermission,
        onManualEntry: widget.onManualEntry,
      ),
      _PermissionState.granted => widget.childBuilder(),
    };
  }
}

class _CameraPermissionCheckingScreen extends StatelessWidget {
  const _CameraPermissionCheckingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(V2Spacing.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: context.v2.accent,
                  ),
                ),
                const SizedBox(height: V2Spacing.space16),
                Text(
                  'Checking camera access',
                  style: V2Typography.titleSm(color: context.v2.fg),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: V2Spacing.space8),
                Text(
                  'Preparing the scanner.',
                  style: V2Typography.bodySm(color: context.v2.fgMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
