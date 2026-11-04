import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/gtin.dart';
import 'package:pharmaguide/services/photo_panel_hints.dart';

final _submission = GtinIdentity.parse('050428381397');

void main() {
  test('directions accept common introductory phrases before the dose', () {
    for (final text in [
      'Suggested Use: For adults, take one capsule daily.',
      'Directions: As a dietary supplement, mix one scoop into water.',
    ]) {
      expect(
        readPanelHints(text, submission: _submission).showsDirections,
        isTrue,
      );
    }
    expect(
      readPanelHints(
        'Directions: For adults only.',
        submission: _submission,
      ).showsDirections,
      isFalse,
    );
  });

  test('only a Nutrition Facts heading without Supplement Facts prompts', () {
    for (final (label, expected) in [
      ('Nutrition Facts\nServing Size 1 can', true),
      ('Nutrition Facts\nSupplement Facts', false),
      ('Serving Size 1 scoop\nAmount Per Serving', false),
    ]) {
      expect(
        readPanelHints(label, submission: _submission).looksLikeFoodLabel,
        expected,
      );
    }
  });

  test('a warning alone does not cover the directions panel', () {
    final hints = readPanelHints(
      'Warning: keep out of reach of children.',
      submission: _submission,
    );
    expect(hints.showsDirectionsOrWarnings, isTrue);
    expect(hints.showsDirections, isFalse);
  });

  test('suggested use alongside Facts covers directions', () {
    final hints = readPanelHints(
      'Supplement Facts\nServing Size 1 scoop\nSuggested Use: Mix 2 scoops daily.',
      submission: _submission,
    );
    expect(hints.showsFactsPanel, isTrue);
    expect(hints.showsDirections, isTrue);
  });

  test('a Supplement Facts panel reads as facts', () {
    final hints = readPanelHints(
      'Supplement Facts\nServing Size 1 Capsule\nAmount Per Serving %DV\n'
      'Vitamin D3 25 mcg 125%',
      submission: _submission,
    );
    expect(hints.showsFactsHeading, isTrue);
    expect(hints.showsFactsPanel, isTrue);
  });

  test('facts table markers count even when the heading is cut off', () {
    final hints = readPanelHints(
      'Serving Size 2 Softgels\nAmount Per Serving\n% Daily Value',
      submission: _submission,
    );
    expect(hints.showsFactsHeading, isFalse);
    expect(hints.showsFactsPanel, isTrue);
  });

  test('a directions and warnings panel is not a facts panel', () {
    final hints = readPanelHints(
      'Suggested Use: Take one capsule daily with food.\n'
      'Warning: Keep out of reach of children. Consult your physician if '
      'pregnant or nursing.',
      submission: _submission,
    );
    expect(hints.showsFactsPanel, isFalse);
    expect(hints.showsDirectionsOrWarnings, isTrue);
  });

  test('directions remain detectable alongside facts and ingredients', () {
    final hints = readPanelHints(
      'Supplement Facts\nServing Size 1 Capsule\n'
      'Other Ingredients: cellulose\nSuggested Use: take one capsule daily.\n'
      'Warning: keep out of reach of children.',
      submission: _submission,
    );
    expect(hints.showsFactsPanel, isTrue);
    expect(hints.showsOtherIngredients, isTrue);
    expect(hints.showsDirectionsOrWarnings, isTrue);
  });

  test('finds the Other Ingredients list, even split across lines', () {
    for (final text in [
      'Other Ingredients: rice flour, gelatin capsule.',
      'Other\nIngredients: cellulose',
      'Inactive ingredients: magnesium stearate',
    ]) {
      expect(
        readPanelHints(text, submission: _submission).showsOtherIngredients,
        isTrue,
        reason: text,
      );
    }
    expect(
      readPanelHints(
        'Contains no artificial ingredients',
        submission: _submission,
      ).showsOtherIngredients,
      isFalse,
    );
  });

  test('recognises the scanned barcode at any printed width', () {
    for (final text in [
      '0 50428 38139 7',
      'UPC 050428381397',
      '0050428381397',
    ]) {
      final hints = readPanelHints(text, submission: _submission);
      expect(hints.showsSubmissionBarcode, isTrue, reason: text);
      expect(hints.conflictingBarcode, isNull, reason: text);
    }
  });

  test('a different full barcode is reported as a conflict', () {
    final hints = readPanelHints('0 36000 29145 2', submission: _submission);
    expect(hints.showsSubmissionBarcode, isFalse);
    expect(hints.conflictingBarcode?.canonicalGtin14, '00036000291452');
  });

  test('a short number that passes a check digit is not a conflict', () {
    // Lot codes and dates are often 8 digits; one in ten passes an EAN-8
    // check digit by chance, so a short run never raises a wrong-product
    // warning.
    final hints = readPanelHints('LOT 96385074', submission: _submission);
    expect(hints.conflictingBarcode, isNull);
  });

  test('no conflict is raised when the scanned barcode is also present', () {
    final hints = readPanelHints(
      '0 50428 38139 7\n0 36000 29145 2',
      submission: _submission,
    );
    expect(hints.showsSubmissionBarcode, isTrue);
    expect(hints.conflictingBarcode, isNull);
  });

  test('no text means no hints', () {
    final hints = readPanelHints('  \n ', submission: _submission);
    expect(hints.showsFactsPanel, isFalse);
    expect(hints.showsDirectionsOrWarnings, isFalse);
    expect(hints.showsOtherIngredients, isFalse);
    expect(hints.showsSubmissionBarcode, isFalse);
    expect(hints.conflictingBarcode, isNull);
  });
}
