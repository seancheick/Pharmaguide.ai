// ClinicianReportBuilder — pure-function markdown summary of the user's
// stack for sharing with a doctor or pharmacist.
//
// Inputs in, markdown string out. No I/O, no provider access, no DB
// reads — the caller assembles the inputs from on-device state and
// hands them in. This makes the output golden-testable and guarantees
// that no health data leaks into a network call from inside the
// builder.
//
// Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track C, C1.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/data/database/user_database.dart';

@immutable
class ClinicianReportBuilder {
  const ClinicianReportBuilder();

  /// Build the markdown summary.
  ///
  /// [intelligence] is the canonical diagnostic verdict from
  /// [StackIntelligenceEngine]. Its `issues` list is already
  /// severity-sorted (most-severe first), so the builder renders it
  /// in order without re-sorting — matching the spec's
  /// "severity-sorted warnings (unsafe > concerning > caution > info)"
  /// requirement.
  ///
  /// [generatedAt] is injected so tests can pin the timestamp.
  String build({
    required UserProfile? profile,
    required List<UserStacksLocalData> stack,
    required StackIntelligence intelligence,
    required DateTime generatedAt,
  }) {
    final buf = StringBuffer();

    // ---- Header + privacy note + disclaimer ----
    buf.writeln('# My Supplement Stack — Clinician Summary');
    buf.writeln();
    buf.writeln('**Generated on device · ${_formatDate(generatedAt)}**');
    buf.writeln();
    buf.writeln(
      '> Educational summary, not medical advice. Generated entirely on '
      'this device — PharmaGuide does not store this report on any '
      'server.',
    );

    // ---- Profile ----
    if (profile != null) {
      final goals = _decodeJsonStringList(profile.goals);
      final conditions = _decodeJsonStringList(profile.conditions);
      final drugClasses = _decodeJsonStringList(profile.drugClasses);
      final allergens = _decodeJsonStringList(profile.allergens);

      final hasAnyProfileField = profile.ageBracket != null ||
          profile.sex != null ||
          conditions.isNotEmpty ||
          drugClasses.isNotEmpty ||
          goals.isNotEmpty ||
          allergens.isNotEmpty;

      if (hasAnyProfileField) {
        buf.writeln();
        buf.writeln('## Profile');
        if (profile.ageBracket != null && profile.ageBracket!.isNotEmpty) {
          buf.writeln('- Age: ${profile.ageBracket}');
        }
        if (profile.sex != null && profile.sex!.isNotEmpty) {
          buf.writeln('- Sex: ${profile.sex}');
        }
        if (conditions.isNotEmpty) {
          buf.writeln('- Conditions: ${conditions.join(", ")}');
        }
        if (drugClasses.isNotEmpty) {
          buf.writeln('- Drug classes: ${drugClasses.join(", ")}');
        }
        if (goals.isNotEmpty) {
          buf.writeln('- Goals: ${goals.join(", ")}');
        }
        if (allergens.isNotEmpty) {
          buf.writeln('- Allergens: ${allergens.join(", ")}');
        }
      }
    }

    // ---- Medications + supplements ----
    final medications =
        stack.where((e) => e.type == 'medication').toList(growable: false);
    final supplements =
        stack.where((e) => e.type == 'supplement').toList(growable: false);

    if (medications.isNotEmpty) {
      buf.writeln();
      buf.writeln('## Medications (${medications.length})');
      for (final m in medications) {
        buf.writeln(_formatStackLine(m));
      }
    }

    if (supplements.isNotEmpty) {
      buf.writeln();
      buf.writeln('## Supplements (${supplements.length})');
      for (final s in supplements) {
        buf.writeln(_formatStackLine(s));
      }
    }

    // ---- Stack diagnosis ----
    buf.writeln();
    buf.writeln('## Stack Diagnosis');
    buf.writeln('- Tier: **${_tierLabel(intelligence.tier)}**');
    buf.writeln('- Stack size: ${intelligence.stackSize}');
    buf.writeln(
      '- Interactions flagged: ${intelligence.interactionCount}',
    );
    buf.writeln(
      '- Nutrient warnings: ${intelligence.nutrientWarningCount}',
    );
    if (intelligence.hasBannedIngredient) {
      buf.writeln('- ⚠️ Banned ingredient detected');
    }
    if (intelligence.hasRecalledIngredient &&
        !intelligence.hasBannedIngredient) {
      buf.writeln('- ⚠️ Recalled ingredient detected');
    }
    if (intelligence.hasContraindicatedInteraction) {
      buf.writeln('- ⚠️ Contraindicated interaction detected');
    }

    // ---- Warnings (severity-sorted, courtesy of B2) ----
    if (intelligence.issues.isNotEmpty) {
      buf.writeln();
      buf.writeln('## Warnings (most severe first)');
      for (final issue in intelligence.issues) {
        buf.writeln('- **${issue.severity.label}** — ${issue.headline}');
      }
    }

    // ---- Footer disclaimer ----
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln(
      '_This is an educational summary, not medical advice. Always '
      "consult your healthcare provider before starting or stopping a "
      'supplement._',
    );

    return buf.toString();
  }

  String _formatStackLine(UserStacksLocalData item) {
    final dosage = (item.dosage ?? '').trim();
    final frequency = (item.frequency ?? '').trim();
    if (dosage.isEmpty && frequency.isEmpty) return '- ${item.name}';
    if (dosage.isNotEmpty && frequency.isEmpty) {
      return '- ${item.name} — $dosage';
    }
    if (dosage.isEmpty && frequency.isNotEmpty) {
      return '- ${item.name} — $frequency';
    }
    return '- ${item.name} — $dosage, $frequency';
  }

  String _tierLabel(StackTier tier) => switch (tier) {
        StackTier.optimized => 'Optimized',
        StackTier.solid => 'Solid',
        StackTier.decent => 'Decent',
        StackTier.concerning => 'Concerning',
        StackTier.unsafe => 'Unsafe',
        StackTier.incomplete => 'More info needed',
      };

  String _formatDate(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  /// Decode a JSON-encoded string array stored in the profile table
  /// (goals, conditions, drug_classes, allergens). Returns const [] on
  /// any decode failure or non-list shape.
  List<String> _decodeJsonStringList(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
      }
    } on FormatException {
      // fall through to empty
    }
    return const <String>[];
  }
}
