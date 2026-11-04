import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

const _id = '018f4c79-7c7e-4c70-9d62-7fc3b9ce6a11';
const _photoId = '10000000-0000-4000-8000-000000000001';

ProductSubmissionPhoto _photo([int byte = 1]) => ProductSubmissionPhoto(
  photoId: _photoId,
  categories: MissingProductSubmissionDraft.requiredCategories,
  bytes: Uint8List.fromList([byte, 2, 3]),
  contentType: 'image/jpeg',
);

LabelMismatchReportDraft _draft([int byte = 1]) => LabelMismatchReportDraft(
  submissionId: _id,
  product: LabelMismatchProductMetadata(dsldId: '12345'),
  categories: {LabelMismatchCategory.amountOrUnit},
  photos: [_photo(byte)],
);

ProductSubmissionRetake _retake() => ProductSubmissionRetake.plan(
  submissionId: _id,
  upc: '050428381397',
  fromRevision: 1,
  membership: const [],
  requestedPanels: {ProductSubmissionEvidenceCategory.supplementFacts},
);

ProductSubmissionService _service(_Backend backend) => ProductSubmissionService(
  backend: backend,
  rpcTimeout: const Duration(milliseconds: 30),
  photoUploadTimeout: const Duration(milliseconds: 30),
);

void main() {
  test(
    'shared backend joins exact attempts and rejects conflicting bytes',
    () async {
      final gate = Completer<void>();
      final backend = _Backend()..gates['create'] = gate;
      final service = _service(backend);
      final other = _service(backend);
      final first = service.submit(_draft());
      final transfer = service.activeTransfer(_id)!;
      final second = other.submit(_draft());
      expect(identical(first, second), isTrue);
      expect(identical(other.activeTransfer(_id), transfer), isTrue);
      final conflict = await other.submit(_draft(9));
      expect(conflict, isA<ProductSubmissionFailure>());
      expect(backend.calls, ['create']);
      gate.complete();
      expect(await first, isA<ProductSubmissionSuccess>());
      expect(await transfer.result, isA<ProductSubmissionSuccess>());
      expect(transfer.phase, ProductSubmissionPhase.succeeded);
      expect(transfer.completedPhotos, 1);
      expect(other.activeTransfer(_id), isNull);
      expect(backend.calls, ['create', 'preflight', 'upload', 'finalize']);
    },
  );

  test('registry lookup and lifecycle events are account scoped', () async {
    final gate = Completer<void>();
    final backend = _Backend()..gates['create'] = gate;
    final service = _service(backend);
    var changes = 0;
    final subscription = service.transferChanges.listen((_) => changes++);
    final result = service.submit(_draft());
    await Future<void>.delayed(Duration.zero);
    expect(changes, 1);
    backend.authenticatedUserId = 'other';
    expect(service.activeTransfer(_id), isNull);
    gate.complete();
    expect(
      (await result as ProductSubmissionFailure).kind,
      ProductSubmissionFailureKind.authenticationRequired,
    );
    await Future<void>.delayed(Duration.zero);
    expect(changes, 1);
    expect(backend.calls, ['create']);
    await subscription.cancel();
  });

  for (final retake in [false, true]) {
    final stages = retake
        ? ['open', 'preflight', 'add', 'upload', 'finalize']
        : ['create', 'preflight', 'upload', 'finalize'];
    for (final stage in stages) {
      test(
        '${retake ? 'retake' : 'initial'} timeout at $stage is terminal, not success',
        () async {
          final gate = Completer<void>();
          final backend = _Backend()..gates[stage] = gate;
          final service = _service(backend);
          final phases = <ProductSubmissionPhase>[];
          final progress = <int>[];
          var lifecycle = 0;
          final subscription = service.transferChanges.listen(
            (_) => lifecycle++,
          );
          final result = retake
              ? service.submitRetake(
                  _retake(),
                  [_photo()],
                  onPhaseChanged: phases.add,
                  onPhotoProgress: (done, _) => progress.add(done),
                )
              : service.submit(
                  _draft(),
                  onPhaseChanged: phases.add,
                  onPhotoProgress: (done, _) => progress.add(done),
                );
          final transfer = service.activeTransfer(_id)!;
          expect(await result, isA<ProductSubmissionFailure>());
          expect(transfer.phase, ProductSubmissionPhase.failed);
          expect(service.activeTransfer(_id), isNull);
          final calls = List<String>.of(backend.calls);
          final completed = List<int>.of(progress);
          gate.complete();
          await Future<void>.delayed(Duration.zero);
          expect(backend.calls, calls);
          expect(progress, completed);
          expect(phases, isNot(contains(ProductSubmissionPhase.succeeded)));
          expect(lifecycle, 2);
          await subscription.cancel();
        },
      );
      test(
        '${retake ? 'retake' : 'initial'} account switch after $stage stops transfer',
        () async {
          final backend = _Backend()
            ..afterStage = (stageName, backend) {
              if (stageName == stage) backend.authenticatedUserId = 'other';
            };
          final service = _service(backend);
          final result = retake
              ? await service.submitRetake(_retake(), [_photo()])
              : await service.submit(_draft());
          expect(
            (result as ProductSubmissionFailure).kind,
            ProductSubmissionFailureKind.authenticationRequired,
          );
          expect(backend.calls.last, stage);
          expect(backend.calls.length, stages.indexOf(stage) + 1);
        },
      );
    }
  }

  test(
    'late upload does not change a newer transfer or publish old progress',
    () async {
      final oldGate = Completer<void>();
      final newGate = Completer<void>();
      final backend = _Backend()..gates['upload'] = oldGate;
      final service = _service(backend);
      final oldFuture = service.submit(_draft());
      final oldTransfer = service.activeTransfer(_id)!;
      expect(await oldFuture, isA<ProductSubmissionFailure>());
      backend.finalizeCalls = 0;
      backend.gates['upload'] = newGate;
      final next = service.submit(_draft());
      final nextTransfer = service.activeTransfer(_id)!;
      oldGate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(identical(service.activeTransfer(_id), nextTransfer), isTrue);
      expect(oldTransfer.phase, ProductSubmissionPhase.failed);
      expect(oldTransfer.completedPhotos, 0);
      newGate.complete();
      expect(await next, isA<ProductSubmissionSuccess>());
    },
  );

  test(
    'retake snapshots caller list and reports every acknowledged photo',
    () async {
      final gate = Completer<void>();
      final backend = _Backend()..gates['open'] = gate;
      final service = _service(backend);
      final photos = [_photo()];
      final progress = <int>[];
      final result = service.submitRetake(
        _retake(),
        photos,
        onPhotoProgress: (done, _) => progress.add(done),
      );
      photos.clear();
      gate.complete();
      expect(await result, isA<ProductSubmissionSuccess>());
      expect(backend.calls, ['open', 'preflight', 'add', 'upload', 'finalize']);
      expect(backend.uploaded.single, [1, 2, 3]);
      expect(progress, [0, 1]);
    },
  );

  test('preflight ready succeeds without mutating ready objects', () async {
    final backend = _Backend()..alreadyReady = true;
    final service = _service(backend);
    final result = service.submit(_draft());
    final transfer = service.activeTransfer(_id)!;
    expect(await result, isA<ProductSubmissionSuccess>());
    expect(backend.calls, ['create', 'preflight']);
    expect(transfer.completedPhotos, transfer.totalPhotos);
  });

  test('false final finalize is not partial success', () async {
    final backend = _Backend()..finalizeReady = false;
    final result = await _service(backend).submit(_draft());
    expect(
      (result as ProductSubmissionFailure).kind,
      ProductSubmissionFailureKind.reportFinalizeFailed,
    );
  });
}

class _Backend implements ProductSubmissionBackend {
  @override
  String? authenticatedUserId = 'owner';
  final calls = <String>[];
  final gates = <String, Completer<void>>{};
  final uploaded = <Uint8List>[];
  void Function(String, _Backend)? afterStage;
  int finalizeCalls = 0;
  bool alreadyReady = false;
  bool finalizeReady = true;

  Future<void> _call(String stage) async {
    calls.add(stage);
    final gate = gates[stage];
    if (gate != null) await gate.future;
    afterStage?.call(stage, this);
  }

  @override
  Future<void> persistSubmission({
    required String functionName,
    required Map<String, Object?> payload,
  }) => _call(
    functionName == ProductSubmissionService.createFunction ? 'create' : 'add',
  );

  @override
  Future<bool> finalizeSubmission({
    required String functionName,
    required String submissionId,
    int? expectedRevision,
  }) async {
    final preflight = finalizeCalls++ == 0;
    await _call(preflight ? 'preflight' : 'finalize');
    return preflight ? alreadyReady : finalizeReady;
  }

  @override
  Future<void> uploadPhoto({
    required String bucket,
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) async {
    await _call('upload');
    uploaded.add(bytes);
  }

  @override
  Future<int> openEvidenceRevision({
    required Map<String, Object?> payload,
  }) async {
    await _call('open');
    return 2;
  }

  @override
  Future<Map<String, Object?>> fetchIntake({
    required String functionName,
    required Map<String, Object?> payload,
  }) => throw UnimplementedError();
  @override
  Future<Map<String, Object?>> fetchOwnEvidence({
    required String submissionId,
  }) => throw UnimplementedError();
  @override
  Future<List<Map<String, Object?>>> listOwnSubmissions({
    required String table,
    required int offset,
    required int limit,
  }) => throw UnimplementedError();
}
