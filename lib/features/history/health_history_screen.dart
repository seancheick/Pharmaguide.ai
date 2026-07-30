import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pharmaguide/core/components/pg_segmented_control.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:pharmaguide/features/history/add_health_event_sheet.dart';
import 'package:pharmaguide/features/history/providers/health_history_providers.dart';
import 'package:pharmaguide/services/history/user_health_event_service.dart';

class HealthHistoryScreen extends ConsumerStatefulWidget {
  const HealthHistoryScreen({super.key});

  @override
  ConsumerState<HealthHistoryScreen> createState() =>
      _HealthHistoryScreenState();
}

class _HealthHistoryScreenState extends ConsumerState<HealthHistoryScreen> {
  final _searchController = TextEditingController();
  var _segment = 0;
  HealthHistoryCategory? _filter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(
      _segment == 0
          ? healthHistoryTimelineProvider
          : healthHistoryUpcomingProvider,
    );
    return Scaffold(
      backgroundColor: V2Colors.bg,
      appBar: AppBar(
        backgroundColor: V2Colors.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Health History',
          style: V2Typography.titleSm(color: V2Colors.fg),
        ),
        actions: [
          IconButton(
            tooltip: 'Add health event',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => showAddHealthEventSheet(context, ref),
          ),
          const SizedBox(width: V2Spacing.space8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              V2Spacing.space24,
              V2Spacing.space8,
              V2Spacing.space24,
              V2Spacing.space12,
            ),
            child: PGSegmentedControl(
              segments: const ['Timeline', 'Upcoming'],
              selectedIndex: _segment,
              onChanged: (value) => setState(() => _segment = value),
            ),
          ),
          if (_segment == 0) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: V2Spacing.space24,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search history',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.space24,
                  vertical: V2Spacing.space8,
                ),
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  for (final category in HealthHistoryCategory.values)
                    _FilterChip(
                      label: _categoryLabel(category),
                      selected: _filter == category,
                      onTap: () => setState(() => _filter = category),
                    ),
                ],
              ),
            ),
          ],
          Expanded(
            child: events.when(
              data: (items) =>
                  _HistoryList(items: _visible(items), upcoming: _segment == 1),
              loading: () => const Center(
                child: CircularProgressIndicator(color: V2Colors.accent),
              ),
              error: (_, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(V2Spacing.space24),
                  child: Text(
                    'Health History is unavailable right now. No events were '
                    'deleted.',
                    textAlign: TextAlign.center,
                    style: V2Typography.body(color: V2Colors.fgMuted),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<HealthHistoryItem> _visible(List<HealthHistoryItem> items) {
    final query = _searchController.text.trim().toLowerCase();
    return items
        .where((item) => _filter == null || item.category == _filter)
        .where((item) => query.isEmpty || item.searchText.contains(query))
        .toList(growable: false);
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.items, required this.upcoming});

  final List<HealthHistoryItem> items;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(V2Spacing.space24),
          child: Text(
            upcoming
                ? 'No upcoming visits, tests, procedures, or reminders.'
                : 'Your health journey will appear here as your stack, '
                      'profile, clinical signals, and saved events change.',
            textAlign: TextAlign.center,
            style: V2Typography.body(color: V2Colors.fgMuted),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space12,
        V2Spacing.space24,
        V2Spacing.space48,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final group = _dateGroup(item.event.effectiveAt);
        final showGroup =
            index == 0 ||
            group != _dateGroup(items[index - 1].event.effectiveAt);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showGroup) ...[
              Padding(
                padding: EdgeInsets.only(
                  top: index == 0 ? 0 : V2Spacing.space24,
                  bottom: V2Spacing.space8,
                ),
                child: Text(
                  group,
                  style: V2Typography.label(color: V2Colors.fgMuted),
                ),
              ),
            ],
            _HistoryEventCard(item: item),
            const SizedBox(height: V2Spacing.space8),
          ],
        );
      },
    );
  }
}

class _HistoryEventCard extends ConsumerWidget {
  const _HistoryEventCard({required this.item});

  final HealthHistoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: V2Colors.surface,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        onTap: () async {
          if (item.category == HealthHistoryCategory.signal &&
              item.event.subjectId != null) {
            await ref
                .read(clinicalSignalLifecycleServiceProvider)
                .markViewed(item.event.subjectId!);
            if (!context.mounted) return;
          }
          _showWhy(context, item);
        },
        child: Padding(
          padding: const EdgeInsets.all(V2Spacing.space16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: V2Colors.accentTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _categoryIcon(item.category),
                  color: V2Colors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: V2Spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.event.title,
                      style: V2Typography.bodyMedium(color: V2Colors.fg),
                    ),
                    if (item.event.summary?.isNotEmpty ?? false) ...[
                      const SizedBox(height: V2Spacing.space4),
                      Text(
                        item.event.summary!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: V2Typography.bodySm(color: V2Colors.fgMuted),
                      ),
                    ],
                    const SizedBox(height: V2Spacing.space8),
                    Text(
                      DateFormat.jm().format(item.event.effectiveAt.toLocal()),
                      style: V2Typography.caption(color: V2Colors.fgSubtle),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: V2Colors.fgSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

void _showWhy(BuildContext context, HealthHistoryItem item) {
  PGModal.bottomSheet<void>(
    context: context,
    builder: (_) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space24,
          V2Spacing.space8,
          V2Spacing.space24,
          V2Spacing.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.event.title,
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              DateFormat.yMMMMd().add_jm().format(
                item.event.effectiveAt.toLocal(),
              ),
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space24),
            Text(
              'Why this changed',
              style: V2Typography.label(color: V2Colors.accent),
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(item.whyChanged, style: V2Typography.body(color: V2Colors.fg)),
            if (item.changedFieldLabels.isNotEmpty) ...[
              const SizedBox(height: V2Spacing.space16),
              Text(
                'Changed fields',
                style: V2Typography.label(color: V2Colors.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space8),
              Wrap(
                spacing: V2Spacing.space8,
                runSpacing: V2Spacing.space8,
                children: [
                  for (final label in item.changedFieldLabels)
                    Chip(label: Text(label)),
                ],
              ),
            ],
            if (item.attachments.isNotEmpty) ...[
              const SizedBox(height: V2Spacing.space24),
              Text(
                'Attachments',
                style: V2Typography.label(color: V2Colors.fgMuted),
              ),
              const SizedBox(height: V2Spacing.space8),
              for (final attachment in item.attachments)
                _AttachmentRow(attachment: attachment),
            ],
            _EventDetailActions(item: item),
            const SizedBox(height: V2Spacing.space16),
            Text(
              'Stored only on this device.',
              style: V2Typography.caption(color: V2Colors.fgSubtle),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.attachment});

  final LocalHealthAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final file = File(attachment.path);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: Image.file(
          file,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.image_not_supported_outlined),
          ),
        ),
      ),
      title: Text(
        attachment.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: const Text('Private on-device photo'),
      trailing: const Icon(Icons.open_in_full_rounded, size: 18),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Padding(
                padding: EdgeInsets.all(V2Spacing.space24),
                child: Text('This attachment is no longer available.'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EventDetailActions extends ConsumerWidget {
  const _EventDetailActions({required this.item});

  final HealthHistoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = item.event;
    final isActiveSignal =
        event.subjectId != null &&
        (event.eventType == HealthEventTypes.clinicalSignalAdded ||
            event.eventType == HealthEventTypes.clinicalSignalChanged);
    final kind = _kindForSubject(event.subjectType);
    final isScheduledCare =
        kind != null &&
        event.subjectId != null &&
        event.state == HealthEventState.scheduled.name;
    if (!isActiveSignal && !isScheduledCare) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: V2Spacing.space24),
      child: isActiveSignal
          ? SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  await ref
                      .read(clinicalSignalLifecycleServiceProvider)
                      .acknowledge(event.subjectId!);
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Mark as reviewed'),
              ),
            )
          : Wrap(
              spacing: V2Spacing.space8,
              runSpacing: V2Spacing.space8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _complete(context, ref, kind!),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Complete'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _reschedule(context, ref, kind!),
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('Reschedule'),
                ),
                TextButton.icon(
                  onPressed: () => _cancel(context, ref, kind!),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel'),
                ),
              ],
            ),
    );
  }

  Future<void> _complete(
    BuildContext context,
    WidgetRef ref,
    UserHealthEventKind kind,
  ) async {
    await ref
        .read(userHealthEventServiceProvider)
        .complete(
          kind: kind,
          subjectId: item.event.subjectId!,
          title: item.event.title,
          completedAt: DateTime.now(),
        );
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _reschedule(
    BuildContext context,
    WidgetRef ref,
    UserHealthEventKind kind,
  ) async {
    final current = item.event.effectiveAt.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !context.mounted) return;
    final newDate = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final hadReminder = item.event.reminderAt != null;
    final reminderAt = newDate.subtract(const Duration(days: 1));
    await ref
        .read(userHealthEventServiceProvider)
        .reschedule(
          kind: kind,
          subjectId: item.event.subjectId!,
          title: item.event.title,
          newDate: newDate,
          reminderAt: hadReminder && reminderAt.isAfter(DateTime.now())
              ? reminderAt
              : null,
        );
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    UserHealthEventKind kind,
  ) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Cancel this event?'),
            content: const Text(
              'The cancellation is added to Health History. The original '
              'entry is not deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Keep'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Cancel event'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    await ref
        .read(userHealthEventServiceProvider)
        .cancel(
          kind: kind,
          subjectId: item.event.subjectId!,
          title: item.event.title,
          effectiveAt: DateTime.now(),
        );
    if (context.mounted) Navigator.of(context).pop();
  }
}

UserHealthEventKind? _kindForSubject(String subjectType) =>
    switch (subjectType) {
      'appointment' => UserHealthEventKind.doctorVisit,
      'exam' => UserHealthEventKind.examOrTest,
      'procedure' => UserHealthEventKind.procedure,
      _ => null,
    };

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: V2Spacing.space8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

String _dateGroup(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final difference = day.difference(today).inDays;
  if (difference == 0) return 'Today';
  if (difference == -1) return 'Yesterday';
  if (difference == 1) return 'Tomorrow';
  return DateFormat.yMMMMd().format(local);
}

String _categoryLabel(HealthHistoryCategory category) => switch (category) {
  HealthHistoryCategory.signal => 'Signals',
  HealthHistoryCategory.stack => 'Stack',
  HealthHistoryCategory.care => 'Care',
  HealthHistoryCategory.profile => 'Profile',
  HealthHistoryCategory.note => 'Notes',
};

IconData _categoryIcon(HealthHistoryCategory category) => switch (category) {
  HealthHistoryCategory.signal => Icons.health_and_safety_outlined,
  HealthHistoryCategory.stack => Icons.layers_outlined,
  HealthHistoryCategory.care => Icons.calendar_month_outlined,
  HealthHistoryCategory.profile => Icons.person_outline_rounded,
  HealthHistoryCategory.note => Icons.note_alt_outlined,
};
