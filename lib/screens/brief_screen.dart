import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/brief.dart';
import '../services/app_settings.dart';
import '../services/brief_store.dart';
import '../services/delivery_inbox.dart';
import '../services/relay_client.dart' show relayPlainText;
import '../services/relay_sync.dart';
import '../state/chat_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/frank_backdrop.dart';
import '../widgets/frank_orb.dart';
import '../widgets/report_reply.dart';
import '../widgets/ui/frank_ui.dart';
import 'brief_settings_screen.dart';
import 'inbox_screen.dart' show showDeliveryReader;

/// Frank's Brief: the day at a glance, then the latest updates from Frank.
/// Pull down to have Hermes write a fresh one.
class BriefScreen extends StatefulWidget {
  const BriefScreen({
    super.key,
    required this.store,
    required this.settings,
    this.chat,
    this.inbox,
    this.now,
  });

  final BriefStore store;
  final AppSettings settings;

  /// For Do it / Reply on suggestions and updates.
  final ChatController? chat;
  final DeliveryInbox? inbox;

  /// Overrides the clock (tests).
  final DateTime? now;

  @override
  State<BriefScreen> createState() => _BriefScreenState();
}

class _BriefScreenState extends State<BriefScreen> {
  List<DeliveryRecord> _updates = const [];

  @override
  void initState() {
    super.initState();
    unawaited(widget.store.load());
    unawaited(_loadUpdates());
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (!widget.store.loading) {
      unawaited(_loadUpdates());
    }
  }

  Future<void> _loadUpdates() async {
    try {
      final inbox = widget.inbox ?? await DeliveryInbox.open();
      final items = (await inbox.list()).where(isRelayRecord).take(5).toList();
      if (mounted) {
        setState(() => _updates = items);
      }
    } catch (_) {}
  }

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await widget.store.requestFresh();
    final error = widget.store.error;
    if (error != null && mounted) {
      messenger?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// A suggestion becomes a reply thread: Do it says yes at once.
  Future<void> _suggestion(BriefItem item, {required bool doIt}) async {
    final chat = widget.chat;
    final brief = widget.store.brief;
    if (chat == null || brief == null) {
      return;
    }
    final body = [
      item.title,
      ?item.detail,
      if (item.action != null) 'Proposed: ${item.action}',
    ].join('\n\n');
    Navigator.of(context).popUntil((route) => route.isFirst);
    await chat.replyTo(
      DeliveryRecord(
        id: 'brief_${brief.id}_${item.title.hashCode}',
        title: 'Suggestion: ${item.title}',
        body: body,
        createdAt: brief.createdAt,
        source: 'brief',
      ),
    );
    if (doIt) {
      await chat.send('Yes, go ahead.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FrankBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListenableBuilder(
          listenable: Listenable.merge([widget.store, widget.settings]),
          builder: (context, _) {
            final media = MediaQuery.of(context);
            final side = math.max(
              AppSpace.gutter,
              (media.size.width - 640) / 2,
            );
            final brief = widget.store.brief;
            return RefreshIndicator(
              color: AppColors.gold,
              backgroundColor: AppColors.surfaceHigh,
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const LargeTitleSliverBar(title: 'Brief'),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      AppSpace.x2,
                      side,
                      AppSpace.x10 + media.padding.bottom,
                    ),
                    sliver: SliverList.list(
                      children: [
                        _Hero(
                          brief: brief,
                          now: widget.now ?? DateTime.now(),
                          writing: widget.store.writing,
                        ),
                        for (final id in widget.settings.briefShown)
                          ..._section(id, brief),
                        const SizedBox(height: AppSpace.x6),
                        _Footer(
                          brief: brief,
                          onCustomize: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) => BriefSettingsScreen(
                                settings: widget.settings,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _section(String id, Brief? brief) {
    Widget card(Widget child) => Padding(
      padding: const EdgeInsets.only(top: AppSpace.x5),
      child: child,
    );
    if (id == 'updates') {
      if (_updates.isEmpty) {
        return const [];
      }
      return [
        card(
          _Card(
            icon: Icons.notifications_none_rounded,
            title: briefSectionNames['updates']!,
            children: [
              for (final record in _updates)
                _UpdateRow(
                  record: record,
                  onTap: () => showDeliveryReader(
                    context,
                    record,
                    onReply: widget.chat?.replyTo,
                  ),
                ),
            ],
          ),
        ),
      ];
    }
    final section = brief?.section(id);
    if (section == null || section.items.isEmpty) {
      return const [];
    }
    final (icon, rows) = switch (id) {
      'today' => (
        Icons.wb_sunny_outlined,
        [for (final item in section.items) _TimelineRow(item: item)],
      ),
      'due' => (
        Icons.flag_outlined,
        [for (final item in section.items) _WhenRow(item: item)],
      ),
      'suggestions' => (
        Icons.auto_awesome_outlined,
        [
          for (final item in section.items)
            _SuggestionRow(
              item: item,
              onDoIt: widget.chat == null
                  ? null
                  : () => _suggestion(item, doIt: true),
              onReply: widget.chat == null
                  ? null
                  : () => _suggestion(item, doIt: false),
            ),
        ],
      ),
      'coming_up' => (
        Icons.event_outlined,
        [for (final item in section.items) _WhenRow(item: item)],
      ),
      'money' => (
        Icons.account_balance_wallet_outlined,
        [for (final item in section.items) _WhenRow(item: item)],
      ),
      _ => (
        Icons.notes_rounded,
        [for (final item in section.items) _WhenRow(item: item)],
      ),
    };
    return [
      card(
        _Card(
          icon: icon,
          title: section.title,
          count: section.items.length,
          children: rows,
        ),
      ),
    ];
  }
}

/// The greeting, the day, the one thing that matters, and Hermes's summary.
class _Hero extends StatelessWidget {
  const _Hero({required this.brief, required this.now, required this.writing});

  final Brief? brief;
  final DateTime now;
  final bool writing;

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final brief = this.brief;
    final date =
        '${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MicroLabel(date.toUpperCase(), padding: EdgeInsets.zero),
                  const SizedBox(height: AppSpace.x2),
                  Text(
                    brief?.greeting ?? _greetingFor(now),
                    style: AppText.display.copyWith(fontSize: 30, height: 1.15),
                  ),
                ],
              ),
            ),
            FrankOrb(size: 52, live: writing),
          ],
        ),
        const SizedBox(height: AppSpace.x4),
        if (writing)
          ShimmerText(
            'Hermes is writing a fresh brief…',
            style: TextStyle(color: AppColors.secondary, fontSize: 16),
          )
        else if (brief == null)
          Text(
            'Your first brief arrives at 6:00. Pull down to ask Hermes for '
            'one now.',
            style: TextStyle(
              color: AppColors.secondary,
              fontSize: 16,
              height: 1.5,
            ),
          )
        else ...[
          if (brief.headline != null)
            Text(
              brief.headline!,
              style: TextStyle(
                color: AppColors.goldText,
                fontSize: 20,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (brief.summary != null) ...[
            const SizedBox(height: AppSpace.x3),
            Text(
              brief.summary!,
              style: TextStyle(
                color: AppColors.secondary,
                fontSize: 16,
                height: 1.55,
              ),
            ),
          ],
        ],
      ],
    );
  }

  static String _greetingFor(DateTime now) {
    if (now.hour < 12) {
      return 'Good morning';
    }
    if (now.hour < 17) {
      return 'Good afternoon';
    }
    return 'Good evening';
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.children,
    this.count,
  });

  final IconData icon;
  final String title;
  final int? count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.gold),
              const SizedBox(width: AppSpace.x2),
              Expanded(
                child: Text(title, style: AppText.label.copyWith(fontSize: 15)),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: AppText.tabular.copyWith(color: AppColors.hint),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.x2),
          ...children,
        ],
      ),
    );
  }
}

/// Today: the time in gold on the left, a thread of dots joining the day.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item});

  final BriefItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(
              item.time ?? 'Today',
              style: AppText.tabular.copyWith(
                color: item.time == null ? AppColors.hint : AppColors.gold,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(child: _ItemText(item: item)),
        ],
      ),
    );
  }
}

/// A row with its "when" on the right; overdue ones in the warning colour.
class _WhenRow extends StatelessWidget {
  const _WhenRow({required this.item});

  final BriefItem item;

  @override
  Widget build(BuildContext context) {
    final when = item.when;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _ItemText(item: item)),
          if (when != null) ...[
            const SizedBox(width: AppSpace.x3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: item.overdue
                    ? AppColors.danger.withValues(alpha: 0.14)
                    : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Text(
                when,
                style: TextStyle(
                  color: item.overdue ? AppColors.danger : AppColors.secondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemText extends StatelessWidget {
  const _ItemText({required this.item});

  final BriefItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title, style: AppText.label.copyWith(fontSize: 15.5)),
        if (item.detail != null) ...[
          const SizedBox(height: 2),
          Text(item.detail!, style: AppText.bodySmall.copyWith(fontSize: 13.5)),
        ],
      ],
    );
  }
}

/// A suggestion with what Frank would do, and the two answers.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.item,
    required this.onDoIt,
    required this.onReply,
  });

  final BriefItem item;
  final VoidCallback? onDoIt;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ItemText(item: item),
          if (item.action != null) ...[
            const SizedBox(height: 6),
            Text(
              'Hermsy will ${item.action![0].toLowerCase()}${item.action!.substring(1)}',
              style: TextStyle(
                color: AppColors.hint,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          if (onDoIt != null) ...[
            const SizedBox(height: AppSpace.x3),
            Row(
              children: [
                GoldButton(
                  label: 'Do it',
                  expanded: false,
                  height: 36,
                  onPressed: onDoIt,
                ),
                const SizedBox(width: AppSpace.x2),
                TextButton(
                  onPressed: onReply,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                  ),
                  child: const Text('Reply'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.record, required this.onTap});

  final DeliveryRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = relayPlainText(record.body).split('\n').first;
    final local = record.createdAt.toLocal();
    final clock =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySmall.copyWith(fontSize: 13.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.x3),
            Text(clock, style: AppText.tabular.copyWith(color: AppColors.hint)),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.brief, required this.onCustomize});

  final Brief? brief;
  final VoidCallback onCustomize;

  @override
  Widget build(BuildContext context) {
    final brief = this.brief;
    final updated = brief == null
        ? null
        : '${brief.createdAt.hour.toString().padLeft(2, '0')}:'
              '${brief.createdAt.minute.toString().padLeft(2, '0')}';
    return Column(
      children: [
        Text(
          updated == null
              ? 'Pull down to ask Hermes for a brief'
              : 'Written at $updated · pull down for a fresh one',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.hint, fontSize: 13),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: onCustomize,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.secondary,
              ),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Customize'),
            ),
            if (brief != null)
              // The Brief is written by AI: it can be reported, like a reply.
              TextButton.icon(
                onPressed: () => reportReply(
                  context,
                  reply: const JsonEncoder.withIndent(
                    '  ',
                  ).convert(brief.toJson()),
                  sentAt: brief.createdAt,
                  source: 'Brief',
                ),
                style: TextButton.styleFrom(foregroundColor: AppColors.hint),
                icon: const Icon(Icons.outlined_flag_rounded, size: 18),
                label: const Text('Report'),
              ),
          ],
        ),
      ],
    );
  }
}
