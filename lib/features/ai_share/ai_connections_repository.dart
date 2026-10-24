import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pharmaguide/data/supabase/supabase_contract.dart';
import 'package:pharmaguide/services/sharing/ai_share_snapshot_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Configured website origin also owns authenticated connection cleanup.
const aiConnectionsWebUrl = String.fromEnvironment(
  'PHARMAGUIDE_AI_CONNECTIONS_URL',
  defaultValue: 'https://pharmaguide.io/account/connections',
);

enum AiDisconnectResult { disconnected, localAccessEnded }

/// Never contains remote payloads, credentials or health information.
class AiDisconnectException implements Exception {
  const AiDisconnectException();
}

/// One approved assistant connection (an `ai_connections` row, ADR-009 S10).
class AiConnection {
  const AiConnection({
    required this.connectionId,
    required this.clientId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.revokedAt,
    this.oauthIssuer,
    this.consentId,
    this.clientName,
    this.callbackHost,
  });

  final String connectionId;

  /// The verified OAuth client identifier of the assistant.
  final String clientId;

  /// Verified metadata stored by the website approval route, never inferred
  /// from a client-supplied name or its identifier.
  final String? clientName;
  final String? callbackHost;

  String get displayName => clientName ?? clientId;

  /// `active`, `revoked` or `expired`.
  final String status;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String? oauthIssuer;
  final String? consentId;
  final DateTime? revokedAt;

  /// Only an active, unexpired connection can receive a share.
  bool isLiveAt(DateTime now) =>
      status == 'active' &&
      revokedAt == null &&
      (expiresAt?.isAfter(now) ?? (oauthIssuer != null && consentId != null));

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
    final issuer = row['oauth_issuer'];
    final consent = row['consent_id'];
    final durable =
        row.containsKey('expires_at') &&
        row['expires_at'] == null &&
        issuer is String &&
        Uri.tryParse(issuer)?.scheme == 'https' &&
        consent is String &&
        consent.startsWith('app_consent_');
    if (createdAt == null || (expiresAt == null && !durable)) return null;
    final revoked = row['revoked_at'];
    return AiConnection(
      connectionId: id,
      clientId: clientId,
      clientName: _displayText(row['client_name']),
      callbackHost: _displayText(row['callback_host']),
      status: status,
      createdAt: createdAt,
      expiresAt: expiresAt,
      revokedAt: revoked == null ? null : DateTime.tryParse('$revoked'),
      oauthIssuer: issuer is String ? issuer : null,
      consentId: consent is String ? consent : null,
    );
  }

  static String? _displayText(Object? value) {
    if (value is! String || value.length > 200) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}

/// A verified destination returned by the signed-in pairing RPC.
class AiPairingPreview {
  const AiPairingPreview({
    required this.clientName,
    required this.callbackHost,
    required this.expiresAt,
  });
  final String clientName;
  final String callbackHost;
  final DateTime expiresAt;

  static String normalizeCode(String value) {
    final code = value.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{12}$').hasMatch(code)) {
      throw const AiPairingException();
    }
    return code;
  }

  static AiPairingPreview parse(Object? value, DateTime now) {
    if (value is! Map || value.containsKey('error')) {
      throw const AiPairingException();
    }
    final name = AiConnection._displayText(value['client_name']);
    final host = AiConnection._displayText(value['callback_host']);
    final expiry = DateTime.tryParse('${value['expires_at']}');
    if (name == null ||
        host == null ||
        expiry == null ||
        !expiry.isAfter(now)) {
      throw const AiPairingException();
    }
    return AiPairingPreview(
      clientName: name,
      callbackHost: host,
      expiresAt: expiry,
    );
  }
}

/// Deliberately carries no remote error, code, token or health data.
class AiPairingException implements Exception {
  const AiPairingException();
}

/// Reads the signed-in user's connections. An interface so screens are
/// tested without the global Supabase client.
abstract interface class AiConnectionsRepository {
  Future<List<AiConnection>> listMine();
  Future<AiDisconnectResult> disconnect(String clientId);
  Future<String?> pendingRevocation();
  Object? get pairingSessionIdentity;
  Future<AiPairingPreview> previewPairing(String code);
  Future<String?> approvePairing(String code);
  Future<void> cancelPairing(String code);
}

class SupabaseAiConnectionsRepository implements AiConnectionsRepository {
  SupabaseAiConnectionsRepository([this._client, this._httpClient]);

  final http.Client? _httpClient;

  final SupabaseClient? _client;

  Future<(int, Map<String, dynamic>)> _connectionRequest(
    Map<String, String> body,
  ) async {
    final transport = _httpClient ?? http.Client();
    try {
      final destination = Uri.parse(aiConnectionsWebUrl);
      if (destination.scheme != 'https' ||
          destination.host.isEmpty ||
          destination.userInfo.isNotEmpty) {
        throw const AiDisconnectException();
      }
      final client = _client ?? Supabase.instance.client;
      final user = client.auth.currentUser?.id;
      if (user == null) throw const AiDisconnectException();
      final originalIdentity = pairingSessionIdentity;
      var session = client.auth.currentSession;
      if (session == null || session.isExpired) {
        session = (await client.auth.refreshSession().timeout(
          const Duration(seconds: 15),
        )).session;
      }
      final identity = pairingSessionIdentity;
      if (session == null ||
          session.isExpired ||
          identity == null ||
          identity != originalIdentity ||
          session.user.id != user) {
        throw const AiDisconnectException();
      }
      final request =
          http.Request(
              'POST',
              Uri.parse(destination.origin).resolve('/api/ai-connections'),
            )
            ..followRedirects = false
            ..headers.addAll({
              'authorization': 'Bearer ${session.accessToken}',
              'content-type': 'application/json',
            })
            ..body = jsonEncode(body);
      final response = await (() async => http.Response.fromStream(
        await transport.send(request),
      ))().timeout(const Duration(seconds: 20));
      if (pairingSessionIdentity != identity) {
        throw const AiDisconnectException();
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const AiDisconnectException();
      return (response.statusCode, decoded);
    } on Object {
      throw const AiDisconnectException();
    } finally {
      if (_httpClient == null) transport.close();
    }
  }

  @override
  Future<AiDisconnectResult> disconnect(String clientId) async {
    final (status, body) = await _connectionRequest({
      'action': 'disconnect',
      'client_id': clientId,
    });
    if (status == 200 && body['disconnected'] == true) {
      return AiDisconnectResult.disconnected;
    }
    if (status == 503 &&
        body['provider_handled'] == true &&
        body['local_access_ended'] == true) {
      return AiDisconnectResult.localAccessEnded;
    }
    throw const AiDisconnectException();
  }

  @override
  Future<String?> pendingRevocation() async {
    final (status, body) = await _connectionRequest({
      'action': 'revocation_status',
    });
    final id = body['client_id'];
    if (status != 200 ||
        !body.containsKey('client_id') ||
        (id != null && (id is! String || id.isEmpty))) {
      throw const AiDisconnectException();
    }
    return id as String?;
  }

  @override
  Object? get pairingSessionIdentity {
    try {
      final session = (_client ?? Supabase.instance.client).auth.currentSession;
      if (session == null) return null;
      // Identity comparison only; the server verifies JWTs and authorization.
      final payload = jsonDecode(
        utf8.decode(
          base64Url.decode(
            base64Url.normalize(session.accessToken.split('.')[1]),
          ),
        ),
      );
      final id = payload is Map ? payload['session_id'] : null;
      if (id is! String || id.isEmpty) return null;
      return (session.user.id, id);
    } on Object {
      return null;
    }
  }

  Future<Map<dynamic, dynamic>> _pairingRpc(String name, String input) async {
    final code = AiPairingPreview.normalizeCode(input);
    try {
      final client = _client ?? Supabase.instance.client;
      final identity = pairingSessionIdentity;
      if (identity == null || client.auth.currentSession?.isExpired != false) {
        throw const AiPairingException();
      }
      final result = await client.rpc<Object?>(name, params: {'p_code': code});
      // A response from an old account or replaced session cannot authorize UI.
      if (pairingSessionIdentity != identity ||
          result is! Map ||
          result.containsKey('error')) {
        throw const AiPairingException();
      }
      return result;
    } on Object {
      throw const AiPairingException();
    }
  }

  @override
  Future<AiPairingPreview> previewPairing(String code) async =>
      AiPairingPreview.parse(
        await _pairingRpc('preview_ai_connection_pairing', code),
        DateTime.now(),
      );

  @override
  Future<String?> approvePairing(String code) async {
    final result = await _pairingRpc('approve_ai_connection_pairing', code);
    if (result['approved'] != true) throw const AiPairingException();
    final id = result['connection_id'];
    if (id == null) {
      return null; // Legacy approval still needs browser completion.
    }
    if (id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
        ).hasMatch(id)) {
      throw const AiPairingException();
    }
    return id;
  }

  @override
  Future<void> cancelPairing(String code) async {
    if ((await _pairingRpc(
          'cancel_my_ai_connection_pairing',
          code,
        ))['cancelled'] !=
        true) {
      throw const AiPairingException();
    }
  }

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
          'revoked_at, client_name, callback_host, oauth_issuer, consent_id',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows
        .map((row) => AiConnection.tryParse(row.cast<String, Object?>()))
        .whereType<AiConnection>()
        .toList(growable: false);
  }
}
