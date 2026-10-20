import 'dart:async';

import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/utils/screen_util.dart';
import 'package:extracter/src/common/widget/app_shell.dart';
import 'package:extracter/src/feature/transcript_detail/widgets/transcript_detail_config_widget.dart';
import 'package:extracter/src/feature/transcripts/controller/transcripts_controller.dart';
import 'package:extracter/src/feature/transcripts/data/transcripts_repository.dart';
import 'package:extracter/src/feature/transcripts/widgets/controllers/transcripts_data_controller.dart';
import 'package:extracter/src/feature/transcripts/widgets/desktop/transcripts_desktop_widget.dart';
import 'package:extracter/src/feature/transcripts/widgets/mobile/transcripts_mobile_widget.dart';
import 'package:flutter/widgets.dart';

class TranscriptsConfigInhWidget extends InheritedWidget {
  const TranscriptsConfigInhWidget({required this.state, required super.child, super.key});

  final TranscriptsConfigWidgetState state;

  static TranscriptsConfigWidgetState of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<TranscriptsConfigInhWidget>()?.widget;
    assert(widget != null, 'TranscriptsConfigInhWidget was not found in element tree');
    return (widget! as TranscriptsConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(TranscriptsConfigInhWidget oldWidget) => false;
}

class TranscriptsConfigWidget extends StatefulWidget {
  const TranscriptsConfigWidget({super.key});

  @override
  State<TranscriptsConfigWidget> createState() => TranscriptsConfigWidgetState();
}

class TranscriptsConfigWidgetState extends State<TranscriptsConfigWidget> {
  late final TranscriptsController transcriptsController;
  late final TranscriptsDataController transcriptsDataController;
  late final AppShellState _shell;
  StreamSubscription<void>? _changes;
  Timer? _debounce;
  String _loadedQuery = '';

  @override
  void initState() {
    super.initState();
    transcriptsDataController = TranscriptsDataController()..addListener(_onDataChanged);
    transcriptsController = TranscriptsController(
      transcriptsRepository: TranscriptsRepositoryImpl(database: Dependencies.of(context).database),
    );
    _changes = transcriptsController.changes.listen((_) => load(silent: true));
    _shell = AppShellScope.of(context);
    _shell.requestedTranscriptId.addListener(_onRequested);
    load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _changes?.cancel();
    _shell.requestedTranscriptId.removeListener(_onRequested);
    transcriptsDataController
      ..removeListener(_onDataChanged)
      ..dispose();
    transcriptsController.dispose();
    super.dispose();
  }

  void load({bool silent = false}) {
    _loadedQuery = transcriptsDataController.query;
    transcriptsController.load(query: _loadedQuery, silent: silent);
  }

  void paginate() {
    if (transcriptsController.isProcessing) return;
    transcriptsController.paginate(query: _loadedQuery);
  }

  /// Desktop selects in place; phone/tablet pushes the transcript screen.
  void open(int id) => context.screenSizeMaybeWhen(
    orElse: () => TranscriptDetailConfigWidget.open(context, transcriptId: id),
    desktop: () => transcriptsDataController.select(id),
  );

  void _onDataChanged() {
    if (transcriptsDataController.query == _loadedQuery) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) load(silent: true);
    });
  }

  void _onRequested() {
    final id = _shell.requestedTranscriptId.value;
    if (id == null) return;
    _shell.requestedTranscriptId.value = null;
    transcriptsDataController.select(id);
  }

  @override
  Widget build(BuildContext context) => TranscriptsConfigInhWidget(
    state: this,
    child: context.screenSizeMaybeWhen(
      orElse: () => const TranscriptsMobileWidget(),
      desktop: () => const TranscriptsDesktopWidget(),
    ),
  );
}
