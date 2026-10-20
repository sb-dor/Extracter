import 'dart:async';

import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/feature/transcription_settings/controller/transcription_settings_controller.dart';
import 'package:extracter/src/feature/transcription_settings/data/transcription_settings_repository.dart';
import 'package:extracter/src/feature/transcription_settings/widgets/controllers/transcription_settings_data_controller.dart';
import 'package:extracter/src/feature/transcription_settings_save/controller/transcription_settings_save_controller.dart';
import 'package:extracter/src/feature/transcription_settings_save/data/transcription_settings_save_repository.dart';
import 'package:flutter/widgets.dart';

class TranscriptionSettingsConfigInhWidget extends InheritedWidget {
  const TranscriptionSettingsConfigInhWidget({required this.state, required super.child, super.key});

  final TranscriptionSettingsConfigWidgetState state;

  static TranscriptionSettingsConfigWidgetState of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<TranscriptionSettingsConfigInhWidget>()?.widget;
    assert(widget != null, 'TranscriptionSettingsConfigInhWidget was not found in element tree');
    return (widget! as TranscriptionSettingsConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(TranscriptionSettingsConfigInhWidget oldWidget) => false;
}

/// App-level owner of the settings draft (used by Transcribe and Models).
/// Coordinates load → draft → save, re-saving whenever the draft changed
/// while a save was in flight, so the latest value always wins.
class TranscriptionSettingsConfigWidget extends StatefulWidget {
  const TranscriptionSettingsConfigWidget({required this.child, super.key});

  final Widget child;

  @override
  State<TranscriptionSettingsConfigWidget> createState() => TranscriptionSettingsConfigWidgetState();
}

class TranscriptionSettingsConfigWidgetState extends State<TranscriptionSettingsConfigWidget> {
  late final TranscriptionSettingsController settingsController;
  late final TranscriptionSettingsSaveController settingsSaveController;
  late final TranscriptionSettingsDataController settingsDataController;

  @override
  void initState() {
    super.initState();
    final dependencies = Dependencies.of(context);
    settingsDataController = TranscriptionSettingsDataController()..addListener(_onDraftChanged);
    settingsController = TranscriptionSettingsController(
      transcriptionSettingsRepository: TranscriptionSettingsRepositoryImpl(
        sharedPreferences: dependencies.sharedPreferences,
      ),
    )..addListener(_onLoaded);
    settingsSaveController = TranscriptionSettingsSaveController(
      transcriptionSettingsSaveRepository: TranscriptionSettingsSaveRepositoryImpl(
        sharedPreferences: dependencies.sharedPreferences,
      ),
    )..addListener(_onSaved);
    settingsController.load();
  }

  @override
  void dispose() {
    settingsDataController
      ..removeListener(_onDraftChanged)
      ..dispose();
    settingsController
      ..removeListener(_onLoaded)
      ..dispose();
    settingsSaveController
      ..removeListener(_onSaved)
      ..dispose();
    super.dispose();
  }

  void _onLoaded() {
    final state = settingsController.state;
    if (state is TranscriptionSettings$CompletedState) settingsDataController.applyLoaded(state.settings);
    // A failed load keeps the defaults but still allows saving them.
    if (state is TranscriptionSettings$ErrorState) settingsDataController.applyLoaded(settingsDataController.draft);
  }

  void _onDraftChanged() {
    if (settingsDataController.isLoaded) settingsSaveController.save(settingsDataController.draft);
  }

  void _onSaved() {
    final state = settingsSaveController.state;
    if (state is! TranscriptionSettingsSave$CompletedState) return;
    // This listener runs inside the finishing save, where a new droppable
    // save would be dropped: re-check once the handler has returned.
    Timer.run(() {
      if (!mounted) return;
      final draft = settingsDataController.draft;
      if (state.settings != draft && !settingsSaveController.isProcessing) settingsSaveController.save(draft);
    });
  }

  @override
  Widget build(BuildContext context) => TranscriptionSettingsConfigInhWidget(state: this, child: widget.child);
}
