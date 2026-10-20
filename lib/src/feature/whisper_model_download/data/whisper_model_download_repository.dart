import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/model_store/model_store.dart';
import 'package:extracter/src/feature/whisper_model_download/models/model_download.dart';
import 'package:http/http.dart' as http;
import 'package:l/l.dart';

abstract interface class IWhisperModelDownloadRepository {
  /// Downloads [spec] into the model store. Emits progress, completes when the
  /// verified file is installed, errors with [ModelDownloadException].
  Stream<ModelDownloadProgress> download(WhisperModelSpec spec, DownloadCancelToken token);
}

final class WhisperModelDownloadRepositoryImpl implements IWhisperModelDownloadRepository {
  WhisperModelDownloadRepositoryImpl({
    required ModelStore modelStore,
    required int? Function(String directory) freeDiskBytes,
    http.Client Function()? clientFactory,
  }) : _store = modelStore,
       _freeDiskBytes = freeDiskBytes,
       _clientFactory = clientFactory ?? http.Client.new;

  final ModelStore _store;
  final int? Function(String directory) _freeDiskBytes;

  /// One client per download so closing it aborts that download only.
  final http.Client Function() _clientFactory;

  static final RegExp _contentRange = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$');

  @override
  Stream<ModelDownloadProgress> download(WhisperModelSpec spec, DownloadCancelToken token) {
    final controller = StreamController<ModelDownloadProgress>();
    Future<void>(() async {
      var began = false;
      http.Client? client;
      try {
        try {
          _store.beginDownload(spec.id);
        } on ModelBusyException {
          throw const ModelDownloadException(ModelDownloadFailure.busy);
        }
        began = true;

        final part = File(_store.partPath(spec));
        var have = part.existsSync() ? part.lengthSync() : 0;
        if (have > spec.sizeBytes) {
          await part.delete();
          have = 0;
        }
        final free = _freeDiskBytes(_store.directory.path);
        if (free != null && free < (spec.sizeBytes - have) + spec.sizeBytes ~/ 10) {
          throw const ModelDownloadException(ModelDownloadFailure.lowStorage);
        }

        client = _clientFactory();
        token.onCancel = client.close;
        var response = await _request(client, spec, have);

        if (have > 0 && response.statusCode == 206 && !_resumable(response, have, spec.sizeBytes)) {
          // The server's range does not continue our partial file: start over.
          await response.stream.drain<void>();
          have = 0;
          response = await _request(client, spec, 0);
        }
        if (response.statusCode == 200) {
          have = 0;
          final length = response.contentLength;
          if (length != null && length != spec.sizeBytes) {
            throw const ModelDownloadException(ModelDownloadFailure.sizeMismatch);
          }
        } else if (response.statusCode != 206) {
          throw ModelDownloadException(ModelDownloadFailure.server, statusCode: response.statusCode);
        }

        final raf = await part.open(mode: have == 0 ? FileMode.write : FileMode.append);
        var received = have;
        var reported = -1;
        try {
          await for (final chunk in response.stream) {
            if (token.isCancelled) break;
            received += chunk.length;
            if (received > spec.sizeBytes) throw const ModelDownloadException(ModelDownloadFailure.sizeMismatch);
            await raf.writeFrom(chunk);
            final permille = received * 1000 ~/ spec.sizeBytes;
            if (permille != reported) {
              reported = permille;
              controller.add(ModelDownloadProgress(receivedBytes: received, totalBytes: spec.sizeBytes));
            }
          }
          await raf.flush();
        } finally {
          await raf.close();
        }
        if (token.isCancelled) throw const ModelDownloadException(ModelDownloadFailure.cancelled);
        if (received != spec.sizeBytes) throw const ModelDownloadException(ModelDownloadFailure.network);

        final digest = await sha256.bind(part.openRead()).first;
        if (digest.toString() != spec.sha256) {
          await part.delete();
          throw const ModelDownloadException(ModelDownloadFailure.hashMismatch);
        }
        await part.rename(_store.filePath(spec));
        _store.completeDownload(spec.id);
        began = false;
      } on ModelDownloadException catch (e, s) {
        controller.addError(e, s);
      } on Object catch (e, s) {
        l.w('model download failed: ${e.runtimeType}');
        final reason = token.isCancelled
            ? ModelDownloadFailure.cancelled
            : e is FileSystemException
            ? ModelDownloadFailure.storage
            : ModelDownloadFailure.network;
        controller.addError(ModelDownloadException(reason), s);
      } finally {
        token.onCancel = null;
        client?.close();
        // The .part file is kept so the next attempt can resume.
        if (began) _store.abortDownload(spec.id);
        await controller.close();
      }
    }).ignore();
    return controller.stream;
  }

  Future<http.StreamedResponse> _request(http.Client client, WhisperModelSpec spec, int from) {
    final request = http.Request('GET', spec.downloadUri);
    if (from > 0) request.headers['Range'] = 'bytes=$from-';
    return client.send(request);
  }

  static bool _resumable(http.StreamedResponse response, int have, int total) {
    final match = _contentRange.firstMatch(response.headers['content-range'] ?? '');
    if (match == null) return false;
    return int.parse(match.group(1)!) == have && int.parse(match.group(3)!) == total;
  }
}
