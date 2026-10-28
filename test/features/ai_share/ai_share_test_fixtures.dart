import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/ai_share/ai_connections_repository.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';
import 'package:pharmaguide/services/sharing/ai_share_snapshot_client.dart';
import 'package:pharmaguide/services/sharing/clinician_report_data.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show HttpMethod;

UserStacksLocalData aiShareEntry(
  String id,
  String name,
  String type, {
  String? dosage,
  DateTime? syncedAt,
  DateTime? updatedAt,
}) {
  final ts = updatedAt ?? DateTime.utc(2026, 10, 12, 12);
  return UserStacksLocalData(
    id: id,
    type: type,
    name: name,
    dsldId: null,
    rxcui: null,
    ingredientKeys: null,
    drugClassesCol: null,
    genericRxcui: null,
    ingredientRxcuisCol: null,
    dosage: dosage,
    frequency: null,
    addedAt: ts,
    clientUpdatedAt: ts,
    deletedAt: null,
    syncedAt: syncedAt,
  );
}

const _drugSupplement = InteractionResult(
  id: 'levothyroxine_iron',
  type: InteractionType.drugSupplement,
  severity: Severity.avoid,
  evidenceLevel: EvidenceLevel.established,
  agent1Name: 'Levothyroxine',
  agent2Name: 'Iron',
  mechanism: 'Iron can reduce levothyroxine absorption.',
  management: 'Separate administration by at least four hours.',
  doseDependant: false,
  doseThreshold: null,
  sourceUrls: ['https://dailymed.nlm.nih.gov/dailymed/example'],
  source: InteractionSource.pipeline,
);

const _supplementSupplement = InteractionResult(
  id: 'calcium_iron',
  type: InteractionType.supplementSupplement,
  severity: Severity.caution,
  evidenceLevel: EvidenceLevel.probable,
  agent1Name: 'Calcium',
  agent2Name: 'Iron',
  mechanism: 'Calcium can lower iron absorption when taken together.',
  management: 'Take them at different times of day.',
  doseDependant: false,
  doseThreshold: null,
  sourceUrls: ['https://ods.od.nih.gov/example'],
  source: InteractionSource.pipeline,
);

const _condition = InteractionResult(
  id: 'pregnancy_vitamin_a',
  type: InteractionType.conditionSupplement,
  severity: Severity.avoid,
  evidenceLevel: EvidenceLevel.established,
  agent1Name: 'Pregnancy',
  agent2Name: 'Vitamin A',
  mechanism: 'High preformed vitamin A intake in pregnancy carries risk.',
  management: 'Worth a conversation with your clinician.',
  doseDependant: true,
  doseThreshold: null,
  sourceUrls: [],
  source: InteractionSource.pipeline,
);

/// A stack whose findings disclose a medication (drug-supplement
/// interaction, medication-nutrient relationship) and a condition.
ClinicianReportData aiShareFixture({List<UserStacksLocalData>? stack}) {
  return ClinicianReportData(
    profile: null,
    stack:
        stack ??
        [
          aiShareEntry('med-1', 'Lisinopril', 'medication', dosage: '10 mg'),
          aiShareEntry('supp-1', 'Iron Bisglycinate', 'supplement'),
          aiShareEntry('supp-2', 'Calcium Citrate', 'supplement'),
        ],
    intelligence: const StackIntelligence(
      tier: StackTier.concerning,
      stackSize: 3,
      issues: [],
      interactionCount: 2,
      nutrientWarningCount: 0,
      hasRecalledIngredient: false,
      hasContraindicatedInteraction: false,
      hasBannedIngredient: false,
    ),
    safetyReport: const StackSafetyReport(
      stackInteractions: [_supplementSupplement, _condition],
      medicationInteractions: [_drugSupplement],
    ),
    depletions: const [
      DepletionMatch(
        depletionId: 'metformin_b12',
        drugDisplayName: 'Metformin',
        drugClassId: 'biguanides',
        nutrientName: 'Vitamin B12',
        nutrientCanonicalId: 'vitamin_b12',
        severity: 'moderate',
        mechanism: 'May reduce absorption over long-term use.',
        recommendation: 'Discuss B12 monitoring with a clinician.',
        evidenceLevel: 'established',
        sourceUrls: ['https://www.gov.uk/drug-safety-update/metformin-b12'],
        alertHeadline: 'Metformin may lower B12 over time',
      ),
    ],
    conditionLabels: const {'pregnant': 'Pregnant'},
    generatedAt: DateTime.utc(2026, 10, 12, 16),
  );
}

/// Strings that only a medication, a medication-derived finding or a
/// profile-derived finding can put into a payload.
const aiShareSensitiveStrings = <String>[
  'Lisinopril',
  '10 mg',
  'Levothyroxine',
  'Metformin',
  'Pregnan',
  'Vitamin A',
];

class RecordedInvoke {
  RecordedInvoke(this.method, this.body);
  final HttpMethod method;
  final Map<String, Object?> body;
}

/// Records every edge-function call; answers like the server contract.
class FakeAiShareBackend {
  FakeAiShareBackend({this.signedIn = true});

  bool signedIn;
  Object? failWith;
  final calls = <RecordedInvoke>[];

  AiShareSnapshotClient client() => AiShareSnapshotClient(
    isSignedIn: () => signedIn,
    invoke: (method, body) async {
      calls.add(RecordedInvoke(method, body));
      final failure = failWith;
      if (failure != null) throw failure;
      if (method == HttpMethod.post) {
        return const AiShareInvokeResponse(
          status: 201,
          data: {'snapshot_id': 'snap-1', 'expires_at': '2026-10-13T16:00:00Z'},
        );
      }
      return const AiShareInvokeResponse(status: 204, data: null);
    },
  );

  List<RecordedInvoke> get uploads =>
      calls.where((c) => c.method == HttpMethod.post).toList();

  List<RecordedInvoke> get deletes =>
      calls.where((c) => c.method == HttpMethod.delete).toList();
}

AiConnection aiConnectionFixture({
  String id = '6f1c2a3b-0000-4000-8000-000000000001',
  String clientId = 'claude-ai',
  String status = 'active',
}) {
  return AiConnection(
    connectionId: id,
    clientId: clientId,
    status: status,
    // Relative to now so "active and unexpired" stays true on any date.
    createdAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 29)),
  );
}

class FakeAiConnectionsRepository implements AiConnectionsRepository {
  FakeAiConnectionsRepository(this.connections);

  final List<AiConnection> connections;
  int loads = 0;
  int disconnectCalls = 0;
  String? pendingClient;
  Future<AiDisconnectResult> Function(String)? onDisconnect;
  @override
  Future<String?> pendingRevocation() async => pendingClient;
  @override
  Future<AiDisconnectResult> disconnect(String clientId) async {
    disconnectCalls++;
    return onDisconnect == null
        ? AiDisconnectResult.disconnected
        : await onDisconnect!(clientId);
  }

  @override
  Object? pairingSessionIdentity = 'test-user';
  Future<AiPairingPreview> Function(String)? preview;
  Future<void> Function(String)? approve;
  String? approvedConnectionId;
  Future<void> Function(String)? cancel;
  @override
  Future<AiPairingPreview> previewPairing(String code) => preview!(code);
  @override
  Future<String?> approvePairing(String code) async {
    await approve!(code);
    return approvedConnectionId;
  }

  @override
  Future<void> cancelPairing(String code) => cancel!(code);

  @override
  Future<List<AiConnection>> listMine() async {
    loads++;
    // Match a fetched result: later server mutations do not alter prior loads.
    return List.of(connections);
  }
}

class MemoryPreferencesStore implements AppPreferencesStore {
  final values = <String, Object>{};
  Future<void> Function()? beforeWrite;

  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;

  @override
  Future<String?> getString(String key) async => values[key] as String?;

  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;

  @override
  Future<void> setString(String key, String value) async {
    await beforeWrite?.call();
    values[key] = value;
  }
}
