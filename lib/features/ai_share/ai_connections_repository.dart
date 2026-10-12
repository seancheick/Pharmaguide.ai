import 'package:pharmaguide/data/supabase/supabase_contract.dart';
import 'package:pharmaguide/services/sharing/ai_share_snapshot_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One approved assistant connection (an `ai_connections` row, ADR-009 S10).
class AiConnection {
  const AiConnection({
    required this.connectionId,
    required this.clientId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.revokedAt,
  });

  final String connectionId;

  /// The verified OAuth client identifier of the assistant.
  final String clientId;

  /// `active`, `revoked` or `expired`.
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;

  /// Only an active, unexpired connection can receive a share.
  bool isLiveAt(DateTime now) =>
      status == 'active' && revokedAt == null && expiresAt.isAfter(now);

  /// Null when a required column is missing or malformed: such a row is
  /// never shown as shareable.
  static AiConnection? tryParse(Map<String, Object?> row) {
    final id = row['connection_id'];
    final clientId = row['client_id'];
    final status = row['status'];
    final createdAt = DateTime.tryParse('${row['created_at']}');
    final expiresAt = DateTime.tryParse('${row['expires_at']}');
    if (id is! String || clientId is! String || status is! String) {
      return null;
    }
    if (createdAt == null || expiresAt == null) return null;
    final revoked = row['revoked_at'];
    return AiConnection(
      connectionId: id,
      clientId: clientId,
      status: status,
      createdAt: createdAt,
      expiresAt: expiresAt,
      revokedAt: revoked == null ? null : DateTime.tryParse('$revoked'),
    );
  }
}

/// Reads the signed-in user's connections. An interface so screens are
/// tested without the global Supabase client.
abstract interface class AiConnectionsRepository {
  Future<List<AiConnection>> listMine();
}

class SupabaseAiConnectionsRepository implements AiConnectionsRepository {
  SupabaseAiConnectionsRepository([this._client]);

  final SupabaseClient? _client;

  @override
  Future<List<AiConnection>> listMine() async {
    final client = _client ?? Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw const AiShareNotSignedIn();
    // RLS limits rows to the caller; the explicit filter keeps intent clear.
    final rows = await client
        .from(SupabaseContract.aiConnectionsTable)
        .select(
          'connection_id, client_id, status, created_at, expires_at, '
          'revoked_at',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows
        .map((row) => AiConnection.tryParse(row.cast<String, Object?>()))
        .whereType<AiConnection>()
        .toList(growable: false);
  }
}
