import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/history/providers/health_history_providers.dart';
import 'package:pharmaguide/services/history/user_health_event_service.dart';

Future<void> showAddHealthEventSheet(BuildContext context, WidgetRef ref) {
  return PGModal.bottomSheet<_AddHealthEventResult>(
    context: context,
    builder: (_) => const _AddHealthEventSheet(),
  ).then((result) {
    if (result == _AddHealthEventResult.savedWithoutDeviceReminder &&
        context.mounted) {
      PGToast.show(
        context,
        'Event saved. Device notifications are off, so the reminder appears '
        'only in Health History.',
        variant: PGToastVariant.info,
      );
    }
  });
}

enum _AddHealthEventResult { saved, savedWithoutDeviceReminder }

class _AddHealthEventSheet extends ConsumerStatefulWidget {
  const _AddHealthEventSheet();

  @override
  ConsumerState<_AddHealthEventSheet> createState() =>
      _AddHealthEventSheetState();
}

class _AddHealthEventSheetState extends ConsumerState<_AddHealthEventSheet> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  UserHealthEventKind _kind = UserHealthEventKind.doctorVisit;
  UserHealthEventStatus _status = UserHealthEventStatus.scheduled;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  DateTime? _followUpAt;
  bool _remind = true;
  bool _saving = false;
  XFile? _selectedAttachment;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space8,
        V2Spacing.space24,
        MediaQuery.viewInsetsOf(context).bottom + V2Spacing.space24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add health event',
            style: V2Typography.titleSm(color: context.v2.fg),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Saved only on this device. Lab values and interpretation are '
            'not part of this beta.',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space24),
          DropdownButtonFormField<UserHealthEventKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Event type'),
            items: const [
              DropdownMenuItem(
                value: UserHealthEventKind.doctorVisit,
                child: Text('Doctor visit'),
              ),
              DropdownMenuItem(
                value: UserHealthEventKind.examOrTest,
                child: Text('Exam or test'),
              ),
              DropdownMenuItem(
                value: UserHealthEventKind.procedure,
                child: Text('Procedure or surgery'),
              ),
              DropdownMenuItem(
                value: UserHealthEventKind.personalNote,
                child: Text('Personal note'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _kind = value;
                if (value == UserHealthEventKind.personalNote) {
                  _status = UserHealthEventStatus.completed;
                  _remind = false;
                }
              });
            },
          ),
          const SizedBox(height: V2Spacing.space16),
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: _titleLabel),
          ),
          const SizedBox(height: V2Spacing.space16),
          if (_kind != UserHealthEventKind.personalNote) ...[
            SegmentedButton<UserHealthEventStatus>(
              segments: const [
                ButtonSegment(
                  value: UserHealthEventStatus.scheduled,
                  label: Text('Upcoming'),
                ),
                ButtonSegment(
                  value: UserHealthEventStatus.completed,
                  label: Text('Completed'),
                ),
              ],
              selected: {_status},
              onSelectionChanged: (value) =>
                  setState(() => _status = value.first),
            ),
            const SizedBox(height: V2Spacing.space16),
          ],
          _DateRow(
            label: _status == UserHealthEventStatus.scheduled
                ? 'Scheduled for'
                : 'Date',
            value: _date,
            onTap: () => _pickDate(_date, (date) => _date = date),
          ),
          if (_status == UserHealthEventStatus.scheduled &&
              _kind != UserHealthEventKind.personalNote)
            _TimeRow(
              value: _date,
              onTap: () => _pickTime(_date, (date) => _date = date),
            ),
          const SizedBox(height: V2Spacing.space16),
          TextField(
            controller: _noteController,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: V2Spacing.space8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.attach_file_rounded,
              color: context.v2.accent,
            ),
            title: Text(
              _selectedAttachment == null
                  ? 'Attach a photo (optional)'
                  : _selectedAttachment!.name,
            ),
            subtitle: const Text('Stored only on this device'),
            trailing: _selectedAttachment == null
                ? const Icon(Icons.add_rounded)
                : IconButton(
                    tooltip: 'Remove attachment',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _selectedAttachment = null),
                  ),
            onTap: _pickAttachment,
          ),
          if (_status == UserHealthEventStatus.scheduled &&
              _kind != UserHealthEventKind.personalNote)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Remind me one day before'),
              subtitle: _canRemindOneDayBefore
                  ? const Text('Notification details stay private')
                  : const Text('Choose a date more than one day away'),
              value: _remind && _canRemindOneDayBefore,
              onChanged: _canRemindOneDayBefore
                  ? (value) => setState(() => _remind = value)
                  : null,
            ),
          Divider(color: context.v2.outline),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Add a follow-up date'),
            subtitle: _followUpAt == null
                ? null
                : Text(DateFormat.yMMMd().add_jm().format(_followUpAt!)),
            value: _followUpAt != null,
            onChanged: (enabled) async {
              if (!enabled) {
                setState(() => _followUpAt = null);
                return;
              }
              await _pickDate(
                _date.add(const Duration(days: 7)),
                (date) => _followUpAt = date,
              );
            },
          ),
          const SizedBox(height: V2Spacing.space16),
          PGPillButton(
            label: _saving ? 'Saving…' : 'Save event',
            icon: Icons.check_rounded,
            expand: true,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  String get _titleLabel => switch (_kind) {
    UserHealthEventKind.doctorVisit => 'Clinician or visit name',
    UserHealthEventKind.examOrTest => 'Exam or test name',
    UserHealthEventKind.procedure => 'Procedure name',
    UserHealthEventKind.personalNote => 'Note title',
  };

  bool get _canRemindOneDayBefore =>
      _date.subtract(const Duration(days: 1)).isAfter(DateTime.now());

  Future<void> _pickDate(DateTime initial, ValueChanged<DateTime> apply) async {
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null && mounted) {
      setState(
        () => apply(
          DateTime(
            value.year,
            value.month,
            value.day,
            initial.hour,
            initial.minute,
          ),
        ),
      );
    }
  }

  Future<void> _pickTime(DateTime initial, ValueChanged<DateTime> apply) async {
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (value != null && mounted) {
      setState(
        () => apply(
          DateTime(
            initial.year,
            initial.month,
            initial.day,
            value.hour,
            value.minute,
          ),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      PGToast.show(
        context,
        'Add a name for this event.',
        variant: PGToastVariant.error,
      );
      return;
    }
    setState(() => _saving = true);
    LocalHealthAttachment? importedAttachment;
    try {
      final reminderRequested =
          _remind &&
          _status == UserHealthEventStatus.scheduled &&
          _canRemindOneDayBefore;
      final reminderAt = reminderRequested
          ? _date.subtract(const Duration(days: 1))
          : null;
      final selected = _selectedAttachment;
      if (selected != null) {
        final imported = await ref
            .read(healthAttachmentStoreProvider)
            .importImage(selected);
        importedAttachment = LocalHealthAttachment(
          path: imported.path,
          displayName: imported.displayName,
          mimeType: imported.mimeType,
        );
      }
      await ref
          .read(userHealthEventServiceProvider)
          .create(
            UserHealthEventInput(
              kind: _kind,
              title: _titleController.text,
              date: _date,
              status: _status,
              note: _noteController.text,
              followUpAt: _followUpAt,
              reminderAt: reminderAt,
              attachments: [if (importedAttachment != null) importedAttachment],
            ),
          );
      var reminderAvailable = true;
      if (reminderRequested) {
        ref.invalidate(healthReminderSyncProvider);
        try {
          reminderAvailable = (await ref.read(
            healthReminderSyncProvider.future,
          )).permissionGranted;
        } on Object {
          reminderAvailable = false;
        }
      }
      if (mounted) {
        Navigator.of(context).pop(
          reminderAvailable
              ? _AddHealthEventResult.saved
              : _AddHealthEventResult.savedWithoutDeviceReminder,
        );
      }
    } on Object {
      if (importedAttachment != null) {
        try {
          await ref
              .read(healthAttachmentStoreProvider)
              .delete(importedAttachment.path);
        } on Object {
          // Preserve the original save failure. Account-switch cleanup also
          // clears the private attachment directory as a final backstop.
        }
      }
      if (!mounted) return;
      setState(() => _saving = false);
      PGToast.show(
        context,
        'Could not save the event. Try again.',
        variant: PGToastVariant.error,
      );
    }
  }

  Future<void> _pickAttachment() async {
    final selected = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (selected != null && mounted) {
      setState(() => _selectedAttachment = selected);
    }
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.calendar_today_outlined,
        color: context.v2.accent,
      ),
      title: Text(label),
      subtitle: Text(DateFormat.yMMMMd().format(value)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.value, required this.onTap});

  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.schedule_rounded, color: context.v2.accent),
      title: const Text('Time'),
      subtitle: Text(DateFormat.jm().format(value)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
