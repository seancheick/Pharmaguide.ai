import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/sharing/ai_share_prefs_store.dart';
import 'package:pharmaguide/services/sharing/report_text.dart';

/// Settings → Connected AI assistants (ADR-009).
///
/// Connections are approved on the website; this screen lists them and is
/// where every sensitive share starts: the user picks a connection, chooses
/// what to include, previews the exact text and shares it. Guests see why
/// an account is needed and nothing is queried.
class AiConnectionsScreen extends ConsumerStatefulWidget {
  const AiConnectionsScreen({super.key, this.onSignIn});

  final VoidCallback? onSignIn;

  @override
  ConsumerState<AiConnectionsScreen> createState() =>
      _AiConnectionsScreenState();
}

class _AiConnectionsScreenState extends ConsumerState<AiConnectionsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(authStateProvider) == AuthMode.signedIn) {
      ref.invalidate(aiConnectionsProvider);
      ref.invalidate(aiPendingRevocationProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authStateProvider) == AuthMode.signedIn;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              context.go(Routes.profile);
            }
          },
        ),
        actions: [
          if (signedIn)
            IconButton(
              tooltip: 'Refresh connections',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                ref.invalidate(aiConnectionsProvider);
                ref.invalidate(aiPendingRevocationProvider);
              },
            ),
        ],
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Connected AI assistants',
          style: V2Typography.titleSm(color: context.v2.fg),
        ),
      ),
      body: SafeArea(
        child: signedIn
            ? const _SignedInBody()
            : _GuestBody(
                onSignIn:
                    widget.onSignIn ??
                    () => context.push(Routes.authInvitation),
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
  const _SignedInBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(aiConnectionsProvider);
    final pending = ref.watch(aiPendingRevocationProvider);
    final pendingClient = pending.asData?.value;
    final prefs =
        ref.watch(aiShareConnectionPrefsProvider).asData?.value ?? const {};
    final pairingEnabled = ref.watch(aiPairingEnabledProvider);

    return ListView(
      padding: const EdgeInsets.all(V2Spacing.space24),
      children: [
        Text(
          pairingEnabled
              ? 'Your assistant connections'
              : 'Personal access is not enabled',
          style: V2Typography.titleSm(color: context.v2.fg),
        ),
        const SizedBox(height: V2Spacing.space8),
        Text(
          'Public personal access is not enabled yet. Existing approved test '
          'connections can read your synced supplement list. You choose which '
          'additional details each assistant can read.',
          style: V2Typography.bodySm(color: context.v2.fgMuted),
        ),
        const SizedBox(height: V2Spacing.space24),
        if (pairingEnabled) ...[
          PGPillButton(
            label: 'Enter approval code',
            icon: Icons.phonelink_lock_outlined,
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AiPairingScreen(),
                ),
              );
              ref.invalidate(aiConnectionsProvider);
              ref.invalidate(aiPendingRevocationProvider);
            },
          ),
          const SizedBox(height: V2Spacing.space24),
        ],
        if (pending.hasError)
          TextButton(
            onPressed: () => ref.invalidate(aiPendingRevocationProvider),
            child: const Text('Disconnect status could not be checked. Retry'),
          ),
        if (pendingClient != null &&
            connections.hasValue &&
            !connections.requireValue.any((c) => c.clientId == pendingClient))
          _ConnectionCard(
            key: ValueKey(pendingClient),
            connection: null,
            prefs: null,
            pendingRevocation: true,
            retryClientId: pendingClient,
          ),
        switch (connections) {
          AsyncData(:final value) when value.isEmpty => Text(
            'No assistants connected yet.',
            style: V2Typography.body(color: context.v2.fgMuted),
          ),
          AsyncData(:final value) => Column(
            children: [
              for (final c in value)
                Padding(
                  padding: const EdgeInsets.only(bottom: V2Spacing.space16),
                  child: _ConnectionCard(
                    key: ValueKey(c.connectionId),
                    connection: c,
                    prefs: prefs[c.connectionId],
                    pendingRevocation: pendingClient == c.clientId,
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
                onPressed: () {
                  ref.invalidate(aiConnectionsProvider);
                  ref.invalidate(aiPendingRevocationProvider);
                },
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

class AiPairingScreen extends ConsumerStatefulWidget {
  const AiPairingScreen({super.key, this.initialCode});
  final String? initialCode;
  @override
  ConsumerState<AiPairingScreen> createState() => AiPairingScreenState();
}

class AiPairingScreenState extends ConsumerState<AiPairingScreen> {
  final _controller = TextEditingController();
  late final AiConnectionsRepository _repository;
  Object? _sessionIdentity;
  String? _code;
  AiPairingPreview? _preview;
  Timer? _expiryTimer;
  bool _busy = false;
  bool _approved = false;
  bool _expired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(aiConnectionsRepositoryProvider);
    _sessionIdentity = _repository.pairingSessionIdentity;
    if (widget.initialCode != null) {
      _controller.text = widget.initialCode!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(aiPairingEnabledProvider) && _sameAccount) {
          unawaited(_loadPreview());
        }
      });
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _sameAccount =>
      _sessionIdentity != null &&
      ref.read(authStateProvider) == AuthMode.signedIn &&
      _repository.pairingSessionIdentity == _sessionIdentity;

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_sameAccount) throw const AiPairingException();
      await action();
    } on Object {
      if (mounted) {
        setState(() {
          _error =
              'This request could not be completed. Check your account and code, or request a new code.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _loadPreview() => _perform(() async {
    final code = AiPairingPreview.normalizeCode(_controller.text);
    final preview = await _repository.previewPairing(code);
    if (!mounted) return;
    if (!_sameAccount || !preview.expiresAt.isAfter(DateTime.now())) {
      throw const AiPairingException();
    }
    setState(() {
      _code = code;
      _preview = preview;
      _expired = false;
    });
    _controller.clear();
    _expiryTimer?.cancel();
    _expiryTimer = Timer(preview.expiresAt.difference(DateTime.now()), () {
      if (mounted) {
        setState(() {
          _expired = true;
        });
      }
    });
  });

  Future<void> _approve() => _perform(() async {
    if (_preview == null || !_preview!.expiresAt.isAfter(DateTime.now())) {
      throw const AiPairingException();
    }
    final connectionId = await _repository.approvePairing(_code!);
    if (!mounted) return;
    if (!_sameAccount || !_preview!.expiresAt.isAfter(DateTime.now())) {
      throw const AiPairingException();
    }
    _expiryTimer?.cancel();
    if (connectionId != null) {
      ref.invalidate(aiConnectionsProvider);
      ref.invalidate(aiPendingRevocationProvider);
      PGToast.show(context, '${_preview!.clientName} is connected.');
      _viewConnections();
      return;
    }
    setState(() {
      _approved = true;
      _code = null;
    });
  });

  void _viewConnections() {
    ref.invalidate(aiConnectionsProvider);
    ref.invalidate(aiPendingRevocationProvider);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go(Routes.aiConnections);
    }
  }

  Future<void> _cancel() => _perform(() async {
    await _repository.cancelPairing(_code!);
    if (mounted && _sameAccount) _viewConnections();
  });

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authStateProvider) == AuthMode.signedIn;
    final preview = _preview;
    final enabled =
        signedIn &&
        _sameAccount &&
        !_busy &&
        ref.watch(aiPairingEnabledProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _viewConnections),
        title: const Text('Approve an assistant'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(V2Spacing.space24),
          children: [
            const Text(
              'Assistant connections are for adults aged 18 and over.',
            ),
            const SizedBox(height: V2Spacing.space16),
            if (!signedIn || !_sameAccount)
              const Text(
                'Your account changed. Close this page and sign in again before approving.',
              ),
            if (_approved) ...[
              Text(
                'Approved on this phone',
                style: V2Typography.titleSm(color: context.v2.fg),
              ),
              const SizedBox(height: V2Spacing.space16),
              const Text(
                'Keep the connection page open on your computer while it finishes. Then view your connections below. No health snapshot has been shared.',
              ),
              const SizedBox(height: V2Spacing.space16),
              PGPillButton(
                label: 'View connections',
                onPressed: _viewConnections,
              ),
            ] else if (preview == null) ...[
              const Text(
                'Enter the code shown in your assistant or browser. Use the same PharmaGuide account on both.',
              ),
              const SizedBox(height: V2Spacing.space16),
              TextField(
                controller: _controller,
                enabled: enabled,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    final raw = newValue.text.toUpperCase().replaceAll(
                      RegExp(r'[\s-]'),
                      '',
                    );
                    if (raw.length > 12 ||
                        !RegExp(r'^[A-Z0-9]*$').hasMatch(raw)) {
                      return oldValue;
                    }
                    final before = newValue.text
                        .substring(
                          0,
                          newValue.selection.extentOffset.clamp(
                            0,
                            newValue.text.length,
                          ),
                        )
                        .replaceAll(RegExp(r'[\s-]'), '')
                        .length;
                    final formatted = [
                      for (var i = 0; i < raw.length; i += 4)
                        raw.substring(i, (i + 4).clamp(0, raw.length)),
                    ].join('-');
                    final cursor = before == 0 ? 0 : before + (before - 1) ~/ 4;
                    return TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: cursor.clamp(0, formatted.length),
                      ),
                    );
                  }),
                ],
                maxLength: 14,
                decoration: const InputDecoration(
                  labelText: 'Approval code',
                  hintText: 'ABCD-EFGH-JKMN',
                ),
              ),
              const SizedBox(height: V2Spacing.space16),
              PGPillButton(
                label: 'Preview destination',
                onPressed: enabled ? _loadPreview : null,
              ),
            ] else ...[
              Text(
                'Check this destination',
                style: V2Typography.titleSm(color: context.v2.fg),
              ),
              const SizedBox(height: V2Spacing.space16),
              Text(
                preview.clientName,
                style: V2Typography.titleSm(color: context.v2.fg),
              ),
              const SizedBox(height: V2Spacing.space8),
              Text(
                preview.callbackHost,
                style: V2Typography.body(color: context.v2.fg),
              ),
              const SizedBox(height: V2Spacing.space16),
              Text(
                'Expires ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(preview.expiresAt.toLocal()))}',
              ),
              const SizedBox(height: V2Spacing.space16),
              const Text(
                'Approve only a request you started for this assistant and destination. This step approves the connection request. You choose and preview any health snapshot separately.',
              ),
              const SizedBox(height: V2Spacing.space24),
              if (_expired)
                const Text(
                  'This code has expired. Request a new code in your assistant or browser.',
                ),
              PGPillButton(
                label: 'Approve request',
                onPressed: enabled && !_expired ? _approve : null,
              ),
              TextButton(
                onPressed: enabled ? _cancel : null,
                child: const Text('Cancel request'),
              ),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(V2Spacing.space16),
                child: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Checking request',
                  ),
                ),
              ),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
          ],
        ),
      ),
    );
  }
}

class _ConnectionCard extends ConsumerStatefulWidget {
  const _ConnectionCard({
    super.key,
    required this.connection,
    required this.prefs,
    required this.pendingRevocation,
    this.retryClientId,
  });

  final AiConnection? connection;
  final String? retryClientId;
  final AiShareConnectionPrefs? prefs;
  final bool pendingRevocation;
  @override
  ConsumerState<_ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends ConsumerState<_ConnectionCard> {
  bool _busy = false;
  bool _localEnded = false;
  bool _needsRetry = false;
  AiConnection get connection => widget.connection!;
  AiShareConnectionPrefs? get prefs => widget.prefs;

  @override
  Widget build(BuildContext context) {
    if (widget.connection == null) {
      return PGSettingsGroup(
        eyebrow: 'Access ended',
        children: [
          PGSettingsTile(
            icon: Icons.link_off_rounded,
            title: _busy ? 'Disconnecting…' : 'Retry disconnect',
            caption:
                'PharmaGuide access ended. Finish disconnecting the provider.',
            onTap: _busy ? null : () => _disconnect(context, ref),
          ),
        ],
      );
    }
    final live =
        !_localEnded &&
        !widget.pendingRevocation &&
        connection.isLiveAt(DateTime.now());
    final status = switch (_localEnded || widget.pendingRevocation
        ? 'revoked'
        : connection.status) {
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
              '· ${!live
                  ? 'Access ended'
                  : connection.expiresAt == null
                  ? 'Until you disconnect'
                  : 'Access ends ${formatReportDate(connection.expiresAt!.toLocal())}'}',
        ),
        if (live) ...[
          PGSettingsTile(
            icon: Icons.tune_rounded,
            title: 'Manage assistant access',
            caption:
                'Your synced supplement list is already accessible. '
                'Choose additional details and preview what the assistant can read.',
            onTap: () async {
              // Read the existing owner at entry, even if the card's async
              // preferences have not loaded yet. Never replace them with defaults.
              AiShareConnectionPrefs? settings;
              try {
                settings = await ref
                    .read(aiSharePrefsStoreProvider)
                    .read(connection.connectionId);
              } on Object {
                if (context.mounted) {
                  PGToast.show(
                    context,
                    'Access settings could not be loaded. Try again.',
                    variant: PGToastVariant.error,
                  );
                }
                return;
              }
              if (!context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AiShareConsentScreen(
                    connection: connection,
                    initialSettings: settings,
                  ),
                ),
              );
            },
          ),
          PGSettingsTile(
            key: const Key('ai_keep_updated'),
            icon: Icons.sync_rounded,
            title: 'Keep this assistant updated',
            caption: saved == null
                ? 'First choose additional details in Manage assistant access'
                : 'While you use PharmaGuide, updates use the categories and duration you last chose when your '
                      'stack changes, including new entries in those categories.',
            trailing: Switch.adaptive(
              value: saved?.keepUpdated ?? false,
              onChanged: saved == null || _busy
                  ? null
                  : (on) => _setKeepUpdated(context, ref, on),
            ),
          ),
        ],
        if (live || _needsRetry || widget.pendingRevocation) ...[
          PGSettingsTile(
            icon: Icons.link_off_rounded,
            title: _busy
                ? 'Disconnecting…'
                : (_needsRetry || widget.pendingRevocation)
                ? 'Retry disconnect'
                : 'Disconnect',
            caption: (_needsRetry || widget.pendingRevocation)
                ? 'PharmaGuide access ended. Finish disconnecting the provider.'
                : 'Delete what you shared and end access',
            destructive: true,
            onTap: _busy ? null : () => _disconnect(context, ref),
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
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(aiConnectionsRepositoryProvider);
    final prefsStore = ref.read(aiSharePrefsStoreProvider);
    final identity = repository.pairingSessionIdentity;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect this assistant?'),
        content: const Text(
          'PharmaGuide ends this assistant’s access and deletes what you shared. Disconnecting cannot erase what the assistant already kept in your chat.',
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
    if (!mounted) return;
    if (confirmed != true ||
        identity == null ||
        repository.pairingSessionIdentity != identity) {
      setState(() => _busy = false);
      return;
    }
    String message;
    var success = false;
    var updatesStopped = false;
    try {
      if (widget.connection != null) {
        await prefsStore.forget(connection.connectionId);
      }
      updatesStopped = true;
      if (!mounted) return;
      ref.invalidate(aiShareConnectionPrefsProvider);
      if (repository.pairingSessionIdentity != identity) {
        throw const AiDisconnectException();
      }
      final result = await repository.disconnect(
        widget.connection?.clientId ?? widget.retryClientId!,
      );
      if (repository.pairingSessionIdentity != identity) {
        throw const AiDisconnectException();
      }
      success = result == AiDisconnectResult.disconnected;
      message = success
          ? 'Assistant disconnected. Access has ended.'
          : 'PharmaGuide access has ended. Provider disconnect is unfinished. Retry disconnect.';
      if (mounted) {
        setState(() {
          _localEnded = true;
          _needsRetry = !success;
        });
        ref.invalidate(aiConnectionsProvider);
        ref.invalidate(aiPendingRevocationProvider);
      }
    } on Object {
      message = updatesStopped
          ? 'Disconnect could not be confirmed. Automatic updates are off. Try again.'
          : 'Could not stop sharing. Try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if ((repository.pairingSessionIdentity == identity) && messenger.mounted) {
      PGToast.showWith(
        messenger,
        message,
        variant: success ? PGToastVariant.success : PGToastVariant.error,
      );
    }
  }
}
