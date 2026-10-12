import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/sharing/ai_share_scope.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The one path by which a consented AI-share snapshot leaves the device
/// (ADR-009's scoped exception to "medications never reach Supabase").
///
/// Thin client over the `ai-share-snapshot` edge function, called with the
/// app's own Supabase session JWT. The caller passes the exact brief text
/// the user previewed; this client never builds, edits or enriches it.
/// Storage, encryption and expiry are the edge function's job, so this file
/// touches no table. `test/safety_invariants/no_health_in_supabase_test.dart`
/// pins this file as the only sender of a health payload.
class AiShareSnapshotClient {
  AiShareSnapshotClient({required this.invoke, required this.isSignedIn});

  /// Production wiring. Reads the Supabase client lazily so constructing
  /// this (for example inside `PGAuthService`) never needs Supabase ready.
  factory AiShareSnapshotClient.production([SupabaseClient? client]) {
    SupabaseClient supabase() => client ?? Supabase.instance.client;
    return AiShareSnapshotClient(
      isSignedIn: () {
        try {
          return supabase().auth.currentSession != null;
        } on Object {
          return false;
        }
      },
      invoke: (method, body) async {
        try {
          final response = await supabase().functions.invoke(
            functionName,
            body: body,
            method: method,
          );
          return AiShareInvokeResponse(
            status: response.status,
            data: response.data,
          );
        } on FunctionException catch (e) {
          // Server details are dropped on purpose: they never reach logs.
          throw AiShareSnapshotRequestFailed(e.status);
        }
      },
    );
  }

  static const functionName = 'ai-share-snapshot';
  static const payloadFormat = 'pharmaguide-brief-markdown/v1';
  static const minTtlHours = 24;
  static const maxTtlHours = 720;
  static const defaultTtlHours = minTtlHours;

  final Future<AiShareInvokeResponse> Function(
    HttpMethod method,
    Map<String, Object?> body,
  )
  invoke;
  final bool Function() isSignedIn;

  static int clampTtlHours(int hours) =>
      hours.clamp(minTtlHours, maxTtlHours).toInt();

  /// A short, content-free revision of the local stack: changes whenever a
  /// row is added, edited or removed. Lets the server mark a snapshot stale.
  static String stackRevisionFor(Iterable<UserStacksLocalData> rows) {
    final lines =
        rows
            .map(
              (r) =>
                  '${r.id}|${r.type}|${r.clientUpdatedAt.toUtc().toIso8601String()}'
                  '|${r.deletedAt?.toUtc().toIso8601String() ?? ''}',
            )
            .toList()
          ..sort();
    return sha256
        .convert(utf8.encode(lines.join('\n')))
        .toString()
        .substring(0, 16);
  }

  /// The revision sent with a snapshot. Medication rows count only when
  /// medications are in the scope, so a change to something the user did
  /// not share is not signalled to the server either.
  static String stackRevisionForScope(
    Iterable<UserStacksLocalData> rows,
    AiShareScope scope,
  ) {
    final shareMedications = scope.normalized.medicationNames;
    return stackRevisionFor(
      rows.where((r) => r.type != 'medication' || shareMedications),
    );
  }

  /// Uploads [payload] (the previewed brief) bound to one connection.
  Future<AiShareSnapshotReceipt> upload({
    required String connectionId,
    required AiShareScope scope,
    required String stackRevision,
    required int ttlHours,
    required String payload,
  }) async {
    _requireSignedIn();
    final normalized = scope.normalized;
    if (connectionId.trim().isEmpty) {
      throw ArgumentError.value(connectionId, 'connectionId', 'is empty');
    }
    if (normalized.isEmpty) {
      throw ArgumentError('An empty scope shares nothing.');
    }
    if (payload.trim().isEmpty) {
      throw ArgumentError('The payload is empty.');
    }
    final response = await invoke(HttpMethod.post, {
      'connection_id': connectionId,
      'scope': normalized.toJson(),
      'stack_revision': stackRevision,
      'ttl_hours': clampTtlHours(ttlHours),
      'format': payloadFormat,
      'payload': payload,
    });
    final data = response.data;
    final snapshotId = data is Map ? data['snapshot_id'] : null;
    final expiresAt = data is Map
        ? DateTime.tryParse('${data['expires_at']}')
        : null;
    if (response.status != 201 || snapshotId is! String || expiresAt == null) {
      throw AiShareSnapshotRequestFailed(response.status);
    }
    return AiShareSnapshotReceipt(snapshotId: snapshotId, expiresAt: expiresAt);
  }

  /// Deletes every snapshot bound to [connectionId].
  Future<void> delete(String connectionId) async {
    _requireSignedIn();
    if (connectionId.trim().isEmpty) {
      throw ArgumentError.value(connectionId, 'connectionId', 'is empty');
    }
    await _delete({'connection_id': connectionId});
  }

  /// Deletes every snapshot of the signed-in user (sign-out purge, S5).
  Future<void> deleteAll() async {
    _requireSignedIn();
    await _delete({'all': true});
  }

  Future<void> _delete(Map<String, Object?> body) async {
    final response = await invoke(HttpMethod.delete, body);
    if (response.status != 204 && response.status != 200) {
      throw AiShareSnapshotRequestFailed(response.status);
    }
  }

  void _requireSignedIn() {
    if (!isSignedIn()) throw const AiShareNotSignedIn();
  }
}

class AiShareInvokeResponse {
  const AiShareInvokeResponse({required this.status, required this.data});

  final int status;
  final Object? data;
}

class AiShareSnapshotReceipt {
  const AiShareSnapshotReceipt({
    required this.snapshotId,
    required this.expiresAt,
  });

  final String snapshotId;
  final DateTime expiresAt;
}

/// Base type for AI-share failures. Messages carry no payload or server text.
sealed class AiShareSnapshotException implements Exception {
  const AiShareSnapshotException();
}

/// Sharing with an assistant needs an account; a guest never uploads.
class AiShareNotSignedIn extends AiShareSnapshotException {
  const AiShareNotSignedIn();

  @override
  String toString() => 'AiShareNotSignedIn';
}

class AiShareSnapshotRequestFailed extends AiShareSnapshotException {
  const AiShareSnapshotRequestFailed(this.status);

  final int status;

  @override
  String toString() => 'AiShareSnapshotRequestFailed(status: $status)';
}
