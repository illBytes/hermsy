import 'package:home_widget/home_widget.dart';

import '../models/brief.dart';
import 'app_settings.dart';

/// The Android widget class (android/.../BriefWidgetProvider.kt).
const briefWidgetProvider = 'BriefWidgetProvider';

/// Sections the widget can list, as rows.
const widgetSectionIds = ['today', 'due', 'coming_up', 'money'];

const _maxRows = 4;

class WidgetRow {
  const WidgetRow({
    required this.lead,
    required this.title,
    this.alert = false,
  });

  /// The time or "when" on the left ("16:00", "Overdue").
  final String lead;
  final String title;

  /// Drawn in the warning colour (overdue).
  final bool alert;
}

class WidgetContent {
  const WidgetContent({
    required this.rows,
    required this.footer,
    this.name,
    this.headline,
  });

  /// "Alex", from the brief's greeting; the widget says the greeting
  /// itself so it is right for the hour it is drawn at.
  final String? name;
  final String? headline;
  final List<WidgetRow> rows;
  final String footer;
}

/// What the widget should show for [brief] under [settings].
WidgetContent briefWidgetContent(Brief? brief, AppSettings settings) {
  if (brief == null) {
    return const WidgetContent(rows: [], footer: '');
  }
  final greeting = brief.greeting ?? '';
  final comma = greeting.lastIndexOf(',');
  final name = comma < 0 ? null : greeting.substring(comma + 1).trim();
  final rows = <WidgetRow>[];
  // The widget follows the Brief's order, among the sections it shows.
  for (final id in settings.briefOrder) {
    if (!settings.widgetSections.contains(id)) {
      continue;
    }
    for (final item in brief.section(id)?.items ?? const <BriefItem>[]) {
      if (rows.length == _maxRows) {
        break;
      }
      rows.add(
        WidgetRow(
          lead: switch (id) {
            'today' => item.time ?? 'Today',
            'money' => 'Money',
            _ => item.when ?? 'Soon',
          },
          title: item.title,
          alert: item.overdue,
        ),
      );
    }
  }
  final suggestions = brief.section('suggestions')?.items.length ?? 0;
  final local = brief.createdAt.toLocal();
  final updated =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  return WidgetContent(
    name: name == null || name.isEmpty ? null : name,
    headline: settings.widgetHeadline ? brief.headline : null,
    rows: rows,
    footer: [
      if (settings.widgetSuggestions && suggestions > 0)
        suggestions == 1 ? '1 suggestion' : '$suggestions suggestions',
      'Updated $updated',
    ].join(' · '),
  );
}

/// Saves [brief] for the home-screen widget and asks Android to redraw it.
/// Safe to call when there is no widget, and from the push isolate.
Future<void> updateBriefWidget(Brief? brief, AppSettings settings) async {
  final content = briefWidgetContent(brief, settings);
  try {
    await HomeWidget.saveWidgetData<String>('brief_name', content.name);
    await HomeWidget.saveWidgetData<String>('brief_headline', content.headline);
    for (var i = 0; i < _maxRows; i++) {
      final row = i < content.rows.length ? content.rows[i] : null;
      await HomeWidget.saveWidgetData<String>(
        'brief_row${i + 1}_lead',
        row?.lead,
      );
      await HomeWidget.saveWidgetData<String>(
        'brief_row${i + 1}_title',
        row?.title,
      );
      await HomeWidget.saveWidgetData<bool>(
        'brief_row${i + 1}_alert',
        row?.alert ?? false,
      );
    }
    await HomeWidget.saveWidgetData<String>('brief_footer', content.footer);
    await HomeWidget.updateWidget(androidName: briefWidgetProvider);
  } catch (_) {
    // No widget support here (tests, desktop): nothing to draw.
  }
}

/// Asks the launcher to add the widget (Android 8+ shows its own dialog).
Future<bool> pinBriefWidget() async {
  try {
    if (await HomeWidget.isRequestPinWidgetSupported() != true) {
      return false;
    }
    await HomeWidget.requestPinWidget(androidName: briefWidgetProvider);
    return true;
  } catch (_) {
    return false;
  }
}
