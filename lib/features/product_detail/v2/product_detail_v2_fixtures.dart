import 'package:pharmaguide/core/components/pg_ingredient_stack.dart';
import 'package:pharmaguide/core/components/pg_severity_badge.dart';

/// Immutable fixture model — plain Dart, no provider coupling.
///
/// Real data wires through `detail_blob_provider` etc. later (Phase 1
/// prototype uses these fixtures so the v2 screen renders in the gallery
/// without catalog plumbing).
class ProductDetailFixture {
  final String id;
  final String productName;
  final String brand;
  final String? form;
  final String? servingSize;
  final String? imageUrl;
  final String? labelImageUrl;
  final double pgScore;
  final String fitState;
  final PGSeverity topSeverity;
  final String topVerdictLabel;
  final String topVerdictExplain;
  final String evidenceLabel;
  final List<PGIngredient> activeIngredients;
  final List<PGIngredient> inactiveIngredients;

  const ProductDetailFixture({
    required this.id,
    required this.productName,
    required this.brand,
    required this.form,
    required this.servingSize,
    required this.imageUrl,
    required this.labelImageUrl,
    required this.pgScore,
    required this.fitState,
    required this.topSeverity,
    required this.topVerdictLabel,
    required this.topVerdictExplain,
    required this.evidenceLabel,
    required this.activeIngredients,
    required this.inactiveIngredients,
  });
}

/// Showcase fixtures covering the v2 plan's stress-test acceptance line:
/// "A product with a long name, missing image, and 20+ ingredients must
/// still look intentional — not like an edge case."
abstract final class ProductDetailFixtures {
  /// Normal case — short name, clear safety, modest ingredient list.
  static const normal = ProductDetailFixture(
    id: 'normal',
    productName: 'Magnesium Glycinate',
    brand: 'Thorne',
    form: 'Capsule',
    servingSize: '2 capsules',
    imageUrl: null,
    labelImageUrl: null,
    pgScore: 88,
    fitState: 'Aligns with your stack',
    topSeverity: PGSeverity.safe,
    topVerdictLabel: 'No high-risk conflicts detected',
    topVerdictExplain:
        'Your stack and conditions show no contraindications for this product.',
    evidenceLabel: 'ESTABLISHED',
    activeIngredients: [
      PGIngredient(name: 'Magnesium (as Glycinate)', dose: '200 mg'),
      PGIngredient(name: 'Glycine', dose: '1.4 g'),
    ],
    inactiveIngredients: [
      PGIngredient(name: 'Hypromellose'),
      PGIngredient(name: 'Microcrystalline cellulose'),
      PGIngredient(name: 'Silicon dioxide'),
    ],
  );

  /// Long-name + ALL-CAPS brand case. Worst-case title wrap.
  static const longName = ProductDetailFixture(
    id: 'longName',
    productName:
        'High-Potency Triple-Strength Marine Omega-3 Fish Oil Concentrate '
        'with Vitamin D3 + K2 (Lemon Flavor)',
    brand: 'NORDIC NATURALS',
    form: 'Softgel',
    servingSize: '2 softgels',
    imageUrl: null,
    labelImageUrl: null,
    pgScore: 74,
    fitState: 'Monitor with your cardiologist',
    topSeverity: PGSeverity.monitor,
    topVerdictLabel: 'Bleeding risk with anticoagulant medications',
    topVerdictExplain:
        'High-dose omega-3 (>3 g/day) can extend bleeding time. Coordinate '
        'with your prescriber if you take warfarin or rivaroxaban.',
    evidenceLabel: 'MODERATE',
    activeIngredients: [
      PGIngredient(name: 'EPA (Eicosapentaenoic Acid)', dose: '650 mg'),
      PGIngredient(name: 'DHA (Docosahexaenoic Acid)', dose: '450 mg'),
      PGIngredient(name: 'Other Omega-3 Fatty Acids', dose: '180 mg'),
      PGIngredient(name: 'Vitamin D3 (Cholecalciferol)', dose: '1000 IU'),
      PGIngredient(name: 'Vitamin K2 (Menaquinone-7)', dose: '90 mcg'),
    ],
    inactiveIngredients: [
      PGIngredient(name: 'Gelatin'),
      PGIngredient(name: 'Glycerin'),
      PGIngredient(name: 'Purified water'),
      PGIngredient(name: 'Lemon oil'),
      PGIngredient(name: 'd-alpha tocopherol'),
    ],
  );

  /// 20+ ingredients case. Tests compact-stack collapse behavior.
  static const manyIngredients = ProductDetailFixture(
    id: 'manyIngredients',
    productName: 'Daily Multivitamin Complex',
    brand: 'Pure Encapsulations',
    form: 'Capsule',
    servingSize: '6 capsules',
    imageUrl: null,
    labelImageUrl: null,
    pgScore: 81,
    fitState: 'Aligns with your stack',
    topSeverity: PGSeverity.safe,
    topVerdictLabel: 'No high-risk conflicts detected',
    topVerdictExplain: 'No interactions found with your current medications.',
    evidenceLabel: 'ESTABLISHED',
    activeIngredients: [
      PGIngredient(name: 'Vitamin A (Beta Carotene)', dose: '3000 IU'),
      PGIngredient(name: 'Vitamin C (Ascorbic Acid)', dose: '200 mg'),
      PGIngredient(name: 'Vitamin D3', dose: '1000 IU'),
      PGIngredient(name: 'Vitamin E', dose: '30 IU'),
      PGIngredient(name: 'Vitamin K2', dose: '120 mcg'),
      PGIngredient(name: 'Thiamine (B1)', dose: '25 mg'),
      PGIngredient(name: 'Riboflavin (B2)', dose: '25 mg'),
      PGIngredient(name: 'Niacin (B3)', dose: '50 mg'),
      PGIngredient(name: 'Pantothenic Acid (B5)', dose: '50 mg'),
      PGIngredient(name: 'Pyridoxal-5-Phosphate (B6)', dose: '25 mg'),
      PGIngredient(name: 'Methylcobalamin (B12)', dose: '500 mcg'),
      PGIngredient(name: 'Folate (5-MTHF)', dose: '400 mcg'),
      PGIngredient(name: 'Biotin', dose: '300 mcg'),
      PGIngredient(name: 'Calcium (Citrate-Malate)', dose: '200 mg'),
      PGIngredient(name: 'Magnesium (Glycinate)', dose: '125 mg'),
      PGIngredient(name: 'Zinc (Picolinate)', dose: '15 mg'),
      PGIngredient(name: 'Selenium (Selenomethionine)', dose: '200 mcg'),
      PGIngredient(name: 'Manganese', dose: '2 mg'),
      PGIngredient(name: 'Chromium (Polynicotinate)', dose: '200 mcg'),
      PGIngredient(name: 'Iodine (Potassium Iodide)', dose: '150 mcg'),
      PGIngredient(name: 'Boron', dose: '1 mg'),
      PGIngredient(name: 'Vanadium', dose: '50 mcg'),
    ],
    inactiveIngredients: [
      PGIngredient(name: 'Hypromellose'),
      PGIngredient(name: 'Microcrystalline cellulose'),
      PGIngredient(name: 'Ascorbyl palmitate'),
      PGIngredient(
        name: 'Titanium dioxide',
        severity: PGSeverity.caution,
      ),
      PGIngredient(name: 'Silicon dioxide'),
      PGIngredient(name: 'Magnesium stearate'),
    ],
  );

  /// High-risk verdict. Tests calm-but-clear contraindicated presentation.
  static const contraindicated = ProductDetailFixture(
    id: 'contraindicated',
    productName: 'St. John\'s Wort Extract',
    brand: 'Generic Brand',
    form: 'Capsule',
    servingSize: '1 capsule',
    imageUrl: null,
    labelImageUrl: null,
    pgScore: 32,
    fitState: 'Worth a conversation with your doctor',
    topSeverity: PGSeverity.contraindicated,
    topVerdictLabel: 'Major interaction with your antidepressant',
    topVerdictExplain:
        'St. John\'s Wort + SSRI raises the risk of serotonin syndrome. '
        'Worth a conversation with your prescriber before starting.',
    evidenceLabel: 'ESTABLISHED',
    activeIngredients: [
      PGIngredient(name: 'St. John\'s Wort Extract (0.3% Hypericin)',
          dose: '300 mg'),
    ],
    inactiveIngredients: [
      PGIngredient(name: 'Rice flour'),
      PGIngredient(name: 'Vegetable capsule'),
    ],
  );

  static List<ProductDetailFixture> get all => [
    normal,
    longName,
    manyIngredients,
    contraindicated,
  ];

  static ProductDetailFixture byId(String id) =>
      all.firstWhere((f) => f.id == id, orElse: () => normal);
}
