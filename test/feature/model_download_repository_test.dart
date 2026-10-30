import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/model_store/model_store.dart';
import 'package:extracter/src/common/utils/cancel_token.dart';
import 'package:extracter/src/feature/whisper_model_download/data/whisper_model_download_repository.dart';
import 'package:extracter/src/feature/whisper_model_download/models/model_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A fake model whose bytes we control (the catalogue entry only lends its id).
final List<int> _bytes = List<int>.generate(100000, (i) => i % 251);
final WhisperModelSpec _spec = WhisperModelSpec(
  id: 'tiny',
  fileName: WhisperModelSpec.byId('tiny')!.fileName,
  sizeBytes: _bytes.length,
  sha256: sha256.convert(_bytes).toString(),
  supportsTranslate: true,
  minRamGb: 0,
  accuracy: 1,
);

void main() {
  late Directory dir;
  late ModelStore store;
  final requests = <http.BaseRequest>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('download_test');
    store = ModelStore(directory: dir);
    await store.initialize();
    requests.clear();
  });

  tearDown(() => dir.delete(recursive: true));

  WhisperModelDownloadRepositoryImpl repo(
    Future<http.StreamedResponse> Function(http.BaseRequest request) handler, {
    int? freeBytes,
  }) => WhisperModelDownloadRepositoryImpl(
    modelStore: store,
    freeDiskBytes: (_) => freeBytes,
    clientFactory: () => MockClient.streaming((request, _) {
      requests.add(request);
      return handler(request);
    }),
  );

  http.StreamedResponse full([List<int>? body]) =>
      http.StreamedResponse(Stream.value(body ?? _bytes), 200, contentLength: (body ?? _bytes).length);

  http.StreamedResponse partial(int from, {String? range}) => http.StreamedResponse(
    Stream.value(_bytes.sublist(from)),
    206,
    headers: {'content-range': range ?? 'bytes $from-${_bytes.length - 1}/${_bytes.length}'},
  );

  Future<ModelDownloadFailure?> run(WhisperModelDownloadRepositoryImpl r, [CancelToken? token]) async {
    try {
      await r.download(_spec, token ?? CancelToken()).drain<void>();
      return null;
    } on ModelDownloadException catch (e) {
      return e.reason;
    }
  }

  test('200: downloads, verifies SHA-256, renames atomically, installs', () async {
    expect(await run(repo((_) async => full())), isNull);
    expect(store.isInstalled('tiny'), isTrue);
    expect(File(store.filePath(_spec)).readAsBytesSync(), _bytes);
    expect(File(store.partPath(_spec)).existsSync(), isFalse);
  });

  test('resumes a .part with Range when the server answers a matching 206', () async {
    await File(store.partPath(_spec)).writeAsBytes(_bytes.sublist(0, 40000));
    expect(await run(repo((r) async => partial(40000))), isNull);
    expect(requests.single.headers['Range'], 'bytes=40000-');
    expect(store.isInstalled('tiny'), isTrue);
  });

  test('206 with a Content-Range that does not continue the .part restarts from 0', () async {
    await File(store.partPath(_spec)).writeAsBytes(_bytes.sublist(0, 40000));
    final r = repo(
      (req) async => req.headers.containsKey('Range') ? partial(40000, range: 'bytes 39000-99999/100000') : full(),
    );
    expect(await run(r), isNull);
    expect(requests, hasLength(2));
    expect(requests.last.headers.containsKey('Range'), isFalse);
    expect(File(store.filePath(_spec)).readAsBytesSync(), _bytes);
  });

  test('server ignoring Range (200) truncates the .part instead of appending', () async {
    await File(store.partPath(_spec)).writeAsBytes(List.filled(40000, 7));
    expect(await run(repo((_) async => full())), isNull);
    expect(File(store.filePath(_spec)).readAsBytesSync(), _bytes);
  });

  test('size mismatch and hash mismatch are refused; corrupt file removed', () async {
    expect(await run(repo((_) async => full(List.filled(10, 1)))), ModelDownloadFailure.sizeMismatch);
    final corrupt = List<int>.of(_bytes)..[500] ^= 0xff;
    expect(await run(repo((_) async => full(corrupt))), ModelDownloadFailure.hashMismatch);
    expect(File(store.partPath(_spec)).existsSync(), isFalse);
    expect(store.isInstalled('tiny'), isFalse);
    expect(store.stateOf('tiny'), ModelFileState.absent, reason: 'store released after failure');
  });

  test('HTTP error status and low storage', () async {
    expect(await run(repo((_) async => http.StreamedResponse(const Stream.empty(), 503))), ModelDownloadFailure.server);
    expect(await run(repo((_) async => full(), freeBytes: 10)), ModelDownloadFailure.lowStorage);
    expect(requests, hasLength(1), reason: 'no request when storage is too low');
  });

  test('cancel stops the download and keeps the .part for resume', () async {
    final token = CancelToken();
    final body = StreamController<List<int>>();
    final r = repo((_) async => http.StreamedResponse(body.stream, 200, contentLength: _bytes.length));
    final result = run(r, token);
    await Future<void>.delayed(Duration.zero);
    body.add(_bytes.sublist(0, 30000));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    token.cancel();
    body.add(_bytes.sublist(30000));
    unawaited(body.close());
    expect(await result, ModelDownloadFailure.cancelled);
    expect(store.isInstalled('tiny'), isFalse);
    expect(File(store.partPath(_spec)).existsSync(), isTrue);
  });

  test('a second download of the same model is refused as busy', () async {
    store.beginDownload('tiny');
    expect(await run(repo((_) async => full())), ModelDownloadFailure.busy);
    store.abortDownload('tiny');
  });
}
