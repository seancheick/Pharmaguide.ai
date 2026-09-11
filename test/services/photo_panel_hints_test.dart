import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/gtin.dart';
import 'package:pharmaguide/services/photo_panel_hints.dart';

final _submission = GtinIdentity.parse('050428381397');

void main() {
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
