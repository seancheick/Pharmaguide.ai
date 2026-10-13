import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_settings_tile.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/ai_share/ai_connections_repository.dart';
import 'package:pharmaguide/features/ai_share/ai_share_consent_screen.dart';
import 'package:pharmaguide/features/ai_share/ai_share_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/sharing/ai_share_prefs_store.dart';
import 'package:pharmaguide/services/sharing/report_text.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings → Connected AI assistants (ADR-009).
///
/// Connections are approved on the website; this screen lists them and is
/// where every sensitive share starts: the user picks a connection, chooses
/// what to include, previews the exact text and shares it. Guests see why
/// an account is needed and nothing is queried.
class AiConnectionsScreen extends ConsumerWidget {
  const AiConnectionsScreen({super.key, this.onSignIn, this.onOpenExternal});

  final VoidCallback? onSignIn;
  final Future<bool> Function(Uri uri)? onOpenExternal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authStateProvider) == AuthMode.signedIn;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Connected AI assistants',
          style: V2Typography.titleSm(color: context.v2.fg),
        ),
      ),
      body: SafeArea(
        child: signedIn
            ? _SignedInBody(onOpenExternal: onOpenExternal)
            : _GuestBody(
                onSignIn: onSignIn ?? () => context.push(Routes.authInvitation),
              ),
      ),
    );
  }
}

class _GuestBody extends StatelessWidget {
  const _GuestBody({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(V2Spacing.space24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hub_outlined, size: 36, color: context.v2.accent),
          const SizedBox(height: V2Spacing.space16),
          Text(
            'Sharing with an AI assistant needs a PharmaGuide account, so '
            'each share is tied to you and removed when you disconnect or '
            'sign out. Until then, everything stays on this device.',
            textAlign: TextAlign.center,
            style: V2Typography.body(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space24),
          PGPillButton(
            label: 'Sign in',
            icon: Icons.login_rounded,
            onPressed: onSignIn,
          ),
        ],
      ),
    );
  }
}

class _SignedInBody extends ConsumerWidget {
  const _SignedInBody({required this.onOpenExternal});

  final Future<bool> Function(Uri uri)? onOpenExternal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(aiConnectionsProvider);
    final prefs =
        ref.watch(aiShareConnectionPrefsProvider).asData?.value ?? const {};
    final rows = ref.watch(activeStackProvider).asData?.value ?? const [];
    // What the personal connector can already read: supplements this device
    // has synced. Medications never sync; they reach an assistant only in a
    // snapshot the user previews and shares.
    final available = rows
        .where((e) => e.type == 'supplement' && e.syncedAt != null)
        .length;

    return ListView(
      padding: const EdgeInsets.all(V2Spacing.space24),
      children: [
        Text(
          '$available ${available == 1 ? 'supplement' : 'supplements'} '
          'available to assistants',
          style: V2Typography.titleSm(color: context.v2.fg),
        ),
        const SizedBox(height: V2Spacing.space8),
        Text(
          'Your synced supplement list. Medications and your health profile '
          'reach an assistant only in a snapshot you preview and share.',
          style: V2Typography.bodySm(color: context.v2.fgMuted),
        ),
        const SizedBox(height: V2Spacing.space24),
        switch (connections) {
          AsyncData(:final value) when value.isEmpty => Text(
            'No assistants connected yet. Connect PharmaGuide from your AI '
            'assistant, then come back here to choose what to share.',
            style: V2Typography.body(color: context.v2.fgMuted),
          ),
          AsyncData(:final value) => Column(
            children: [
              for (final c in value)
                Padding(
                  padding: const EdgeInsets.only(bottom: V2Spacing.space16),
                  child: _ConnectionCard(
                    connection: c,
                    prefs: prefs[c.connectionId],
                    onOpenExternal: onOpenExternal,
                  ),
                ),
            ],
          ),
          AsyncError() => Column(
            children: [
              Text(
                'Connections could not be loaded. Try again.',
                style: V2Typography.body(color: context.v2.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space16),
              PGPillButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                onPressed: () => ref.invalidate(aiConnectionsProvider),
              ),
            ],
          ),
          _ => Center(
            child: CircularProgressIndicator(color: context.v2.accent),
          ),
        },
      ],
    );
  }
}

class _ConnectionCard extends ConsumerWidget {
  const _ConnectionCard({
    required this.connection,
    required this.prefs,
    required this.onOpenExternal,
  });

  final AiConnection connection;
  final AiShareConnectionPrefs? prefs;
  final Future<bool> Function(Uri uri)? onOpenExternal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = connection.isLiveAt(DateTime.now());
    final status = switch (connection.status) {
      'active' when live => 'Active',
      'active' || 'expired' => 'Expired',
      _ => 'Disconnected',
    };
    final saved = prefs;
    return PGSettingsGroup(
      eyebrow: status,
      children: [
        PGSettingsTile(
          icon: Icons.smart_toy_outlined,
          title: connection.displayName,
          caption:
              '${connection.callbackHost == null ? '' : '${connection.callbackHost} · '}'
              'Connected ${formatReportDate(connection.createdAt.toLocal())} '
              '· Access ends ${formatReportDate(connection.expiresAt.toLocal())}',
        ),
        if (live) ...[
          PGSettingsTile(
            icon: Icons.ios_share_rounded,
            title: 'Share more with this assistant',
            caption: 'Choose what to include and preview it first',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AiShareConsentScreen(connection: connection),
              ),
            ),
          ),
          PGSettingsTile(
            key: const Key('ai_keep_updated'),
            icon: Icons.sync_rounded,
            title: 'Keep this assistant updated',
            caption: saved == null
                ? 'Available after your first share'
                : 'Uses the categories and duration you last chose when your '
                      'stack changes, including new entries in those categories.',
            trailing: Switch.adaptive(
              value: saved?.keepUpdated ?? false,
              onChanged: saved == null
                  ? null
                  : (on) => _setKeepUpdated(context, ref, on),
            ),
          ),
          PGSettingsTile(
            icon: Icons.link_off_rounded,
            title: 'Disconnect',
            caption: 'Delete what you shared and end access',
            destructive: true,
            onTap: () => _disconnect(context, ref),
          ),
        ],
      ],
    );
  }

  Future<void> _setKeepUpdated(
    BuildContext context,
    WidgetRef ref,
    bool on,
  ) async {
    try {
      await ref
          .read(aiSharePrefsStoreProvider)
          .setKeepUpdated(connection.connectionId, on);
    } on Object {
      if (context.mounted) {
        PGToast.show(
          context,
          'That setting could not be saved. Try again.',
          variant: PGToastVariant.error,
        );
      }
    }
    ref.invalidate(aiShareConnectionPrefsProvider);
  }

  Future<void> _disconnect(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect this assistant?'),
        content: const Text(
          'PharmaGuide deletes what you shared with this assistant, then '
          'opens pharmaguide.io so you can end its access. Disconnecting '
          'cannot erase what the assistant already kept in your chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('ai_disconnect_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(aiSharePrefsStoreProvider).forget(connection.connectionId);
    } on Object {
      if (context.mounted) {
        PGToast.show(
          context,
          'Could not stop sharing. Try again.',
          variant: PGToastVariant.error,
        );
      }
      return;
    }
    ref.invalidate(aiShareConnectionPrefsProvider);
    var deleted = true;
    try {
      await ref
          .read(aiShareSnapshotClientProvider)
          .delete(connection.connectionId);
    } on Object catch (error, stackTrace) {
      deleted = false;
      CrashReportingService().recordError(
        error,
        stackTrace,
        hint: 'ai_share:disconnect_delete_failed',
      );
    }
    final open =
        onOpenExternal ??
        (Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
    await open(Uri.parse(aiConnectionsWebUrl));
    if (!deleted && context.mounted) {
      PGToast.show(
        context,
        'Shared data could not be deleted yet. Try Disconnect again.',
        variant: PGToastVariant.error,
      );
    }
  }
}
