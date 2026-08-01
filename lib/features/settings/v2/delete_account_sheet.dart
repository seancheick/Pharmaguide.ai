import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/services/auth/account_deletion_service.dart';

typedef DeleteAccountCallback =
    Future<AccountDeletionResult> Function(String confirmation);

class DeleteAccountSheet extends StatefulWidget {
  const DeleteAccountSheet({
    super.key,
    required this.onDelete,
    required this.onDeleted,
  });

  final DeleteAccountCallback onDelete;
  final VoidCallback onDeleted;

  @override
  State<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<DeleteAccountSheet> {
  final TextEditingController _confirmation = TextEditingController();
  bool _showFinalConfirmation = false;
  bool _understands = false;
  bool _deleting = false;
  String? _error;

  bool get _canDelete =>
      _confirmation.text == 'DELETE' && _understands && !_deleting;

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_canDelete) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    final result = await widget.onDelete(_confirmation.text);
    if (!mounted) return;
    switch (result) {
      case AccountDeletionResult.deleted:
        widget.onDeleted();
        if (Navigator.canPop(context)) {
          await Navigator.maybePop(context);
        } else {
          setState(() => _deleting = false);
        }
        return;
      case AccountDeletionResult.deletedLocalCleanupIncomplete:
        widget.onDeleted();
        setState(() {
          _deleting = false;
          _error =
              'Your online account was deleted, but this device could not '
              'confirm every local cleanup step. Close and reinstall the app '
              'before giving this device to someone else.';
        });
        return;
      case AccountDeletionResult.remoteFailed:
        setState(() {
          _deleting = false;
          _error =
              'Account deletion could not be confirmed. Your local data is '
              'still on this device; private submission photos may already '
              'have been removed. Check your connection and try again.';
        });
        return;
      case AccountDeletionResult.confirmationRequired:
        setState(() {
          _deleting = false;
          _error = 'Type DELETE exactly and confirm the warning.';
        });
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.v2;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: V2Motion.fast,
      curve: V2Motion.decelerate,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            V2Spacing.space24,
            V2Spacing.space8,
            V2Spacing.space24,
            V2Spacing.space24,
          ),
          children: [
            Icon(
              Icons.delete_forever_outlined,
              color: palette.contraindicated,
              size: 40,
            ),
            const SizedBox(height: V2Spacing.space16),
            Text(
              'Delete account permanently?',
              style: V2Typography.title(color: palette.fg),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'This cannot be undone. You will need to create a new account to '
              'use signed-in features again.',
              style: V2Typography.bodySm(color: palette.fgMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: V2Spacing.space16),
            const _WarningLine('Your supplement and medication stack'),
            const _WarningLine(
              'Your profile, scans, health history, and attachments',
            ),
            const _WarningLine(
              'Your private product submission photos and statuses',
            ),
            const _WarningLine('Your PharmaGuide sign-in account'),
            const SizedBox(height: V2Spacing.space24),
            if (!_showFinalConfirmation)
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () =>
                      setState(() => _showFinalConfirmation = true),
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.contraindicated,
                  ),
                  child: const Text('Continue'),
                ),
              )
            else ...[
              Text(
                'Type DELETE to confirm',
                style: V2Typography.body(color: palette.fg),
              ),
              const SizedBox(height: V2Spacing.space8),
              TextField(
                controller: _confirmation,
                enabled: !_deleting,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() => _error = null),
                decoration: const InputDecoration(
                  hintText: 'DELETE',
                  border: OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _understands,
                onChanged: _deleting
                    ? null
                    : (value) => setState(() {
                        _understands = value ?? false;
                        _error = null;
                      }),
                title: Text(
                  'I understand this cannot be undone',
                  style: V2Typography.bodySm(color: palette.fg),
                ),
              ),
              if (_error != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: V2Typography.bodySm(color: palette.contraindicated),
                  ),
                ),
                const SizedBox(height: V2Spacing.space12),
              ],
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _canDelete ? _delete : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.contraindicated,
                  ),
                  child: _deleting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Delete forever'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WarningLine extends StatelessWidget {
  const _WarningLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.v2;
    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(
              Icons.remove_circle_outline,
              size: 18,
              color: palette.contraindicated,
            ),
          ),
          const SizedBox(width: V2Spacing.space8),
          Expanded(
            child: Text(text, style: V2Typography.bodySm(color: palette.fg)),
          ),
        ],
      ),
    );
  }
}
