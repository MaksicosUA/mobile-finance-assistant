import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/settings_widgets.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../finance_entry/domain/finance_entry_models.dart';
import '../application/timezone_controller.dart';
import '../domain/timezone_options.dart';

/// Choose where this account's months are drawn (ADR 0028).
///
/// The screen says plainly what does *not* change: recorded operations keep
/// their dates. Someone who has moved is otherwise entitled to assume their
/// history is about to be re-filed, which would be a reason not to touch it.
class TimezonePage extends ConsumerStatefulWidget {
  const TimezonePage({super.key});

  @override
  ConsumerState<TimezonePage> createState() => _TimezonePageState();
}

class _TimezonePageState extends ConsumerState<TimezonePage> {
  final _search = TextEditingController();
  var _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(timezoneControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(timezoneControllerProvider);

    ref.listen<TimezoneState>(timezoneControllerProvider, (previous, next) {
      if (next is! TimezoneReady || next.failure == null) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(_failureMessage(next, l10n))),
      );
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.timezoneTitle)),
      body: SafeArea(child: _body(state, l10n)),
    );
  }

  Widget _body(TimezoneState state, AppLocalizations l10n) {
    switch (state) {
      case TimezoneLoading():
        return const Center(child: CircularProgressIndicator());
      case TimezoneAccountRequired():
        return _Message(
          key: const Key('timezone-account-required'),
          text: l10n.timezoneAccountRequired,
        );
      case TimezoneLoadFailure():
        return _Message(
          key: const Key('timezone-load-error'),
          text: l10n.timezoneLoadError,
          onRetry: () => ref.read(timezoneControllerProvider.notifier).load(),
          retryLabel: l10n.retryAction,
        );
      case TimezoneReady():
        return _ready(state, l10n);
    }
  }

  Widget _ready(TimezoneReady state, AppLocalizations l10n) {
    final matches = _visibleOptions(state);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.timezoneCurrent(state.canonicalTimezone),
                key: const Key('timezone-current'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.timezoneExplanation,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('timezone-search'),
                controller: _search,
                enabled: !state.isSubmitting,
                decoration: InputDecoration(
                  labelText: l10n.timezoneSearchField,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ],
          ),
        ),
        if (state.isSubmitting)
          const LinearProgressIndicator(key: Key('timezone-submitting')),
        Expanded(
          child: matches.isEmpty
              ? _Message(
                  key: const Key('timezone-no-matches'),
                  text: l10n.timezoneNothingFound,
                )
              : ListView.builder(
                  key: const Key('timezone-list'),
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final entry = matches[index];
                    return switch (entry) {
                      _SectionEntry(:final label) => Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.xs,
                        ),
                        child: SettingsSectionLabel(label),
                      ),
                      _ZoneEntry(:final option) => _ZoneRow(
                        option: option,
                        selected: option.id == state.canonicalTimezone,
                        enabled: !state.isSubmitting,
                        onPressed: () => _confirm(option, l10n),
                      ),
                    };
                  },
                ),
        ),
      ],
    );
  }

  /// The device's zone first when it differs, then everything else.
  ///
  /// The account's current zone is included even when the catalogue does not
  /// know it, so the screen can always show what is in force.
  List<_Entry> _visibleOptions(TimezoneReady state) {
    final device = state.deviceTimezone;
    final entries = <_Entry>[];
    if (device != null) {
      final option = _optionFor(device);
      if (option.matches(_query)) {
        entries.add(
          _SectionEntry(AppLocalizations.of(context).timezoneDeviceSection),
        );
        entries.add(_ZoneEntry(option));
      }
    }

    final known = {for (final option in timezoneOptions) option.id};
    final rest = <TimezoneOption>[
      if (!known.contains(state.canonicalTimezone))
        _optionFor(state.canonicalTimezone),
      ...timezoneOptions,
    ].where((option) => option.id != device && option.matches(_query)).toList();
    if (rest.isNotEmpty) {
      entries.add(
        _SectionEntry(AppLocalizations.of(context).timezoneAllSection),
      );
      entries.addAll(rest.map(_ZoneEntry.new));
    }
    return entries;
  }

  TimezoneOption _optionFor(String id) {
    for (final option in timezoneOptions) {
      if (option.id == id) return option;
    }
    return TimezoneOption(id, id);
  }

  Future<void> _confirm(TimezoneOption option, AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.timezoneConfirmTitle(option.label)),
        content: Text(l10n.timezoneConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            key: const Key('timezone-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.timezoneConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final settled = await ref
        .read(timezoneControllerProvider.notifier)
        .correct(option.id);
    if (!settled || !mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.timezoneCorrected(option.label))),
    );
  }

  String _failureMessage(TimezoneReady state, AppLocalizations l10n) {
    for (final issue in state.issues) {
      return switch (issue.code) {
        FinanceTimezoneIssueCode.timezoneUnchanged =>
          l10n.timezoneUnchangedError,
        FinanceTimezoneIssueCode.timezoneBehindRecordedOperations =>
          l10n.timezoneBehindOperationsError,
      };
    }
    return l10n.timezoneWriteError;
  }
}

sealed class _Entry {
  const _Entry();
}

final class _SectionEntry extends _Entry {
  const _SectionEntry(this.label);

  final String label;
}

final class _ZoneEntry extends _Entry {
  const _ZoneEntry(this.option);

  final TimezoneOption option;
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final TimezoneOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('timezone-option-${option.id}'),
      title: Text(option.label),
      subtitle: Text(option.id),
      // Selection is carried by the check mark and the semantics, never by
      // colour alone.
      trailing: selected ? const Icon(Icons.check) : null,
      selected: selected,
      enabled: enabled && !selected,
      onTap: selected || !enabled ? null : onPressed,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    this.onRetry,
    this.retryLabel,
    super.key,
  });

  final String text;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (onRetry != null && retryLabel != null) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: onRetry, child: Text(retryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
