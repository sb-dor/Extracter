import 'dart:io';

import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/model_store/model_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late ModelStore store;
  final tiny = WhisperModelSpec.byId('tiny')!;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('model_store_test');
    // An installed model is a final-named file of the exact catalogue size.
    await File('${dir.path}/${tiny.fileName}').writeAsBytes(List.filled(tiny.sizeBytes, 0));
    store = ModelStore(directory: dir);
    await store.initialize();
  });

  tearDown(() => dir.delete(recursive: true));

  test('detects installed models by exact size only', () async {
    expect(store.isInstalled('tiny'), isTrue);
    expect(store.isInstalled('base'), isFalse);
    final base = WhisperModelSpec.byId('base')!;
    await File('${dir.path}/${base.fileName}').writeAsBytes([1, 2, 3]);
    final other = ModelStore(directory: dir);
    await other.initialize();
    expect(other.isInstalled('base'), isFalse, reason: 'truncated file is not installed');
  });

  test('reservation blocks delete until released; release is idempotent', () async {
    final a = store.reserve('tiny');
    final b = store.reserve('tiny');
    expect(store.reservationsOf('tiny'), 2);
    await expectLater(store.delete('tiny'), throwsA(isA<ModelInUseException>()));
    a
      ..release()
      ..release();
    expect(store.reservationsOf('tiny'), 1);
    b.release();
    expect(store.reservationsOf('tiny'), 0);
    await store.delete('tiny');
    expect(store.isInstalled('tiny'), isFalse);
    expect(File(store.filePath(tiny)).existsSync(), isFalse);
  });

  test('cannot reserve a missing model', () {
    expect(() => store.reserve('base'), throwsA(isA<ModelNotInstalledException>()));
    expect(() => store.reserve('nope'), throwsA(isA<ModelNotInstalledException>()));
  });

  test('download and delete exclude each other', () async {
    store.beginDownload('base');
    expect(() => store.beginDownload('base'), throwsA(isA<ModelBusyException>()));
    expect(store.stateOf('base'), ModelFileState.downloading);
    store.abortDownload('base');
    expect(store.stateOf('base'), ModelFileState.absent);
    expect(() => store.beginDownload('tiny'), throwsA(isA<ModelBusyException>()), reason: 'already installed');
  });

  test('notifies listeners on every state change', () {
    var notified = 0;
    store.addListener(() => notified++);
    store.reserve('tiny').release();
    store
      ..beginDownload('base')
      ..completeDownload('base');
    expect(notified, 4);
    expect(store.isInstalled('base'), isTrue);
  });
}
