import 'dart:convert';

import 'package:pharmaguide/data/database/interaction_database.dart';

class ResearchPairSentence {
  final String sentence;
  final String? pmid;

  const ResearchPairSentence({required this.sentence, this.pmid});
}

class ResearchPairEvidence {
  final String pairId;
  final String entityAName;
  final String entityBName;
  final String entityAType;
  final String entityBType;
  final String? canonicalIdA;
  final String? canonicalIdB;
  final String? rxcuiA;
  final String? rxcuiB;
  final int paperCount;
  final int humanStudyCount;
  final int clinicalStudyCount;
  final int? latestPaperYear;
  final List<ResearchPairSentence> topSentences;
  final List<String> topPmids;

  const ResearchPairEvidence({
    required this.pairId,
    required this.entityAName,
    required this.entityBName,
    required this.entityAType,
    required this.entityBType,
    required this.canonicalIdA,
    required this.canonicalIdB,
    required this.rxcuiA,
    required this.rxcuiB,
    required this.paperCount,
    required this.humanStudyCount,
    required this.clinicalStudyCount,
    required this.latestPaperYear,
    required this.topSentences,
    required this.topPmids,
  });

  factory ResearchPairEvidence.fromRow(ResearchPairRow row) {
    return ResearchPairEvidence(
      pairId: row.pairId,
      entityAName: row.entityAName,
      entityBName: row.entityBName,
      entityAType: row.entityAType,
      entityBType: row.entityBType,
      canonicalIdA: row.canonicalIdA,
      canonicalIdB: row.canonicalIdB,
      rxcuiA: row.rxcuiA,
      rxcuiB: row.rxcuiB,
      paperCount: row.paperCount,
      humanStudyCount: row.humanStudyCount,
      clinicalStudyCount: row.clinicalStudyCount,
      latestPaperYear: row.latestPaperYear,
      topSentences: _decodeSentences(row.topSentencesJson),
      topPmids: _decodeStringList(row.topPmidsJson),
    );
  }

  bool involvesCanonicalId(String canonicalId) {
    final normalized = canonicalId.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return canonicalIdA?.toLowerCase() == normalized ||
        canonicalIdB?.toLowerCase() == normalized;
  }

  bool involvesRxcui(String rxcui) {
    final normalized = rxcui.trim();
    if (normalized.isEmpty) return false;
    return rxcuiA == normalized || rxcuiB == normalized;
  }

  String otherEntityNameForCanonical(String canonicalId) {
    final normalized = canonicalId.trim().toLowerCase();
    if (canonicalIdA?.toLowerCase() == normalized) return entityBName;
    if (canonicalIdB?.toLowerCase() == normalized) return entityAName;
    return '$entityAName + $entityBName';
  }

  String get pairLabel => '$entityAName + $entityBName';

  static List<ResearchPairSentence> _decodeSentences(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <ResearchPairSentence>[];
      final out = <ResearchPairSentence>[];
      for (final entry in decoded.whereType<Map<String, dynamic>>()) {
        final sentence = (entry['sentence'] ?? entry['text'] ?? '')
            .toString()
            .trim();
        if (sentence.isEmpty) continue;
        final pmid = entry['pmid']?.toString().trim();
        out.add(
          ResearchPairSentence(
            sentence: sentence,
            pmid: pmid == null || pmid.isEmpty ? null : pmid,
          ),
        );
      }
      return out;
    } on FormatException {
      return const <ResearchPairSentence>[];
    }
  }

  static List<String> _decodeStringList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      return const <String>[];
    }
  }
}
