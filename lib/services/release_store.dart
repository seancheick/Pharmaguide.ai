// Immutable release folders with one active pointer (ADR-012).
//
// Each release is a folder holding the catalog, the rules and `release.json`.
// A folder never changes once complete, and `active.json`, replaced by atomic
// rename, is the only thing that says which one is live. A crash leaves the old
// pointer or the new one, and each names a complete folder. Nothing open ever
// moves, so a check already running finishes on the release it started with.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:drift/native.dart' show SqliteException;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/core/utils/app_version.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/catalog_version.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

/// The open-time work a prepared folder has had. Raise it whenever the
/// columns, indexes or schema versions in `CoreDatabase` and
/// `InteractionDatabase` change (a test pins them): the next launch rebuilds
/// the folder from the same files, because release files are never written in
/// place.
const int kReleasePreparation = 1;

const _catalogFile = 'catalog.db';
const _rulesFile = 'rules.sqlite';
const _recordFile = 'release.json';
const _pointerFile = 'active.json';
const _stagingDir = 'staging';
const _legacyHoldingDir = 'legacy';

/// A build whose bundled rules can't open still launches, and interaction
/// checks show their unavailable state. A release gate fails such a build.
const _noRules = 'none';

/// Points a crash test can stop at. Each one is the moment just before that
/// step takes effect.
@visibleForTesting
enum ReleaseStep {
  assemble,
  prepare,
  writeRecord,
  fetchStackData,
  publishFolder,
  commitStackData,
  swapPointer,
  openNew,
  confirm,
}

class ReleaseRecord {
  const ReleaseRecord({
    required this.id,
    required this.sequence,
    required this.catalogVersion,
    required this.rulesVersion,
    required this.catalogSha256,
    required this.rulesSha256,
    required this.minRulesVersion,
    required this.preparation,
    this.qualityWithheld = false,
  });

  final String id;

  /// 0 for bundled, migrated and unsigned releases.
  final int sequence;
  final String catalogVersion;
  final String rulesVersion;

  /// The hash of each file as published, which the prepared file no longer has.
  final String? catalogSha256;
  final String? rulesSha256;
  final String? minRulesVersion;
  final int preparation;

  /// This folder's catalog had its quality scores removed on the phone,
  /// because the version was blocked with no replacement.
  final bool qualityWithheld;

  static String idFor({
    required int sequence,
    required String catalogVersion,
    required String rulesVersion,
    bool qualityWithheld = false,
  }) =>
      's${sequence}_${catalogVersion}_${rulesVersion}_'
      'p$kReleasePreparation${qualityWithheld ? '_q' : ''}';

  Map<String, Object?> toJson() => {
    'id': id,
    'sequence': sequence,
    'catalog_version': catalogVersion,
    'rules_version': rulesVersion,
    'catalog_sha256': catalogSha256,
    'rules_sha256': rulesSha256,
    'min_rules_version': minRulesVersion,
    'preparation': preparation,
    'quality_withheld': qualityWithheld,
  };

  /// Null when [json] isn't a complete record.
  static ReleaseRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final sequence = json['sequence'];
    final catalogVersion = json['catalog_version'];
    final rulesVersion = json['rules_version'];
    final preparation = json['preparation'];
    if (id is! String ||
        sequence is! int ||
        catalogVersion is! String ||
        rulesVersion is! String ||
        preparation is! int) {
      return null;
    }
    String? optional(String key) {
      final value = json[key];
      return value is String ? value : null;
    }

    return ReleaseRecord(
      id: id,
      sequence: sequence,
      catalogVersion: catalogVersion,
      rulesVersion: rulesVersion,
      catalogSha256: optional('catalog_sha256'),
      rulesSha256: optional('rules_sha256'),
      minRulesVersion: optional('min_rules_version'),
      preparation: preparation,
      qualityWithheld: json['quality_withheld'] == true,
    );
  }
}

@immutable
class ReleasePointer {
  const ReleasePointer({
    required this.active,
    this.previous,
    this.confirmed = false,
    this.highestSequence = 0,
    this.blockedCatalog = const {},
    this.blockedRules = const {},
    this.refused = const {},
    this.bundleSeen,
  });

  final String active;
  final String? previous;
  final bool confirmed;

  /// A lower sequence is a replay of an old signed release.
  final int highestSequence;
  final Set<String> blockedCatalog;
  final Set<String> blockedRules;

  /// Folders that failed to open, which are never selected again.
  final Set<String> refused;

  /// The bundled pair this phone last reconciled with. It changes only when
  /// the app updates, so a signed rollback isn't undone by the next launch.
  final String? bundleSeen;

  ReleasePointer copyWith({
    String? active,
    String? Function()? previous,
    bool? confirmed,
    int? highestSequence,
    Set<String>? blockedCatalog,
    Set<String>? blockedRules,
    Set<String>? refused,
    String? bundleSeen,
  }) => ReleasePointer(
    active: active ?? this.active,
    previous: previous == null ? this.previous : previous(),
    confirmed: confirmed ?? this.confirmed,
    highestSequence: highestSequence ?? this.highestSequence,
    blockedCatalog: blockedCatalog ?? this.blockedCatalog,
    blockedRules: blockedRules ?? this.blockedRules,
    refused: refused ?? this.refused,
    bundleSeen: bundleSeen ?? this.bundleSeen,
  );

  Map<String, Object?> toJson() => {
    'active': active,
    'previous': previous,
    'confirmed': confirmed,
    'highest_sequence': highestSequence,
    'blocked_versions': {
      'catalog': blockedCatalog.toList()..sort(),
      'rules': blockedRules.toList()..sort(),
    },
    'refused': refused.toList()..sort(),
    'bundle_seen': bundleSeen,
  };

  static ReleasePointer? fromJson(Object? json) {
    if (json is! Map) return null;
    final active = json['active'];
    if (active is! String || active.isEmpty) return null;
    Set<String> list(Object? raw) =>
        raw is List ? raw.whereType<String>().toSet() : const {};
    final blocked = json['blocked_versions'];
    final highest = json['highest_sequence'];
    final previous = json['previous'];
    final bundleSeen = json['bundle_seen'];
    return ReleasePointer(
      active: active,
      previous: previous is String ? previous : null,
      confirmed: json['confirmed'] == true,
      highestSequence: highest is int ? highest : 0,
      blockedCatalog: blocked is Map ? list(blocked['catalog']) : const {},
      blockedRules: blocked is Map ? list(blocked['rules']) : const {},
      refused: list(json['refused']),
      bundleSeen: bundleSeen is String ? bundleSeen : null,
    );
  }
}

/// One complete, open release. Everything evaluated against it reads these
/// handles, so a check never mixes parts of two releases.
class ReleaseGeneration {
  ReleaseGeneration({
    required this.record,
    required this.core,
    required this.rules,
    required this.rulesWithheld,
  });

  final ReleaseRecord record;
  final CoreDatabase core;

  /// Null when the rules couldn't open, or were withheld.
  final InteractionDatabase? rules;

  /// The rules version is blocked with no replacement, so interaction checks
  /// stay in their unavailable state and show a specific notice.
  final bool rulesWithheld;

  bool get qualityWithheld => record.qualityWithheld;

  Future<void> close() async {
    await core.close();
    await rules?.close();
  }
}

/// A candidate release, with its files already downloaded and verified. A null
/// file reuses the active release's.
class ReleaseCandidate {
  const ReleaseCandidate({
    required this.sequence,
    required this.catalogVersion,
    required this.catalogSha256,
    required this.minRulesVersion,
    this.stagedCatalog,
    this.stagedRules,
    this.rulesVersion,
    this.rulesSha256,
  });

  final int sequence;
  final String catalogVersion;
  final String? catalogSha256;
  final String? minRulesVersion;
  final File? stagedCatalog;
  final File? stagedRules;
  final String? rulesVersion;
  final String? rulesSha256;
}

/// Fetches what a candidate needs before it activates, then returns the step
/// that stores it. The store runs that step last, so a failed fetch leaves the
/// phone's current data alone.
typedef ReleaseStackData =
    Future<Future<void> Function()> Function(CoreDatabase candidate);

sealed class ReleaseActivation {
  const ReleaseActivation();
}

class ReleaseActivated extends ReleaseActivation {
  const ReleaseActivated(this.generation);
  final ReleaseGeneration generation;
}

/// The update didn't happen. The phone stays on its release, whose handles are
/// still good because nothing moved.
class ReleaseNotActivated extends ReleaseActivation {
  const ReleaseNotActivated(this.reason);
  final String reason;
}

class ReleaseStore {
  ReleaseStore({
    required this.documents,
    AssetBundle? bundle,
    this.appVersion = kAppVersion,
    @visibleForTesting this.onStep,
  }) : bundle = bundle ?? rootBundle;

  final Directory documents;
  final AssetBundle bundle;
  final String appVersion;

  /// Test seam: throwing here stands in for the process dying at that step,
  /// because no step cleans up after itself; the next launch does.
  final FutureOr<void> Function(ReleaseStep step)? onStep;

  Directory get _root => Directory(p.join(documents.path, 'releases'));
  Directory get _staging => Directory(p.join(_root.path, _stagingDir));
  Directory get _legacyHolding =>
      Directory(p.join(_root.path, _legacyHoldingDir));
  File get _pointerPath => File(p.join(_root.path, _pointerFile));

  ReleasePointer? _pointer;
  ReleaseRecord? _active;
  bool _unreadableAtOpen = false;

  /// The release in use, once [open] has run.
  ReleaseRecord? get active => _active;
  Set<String> get refused => _pointer?.refused ?? const {};
  int get highestSequence => _pointer?.highestSequence ?? 0;

  /// Where a download for this store keeps its partial files.
  Directory get downloads => Directory(p.join(_staging.path, 'downloads'));

  Directory _folder(String id) => Directory(p.join(_root.path, id));

  Future<void> _step(ReleaseStep step) async => onStep?.call(step);

  // ---------------------------------------------------------------------------
  // Boot and selection
  // ---------------------------------------------------------------------------

  /// Selects a release and opens it. Safe to call again at any time, which
  /// opens fresh handles; the caller adopts them and keeps its old ones until
  /// the process ends. Needs no network. Throws only when even the bundled
  /// catalog can't open, or when nothing on disk can be read right now.
  Future<ReleaseGeneration> open() async {
    try {
      await _root.create(recursive: true);
      await _keepingCurrentRelease('clear_failed', _clearAssemblies);
      _pointer =
          await _readPointer() ??
          await _rebuildPointer() ??
          await _migrateLegacyFiles();
    } on SimulatedReleaseCrash {
      rethrow;
    } on Object catch (e, st) {
      final inPlace = await _openLegacyInPlace();
      if (inPlace == null) rethrow;
      CrashReportingService().recordError(
        e,
        st,
        hint: 'release_store:migration_failed',
      );
      return inPlace;
    }

    final bundled = await _bundledIdentity();
    await _keepingCurrentRelease(
      'reconcile_failed',
      () => _reconcileWithBundle(bundled),
    );
    await _keepingCurrentRelease('reprepare_failed', _reprepareIfNeeded);
    final generation = await reselect();
    await _deleteLegacyFiles();
    if (!_unreadableAtOpen) await _retainActiveAndPrevious();
    return generation;
  }

  /// Applies the known revocations and opens what they require, during a
  /// session as well as at launch. Deletes nothing: the caller's current handles
  /// must stay usable until the process ends.
  Future<ReleaseGeneration> reselect() async {
    if (_pointer == null) {
      // Running from the old files. Moving them now would break the handles the
      // caller holds, so the move waits for the next launch.
      return await _openLegacyInPlace() ??
          (throw StateError('No release can be read right now'));
    }
    await _keepingCurrentRelease(
      'resolve_blocked_failed',
      _resolveBlockedVersions,
    );
    final generation = await _openFirstUsable();
    if (isSettled(generation) || _unreadableAtOpen) return generation;

    // A fallback landed on a version the revocations cover. Resolve once more
    // from there; if that can't finish, the next launch tries again.
    await _keepingCurrentRelease(
      'resolve_blocked_failed',
      _resolveBlockedVersions,
    );
    final resolved = await _openFirstUsable();
    await generation.close();
    return resolved;
  }

  /// A step that can only improve on the selected release. If it fails, such as
  /// on a full disk, the phone stays where it is and the next launch tries again.
  Future<void> _keepingCurrentRelease(
    String hint,
    Future<void> Function() step,
  ) async {
    try {
      await step();
    } on SimulatedReleaseCrash {
      rethrow;
    } on Object catch (e, st) {
      CrashReportingService().recordError(e, st, hint: 'release_store:$hint');
    }
  }

  /// Tries the active release, the previous one, any other kept folder, then
  /// the bundled pair. A release that fails is recorded so that it isn't
  /// selected again. A file that can't be read right now, such as before first
  /// unlock, says nothing about the release, so nothing on disk changes.
  Future<ReleaseGeneration> _openFirstUsable() async {
    _unreadableAtOpen = false;
    final tried = <String>{};
    Future<ReleaseGeneration?> attempt(String id) async {
      if (!tried.add(id)) return null;
      final pointer = _pointer!;
      if (pointer.refused.contains(id)) return null;
      final record = await _readRecord(id);
      if (record == null) return null;
      try {
        return await _openFolder(record);
      } on Object catch (e, st) {
        debugPrint('[release] $id failed to open: ${e.runtimeType}');
        CrashReportingService().recordError(
          e,
          st,
          hint: 'release_store:open_failed',
        );
        if (_isTemporaryReadFailure(e)) {
          _unreadableAtOpen = true;
        } else {
          await _writePointer(
            pointer.copyWith(refused: {...pointer.refused, id}),
          );
        }
        return null;
      }
    }

    final start = _pointer!;
    for (final id in [
      start.active,
      ?start.previous,
      ...await _keptFoldersNewestFirst(),
    ]) {
      final generation = await attempt(id);
      if (generation == null) continue;
      if (_unreadableAtOpen) {
        _active = generation.record;
      } else {
        await _select(generation.record);
      }
      return generation;
    }
    if (_unreadableAtOpen) {
      throw StateError('No release can be read right now');
    }

    final record = await _assembleBundled(await _bundledIdentity());
    final generation = await _openFolder(record);
    await _select(record);
    return generation;
  }

  Future<void> _select(ReleaseRecord record) async {
    final pointer = _pointer!;
    final moved = pointer.active != record.id;
    if (moved || !pointer.confirmed) {
      await _writePointer(
        pointer.copyWith(
          active: record.id,
          previous: moved ? () => null : null,
          confirmed: true,
        ),
      );
    }
    _active = record;
  }

  /// Read-only handles over a complete folder, proved usable.
  Future<ReleaseGeneration> _openFolder(ReleaseRecord record) async {
    final folder = _folder(record.id);
    final catalogFile = File(p.join(folder.path, _catalogFile));
    if (!await catalogFile.exists()) {
      throw StateError('Release ${record.id} has no catalog file');
    }
    final core = CoreDatabase.readOnly(catalogFile);
    InteractionDatabase? rules;
    try {
      await core.validateCatalogSnapshot();
      final pointer = _pointer;
      final withheld =
          pointer?.blockedRules.contains(record.rulesVersion) == true;
      if (!withheld && record.rulesVersion != _noRules) {
        final rulesPath = p.join(folder.path, _rulesFile);
        if (!await File(rulesPath).exists()) {
          throw StateError('Release ${record.id} has no rules file');
        }
        rules = await _openRules(rulesPath);
      }
      return ReleaseGeneration(
        record: record,
        core: core,
        rules: rules,
        rulesWithheld: withheld,
      );
    } on Object {
      await core.close();
      rethrow;
    }
  }

  Future<InteractionDatabase> _openRules(String path) async {
    final db = InteractionDatabase.readOnly(File(path));
    try {
      final metadata = await db.getMetadata();
      enforceInteractionDatabaseVersionGate(
        minAppVersion: metadata.minAppVersion,
        schemaVersion: metadata.schemaVersion,
        appVersion: appVersion,
      );
      return db;
    } on Object {
      await db.close();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Activation
  // ---------------------------------------------------------------------------

  /// Installs [candidate] and makes it the active release. The pointer swap is
  /// the only step that changes what is active; any failure before it leaves
  /// the phone exactly where it was.
  Future<ReleaseActivation> activate(
    ReleaseCandidate candidate, {
    ReleaseStackData? stackData,
  }) async {
    final ReleaseRecord record;
    Future<void> Function()? storeStackData;
    try {
      final assembled = await _assembleCandidate(candidate);
      record = assembled.record;
      if (_pointer?.refused.contains(record.id) == true) {
        throw const _ReleaseRefused('This release failed to open before');
      }
      if (stackData != null) {
        await _step(ReleaseStep.fetchStackData);
        final probe = CoreDatabase.readOnly(
          File(p.join(assembled.folder.path, _catalogFile)),
        );
        try {
          storeStackData = await stackData(probe);
        } finally {
          await probe.close();
        }
      }
      await _publishFolder(assembled.folder, record);
    } on _ReleaseRefused catch (e) {
      await _discardStaged(candidate);
      await _clearAssemblies();
      return ReleaseNotActivated(e.reason);
    } on SimulatedReleaseCrash {
      rethrow;
    } on Object catch (e, st) {
      CrashReportingService().recordError(
        e,
        st,
        hint: 'release_store:assemble_failed',
      );
      await _clearAssemblies();
      return ReleaseNotActivated('$e');
    }

    final before = _pointer ?? ReleasePointer(active: record.id);
    try {
      await _step(ReleaseStep.commitStackData);
      await storeStackData?.call();
      await _step(ReleaseStep.swapPointer);
      await _writePointer(
        before.copyWith(
          active: record.id,
          previous: before.active == record.id ? null : () => before.active,
          confirmed: false,
          highestSequence: math.max(before.highestSequence, candidate.sequence),
        ),
      );
    } on SimulatedReleaseCrash {
      rethrow;
    } on Object catch (e) {
      return ReleaseNotActivated('Pointer swap failed: $e');
    }

    final ReleaseGeneration generation;
    try {
      await _step(ReleaseStep.openNew);
      generation = await _openFolder(record);
    } on SimulatedReleaseCrash {
      rethrow;
    } on Object catch (e, st) {
      CrashReportingService().recordError(
        e,
        st,
        fatal: true,
        hint: 'release_store:activation_open_failed',
      );
      // Back to the last good pair, whose handles the caller still holds.
      await _writePointer(
        before.copyWith(
          refused: _isTemporaryReadFailure(e)
              ? before.refused
              : {...before.refused, record.id},
          highestSequence: math.max(before.highestSequence, candidate.sequence),
        ),
      );
      return ReleaseNotActivated('Open failed: $e');
    }

    await _step(ReleaseStep.confirm);
    await _writePointer(_pointer!.copyWith(confirmed: true));
    _active = record;
    return ReleaseActivated(generation);
  }

  Future<({Directory folder, ReleaseRecord record})> _assembleCandidate(
    ReleaseCandidate candidate,
  ) async {
    final active = _active;
    var stagedRules = candidate.stagedRules;
    var rulesVersion = candidate.rulesVersion ?? active?.rulesVersion;
    if (active == null && stagedRules == null) {
      // No release opened at boot: the bundled rules go with this catalog.
      stagedRules = File(p.join(downloads.path, 'rules.bundled'));
      await stagedRules.parent.create(recursive: true);
      await _writeAsset(bundledInteractionDatabaseAssetPath, stagedRules.path);
      rulesVersion = await _readRulesVersion(stagedRules.path);
    }
    if (rulesVersion == null) {
      throw const _ReleaseRefused('No rules for this release');
    }
    final record = ReleaseRecord(
      id: ReleaseRecord.idFor(
        sequence: candidate.sequence,
        catalogVersion: candidate.catalogVersion,
        rulesVersion: rulesVersion,
      ),
      sequence: candidate.sequence,
      catalogVersion: candidate.catalogVersion,
      rulesVersion: rulesVersion,
      catalogSha256: candidate.catalogSha256,
      rulesSha256: candidate.rulesSha256 ?? active?.rulesSha256,
      minRulesVersion: candidate.minRulesVersion,
      preparation: kReleasePreparation,
    );
    if (await _readRecord(record.id) != null) {
      await _discardStaged(candidate);
      return (folder: _folder(record.id), record: record);
    }
    if (candidate.stagedCatalog == null && active?.qualityWithheld == true) {
      throw const _ReleaseRefused('The active catalog has its scores removed');
    }

    Future<void> place(File? staged, String name) async {
      final target = File(p.join(_assemblyPath(record.id), name));
      if (staged != null) {
        await staged.rename(target.path);
      } else if (active != null) {
        await File(p.join(_folder(active.id).path, name)).copy(target.path);
      } else {
        throw _ReleaseRefused('Nothing to reuse for $name');
      }
    }

    final assembly = await _startAssembly(record.id);
    await place(candidate.stagedCatalog, _catalogFile);
    await place(stagedRules, _rulesFile);
    await _prepareAndCheck(assembly, record);
    return (folder: assembly, record: record);
  }

  /// Runs the open-time work on the staged copy and proves both files are what
  /// the record says. This is the last write these files ever get.
  Future<void> _prepareAndCheck(Directory folder, ReleaseRecord record) async {
    await _step(ReleaseStep.prepare);
    final catalogPath = p.join(folder.path, _catalogFile);
    final core = CoreDatabase.open(catalogPath);
    try {
      final version = await core.validateCatalogSnapshot();
      if (version != record.catalogVersion) {
        throw _ReleaseRefused(
          'Catalog is $version, expected ${record.catalogVersion}',
        );
      }
    } on _ReleaseRefused {
      rethrow;
    } on Object catch (e) {
      throw _ReleaseRefused('Catalog failed validation: $e');
    } finally {
      await _closeQuietly(core.close);
    }

    final rulesPath = p.join(folder.path, _rulesFile);
    final rules = InteractionDatabase.open(rulesPath);
    try {
      final metadata = await rules.getMetadata();
      enforceInteractionDatabaseVersionGate(
        minAppVersion: metadata.minAppVersion,
        schemaVersion: metadata.schemaVersion,
        appVersion: appVersion,
      );
      if (metadata.interactionDbVersion != record.rulesVersion) {
        throw _ReleaseRefused(
          'Rules are ${metadata.interactionDbVersion}, '
          'expected ${record.rulesVersion}',
        );
      }
    } on _ReleaseRefused {
      rethrow;
    } on Object catch (e) {
      throw _ReleaseRefused('Rules failed validation: $e');
    } finally {
      await _closeQuietly(rules.close);
    }

    await _flushFile(File(catalogPath));
    await _flushFile(File(rulesPath));
    await _step(ReleaseStep.writeRecord);
    await _writeDurably(
      File(p.join(folder.path, _recordFile)),
      jsonEncode(record.toJson()),
    );
    await flushDirectory(folder.path);
  }

  Future<void> _publishFolder(Directory assembly, ReleaseRecord record) async {
    final target = _folder(record.id);
    if (assembly.path == target.path) return;
    await _step(ReleaseStep.publishFolder);
    await assembly.rename(target.path);
    await flushDirectory(_root.path);
  }

  String _assemblyPath(String id) => p.join(_staging.path, 'assembly-$id');

  Future<Directory> _startAssembly(String id) async {
    await _step(ReleaseStep.assemble);
    final assembly = Directory(_assemblyPath(id));
    if (await assembly.exists()) await assembly.delete(recursive: true);
    return assembly.create(recursive: true);
  }

  Future<void> _clearAssemblies() async {
    if (!await _staging.exists()) return;
    await for (final entry in _staging.list()) {
      if (entry is Directory &&
          p.basename(entry.path).startsWith('assembly-')) {
        await entry.delete(recursive: true);
      }
    }
  }

  Future<void> _discardStaged(ReleaseCandidate candidate) async {
    for (final file in [candidate.stagedCatalog, candidate.stagedRules]) {
      try {
        if (file != null && await file.exists()) await file.delete();
      } on Object {
        // Launch clears staging; nothing depends on this.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Revocation
  // ---------------------------------------------------------------------------

  /// Records what a verified manifest said, even when the release itself can't
  /// activate, so it survives a restart while offline.
  Future<void> recordVerified({
    required int sequence,
    required Set<String> blockedCatalog,
    required Set<String> blockedRules,
  }) async {
    final pointer = _pointer;
    if (pointer == null) return;
    await _writePointer(
      pointer.copyWith(
        highestSequence: math.max(pointer.highestSequence, sequence),
        blockedCatalog: blockedCatalog,
        blockedRules: blockedRules,
      ),
    );
  }

  /// Whether the active release names a blocked version.
  bool get activeIsBlocked {
    final active = _active;
    final pointer = _pointer;
    if (active == null || pointer == null) return false;
    return (pointer.blockedCatalog.contains(active.catalogVersion) &&
            !active.qualityWithheld) ||
        pointer.blockedRules.contains(active.rulesVersion);
  }

  /// Whether [generation] already reflects the known revocations. When it
  /// doesn't, calling [open] again selects what they require.
  bool isSettled(ReleaseGeneration generation) {
    final pointer = _pointer;
    if (pointer == null) return true;
    final record = generation.record;
    return generation.rulesWithheld ==
            pointer.blockedRules.contains(record.rulesVersion) &&
        record.qualityWithheld ==
            pointer.blockedCatalog.contains(record.catalogVersion);
  }

  bool _isBlocked(ReleaseRecord record) {
    final pointer = _pointer!;
    return pointer.blockedCatalog.contains(record.catalogVersion) ||
        pointer.blockedRules.contains(record.rulesVersion);
  }

  /// A phone on a blocked version returns to its previous confirmed release if
  /// that isn't blocked. Otherwise only the affected assessment is withheld:
  /// [_openFolder] leaves blocked rules closed, and a blocked catalog becomes a
  /// local copy without quality scores. Products stay available, and catalog
  /// safety status is never touched.
  Future<void> _resolveBlockedVersions() async {
    final pointer = _pointer!;
    final active = await _readRecord(pointer.active);
    if (active == null) return;
    final previousId = pointer.previous;
    final previous = previousId == null ? null : await _readRecord(previousId);

    // The block was lifted: return to the file with its scores.
    if (active.qualityWithheld &&
        !pointer.blockedCatalog.contains(active.catalogVersion) &&
        previous?.catalogVersion == active.catalogVersion &&
        previous?.qualityWithheld == false) {
      await _writePointer(
        pointer.copyWith(active: previous!.id, previous: () => null),
      );
      return;
    }
    if (!_isBlocked(active)) return;

    if (previous != null &&
        !_isBlocked(previous) &&
        !pointer.refused.contains(previous.id)) {
      await _writePointer(
        pointer.copyWith(active: previous.id, previous: () => null),
      );
      return;
    }

    if (pointer.blockedCatalog.contains(active.catalogVersion) &&
        !active.qualityWithheld) {
      await _withholdQuality(active);
    }
  }

  Future<void> _withholdQuality(ReleaseRecord source) async {
    final record = ReleaseRecord(
      id: ReleaseRecord.idFor(
        sequence: source.sequence,
        catalogVersion: source.catalogVersion,
        rulesVersion: source.rulesVersion,
        qualityWithheld: true,
      ),
      sequence: source.sequence,
      catalogVersion: source.catalogVersion,
      rulesVersion: source.rulesVersion,
      catalogSha256: source.catalogSha256,
      rulesSha256: source.rulesSha256,
      minRulesVersion: source.minRulesVersion,
      preparation: kReleasePreparation,
      qualityWithheld: true,
    );
    if (_pointer!.refused.contains(record.id)) {
      // Built here from a good file, so a damaged copy can simply be rebuilt.
      await _folder(record.id).delete(recursive: true);
      await _writePointer(
        _pointer!.copyWith(refused: _pointer!.refused.difference({record.id})),
      );
    }
    if (await _readRecord(record.id) == null) {
      final assembly = await _startAssembly(record.id);
      final from = _folder(source.id).path;
      await File(
        p.join(from, _catalogFile),
      ).copy(p.join(assembly.path, _catalogFile));
      await File(
        p.join(from, _rulesFile),
      ).copy(p.join(assembly.path, _rulesFile));
      final core = CoreDatabase.open(p.join(assembly.path, _catalogFile));
      try {
        await core.withholdQualityScores();
      } finally {
        await _closeQuietly(core.close);
      }
      await _prepareAndCheck(assembly, record);
      await _publishFolder(assembly, record);
    }
    await _writePointer(
      _pointer!.copyWith(active: record.id, previous: () => source.id),
    );
  }

  // ---------------------------------------------------------------------------
  // The bundled pair
  // ---------------------------------------------------------------------------

  Future<_BundleIdentity> _bundledIdentity() async {
    Future<Map<String, dynamic>> read(String path) async {
      try {
        final decoded = jsonDecode(await bundle.loadString(path));
        if (decoded is Map<String, dynamic>) return decoded;
      } on Object {
        // Release gates require these. A test fixture may omit one, and the
        // version then comes from the file itself.
      }
      return const {};
    }

    final catalog = await read(bundledCoreDatabaseManifestAssetPath);
    final rules = await read(bundledInteractionDatabaseManifestAssetPath);
    String? checksum(Map<String, dynamic> manifest) {
      final raw = (manifest['checksum_sha256'] ?? manifest['checksum'])
          ?.toString();
      return raw != null && raw.startsWith('sha256:') ? raw.substring(7) : raw;
    }

    return _BundleIdentity(
      catalogVersion: catalog['db_version']?.toString(),
      catalogSha256: checksum(catalog),
      rulesVersion: (rules['interaction_db_version'] ?? rules['db_version'])
          ?.toString(),
      rulesSha256: checksum(rules),
    );
  }

  /// Puts the bundled pair, or the held root catalog and the bundled rules,
  /// into a complete folder and points at it. The bundle counts as seen only if
  /// all of it is in use or was passed over for something newer, so a launch
  /// that couldn't use it tries again.
  Future<ReleaseRecord> _assembleBundled(
    _BundleIdentity identity, {
    bool fromHolding = false,
  }) async {
    final Directory assembly;
    if (fromHolding) {
      assembly = _legacyHolding;
      await _step(ReleaseStep.assemble);
    } else {
      assembly = await _startAssembly('bundled');
    }
    final catalogPath = p.join(assembly.path, _catalogFile);
    final rulesPath = p.join(assembly.path, _rulesFile);
    if (!fromHolding) {
      await _writeAsset(bundledCoreDatabaseAssetPath, catalogPath);
    }
    final catalogVersion = await _readCatalogVersion(catalogPath);
    if (catalogVersion == null) {
      throw StateError('Bundled catalog failed validation');
    }
    String? rulesVersion;
    try {
      await _writeAsset(bundledInteractionDatabaseAssetPath, rulesPath);
      rulesVersion = await _readRulesVersion(rulesPath);
    } on Object catch (e) {
      debugPrint('[release] bundled rules unavailable: ${e.runtimeType}');
    }
    final bundleApplied =
        rulesVersion != null &&
        !(fromHolding && _bundleIsNewer(identity, catalogVersion));
    rulesVersion ??= await _adoptRootRules(rulesPath);

    final record = ReleaseRecord(
      id: ReleaseRecord.idFor(
        sequence: 0,
        catalogVersion: catalogVersion,
        rulesVersion: rulesVersion ?? _noRules,
      ),
      sequence: 0,
      catalogVersion: catalogVersion,
      rulesVersion: rulesVersion ?? _noRules,
      catalogSha256: fromHolding ? null : identity.catalogSha256,
      rulesSha256: identity.rulesSha256,
      minRulesVersion: null,
      preparation: kReleasePreparation,
    );

    // The last resort must be able to replace a damaged copy of itself.
    final existing = _folder(record.id);
    final refused = _pointer?.refused ?? const <String>{};
    if (refused.contains(record.id) && await existing.exists()) {
      await existing.delete(recursive: true);
    }
    if (await _readRecord(record.id) != null) {
      await assembly.delete(recursive: true);
    } else {
      if (rulesVersion == null) {
        await _flushFile(File(catalogPath));
        await _step(ReleaseStep.writeRecord);
        await _writeDurably(
          File(p.join(assembly.path, _recordFile)),
          jsonEncode(record.toJson()),
        );
      } else {
        await _prepareAndCheck(assembly, record);
      }
      await _publishFolder(assembly, record);
    }

    await _writePointer(
      (_pointer ?? ReleasePointer(active: record.id)).copyWith(
        active: record.id,
        previous: () => null,
        confirmed: false,
        refused: refused.difference({record.id}),
        bundleSeen: bundleApplied ? identity.tag : null,
      ),
    );
    return record;
  }

  bool _bundleIsNewer(_BundleIdentity identity, String catalogVersion) =>
      identity.catalogVersion != null &&
      CatalogVersion.isRemoteNewer(
        remoteVersion: identity.catalogVersion,
        localVersion: catalogVersion,
      );

  /// The bundled rules can't be used this launch: the old install's rules, if
  /// valid, are better than none until they can. Otherwise [rulesPath] is left
  /// empty so nothing later reuses a damaged file.
  Future<String?> _adoptRootRules(String rulesPath) async {
    final partial = File(rulesPath);
    if (await partial.exists()) await partial.delete();
    final root = File(p.join(documents.path, 'interaction_db.sqlite'));
    if (!await root.exists()) return null;
    final version = await _readRulesVersion(root.path);
    if (version != null) await root.rename(rulesPath);
    return version;
  }

  Future<void> _writeAsset(String assetPath, String targetPath) async {
    final data = await bundle.load(assetPath);
    await _writeBytesChunked(
      File(targetPath),
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  /// After an app update, the bundled catalog replaces the active one only if
  /// it is newer, and the bundled rules only if they are newer and satisfy the
  /// active release's pair rule. Blocked versions are never picked. Runs once
  /// per bundle, so a signed rollback isn't undone by the next launch.
  Future<void> _reconcileWithBundle(_BundleIdentity bundled) async {
    final pointer = _pointer!;
    if (bundled.tag == pointer.bundleSeen) return;
    final active = await _readRecord(pointer.active);
    if (active == null) return;

    final catalogNewer =
        bundled.catalogVersion != null &&
        !pointer.blockedCatalog.contains(bundled.catalogVersion) &&
        CatalogVersion.isRemoteNewer(
          remoteVersion: bundled.catalogVersion,
          localVersion: active.catalogVersion,
        );
    final rulesNewer =
        bundled.rulesVersion != null &&
        !pointer.blockedRules.contains(bundled.rulesVersion) &&
        (active.rulesVersion == _noRules ||
            (compareSemver(bundled.rulesVersion!, active.rulesVersion) ?? -1) >
                0) &&
        (active.minRulesVersion == null ||
            (compareSemver(bundled.rulesVersion!, active.minRulesVersion!) ??
                    -1) >=
                0);
    if (!catalogNewer && !rulesNewer) {
      // With no rules at all, keep looking for bundled ones on later launches.
      if (active.rulesVersion != _noRules) {
        await _writePointer(pointer.copyWith(bundleSeen: bundled.tag));
      }
      return;
    }

    // A catalog with its scores removed stays marked, so it is never reused.
    final qualityWithheld = active.qualityWithheld && !catalogNewer;
    final record = ReleaseRecord(
      id: ReleaseRecord.idFor(
        sequence: active.sequence,
        catalogVersion: catalogNewer
            ? bundled.catalogVersion!
            : active.catalogVersion,
        rulesVersion: rulesNewer ? bundled.rulesVersion! : active.rulesVersion,
        qualityWithheld: qualityWithheld,
      ),
      sequence: active.sequence,
      catalogVersion: catalogNewer
          ? bundled.catalogVersion!
          : active.catalogVersion,
      rulesVersion: rulesNewer ? bundled.rulesVersion! : active.rulesVersion,
      catalogSha256: catalogNewer
          ? bundled.catalogSha256
          : active.catalogSha256,
      rulesSha256: rulesNewer ? bundled.rulesSha256 : active.rulesSha256,
      minRulesVersion: active.minRulesVersion,
      preparation: kReleasePreparation,
      qualityWithheld: qualityWithheld,
    );
    if (await _readRecord(record.id) == null) {
      final assembly = await _startAssembly(record.id);
      final from = _folder(active.id).path;
      final catalogPath = p.join(assembly.path, _catalogFile);
      final rulesPath = p.join(assembly.path, _rulesFile);
      if (catalogNewer) {
        await _writeAsset(bundledCoreDatabaseAssetPath, catalogPath);
      } else {
        await File(p.join(from, _catalogFile)).copy(catalogPath);
      }
      if (rulesNewer) {
        await _writeAsset(bundledInteractionDatabaseAssetPath, rulesPath);
      } else {
        await File(p.join(from, _rulesFile)).copy(rulesPath);
      }
      await _prepareAndCheck(assembly, record);
      await _publishFolder(assembly, record);
    }
    await _writePointer(
      pointer.copyWith(
        active: record.id,
        previous: () => active.id,
        confirmed: false,
        bundleSeen: bundled.tag,
      ),
    );
  }

  /// A build whose open-time work changed rebuilds the active folder from the
  /// same files, since nothing may be written in place.
  Future<void> _reprepareIfNeeded() async {
    final pointer = _pointer!;
    final active = await _readRecord(pointer.active);
    if (active == null || active.preparation == kReleasePreparation) return;
    final record = ReleaseRecord(
      id: ReleaseRecord.idFor(
        sequence: active.sequence,
        catalogVersion: active.catalogVersion,
        rulesVersion: active.rulesVersion,
        qualityWithheld: active.qualityWithheld,
      ),
      sequence: active.sequence,
      catalogVersion: active.catalogVersion,
      rulesVersion: active.rulesVersion,
      catalogSha256: active.catalogSha256,
      rulesSha256: active.rulesSha256,
      minRulesVersion: active.minRulesVersion,
      preparation: kReleasePreparation,
      qualityWithheld: active.qualityWithheld,
    );
    if (await _readRecord(record.id) == null) {
      final assembly = await _startAssembly(record.id);
      final from = _folder(active.id).path;
      for (final name in [_catalogFile, _rulesFile]) {
        await File(p.join(from, name)).copy(p.join(assembly.path, name));
      }
      await _prepareAndCheck(assembly, record);
      await _publishFolder(assembly, record);
    }
    await _writePointer(
      pointer.copyWith(
        active: record.id,
        // A withheld catalog's previous is the file that still has its scores.
        previous: () => active.qualityWithheld ? pointer.previous : active.id,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Installs from before release folders
  // ---------------------------------------------------------------------------

  /// Moves an existing install into a folder. A root catalog at least as new as
  /// the bundled one moves rather than copies, so an install that had no room
  /// for a second copy still upgrades. An older one is replaced by the bundled
  /// catalog, or moved too if that can't be written. The move goes through a
  /// holding folder that launch doesn't clear, so a crash anywhere repeats from
  /// there.
  Future<ReleasePointer> _migrateLegacyFiles() async {
    final bundled = await _bundledIdentity();
    final held = File(p.join(_legacyHolding.path, _catalogFile));
    if (await held.exists()) {
      await _assembleBundled(bundled, fromHolding: true);
      return _pointer!;
    }

    final rootCatalog = File(p.join(documents.path, 'pharmaguide_core.db'));
    await _settleInterruptedSwap(rootCatalog.path);
    final version = await _readCatalogVersion(rootCatalog.path);
    if (version != null && !_bundleIsNewer(bundled, version)) {
      await _holdRootCatalog(rootCatalog, held);
      await _assembleBundled(bundled, fromHolding: true);
      return _pointer!;
    }
    try {
      await _assembleBundled(bundled);
    } on SimulatedReleaseCrash {
      rethrow;
    } on Object {
      if (version == null) rethrow;
      await _clearAssemblies();
      await _holdRootCatalog(rootCatalog, held);
      await _assembleBundled(bundled, fromHolding: true);
    }
    return _pointer!;
  }

  Future<void> _holdRootCatalog(File rootCatalog, File held) async {
    await _legacyHolding.create();
    await rootCatalog.rename(held.path);
    await flushDirectory(documents.path);
    await flushDirectory(_legacyHolding.path);
  }

  /// When an old install can't be moved at all, such as on a completely full
  /// disk, its files still work: read-only handles over them, with no pointer,
  /// and the next launch tries the move again. Returns null if they can't open.
  Future<ReleaseGeneration?> _openLegacyInPlace() async {
    File inHolding(String name) => File(p.join(_legacyHolding.path, name));
    File inRoot(String name) => File(p.join(documents.path, name));
    final catalog = await inHolding(_catalogFile).exists()
        ? inHolding(_catalogFile)
        : inRoot('pharmaguide_core.db');
    if (!await catalog.exists()) return null;

    CoreDatabase? core;
    try {
      core = CoreDatabase.readOnly(catalog);
      final catalogVersion = await core.validateCatalogSnapshot();
      InteractionDatabase? rules;
      String? rulesVersion;
      for (final file in [
        inHolding(_rulesFile),
        inRoot('interaction_db.sqlite'),
      ]) {
        if (rules != null || !await file.exists()) continue;
        try {
          rules = await _openRules(file.path);
          rulesVersion = (await rules.getMetadata()).interactionDbVersion;
        } on Object catch (e) {
          debugPrint('[release] old rules unavailable: ${e.runtimeType}');
        }
      }
      return ReleaseGeneration(
        record: ReleaseRecord(
          id: ReleaseRecord.idFor(
            sequence: 0,
            catalogVersion: catalogVersion,
            rulesVersion: rulesVersion ?? _noRules,
          ),
          sequence: 0,
          catalogVersion: catalogVersion,
          rulesVersion: rulesVersion ?? _noRules,
          catalogSha256: null,
          rulesSha256: null,
          minRulesVersion: null,
          preparation: kReleasePreparation,
        ),
        core: core,
        rules: rules,
        rulesWithheld: false,
      );
    } on Object catch (e) {
      debugPrint('[release] old install unavailable: ${e.runtimeType}');
      await _closeQuietly(() async => core?.close());
      return null;
    }
  }

  /// What the root-file catalog swap left behind if it was interrupted: the
  /// backup is the last catalog known to work unless the live file passed the
  /// recorded activation intent.
  Future<void> _settleInterruptedSwap(String dbPath) async {
    final backup = File('$dbPath.backup');
    final marker = File('$dbPath.activation.json');
    final hasMarker = await marker.exists();
    if (!hasMarker && !await backup.exists()) return;

    final intent = hasMarker ? await _readSwapIntent(marker) : null;
    final version = hasMarker && intent == null
        ? null
        : await _readCatalogVersion(dbPath);
    final accepted =
        version != null &&
        (intent == null ||
            version == intent.expected ||
            version == intent.previous);
    if (!accepted) {
      if (await backup.exists()) {
        await backup.rename(dbPath);
      } else if (await File(dbPath).exists()) {
        // No recovery file: the bundled catalog takes over.
        await File(dbPath).delete();
      }
    }
  }

  Future<({String expected, String? previous})?> _readSwapIntent(
    File marker,
  ) async {
    try {
      final intent = jsonDecode(await marker.readAsString());
      if (intent is! Map) return null;
      final expected = intent['expected'];
      final previous = intent['previous'];
      if (expected is! String || expected.isEmpty) return null;
      if (previous != null && previous is! String) return null;
      return (expected: expected, previous: previous as String?);
    } on Object {
      return null;
    }
  }

  Future<void> _deleteLegacyFiles() async {
    const names = [
      'pharmaguide_core.db',
      'pharmaguide_core.db.backup',
      'pharmaguide_core.db.activation.json',
      'pharmaguide_core.db.activation.json.tmp',
      'pharmaguide_core.db.staging',
      'pharmaguide_core.db.staging.version',
      'pharmaguide_core.db.bundle_marker.json',
      'pharmaguide_core.db-journal',
      'interaction_db.sqlite',
      'interaction_db.sqlite.bundle_marker.json',
      'interaction_db.sqlite-journal',
    ];
    for (final name in names) {
      try {
        final file = File(p.join(documents.path, name));
        if (await file.exists()) await file.delete();
      } on Object {
        // Retried next launch; the files are no longer read.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Retention
  // ---------------------------------------------------------------------------

  /// Keeps the active release and the previous one, at launch only, so a file a
  /// running check has open is never deleted.
  Future<void> _retainActiveAndPrevious() async {
    final pointer = _pointer!;
    final keep = {pointer.active, ?pointer.previous, _stagingDir};
    await for (final entry in _root.list()) {
      if (entry is! Directory || keep.contains(p.basename(entry.path))) {
        continue;
      }
      try {
        await entry.delete(recursive: true);
      } on Object {
        // Retried next launch.
      }
    }
  }

  Future<List<String>> _keptFoldersNewestFirst() async {
    final records = <ReleaseRecord>[];
    await for (final entry in _root.list()) {
      if (entry is! Directory) continue;
      final record = await _readRecord(p.basename(entry.path));
      if (record != null) records.add(record);
    }
    records.sort((a, b) {
      final bySequence = b.sequence.compareTo(a.sequence);
      if (bySequence != 0) return bySequence;
      final bVersion = CatalogVersion.parse(b.catalogVersion);
      final aVersion = CatalogVersion.parse(a.catalogVersion);
      if (aVersion == null || bVersion == null) return 0;
      return bVersion.compareTo(aVersion);
    });
    return [for (final record in records) record.id];
  }

  // ---------------------------------------------------------------------------
  // Pointer and record files
  // ---------------------------------------------------------------------------

  Future<ReleasePointer?> _readPointer() async {
    if (!await _pointerPath.exists()) return null;
    try {
      return ReleasePointer.fromJson(
        jsonDecode(await _pointerPath.readAsString()),
      );
    } on Object {
      return null;
    }
  }

  /// A missing or invalid pointer with folders on disk: every kept folder
  /// validated before it was completed, so the newest one that opens wins, and
  /// the highest sequence is at least the newest folder's.
  Future<ReleasePointer?> _rebuildPointer() async {
    final kept = await _keptFoldersNewestFirst();
    if (kept.isEmpty) return null;
    final newest = await _readRecord(kept.first);
    return ReleasePointer(
      active: kept.first,
      previous: kept.length > 1 ? kept[1] : null,
      highestSequence: newest?.sequence ?? 0,
    );
  }

  Future<ReleaseRecord?> _readRecord(String id) async {
    final file = File(p.join(_folder(id).path, _recordFile));
    if (!await file.exists()) return null;
    try {
      final record = ReleaseRecord.fromJson(
        jsonDecode(await file.readAsString()),
      );
      return record?.id == id ? record : null;
    } on Object {
      return null;
    }
  }

  Future<void> _writePointer(ReleasePointer pointer) async {
    await _writeDurably(_pointerPath, jsonEncode(pointer.toJson()));
    await flushDirectory(_root.path);
    _pointer = pointer;
  }

  /// Flush a temporary file, then rename it over the target.
  Future<void> _writeDurably(File target, String contents) async {
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(target.path);
  }

  Future<void> _flushFile(File file) async {
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  Future<String?> _readCatalogVersion(String path) async {
    if (!await File(path).exists()) return null;
    CoreDatabase? db;
    try {
      db = CoreDatabase.open(path);
      return await db.validateCatalogSnapshot();
    } on Object catch (e) {
      // Not being able to read a file says nothing about the file.
      if (_isTemporaryReadFailure(e)) rethrow;
      return null;
    } finally {
      await _closeQuietly(() async => db?.close());
    }
  }

  Future<String?> _readRulesVersion(String path) async {
    InteractionDatabase? db;
    try {
      db = InteractionDatabase.open(path);
      return (await db.getMetadata()).interactionDbVersion;
    } on Object {
      return null;
    } finally {
      await _closeQuietly(() async => db?.close());
    }
  }

  Future<void> _closeQuietly(Future<void> Function() close) async {
    try {
      await close();
    } on Object {
      // Best-effort; a malformed file can fail before drift opens it.
    }
  }
}

/// Thrown by a test's [ReleaseStore.onStep] to stand in for the process dying.
@visibleForTesting
class SimulatedReleaseCrash implements Exception {
  const SimulatedReleaseCrash(this.step);
  final ReleaseStep step;

  @override
  String toString() => 'SimulatedReleaseCrash($step)';
}

class _ReleaseRefused implements Exception {
  const _ReleaseRefused(this.reason);
  final String reason;

  @override
  String toString() => reason;
}

class _BundleIdentity {
  const _BundleIdentity({
    required this.catalogVersion,
    required this.catalogSha256,
    required this.rulesVersion,
    required this.rulesSha256,
  });

  final String? catalogVersion;
  final String? catalogSha256;
  final String? rulesVersion;
  final String? rulesSha256;

  String get tag => '$catalogVersion|$rulesVersion';
}

/// Chunk size for streamed asset to disk copies (4 MiB).
const int _assetWriteChunkBytes = 4 << 20;

/// Writes [bytes] in chunks, which keeps peak memory at one asset copy and
/// yields to the event loop between chunks, so first launch doesn't jank.
Future<void> _writeBytesChunked(File file, Uint8List bytes) async {
  await file.parent.create(recursive: true);
  final sink = file.openWrite();
  try {
    for (
      var offset = 0;
      offset < bytes.length;
      offset += _assetWriteChunkBytes
    ) {
      final end = math.min(offset + _assetWriteChunkBytes, bytes.length);
      sink.add(Uint8List.sublistView(bytes, offset, end));
      await sink.flush();
    }
  } finally {
    await sink.close();
  }
}

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _FdNative = Int32 Function(Int32);
typedef _FdDart = int Function(int);

/// Flushes a directory's entries, so a rename survives power loss. dart:io has
/// no way to do this. Best-effort by design: losing it can only leave the older
/// pointer, or one that names a missing folder, and both recover at launch.
@visibleForTesting
Future<void> flushDirectory(String path) async {
  if (!Platform.isIOS && !Platform.isAndroid && !Platform.isMacOS) return;
  try {
    final libc = DynamicLibrary.process();
    final open = libc.lookupFunction<_OpenNative, _OpenDart>('open');
    final fsync = libc.lookupFunction<_FdNative, _FdDart>('fsync');
    final close = libc.lookupFunction<_FdNative, _FdDart>('close');
    final native = path.toNativeUtf8();
    try {
      final descriptor = open(native, 0);
      if (descriptor >= 0) {
        fsync(descriptor);
        close(descriptor);
      }
    } finally {
      malloc.free(native);
    }
  } on Object {
    // See above.
  }
}

/// Busy, locked, I/O, full disk and can't-open say something about this moment.
/// Anything else, such as corrupt bytes or a failed validation, is about the
/// release itself.
bool _isTemporaryReadFailure(Object error) {
  final cause = error is DriftRemoteException ? error.remoteCause : error;
  if (cause is FileSystemException) return true;
  if (cause is! SqliteException) return false;
  return const {5, 6, 10, 13, 14}.contains(cause.extendedResultCode & 0xff);
}
