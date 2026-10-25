import 'package:flutter/material.dart';

import '../models/brief.dart';
import '../services/app_settings.dart';
import '../services/brief_widget.dart';
import '../theme/app_theme.dart';
import '../widgets/frank_backdrop.dart';
import '../widgets/ui/frank_ui.dart';

/// Which sections the Brief shows, and in what order (drag to reorder).
class BriefSettingsScreen extends StatelessWidget {
  const BriefSettingsScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return FrankBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Customize Brief')),
        body: ListenableBuilder(
          listenable: settings,
          builder: (context, _) {
            final order = settings.briefOrder;
            return ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.x2,
                AppSpace.gutter,
                AppSpace.x10,
              ),
              header: Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.x4),
                child: Text(
                  'Turn sections on or off, and drag them into the order you '
                  'want. Hermes writes every section; this only changes what '
                  'you see.',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 15,
                    height: 1.47,
                  ),
                ),
              ),
              footer: _WidgetSettings(settings: settings),
              itemCount: order.length,
              onReorderItem: (from, to) {
                final next = List.of(order);
                next.insert(to, next.removeAt(from));
                settings.setBriefOrder(next);
              },
              itemBuilder: (context, index) {
                final id = order[index];
                return Padding(
                  key: ValueKey(id),
                  padding: const EdgeInsets.only(bottom: AppSpace.x2),
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    child: Row(
                      children: [
                        Expanded(
                          child: FrankSwitchTile(
                            title: briefSectionNames[id] ?? id,
                            value: !settings.briefHidden.contains(id),
                            onChanged: (shown) =>
                                settings.setBriefShown(id, shown),
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: AppColors.hint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// What the home-screen widget shows, and a button to add it.
class _WidgetSettings extends StatelessWidget {
  const _WidgetSettings({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MicroLabel('Home-screen widget'),
          FrankGroup(
            children: [
              FrankSwitchTile(
                title: 'Headline',
                subtitle: 'The one thing that matters most',
                value: settings.widgetHeadline,
                onChanged: settings.setWidgetHeadline,
              ),
              for (final id in widgetSectionIds)
                FrankSwitchTile(
                  title: briefSectionNames[id] ?? id,
                  subtitle: id == 'money'
                      ? 'Shows on your home screen, outside Hermsy\'s lock'
                      : null,
                  value: settings.widgetSections.contains(id),
                  onChanged: (shown) => settings.setWidgetSection(id, shown),
                ),
              FrankSwitchTile(
                title: 'Suggestion count',
                value: settings.widgetSuggestions,
                onChanged: settings.setWidgetSuggestions,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.x4),
          GoldButton(
            label: 'Add widget to home screen',
            icon: Icons.widgets_outlined,
            onPressed: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              if (!await pinBriefWidget()) {
                messenger?.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Long-press your home screen, tap Widgets, and find '
                      'Hermsy Brief.',
                    ),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: AppSpace.x2),
          Text(
            'The widget shows up to four rows, in the Brief\'s order. Tap it '
            'to open the Brief.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.hint, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
