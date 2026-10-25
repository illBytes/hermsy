import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/voice_models.dart';
import '../theme/app_theme.dart';
import '../widgets/frank_backdrop.dart';
import '../widgets/ui/frank_ui.dart';

/// One line for the Settings row: where the voice models stand.
String voiceModelsSummary(VoiceModelStore store) {
  if (store.copying case final copying?) {
    return 'Copying from the folder · ${(copying * 100).floor()}%';
  }
  if (store.allReady) {
    return 'Ready · ${formatBytes(store.diskBytes)} on this phone';
  }
  final total = formatBytes(store.totalBytes);
  if (store.downloading) {
    final percent = (store.receivedBytes * 100 / store.totalBytes).floor();
    return 'Downloading · $percent% of $total';
  }
  if (store.pausedReason != null) {
    return '${store.pausedReason} · ${formatBytes(store.receivedBytes)} of $total';
  }
  if (store.receivedBytes > 0) {
    return 'Paused · ${formatBytes(store.receivedBytes)} of $total';
  }
  return 'Not downloaded · $total';
}

/// The on-device voice models: what they are, how far along they are, and
/// download, pause and delete.
class VoiceModelsScreen extends StatelessWidget {
  const VoiceModelsScreen({
    super.key,
    required this.store,
    required this.settings,
  });

  final VoiceModelStore store;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return FrankBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListenableBuilder(
          listenable: Listenable.merge([store, settings]),
          builder: (context, _) {
            final media = MediaQuery.of(context);
            final side = math.max(
              AppSpace.gutter,
              (media.size.width - 640) / 2,
            );
            return CustomScrollView(
              slivers: [
                const LargeTitleSliverBar(title: 'Voice models'),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    side,
                    AppSpace.x2,
                    side,
                    AppSpace.x10 + media.padding.bottom,
                  ),
                  sliver: SliverList.list(
                    children: [
                      Text(
                        'Voice mode listens, transcribes and speaks on this '
                        'phone, so your voice never leaves it. These models '
                        'download once.',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontSize: 15,
                          height: 1.47,
                        ),
                      ),
                      const SizedBox(height: AppSpace.x6),
                      _Overall(store: store, settings: settings),
                      const SizedBox(height: AppSpace.x6),
                      const MicroLabel('Models'),
                      FrankGroup(
                        children: [
                          for (final model in store.models)
                            _ModelTile(model: model, store: store),
                        ],
                      ),
                      if (store.extras.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        const MicroLabel('Optional'),
                        FrankGroup(
                          children: [
                            for (final model in store.extras)
                              _ModelTile(
                                model: model,
                                store: store,
                                onTap: () => _extra(context, model),
                              ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            4,
                            AppSpace.x2,
                            4,
                            0,
                          ),
                          child: Text(
                            'Choose which Kokoro speaks under Hermsy\'s voice. '
                            'Voice mode works without these.',
                            style: TextStyle(
                              color: AppColors.hint,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      const MicroLabel('Download'),
                      FrankGroup(
                        children: [
                          FrankTile(
                            icon: Icons.drive_folder_upload_outlined,
                            title: 'Import from a folder',
                            subtitle:
                                'Copy models already on this phone, from '
                                'your computer or another Hermsy, instead '
                                'of downloading them',
                            onTap: store.downloading
                                ? null
                                : () => _import(context),
                          ),
                          FrankSwitchTile(
                            icon: Icons.wifi_rounded,
                            title: 'Download on Wi-Fi only',
                            subtitle:
                                'Wait for Wi-Fi instead of using mobile '
                                'data',
                            value: settings.voiceModelsWifiOnly,
                            onChanged: settings.setVoiceModelsWifiOnly,
                          ),
                        ],
                      ),
                      if (store.allReady ||
                          store.receivedBytes > 0 ||
                          store.extras.any(store.isReady)) ...[
                        const SizedBox(height: 28),
                        FrankGroup(
                          children: [
                            FrankTile(
                              icon: Icons.delete_outline_rounded,
                              title: 'Delete voice models',
                              subtitle:
                                  'Frees the space. Voice mode needs '
                                  'them again to work.',
                              danger: true,
                              onTap: () => _delete(context),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    String note;
    try {
      final imported = await store.importFromFolder();
      final failed = [...store.models, ...store.extras]
          .where((m) => store.progressOf(m).state == ModelState.failed)
          .map((m) => m.name)
          .toList();
      note = imported.isEmpty && failed.isEmpty
          ? 'No voice models in that folder. Pick the folder that holds '
                'them (for example "Hermsy voice models" in Download).'
          : [
              if (imported.isNotEmpty) 'Added ${imported.join(', ')}.',
              if (failed.isNotEmpty)
                '${failed.join(', ')} could not be used; download '
                    '${failed.length == 1 ? 'it' : 'them'} instead.',
            ].join(' ');
    } catch (error) {
      note = 'Could not copy the models: $error';
    }
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(note)));
  }

  /// An optional model: download it, pause it, or remove it.
  Future<void> _extra(BuildContext context, VoiceModel model) async {
    final state = store.progressOf(model).state;
    if (state == ModelState.ready) {
      final ok = await showFrankConfirm(
        context,
        title: 'Remove ${model.name}?',
        message:
            'This frees ${formatBytes(model.diskBytes)}. Hermsy goes back to '
            'the compressed Kokoro.',
        confirmLabel: 'Remove',
        destructive: true,
      );
      if (ok) {
        if (model.id == kokoroFull.id) {
          await settings.setKokoroFull(false);
        }
        await store.delete(model);
      }
      return;
    }
    if (store.downloading) {
      store.cancel();
      return;
    }
    await store.download(model, wifiOnly: settings.voiceModelsWifiOnly);
  }

  Future<void> _delete(BuildContext context) async {
    final extras = store.extras
        .where(store.isReady)
        .fold(0, (sum, m) => sum + m.diskBytes);
    final kept = math.max(
      store.receivedBytes,
      store.allReady ? store.diskBytes : 0,
    );
    final ok = await showFrankConfirm(
      context,
      title: 'Delete voice models?',
      message:
          'This removes ${formatBytes(kept + extras)} '
          'from this phone. Voice mode will need them downloaded again.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) {
      await store.deleteAll();
    }
  }
}

/// The whole download: a bar, the bytes, and the one button that matters.
class _Overall extends StatelessWidget {
  const _Overall({required this.store, required this.settings});

  final VoiceModelStore store;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final fraction =
        store.copying ??
        (store.allReady
            ? 1.0
            : (store.receivedBytes / store.totalBytes).clamp(0.0, 1.0));
    final failed = store.models
        .map(store.progressOf)
        .where((p) => p.state == ModelState.failed)
        .toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            voiceModelsSummary(store),
            style: AppText.label.copyWith(fontSize: 16),
          ),
          const SizedBox(height: AppSpace.x3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              color: store.allReady ? AppColors.mint : AppColors.gold,
              backgroundColor: AppColors.hairline,
            ),
          ),
          if (failed.isNotEmpty) ...[
            const SizedBox(height: AppSpace.x3),
            Text(
              failed.first.error ?? 'A download failed.',
              style: AppText.bodySmall.copyWith(color: AppColors.danger),
            ),
          ],
          if (!store.allReady && store.copying == null) ...[
            const SizedBox(height: AppSpace.x4),
            if (store.downloading)
              GoldButton(
                label: 'Pause',
                icon: Icons.pause_rounded,
                onPressed: store.cancel,
              )
            else
              GoldButton(
                label: store.receivedBytes > 0 ? 'Resume download' : 'Download',
                icon: Icons.download_rounded,
                onPressed: () =>
                    store.downloadAll(wifiOnly: settings.voiceModelsWifiOnly),
              ),
            const SizedBox(height: AppSpace.x2),
            Text(
              'Keep Hermsy open while it downloads. If it stops, it picks up '
              'where it left off.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.hint, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.model, required this.store, this.onTap});

  final VoiceModel model;
  final VoiceModelStore store;

  /// For optional models, which are managed one by one.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final progress = store.progressOf(model);
    final size = formatBytes(model.downloadBytes);
    final (String state, Color color) = switch (progress.state) {
      ModelState.ready => ('Ready', AppColors.mint),
      ModelState.downloading => (
        '${(progress.received * 100 / model.downloadBytes).floor()}%',
        AppColors.gold,
      ),
      ModelState.verifying => ('Checking', AppColors.gold),
      ModelState.unpacking => ('Unpacking', AppColors.gold),
      ModelState.failed => ('Failed', AppColors.danger),
      ModelState.missing =>
        progress.received > 0
            ? (
                '${(progress.received * 100 / model.downloadBytes).floor()}%',
                AppColors.hint,
              )
            : (size, AppColors.hint),
    };
    final action = onTap == null
        ? null
        : switch (progress.state) {
            ModelState.ready => 'tap to remove',
            ModelState.downloading ||
            ModelState.verifying ||
            ModelState.unpacking => 'tap to pause',
            _ => progress.received > 0 ? 'tap to resume' : 'tap to download',
          };
    return FrankTile(
      icon: switch (model.id) {
        'vad' => Icons.graphic_eq_rounded,
        'stt' => Icons.hearing_rounded,
        _ => Icons.record_voice_over_rounded,
      },
      title: model.name,
      onTap: onTap,
      // The size sits on the right until there is progress to show there.
      subtitle: [model.role, if (state != size) size, ?action].join(' · '),
      trailing: Text(
        state,
        style: AppText.tabular.copyWith(fontSize: 14, color: color),
      ),
    );
  }
}
