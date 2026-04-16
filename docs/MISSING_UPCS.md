# Products Missing UPCs

**Total:** 250 products across 19 brands
**Source:** `pharmaguide_core.db`
**Generated:** 2026-04-15

## What this is

These products exist in the app database but have no scannable UPC barcode.
Users can still find them via search (by name/brand), but barcode scanning will fail.

**Invalid UPC marker:** Products with non-empty but invalid UPCs (not 12/13 digits) are also listed here.

## How to fill them

1. **Automated:** Run `backfill_upc.py` in `~/Downloads/dsld_clean/scripts/` — searches UPCitemdb by brand + name
2. **Manual:** Look up the product on Amazon/Walmart/iHerb/brand site and edit the staged JSON at `~/Documents/DataSetDsld/staging/brands/<Brand>/<dsld_id>.json`
3. After patching, rebuild the pipeline DB

---

## Table of Contents

- [CVS Health](#cvs-health) — 18 products
- [CVS Pharmacy](#cvs-pharmacy) — 9 products
- [Goli Nutrition](#goli-nutrition) — 3 products
- [HUM](#hum) — 2 products
- [Legion](#legion) — 3 products
- [Nature Made](#nature-made) — 164 products
- [Nature Made Kids First](#nature-made-kids-first) — 3 products
- [Nature Made Solutions](#nature-made-solutions) — 1 products
- [Nature Made VitaMelts](#nature-made-vitamelts) — 1 products
- [Nature Made WellBlends](#nature-made-wellblends) — 1 products
- [Nature Made Wellblends](#nature-made-wellblends) — 1 products
- [OLLY](#olly) — 7 products
- [Pure Encapsulations](#pure-encapsulations) — 8 products
- [Ritual](#ritual) — 3 products
- [Thorne](#thorne) — 2 products
- [Thorne Research](#thorne-research) — 6 products
- [Transparent Labs](#transparent-labs) — 7 products
- [vitaFusion Fiber Well](#vitafusion-fiber-well) — 1 products
- [vitafusion](#vitafusion) — 10 products

---

## CVS Health

**Count:** 18

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 276002 | Adult 50+ Eye Health | _(empty)_ | discontinued |
| 272474 | Calcium & Vitamin D3 Gummies | _(empty)_ | discontinued |
| 278525 | Calcium 600 mg & Vitamin D3 | _(empty)_ | active |
| 278524 | Calcium Citrate 630 mg + D3 500 IU | _(empty)_ | active |
| 210396 | Calcium, Magnesium & Zinc | _(empty)_ | active |
| 211014 | Children's Gummy Dinos | _(empty)_ | discontinued |
| 278527 | Children's Organic Daily Multivitamin Gummies | _(empty)_ | active |
| 276003 | Digestive Probiotic | _(empty)_ | active |
| 211031 | Eye Health & Lutein | _(empty)_ | active |
| 76540 | Fiber Formula | _(empty)_ | active |
| 239657 | Glucosamine Sulfate 2000 mg | _(empty)_ | active |
| 76542 | Intestinal Formula | _(empty)_ | active |
| 76539 | Liver Formula | _(empty)_ | active |
| 278549 | Men's Daily Multivitamin | _(empty)_ | discontinued |
| 210949 | One Daily Men's 50+ Advanced | _(empty)_ | active |
| 278546 | One Daily Women's 50+ Advanced | _(empty)_ | discontinued |
| 82365 | One Daily Women's 50+ Advanced | _(empty)_ | discontinued |
| 210972 | Spectravite Ultra Men | _(empty)_ | active |

## CVS Pharmacy

**Count:** 9

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 12944 | Algal-900 DHA | _(empty)_ | active |
| 25841 | Children's Chewable Vitamin D 400 IU Fruit Flavored | _(empty)_ | active |
| 263890 | Children's Immune Support Honey Lemon Flavored | _(empty)_ | active |
| 25935 | DHA | _(empty)_ | active |
| 25831 | Glucosamine Chondroitin Regular Strength | _(empty)_ | discontinued |
| 25932 | Multivitamin/Multimineral | _(empty)_ | active |
| 25839 | One Daily Bone Health + UC-II For Joints | _(empty)_ | active |
| 82333 | Spectravite Adult | _(empty)_ | active |
| 82364 | Spectravite Ultra Women | _(empty)_ | active |

## Goli Nutrition

**Count:** 3

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 245156 | Ashwagandha Gummies Mixed Berry | _(empty)_ | active |
| 335679 | Matcha Mind | _(empty)_ | active |
| 268686 | Supergreens Gummies | _(empty)_ | active |

## HUM

**Count:** 2

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 241715 | Killer Nails | _(empty)_ | active |
| 241716 | Red Carpet | _(empty)_ | active |

## Legion

**Count:** 3

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 339533 | Phoenix | _(empty)_ | active |
| 303533 | Pulse Fruit Punch | _(empty)_ | active |
| 274376 | Whey+ Dutch Chocolate | _(empty)_ | active |

## Nature Made

**Count:** 164

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 26671 | Adult Chewable D3 1000 IU Grape Flavor | _(empty)_ | discontinued |
| 9232 | Adult Multivitamin | _(empty)_ | active |
| 270951 | Alpha Lipoic Acid 200 mg | _(empty)_ | active |
| 9107 | Antioxidant Formula | _(empty)_ | active |
| 270954 | Biotin 1000 mcg | _(empty)_ | active |
| 26624 | Biotin 5000 mcg | _(empty)_ | discontinued |
| 239938 | Biotin Adult Gummies 3000 mcg | _(empty)_ | active |
| 180429 | Burp-less Fish Oil 1200 mg | _(empty)_ | active |
| 180439 | Burp-less Fish Oil 1200 mg | _(empty)_ | active |
| 288083 | Burp-less Fish Oil 1200 mg | _(empty)_ | active |
| 211250 | C Vitamin Adult Gummies Tangerine | _(empty)_ | active |
| 271077 | Calcium 500 mg | _(empty)_ | active |
| 71241 | Calcium 500 mg | _(empty)_ | active |
| 8828 | Calcium 500 mg | _(empty)_ | discontinued |
| 9078 | Calcium 500 mg Supplement | _(empty)_ | discontinued |
| 8837 | Calcium 500 mg Supplement With Vitamin D | _(empty)_ | active |
| 8836 | Calcium 500 mg Supplement with Vitamin D | _(empty)_ | active |
| 71234 | Calcium 600 mg | _(empty)_ | active |
| 8951 | Calcium 600 mg Supplement | _(empty)_ | active |
| 8955 | Calcium 600 mg Supplement With Vitamin D | _(empty)_ | active |
| 8957 | Calcium 600 mg Supplement With Vitamin D | _(empty)_ | active |
| 279713 | Calcium 750 mg | _(empty)_ | active |
| 82550 | Calcium 750 mg+D+K | _(empty)_ | discontinued |
| 71289 | Calcium Adult Gummies | _(empty)_ | active |
| 71384 | Calcium Citrate + Magnesium | _(empty)_ | active |
| 8797 | Calcium Citrate Supplement With Vitamin D | _(empty)_ | discontinued |
| 8959 | Calcium Citrate Supplement With Vitamin D | _(empty)_ | discontinued |
| 271078 | Calcium Gummies 500 mg | _(empty)_ | active |
| 272561 | Calcium Magnesium Zinc | _(empty)_ | active |
| 8912 | Chewable Calcium 600 mg Supplement With Vitamin D 200 IU | _(empty)_ | active |
| 9244 | Chewable Calcium 600 mg Supplement with Vitamin D 200 IU | _(empty)_ | active |
| 180441 | Chewable Vitamin C 500 mg | _(empty)_ | active |
| 209600 | Chewable Vitamin C 500 mg Orange | _(empty)_ | active |
| 9246 | Chewable Vitamin C 500 mg Supplement | _(empty)_ | active |
| 179821 | CholestOff Complete | _(empty)_ | discontinued |
| 271299 | CholestOff Complete | _(empty)_ | active |
| 285745 | CholestOff Complete | _(empty)_ | active |
| 26633 | CholestOff Original | _(empty)_ | active |
| 82539 | CholestOff Original | _(empty)_ | active |
| 270710 | CholestOff Plus | _(empty)_ | active |
| 71081 | CholestOff Plus 450 mg | _(empty)_ | active |
| 180420 | CoQ10 100 mg | _(empty)_ | active |
| 270947 | CoQ10 100 mg | _(empty)_ | active |
| 8782 | CoQ10 100 mg Supplement | _(empty)_ | active |
| 180379 | CoQ10 200 mg | _(empty)_ | active |
| 179677 | CoQ10 400 mg | _(empty)_ | active |
| 209640 | CoQ10 Adult Gummies Mango | _(empty)_ | active |
| 8953 | CoQ10 Supplement 200 mg | _(empty)_ | active |
| 82688 | Cod Liver Oil | _(empty)_ | active |
| 180421 | D3 1000 IU | _(empty)_ | active |
| 180424 | D3 1000 IU | _(empty)_ | discontinued |
| 71258 | D3 1000 IU | _(empty)_ | discontinued |
| 287806 | D3 1000 IU (25 mcg) | _(empty)_ | active |
| 180423 | D3 2000 IU | _(empty)_ | active |
| 26672 | D3 400 IU | _(empty)_ | active |
| 270957 | D3 50 mcg | _(empty)_ | active |
| 71376 | D3 5000 IU | _(empty)_ | active |
| 274365 | D3 Gummies 2000 IU (50 mcg) | _(empty)_ | active |
| 271079 | Daily Energy Gummies | _(empty)_ | active |
| 271624 | Daily Maximin Pack | _(empty)_ | active |
| 273228 | Elderberry Max Mixed Berry | _(empty)_ | active |
| 239941 | Energy B12 Adult Gummies 1000 mcg | _(empty)_ | active |
| 9125 | Essential Balance | _(empty)_ | active |
| 270952 | Extra Strength Biotin 2500 mcg | _(empty)_ | active |
| 240870 | Extra Strength D3 5000 IU (125 mcg) | _(empty)_ | active |
| 8821 | Eye Defense | _(empty)_ | active |
| 13801 | Fish Oil 1000 mg | _(empty)_ | active |
| 180426 | Fish Oil 1000 mg | _(empty)_ | active |
| 82715 | Fish Oil 1000 mg | _(empty)_ | active |
| 180435 | Fish Oil 1200 mg | _(empty)_ | active |
| 180438 | Fish Oil 1200 mg | _(empty)_ | active |
| 82691 | Fish Oil 1200 mg One Per Day | _(empty)_ | discontinued |
| 26648 | Fish Oil 500 mg 360 mg Omega-3 | _(empty)_ | active |
| 26655 | Fish Oil Adult Gummies | _(empty)_ | discontinued |
| 211283 | Fish Oil Pearls | _(empty)_ | discontinued |
| 231416 | Fish Oil Pearls | _(empty)_ | active |
| 71309 | Flaxseed Oil 1400 mg | _(empty)_ | active |
| 211387 | Flush-Free Niacin 500 mg | _(empty)_ | active |
| 270953 | Folic Acid 400 mcg | _(empty)_ | active |
| 179920 | Full Strength Mini Omega-3 | _(empty)_ | active |
| 71294 | Full Strength Mini Omega-3 | _(empty)_ | discontinued |
| 302768 | Full Strength Minis Super Omega-3 | _(empty)_ | active |
| 270958 | Good Sleep Gummies Dreamy Strawberry | _(empty)_ | active |
| 211251 | Hair, Skin, & Nails | _(empty)_ | discontinued |
| 271084 | Hair-Skin-Nails | _(empty)_ | active |
| 271631 | Hair-Skin-Nails | _(empty)_ | active |
| 279768 | Hair-Skin-Nails | _(empty)_ | active |
| 209646 | Hair-Skin-Nails Adult Gummies | _(empty)_ | active |
| 270959 | Hair-Skin-Nails Gummies | _(empty)_ | active |
| 26644 | High Potency Biotin 2500 mcg | _(empty)_ | active |
| 179720 | High Potency D3 5000 IU | _(empty)_ | active |
| 209393 | High Potency Magnesium 400 mg | _(empty)_ | active |
| 26640 | High Potency Magnesium 400 mg | _(empty)_ | discontinued |
| 8936 | Iron 65 mg | _(empty)_ | active |
| 240874 | Iron 65 mg (325 mg Ferrous Sulfate) | _(empty)_ | active |
| 9080 | Iron Supplement | _(empty)_ | active |
| 279867 | K2 100 mcg | _(empty)_ | active |
| 26625 | L-Lysine 500 mg | _(empty)_ | discontinued |
| 180442 | Magnesium 250 mg | _(empty)_ | active |
| 270965 | Magnesium Citrate 250 mg | _(empty)_ | active |
| 322551 | Magnesium Glycinate 200 mg | _(empty)_ | active |
| 179940 | Maximum Strength Magnesium 500 mg | _(empty)_ | active |
| 271095 | Melatonin + 200 mg L-Theanine | _(empty)_ | active |
| 71312 | Melatonin + 200 mg L-Theanine | _(empty)_ | discontinued |
| 270948 | Melatonin 3 mg | _(empty)_ | active |
| 180126 | Melatonin 5 mg | _(empty)_ | active |
| 209660 | Melatonin Adult Gummies Strawberry | _(empty)_ | active |
| 209485 | Melatonin Maximum Strength 5 mg | _(empty)_ | active |
| 270955 | Mini Omega-3 540 mg | _(empty)_ | active |
| 211279 | Multi + Omega-3 Adult Gummies | _(empty)_ | active |
| 270966 | Multi + Omega-3 Gummies | _(empty)_ | active |
| 9112 | Multi 50+ Bone & Heart Health | _(empty)_ | active |
| 209449 | Multi Adult Gummies | _(empty)_ | discontinued |
| 71364 | Multi Adult Gummies | _(empty)_ | discontinued |
| 8920 | Multi Chewable For Adults | _(empty)_ | active |
| 9128 | Multi Complete | _(empty)_ | active |
| 26646 | Multi Complete With Iron & Calcium | _(empty)_ | active |
| 9245 | Multi Complete With Lutein | _(empty)_ | active |
| 9118 | Multi Complete with iron | _(empty)_ | active |
| 8927 | Multi Daily Essential Formula | _(empty)_ | active |
| 82683 | Multi For Her | _(empty)_ | discontinued |
| 26674 | Multi For Her 50+ With Calcium No Iron | _(empty)_ | active |
| 8798 | Multi For Her With Calcium & Iron | _(empty)_ | discontinued |
| 26687 | Multi For Her Wtih Iron & Calcium | _(empty)_ | active |
| 270971 | Multi Gummies | _(empty)_ | active |
| 8978 | Multi Prenatal | _(empty)_ | active |
| 270967 | Multi for Her + Omega-3s Gummies | _(empty)_ | active |
| 211272 | Multi for Her plus Omega-3s | _(empty)_ | active |
| 270969 | Multi for Him | _(empty)_ | active |
| 239942 | Multi for Him Adult Gummies | _(empty)_ | active |
| 271074 | Omega-3 with Xtra Absorb Technology | _(empty)_ | active |
| 71328 | Postnatal Multi + DHA | _(empty)_ | discontinued |
| 271090 | Prenatal Multi | _(empty)_ | active |
| 209359 | Prenatal Multi + DHA | _(empty)_ | active |
| 241703 | Prenatal Multi + DHA 200 mg | _(empty)_ | active |
| 26688 | Prenatal Multi +DHA | _(empty)_ | active |
| 271075 | Stress B-Complex | _(empty)_ | active |
| 209616 | Super B Energy Complex | _(empty)_ | active |
| 180430 | Super B-Complex | _(empty)_ | active |
| 82538 | Super B-Complex | _(empty)_ | discontinued |
| 8795 | Super B-Complex Supplement With Vitamin C | _(empty)_ | active |
| 8799 | Super B-Complex Supplement With Vitamin C | _(empty)_ | active |
| 271080 | Super C | _(empty)_ | active |
| 209577 | Super Strength Cranberry 450 mg Extract with Vitamin C | _(empty)_ | active |
| 268025 | Triple Flex Triple Strength | _(empty)_ | active |
| 271076 | Triple Flex Triple Strength | _(empty)_ | active |
| 211265 | Triple Flex with Vitamin D3 | _(empty)_ | active |
| 26689 | Triple Omega | _(empty)_ | discontinued |
| 71299 | Triple Probiotic | _(empty)_ | active |
| 71253 | TripleFlex | _(empty)_ | discontinued |
| 71334 | TripleFlex 50+ | _(empty)_ | active |
| 26652 | Turmeric Curcumin | _(empty)_ | discontinued |
| 317709 | Turmeric Extra Strength 1000 mg (950 mg Curcuminoids) | _(empty)_ | active |
| 71338 | Utlra Omega-3 Fish Oil 1400 mg | _(empty)_ | discontinued |
| 209633 | VitaMelts Strawberry Lemonade | _(empty)_ | active |
| 209429 | VitaMelts Tropical Fruit | _(empty)_ | active |
| 209169 | Vitamin B1 100 mg | _(empty)_ | active |
| 302771 | Vitamin C 500 mg | _(empty)_ | active |
| 302755 | Vitamin C Adult Gummies Orange | _(empty)_ | active |
| 270968 | Vitamin C Gummies Tangerine | _(empty)_ | active |
| 24784 | Vitamin D3 5000 IU | _(empty)_ | active |
| 239936 | Vitamin D3 Adult Gummies | _(empty)_ | active |
| 71345 | Vitamin D3 Adult Gummies | _(empty)_ | discontinued |
| 8918 | Vitamin E 400 IU Supplement | _(empty)_ | active |

## Nature Made Kids First

**Count:** 3

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 270960 | Calcium + Vitamin D3 Gummies | _(empty)_ | active |
| 270961 | Fiber Gummies | _(empty)_ | active |
| 270962 | Vitamin C Gummies 125 mg Tangerine | _(empty)_ | active |

## Nature Made Solutions

**Count:** 1

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 271091 | Triple Flex 50+ Triple Strength | _(empty)_ | active |

## Nature Made VitaMelts

**Count:** 1

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 71365 | Hair-Skin-Nails Strawberry Lemonade | _(empty)_ | discontinued |

## Nature Made WellBlends

**Count:** 1

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 333477 | Energy Max Mocha | _(empty)_ | active |

## Nature Made Wellblends

**Count:** 1

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 272720 | Immune & Respiratory | _(empty)_ | active |

## OLLY

**Count:** 7

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 265456 | Beat the Bloat | _(empty)_ | discontinued |
| 328482 | Chill Thinker Brainy Chews Pomegranate Bliss | _(empty)_ | active |
| 328484 | Energized Thinker Brainy Chews Tropical Groove | _(empty)_ | active |
| 328485 | Focused Thinker Brainy Chews Raspberry Jam | _(empty)_ | active |
| 316119 | Plant Powered Focus | _(empty)_ | active |
| 303971 | Relaxing Sleep Fast Dissolve Tablets Apple Berry | _(empty)_ | active |
| 303972 | Sleep Fast Dissolve Tablets Strawberry | _(empty)_ | active |

## Pure Encapsulations

**Count:** 8

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 207879 | E.P.O. (Evening Primrose Oil) | _(empty)_ | discontinued |
| 207894 | LVR Formula | _(empty)_ | discontinued |
| 207882 | Maca-3 | _(empty)_ | discontinued |
| 207899 | Mineral 650 | _(empty)_ | discontinued |
| 207850 | Nutrient 950 | _(empty)_ | discontinued |
| 207903 | OptiFerin-C | _(empty)_ | discontinued |
| 13565 | P5P 50 | _(empty)_ | discontinued |
| 207886 | Potassium (Aspartate) | _(empty)_ | discontinued |

## Ritual

**Count:** 3

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 323711 | Essential for Men | _(empty)_ | active |
| 278454 | Essential for Women Mint Essenced | _(empty)_ | active |
| 299239 | Synbiotic+ | _(empty)_ | active |

## Thorne

**Count:** 2

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 306247 | FloraSport 20B | _(empty)_ | active |
| 209571 | Multi-Vitamin Elite A.M. | _(empty)_ | discontinued |

## Thorne Research

**Count:** 6

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 20153 | Basic B Complex | `6 93 49 0403 2` | discontinued |
| 74938 | Multi-Vitamin Elite A.M. | _(empty)_ | discontinued |
| 16236 | Myco-Immune | _(empty)_ | discontinued |
| 15756 | Vitamin D | _(empty)_ | discontinued |
| 15762 | Vitamin D/K2 | _(empty)_ | discontinued |
| 15761 | Vitamin K2 | _(empty)_ | discontinued |

## Transparent Labs

**Count:** 7

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 295773 | Bulk Strawberry Kiwi | _(empty)_ | active |
| 325587 | Creatine HMB Strawberry Lemonade | _(empty)_ | active |
| 305203 | KSM-66 | _(empty)_ | active |
| 249741 | Preseries Bulk Blue Raspberry | `V2` | active |
| 309959 | Preseries Lean Pre-Workout Tropical Punch | _(empty)_ | active |
| 309960 | Preseries Stim-Free Blue Raspberry | _(empty)_ | active |
| 339541 | Vitality | _(empty)_ | active |

## vitaFusion Fiber Well

**Count:** 1

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 274597 | Sugar Free Gummies | _(empty)_ | active |

## vitafusion

**Count:** 10

| DSLD ID | Product Name | Current UPC | Status |
|---------|--------------|-------------|--------|
| 12930 | B Complex Energy Wild Strawberry | _(empty)_ | active |
| 174855 | B Complex Natural Strawberry Flavor | _(empty)_ | active |
| 12928 | Calcium 500 mg | _(empty)_ | active |
| 12932 | Fiber Gummies | _(empty)_ | active |
| 26587 | Men's Daily MultiVitamin Formula | _(empty)_ | active |
| 241721 | Men's Powerful Multi Natural Berry Flavor | _(empty)_ | active |
| 337363 | Super Immune Support Natural Mixed Berry Citrus Flavor | _(empty)_ | active |
| 240457 | Women's | _(empty)_ | active |
| 12933 | Women's Complete MultiVitamin Formula | _(empty)_ | active |
| 26583 | Women's Daily Multivitamin Formula | _(empty)_ | active |
