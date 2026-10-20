import 'package:control/control.dart';
import 'package:extracter/src/feature/whisper_models/data/whisper_models_repository.dart';
import 'package:extracter/src/feature/whisper_models/models/whisper_model_item.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'whisper_models_controller.freezed.dart';

@freezed
sealed class WhisperModelsState with _$WhisperModelsState {
  const factory WhisperModelsState.initial() = WhisperModels$InitialState;

  const factory WhisperModelsState.inProgress() = WhisperModels$InProgressState;

  const factory WhisperModelsState.error() = WhisperModels$ErrorState;

  const factory WhisperModelsState.completed(WhisperModelsSnapshot snapshot) = WhisperModels$CompletedState;
}

/// The model catalogue with installed / reserved state on this device.
final class WhisperModelsController extends StateController<WhisperModelsState> with SequentialControllerHandler {
  WhisperModelsController({
    required IWhisperModelsRepository whisperModelsRepository,
    super.initialState = const WhisperModelsState.initial(),
  }) : _repository = whisperModelsRepository;

  final IWhisperModelsRepository _repository;

  /// For the config widget to reload when model files change.
  Listenable get changes => _repository.changes;

  /// [silent] keeps the current list on screen while refreshing.
  void load({bool silent = false}) => handle(() async {
    if (!silent || state is! WhisperModels$CompletedState) setState(const WhisperModelsState.inProgress());
    setState(WhisperModelsState.completed(await _repository.load()));
  }, error: (error, stackTrace) async => setState(const WhisperModelsState.error()));
}
