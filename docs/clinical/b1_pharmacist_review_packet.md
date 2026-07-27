# B1 pharmacist review packet

Status: **clinical reviewer sign-off requested**

Scope: **33 active verified records only**. The 47 suppressed/rejected records are intentionally not consumer-facing and are outside this packet.

Artifact: schema `5.4.0`, content version `2026-07-27`, content hash `sha256:98259507ef920a503084f748b11c9bbcc1d7ec7fabdadb9d3d7326610bef2753`.

## Review focus

- Confirm the medication scope and nutrient relationship are clinically accurate.
- Confirm the mechanism and clinical impact are supported by the linked evidence.
- Confirm recommendations are calm, actionable, and do not imply universal supplementation.
- Confirm monitoring and supplement-interaction records are not presented as measured deficiency.
- Record approval or requested revision by record ID; do not review the suppressed/rejected corpus.

## App presentation

Verified records:

![Verified medication-nutrient presentation](../../test/release_gate/goldens/med_nutrient_verified.png)

Unavailable analysis (explicitly not an all-clear):

![Unavailable medication-nutrient presentation](../../test/release_gate/goldens/med_nutrient_unavailable.png)

## Active-record index

| Record | Medication / class | Nutrient | Relationship |
|---|---|---|---|
| `DEP_ANTACIDS_IRON` | Acid reducers (PPIs and H2 blockers) (`class:acid_suppressants`) | Iron | `depletion` |
| `DEP_ANTICONVULSANTS_VITAMIND` | Carbamazepine (`2002`) | Vitamin D | `depletion` |
| `DEP_CHOLESTYRAMINE_VITAMINA` | Cholestyramine (bile-acid sequestrant) (`2447`) | Vitamin A | `depletion` |
| `DEP_CHOLESTYRAMINE_VITAMIND` | Cholestyramine (bile-acid sequestrant) (`2447`) | Vitamin D | `depletion` |
| `DEP_CHOLESTYRAMINE_VITAMINE` | Cholestyramine (bile-acid sequestrant) (`2447`) | Vitamin E | `depletion` |
| `DEP_CHOLESTYRAMINE_VITAMINK` | Cholestyramine (bile-acid sequestrant) (`2447`) | Vitamin K | `depletion` |
| `DEP_COLCHICINE_VITAMINB12` | Colchicine (gout medication) (`2683`) | Vitamin B12 | `depletion` |
| `DEP_ANTICONVULSANTS_CALCIUM` | Enzyme-inducing antiseizure medications (`class:enzyme_inducing_antiseizure_medications`) | Calcium | `depletion` |
| `DEP_ANTICONVULSANTS_VITAMINK` | Enzyme-inducing antiseizure medications (`class:enzyme_inducing_antiseizure_medications`) | Vitamin K | `depletion` |
| `DEP_DIURETICS_THIAMINE` | Furosemide (Lasix) (`4603`) | Thiamin | `depletion` |
| `DEP_ISONIAZID_VITAMINB6` | Isoniazid (tuberculosis medication) (`6038`) | Vitamin B6 | `depletion` |
| `DEP_LEVOTHYROXINE_CALCIUM` | Levothyroxine (thyroid hormone replacement) (`10582`) | Calcium | `supplement_interaction` |
| `DEP_LEVOTHYROXINE_IRON` | Levothyroxine (thyroid hormone replacement) (`10582`) | Iron | `supplement_interaction` |
| `DEP_DIURETICS_CALCIUM` | Loop diuretics (water pills like furosemide) (`class:loop_diuretics`) | Calcium | `depletion` |
| `DEP_METFORMIN_VITAMINB12` | Metformin (type 2 diabetes medication) (`6809`) | Vitamin B12 | `depletion` |
| `DEP_METHOTREXATE_FOLATE` | Methotrexate (antifolate medication) (`6851`) | Folate | `functional_antagonism` |
| `DEP_OCP_VITAMINB6` | Oral contraceptives (birth control pills) (`class:oral_contraceptives`) | Vitamin B6 | `depletion` |
| `DEP_ORLISTAT_VITAMINA` | Orlistat (fat-blocking weight-loss medication) (`37925`) | Vitamin A | `depletion` |
| `DEP_ORLISTAT_VITAMIND` | Orlistat (fat-blocking weight-loss medication) (`37925`) | Vitamin D | `depletion` |
| `DEP_ORLISTAT_VITAMINE` | Orlistat (fat-blocking weight-loss medication) (`37925`) | Vitamin E | `depletion` |
| `DEP_ORLISTAT_VITAMINK` | Orlistat (fat-blocking weight-loss medication) (`37925`) | Vitamin K | `depletion` |
| `DEP_ANTICONVULSANTS_FOLATE` | Phenytoin (`8183`) | Folate | `depletion` |
| `DEP_ANTICONVULSANTS_VITAMINB12` | Phenytoin (`8183`) | Vitamin B12 | `depletion` |
| `DEP_ANTACIDS_CALCIUM` | Proton pump inhibitors (PPIs) (`class:proton_pump_inhibitors`) | Calcium | `depletion` |
| `DEP_SSRIS_SODIUM` | SSRIs (antidepressants) (`class:ssris`) | Sodium | `monitoring_stability` |
| `DEP_STATINS_COQ10` | Statins (cholesterol-lowering medications) (`class:statins`) | Coenzyme Q10 | `depletion` |
| `DEP_SULFASALAZINE_FOLATE` | Sulfasalazine (inflammatory bowel disease / arthritis medication) (`9524`) | Folate | `depletion` |
| `DEP_CORTICOSTEROIDS_CALCIUM` | Systemic corticosteroids (prednisone, prednisolone, dexamethasone) (`class:corticosteroids`) | Calcium | `depletion` |
| `DEP_CORTICOSTEROIDS_VITAMIND` | Systemic corticosteroids (prednisone, prednisolone, dexamethasone) (`class:corticosteroids`) | Vitamin D | `monitoring_stability` |
| `DEP_DIURETICS_ZINC` | Thiazide diuretics (e.g., hydrochlorothiazide) (`class:thiazide_diuretics`) | Zinc | `depletion` |
| `DEP_DIURETICS_FOLATE` | Triamterene (in Dyazide, Maxzide) (`10763`) | Folate | `functional_antagonism` |
| `DEP_ANTICONVULSANTS_LCARNITINE` | Valproate (valproic acid, divalproex / Depakote) (`class:valproate`) | L-Carnitine | `depletion` |
| `DEP_ANTICOAGULANTS_VITAMINK` | Warfarin (anticoagulant / blood thinner) (`class:anticoagulants`) | Vitamin K | `functional_antagonism` |

## Record details

### 1. `DEP_ANTACIDS_IRON`

- Medication / class: Acid reducers (PPIs and H2 blockers) (`class:acid_suppressants`)
- Nutrient: Iron (`iron`)
- Relationship: `depletion`; severity `moderate`; onset `months`
- Mechanism: Gastric acid reduces dietary non-heme iron (Fe3+) to the absorbable ferrous form (Fe2+) and frees iron from food. Both PPIs and H2 blockers suppress acid, so long-term use can lower non-heme iron absorption; the effect is dose-related and reverses after stopping.
- Clinical impact: Over months to years this can contribute to iron deficiency and, if unaddressed, iron-deficiency anemia — most relevant for menstruating women, frequent blood donors, and people with low dietary iron. Heme iron from meat is less affected.
- Recommendation: If you take a PPI or H2 blocker long-term and are at risk (menstruating, low iron, plant-based diet), ask your doctor to check ferritin. Take any iron supplement a couple of hours apart from your acid reducer, and with vitamin C to aid absorption.
- Evidence: [Lam JR et al. Proton pump inhibitor and histamine-2 receptor antagonist use and iron deficiency. Gastroenterology. 2017](https://pubmed.ncbi.nlm.nih.gov/27890768/); [Hutchinson C et al. Proton pump inhibitors suppress absorption of dietary non-haem iron in hereditary haemochromatosis. Gut. 2007](https://pubmed.ncbi.nlm.nih.gov/17344278/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 2. `DEP_ANTICONVULSANTS_VITAMIND`

- Medication / class: Carbamazepine (`drug:2002`)
- Nutrient: Vitamin D (`vitamin_d`)
- Relationship: `depletion`; severity `significant`; onset `months`
- Mechanism: Long-term carbamazepine treatment is associated with lower circulating 25-hydroxyvitamin D. Carbamazepine is an enzyme-inducing antiseizure medication; this record does not generalize that result to every antiseizure medicine.
- Clinical impact: Lower vitamin D can contribute to poorer bone health over time. Individual fracture risk and treatment decisions need clinical assessment.
- Recommendation: Discuss vitamin D intake and whether testing is appropriate with the clinician managing carbamazepine. Do not start high-dose vitamin D without individualized advice.
- Evidence: [Impact of carbamazepine on vitamin D levels: A meta-analysis. Epilepsy Res. 2021.](https://pubmed.ncbi.nlm.nih.gov/34847425/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 3. `DEP_CHOLESTYRAMINE_VITAMINA`

- Medication / class: Cholestyramine (bile-acid sequestrant) (`drug:2447`)
- Nutrient: Vitamin A (`vitamin_a`)
- Relationship: `depletion`; severity `moderate`; onset `months`
- Mechanism: Cholestyramine binds bile acids in the gut and can interfere with fat digestion and absorption. Because Vitamin A is fat-soluble, long-term bile-acid binding can reduce absorption unless vitamin timing is managed.
- Clinical impact: Lower Vitamin A absorption can matter during long-term cholestyramine use, especially when diet is marginal, fat absorption is already impaired, or pregnancy/nutrition needs are higher.
- Recommendation: Review fat-soluble vitamin intake and timing with the prescriber. Vitamins are often separated from cholestyramine so binding in the gut is less likely.
- Evidence: [DailyMed — CHOLESTYRAMINE prescribing information](https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=09420793-7357-4194-8172-0b1cddb167fe)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 4. `DEP_CHOLESTYRAMINE_VITAMIND`

- Medication / class: Cholestyramine (bile-acid sequestrant) (`drug:2447`)
- Nutrient: Vitamin D (`vitamin_d`)
- Relationship: `depletion`; severity `moderate`; onset `months`
- Mechanism: Cholestyramine binds bile acids in the gut and can interfere with fat digestion and absorption. Because Vitamin D is fat-soluble, long-term bile-acid binding can reduce absorption unless vitamin timing is managed.
- Clinical impact: Lower Vitamin D absorption can matter during long-term cholestyramine use, especially when diet is marginal, fat absorption is already impaired, or pregnancy/nutrition needs are higher.
- Recommendation: Review fat-soluble vitamin intake and timing with the prescriber. Vitamins are often separated from cholestyramine so binding in the gut is less likely.
- Evidence: [DailyMed — CHOLESTYRAMINE prescribing information](https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=09420793-7357-4194-8172-0b1cddb167fe)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 5. `DEP_CHOLESTYRAMINE_VITAMINE`

- Medication / class: Cholestyramine (bile-acid sequestrant) (`drug:2447`)
- Nutrient: Vitamin E (`vitamin_e`)
- Relationship: `depletion`; severity `moderate`; onset `months`
- Mechanism: Cholestyramine binds bile acids in the gut and can interfere with fat digestion and absorption. Because Vitamin E is fat-soluble, long-term bile-acid binding can reduce absorption unless vitamin timing is managed.
- Clinical impact: Lower Vitamin E absorption can matter during long-term cholestyramine use, especially when diet is marginal, fat absorption is already impaired, or pregnancy/nutrition needs are higher.
- Recommendation: Review fat-soluble vitamin intake and timing with the prescriber. Vitamins are often separated from cholestyramine so binding in the gut is less likely.
- Evidence: [DailyMed — CHOLESTYRAMINE prescribing information](https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=09420793-7357-4194-8172-0b1cddb167fe)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 6. `DEP_CHOLESTYRAMINE_VITAMINK`

- Medication / class: Cholestyramine (bile-acid sequestrant) (`drug:2447`)
- Nutrient: Vitamin K (`vitamin_k`)
- Relationship: `depletion`; severity `moderate`; onset `months`
- Mechanism: Cholestyramine binds bile acids in the gut and can interfere with fat digestion and absorption. Because Vitamin K is fat-soluble, long-term bile-acid binding can reduce absorption unless vitamin timing is managed.
- Clinical impact: Lower Vitamin K absorption can matter during long-term cholestyramine use, especially when diet is marginal, fat absorption is already impaired, or pregnancy/nutrition needs are higher.
- Recommendation: Review fat-soluble vitamin intake and timing with the prescriber. Vitamins are often separated from cholestyramine so binding in the gut is less likely.
- Evidence: [DailyMed — CHOLESTYRAMINE prescribing information](https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=09420793-7357-4194-8172-0b1cddb167fe)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 7. `DEP_COLCHICINE_VITAMINB12`

- Medication / class: Colchicine (gout medication) (`drug:2683`)
- Nutrient: Vitamin B12 (`vitamin_b12`)
- Relationship: `depletion`; severity `moderate`; onset `months`
- Mechanism: Colchicine can affect intestinal mucosal function and has been listed among medicines associated with vitamin B12 malabsorption. Long-term use may reduce B12 uptake in susceptible people.
- Clinical impact: Lower B12 status over time can contribute to anemia, neuropathy symptoms, fatigue, and cognitive changes. Risk is higher when other B12 absorption risks are present.
- Recommendation: Consider periodic B12 monitoring during long-term colchicine therapy, especially if neuropathy symptoms, anemia, or additional B12 risk factors are present.
- Evidence: [DailyMed — Cyanocobalamin label, B12 malabsorption causes](https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=9172ca9d-6419-41de-829c-4f9a16220b46); [Webb DI et al. Mechanism of vitamin B12 malabsorption in patients receiving colchicine. N Engl J Med. 1968;279(16):845-50](https://pubmed.ncbi.nlm.nih.gov/5677718/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 8. `DEP_ANTICONVULSANTS_CALCIUM`

- Medication / class: Enzyme-inducing antiseizure medications (`class:enzyme_inducing_antiseizure_medications`)
- Nutrient: Calcium (`calcium`)
- Relationship: `depletion`; severity `significant`; onset `months`
- Mechanism: Anticonvulsant-associated bone disease can involve increased bone remodeling. Reduced vitamin D and lower calcium intake are relevant clinical considerations; this record is limited to the reviewed enzyme-inducing subset.
- Clinical impact: Long-term treatment can be associated with bone-health concerns. The appropriate evaluation depends on individual fracture and osteoporosis risk.
- Recommendation: Discuss dietary calcium, vitamin D, and bone-health risk with the clinician managing long-term enzyme-inducing antiseizure treatment rather than self-prescribing a dose.
- Evidence: [Treatment of anticonvulsant drug-induced bone disease. Epilepsy Behav. 2004.](https://pubmed.ncbi.nlm.nih.gov/15123011/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 9. `DEP_ANTICONVULSANTS_VITAMINK`

- Medication / class: Enzyme-inducing antiseizure medications (`class:enzyme_inducing_antiseizure_medications`)
- Nutrient: Vitamin K (`vitamin_k`)
- Relationship: `depletion`; severity `significant`; onset `months`
- Mechanism: The pregnancy literature on enzyme-inducing antiseizure medications and vitamin K is mixed. A small older study found lower neonatal vitamin-K markers without antenatal supplementation, while a later review did not find evidence of increased neonatal hemorrhagic disease overall.
- Clinical impact: Pregnancy-specific vitamin K decisions should be individualized with obstetric and neurology care; this is not evidence of a routine vitamin K deficiency in every person taking an antiseizure medication.
- Recommendation: If pregnant or planning pregnancy while taking an enzyme-inducing antiseizure medication, discuss vitamin K and newborn-bleeding considerations with the neurologist and obstetric clinician. Do not self-start high-dose vitamin K.
- Evidence: [Does vitamin K prophylaxis prevent bleeding in neonates exposed to enzyme-inducing antiepileptic drugs in utero? Can Fam Physician. 2006.](https://pubmed.ncbi.nlm.nih.gov/16812962/); [Supplementation of vitamin K in pregnant women receiving anticonvulsant therapy prevents neonatal vitamin K deficiency. Am J Obstet Gynecol. 1993.](https://pubmed.ncbi.nlm.nih.gov/8456897/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 10. `DEP_DIURETICS_THIAMINE`

- Medication / class: Furosemide (Lasix) (`drug:4603`)
- Nutrient: Thiamin (`thiamin`)
- Relationship: `depletion`; severity `significant`; onset `months`
- Mechanism: Furosemide increases urine flow, and thiamine is carried out with it, so urinary thiamine loss rises. The effect tracks with the degree of diuresis and is greatest with higher doses and long-term use.
- Clinical impact: In people on chronic, higher-dose furosemide — especially for heart failure — this can lead to thiamine deficiency, which may worsen heart function and, when severe, affect the nervous system. Everyday low-dose users with good intake are at much lower risk.
- Recommendation: If you take furosemide long-term, especially for heart failure, ask your doctor about checking thiamine or taking a thiamine-containing supplement. Do not change your diuretic on your own.
- Evidence: [Seligmann H et al. Thiamine deficiency in patients with congestive heart failure receiving long-term furosemide therapy: a pilot study. Am J Med. 1991](https://pubmed.ncbi.nlm.nih.gov/1867241/); [Zenuk C et al. Thiamine deficiency in congestive heart failure patients receiving long term furosemide therapy. Can J Clin Pharmacol. 2003](https://pubmed.ncbi.nlm.nih.gov/14712323/); [Hanninen SA et al. The prevalence of thiamin deficiency in hospitalized patients with congestive heart failure. J Am Coll Cardiol. 2006](https://pubmed.ncbi.nlm.nih.gov/16412860/); [Rieck J et al. Urinary loss of thiamine is increased by low doses of furosemide in healthy volunteers. J Lab Clin Med. 1999](https://pubmed.ncbi.nlm.nih.gov/10482308/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 11. `DEP_ISONIAZID_VITAMINB6`

- Medication / class: Isoniazid (tuberculosis medication) (`drug:6038`)
- Nutrient: Vitamin B6 (`vitamin_b6`)
- Relationship: `depletion`; severity `significant`; onset `months`
- Mechanism: Isoniazid binds and inactivates pyridoxal phosphate, the active coenzyme form of vitamin B6, and increases urinary loss of pyridoxine metabolites. This can lower functional B6 status during tuberculosis therapy.
- Clinical impact: Low vitamin B6 during isoniazid therapy can contribute to peripheral neuropathy, tingling, burning sensations, and rarely anemia or neuropsychiatric symptoms. Higher-risk patients are often supplemented from the start.
- Recommendation: Pyridoxine is commonly used with isoniazid, especially in people at higher neuropathy risk. Confirm the exact dose with the clinician managing tuberculosis therapy.
- Evidence: [van der Watt JJ et al. Polyneuropathy, anti-tuberculosis treatment and the role of pyridoxine in the HIV/AIDS era: a systematic review. Int J Tuberc Lung Dis. 2011;15(6):722-8](https://pubmed.ncbi.nlm.nih.gov/21477422/); [DailyMed — ISONIAZID prescribing information](https://dailymed.nlm.nih.gov/dailymed/lookup.cfm?setid=6dab7b7b-a3a9-47ef-b423-134bc6970d8b)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 12. `DEP_LEVOTHYROXINE_CALCIUM`

- Medication / class: Levothyroxine (thyroid hormone replacement) (`drug:10582`)
- Nutrient: Calcium (`calcium`)
- Relationship: `supplement_interaction`; severity `moderate`; onset `weeks`
- Mechanism: Calcium supplements and calcium-rich foods bind levothyroxine in the gastrointestinal tract through a direct physicochemical interaction, reducing drug absorption rather than depleting body calcium stores. Levothyroxine adsorbs to calcium carbonate in an acidic environment, lowering its bioavailability.
- Clinical impact: Taking calcium together with levothyroxine reduces thyroid hormone absorption and can raise TSH into the underactive range — in a pharmacokinetic study, levothyroxine uptake fell from about 84% to 58% when taken with a large (2 g) calcium dose. The result can be inadequate thyroid control and hypothyroid symptoms.
- Recommendation: Take levothyroxine at least 4 hours apart from calcium supplements or calcium-rich meals. If you start, stop, or change calcium timing, ask your clinician about checking your thyroid levels.
- Evidence: [Singh N et al. Effect of calcium carbonate on the absorption of levothyroxine. JAMA. 2000;283(21):2822-5](https://pubmed.ncbi.nlm.nih.gov/10838651/); [Singh N et al. The acute effect of calcium carbonate on the intestinal absorption of levothyroxine. Thyroid. 2001;11(10):967-71](https://pubmed.ncbi.nlm.nih.gov/11716045/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 13. `DEP_LEVOTHYROXINE_IRON`

- Medication / class: Levothyroxine (thyroid hormone replacement) (`drug:10582`)
- Nutrient: Iron (`iron`)
- Relationship: `supplement_interaction`; severity `moderate`; onset `weeks`
- Mechanism: Iron supplements form an insoluble complex with levothyroxine in the gut, reducing levothyroxine absorption. This is a drug-nutrient interaction affecting drug bioavailability rather than a direct iron depletion; in a controlled trial, taking ferrous sulfate with levothyroxine raised TSH from 1.6 to 5.4 mU/L over 12 weeks.
- Clinical impact: Co-administration can lead to inadequate thyroid hormone levels and a return of hypothyroid symptoms; the effect is variable but clinically significant in some patients.
- Recommendation: Take iron supplements at least 4 hours before or after levothyroxine. If you start or stop iron, ask your clinician about rechecking your thyroid levels.
- Evidence: [Campbell NR et al. Ferrous sulfate reduces thyroxine efficacy in patients with hypothyroidism. Ann Intern Med. 1992;117(12):1010-3](https://pubmed.ncbi.nlm.nih.gov/1443969/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 14. `DEP_DIURETICS_CALCIUM`

- Medication / class: Loop diuretics (water pills like furosemide) (`class:loop_diuretics`)
- Nutrient: Calcium (`calcium`)
- Relationship: `depletion`; severity `moderate`; onset `months`
- Mechanism: Loop diuretics (furosemide, bumetanide, torsemide) inhibit the NKCC2 transporter in the thick ascending limb, which is also needed for calcium reabsorption, so more calcium is lost in the urine. Thiazide diuretics do the opposite and retain calcium.
- Clinical impact: Long-term loop-diuretic use is linked to a modestly higher fracture risk, mainly in older adults, and part of that may reflect falls rather than bone loss alone. It is a modest effect and does not by itself mean a calcium shortfall.
- Recommendation: If you take a loop diuretic long-term, aim for adequate dietary calcium and vitamin D and ask your doctor about bone health. Most people do not need high-dose calcium supplements.
- Evidence: [Rejnmark L et al. Fracture risk in patients treated with loop diuretics. J Intern Med. 2006](https://pubmed.ncbi.nlm.nih.gov/16336519/); [Corrao G et al. Antihypertensive medications, loop diuretics, and risk of hip fracture in the elderly. Drugs Aging. 2015](https://pubmed.ncbi.nlm.nih.gov/26589307/); [Warshaw BL et al. The effect of chronic furosemide administration on urinary calcium excretion and calcium balance in growing rats. Pediatr Res. 1980](https://pubmed.ncbi.nlm.nih.gov/7465281/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 15. `DEP_METFORMIN_VITAMINB12`

- Medication / class: Metformin (type 2 diabetes medication) (`drug:6809`)
- Nutrient: Vitamin B12 (`vitamin_b12`)
- Relationship: `depletion`; severity `significant`; onset `years`
- Mechanism: Metformin impairs B12 absorption by interfering with a calcium-dependent intrinsic factor-B12 receptor complex on the ileal mucosa. This disrupts the final step of B12 uptake from the small intestine. The effect is dose-dependent and reverses with calcium supplementation in some patients.
- Clinical impact: Roughly 6-30% of long-term metformin users show low or deficient B12, depending on how deficiency is defined and how long metformin is taken. Low B12 can cause peripheral neuropathy (which may be misattributed to diabetic neuropathy), megaloblastic anemia, and cognitive changes, and may develop insidiously over years.
- Recommendation: The ADA recommends periodic B12 monitoring for all patients on metformin. Supplement with sublingual methylcobalamin 1,000 mcg/day if levels are borderline or low.
- Evidence: [NIH ODS — Vitamin B12 Fact Sheet for Health Professionals](https://ods.od.nih.gov/factsheets/VitaminB12-HealthProfessional/); [de Jager J et al. Long term treatment with metformin in patients with type 2 diabetes and risk of vitamin B-12 deficiency. BMJ. 2010](https://pubmed.ncbi.nlm.nih.gov/20488910/); [Bauman WA et al. Increased intake of calcium reverses vitamin B12 malabsorption induced by metformin. Diabetes Care. 2000](https://pubmed.ncbi.nlm.nih.gov/10977010/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 16. `DEP_METHOTREXATE_FOLATE`

- Medication / class: Methotrexate (antifolate medication) (`drug:6851`)
- Nutrient: Folate (`folate`)
- Relationship: `functional_antagonism`; severity `significant`; onset `weeks`
- Mechanism: Methotrexate is an antifolate drug that inhibits folate-dependent metabolic pathways, including dihydrofolate reductase-related recycling. In low-dose inflammatory disease treatment, folic acid is often used to reduce folate-mediated side effects.
- Clinical impact: Insufficient folate support during methotrexate therapy can contribute to mouth sores, nausea, liver-enzyme elevations, cytopenias, and treatment intolerance. The right schedule depends on the methotrexate regimen.
- Recommendation: Folic acid or folinic acid support should be clinician-directed with methotrexate. Do not change the folate schedule without the prescriber, because timing and dose can matter.
- Evidence: [Morgan SL, Baggott JE, Alarcon GS. Methotrexate in rheumatoid arthritis: folate supplementation should always be given. BioDrugs. 1997;8(3):164-75](https://pubmed.ncbi.nlm.nih.gov/18020507/); [Shea B et al. Folic acid and folinic acid for reducing side effects in patients receiving methotrexate for rheumatoid arthritis. Cochrane Database Syst Rev. 2013;(5):CD000951](https://pubmed.ncbi.nlm.nih.gov/23728635/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 17. `DEP_OCP_VITAMINB6`

- Medication / class: Oral contraceptives (birth control pills) (`class:oral_contraceptives`)
- Nutrient: Vitamin B6 (`vitamin_b6`)
- Relationship: `depletion`; severity `moderate`; onset `months`
- Mechanism: Estrogen-containing oral contraceptives are associated with lower plasma pyridoxal-5'-phosphate (the active form of vitamin B6) in population studies. The effect is modest with today's low-dose formulations and was larger with the higher-estrogen pills of earlier decades.
- Clinical impact: The change in B6 status is usually subclinical. The main practical concern is entering pregnancy with reduced B6 reserves in someone who stops the pill and conceives soon after.
- Recommendation: A normal diet (poultry, fish, potatoes, chickpeas, bananas) or a standard multivitamin typically provides enough B6 — high-dose B6 supplements are not recommended, because chronic intake well above the daily requirement can cause nerve symptoms. If you are planning pregnancy, discuss B6 and folate with your clinician.
- Evidence: [Wilson SMC et al. Oral contraceptive use: impact on folate, vitamin B6, and vitamin B12 status. Nutr Rev. 2011;69(10):572-83](https://pubmed.ncbi.nlm.nih.gov/21967158/); [NIH ODS — Vitamin B6 Fact Sheet for Health Professionals](https://ods.od.nih.gov/factsheets/VitaminB6-HealthProfessional/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 18. `DEP_ORLISTAT_VITAMINA`

- Medication / class: Orlistat (fat-blocking weight-loss medication) (`drug:37925`)
- Nutrient: Vitamin A (`vitamin_a`)
- Relationship: `depletion`; severity `moderate`; onset `months`
- Mechanism: Orlistat inhibits gastrointestinal lipases and reduces absorption of dietary fat. Because Vitamin A is fat-soluble, lower fat absorption can reduce uptake unless vitamin intake is separated from the orlistat dose.
- Clinical impact: Lower Vitamin A absorption can matter during long-term orlistat use, especially when dietary intake is marginal or when other conditions already affect fat absorption.
- Recommendation: Use a multivitamin containing vitamins A, D, E, and K at least 2 hours before or after orlistat, following the product label and clinician advice.
- Evidence: [DailyMed — XENICAL (orlistat) prescribing information](https://dailymed.nlm.nih.gov/dailymed/lookup.cfm?setid=6240792b-9224-2d10-e053-2a91aa0a2c3e)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 19. `DEP_ORLISTAT_VITAMIND`

- Medication / class: Orlistat (fat-blocking weight-loss medication) (`drug:37925`)
- Nutrient: Vitamin D (`vitamin_d`)
- Relationship: `depletion`; severity `moderate`; onset `months`
- Mechanism: Orlistat inhibits gastrointestinal lipases and reduces absorption of dietary fat. Because Vitamin D is fat-soluble, lower fat absorption can reduce uptake unless vitamin intake is separated from the orlistat dose.
- Clinical impact: Lower Vitamin D absorption can matter during long-term orlistat use, especially when dietary intake is marginal or when other conditions already affect fat absorption.
- Recommendation: Use a multivitamin containing vitamins A, D, E, and K at least 2 hours before or after orlistat, following the product label and clinician advice.
- Evidence: [DailyMed — XENICAL (orlistat) prescribing information](https://dailymed.nlm.nih.gov/dailymed/lookup.cfm?setid=6240792b-9224-2d10-e053-2a91aa0a2c3e)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 20. `DEP_ORLISTAT_VITAMINE`

- Medication / class: Orlistat (fat-blocking weight-loss medication) (`drug:37925`)
- Nutrient: Vitamin E (`vitamin_e`)
- Relationship: `depletion`; severity `moderate`; onset `months`
- Mechanism: Orlistat inhibits gastrointestinal lipases and reduces absorption of dietary fat. Because Vitamin E is fat-soluble, lower fat absorption can reduce uptake unless vitamin intake is separated from the orlistat dose.
- Clinical impact: Lower Vitamin E absorption can matter during long-term orlistat use, especially when dietary intake is marginal or when other conditions already affect fat absorption.
- Recommendation: Use a multivitamin containing vitamins A, D, E, and K at least 2 hours before or after orlistat, following the product label and clinician advice.
- Evidence: [DailyMed — XENICAL (orlistat) prescribing information](https://dailymed.nlm.nih.gov/dailymed/lookup.cfm?setid=6240792b-9224-2d10-e053-2a91aa0a2c3e)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 21. `DEP_ORLISTAT_VITAMINK`

- Medication / class: Orlistat (fat-blocking weight-loss medication) (`drug:37925`)
- Nutrient: Vitamin K (`vitamin_k`)
- Relationship: `depletion`; severity `moderate`; onset `months`
- Mechanism: Orlistat inhibits gastrointestinal lipases and reduces absorption of dietary fat. Because Vitamin K is fat-soluble, lower fat absorption can reduce uptake unless vitamin intake is separated from the orlistat dose.
- Clinical impact: Lower Vitamin K absorption can matter during long-term orlistat use, especially when dietary intake is marginal or when other conditions already affect fat absorption.
- Recommendation: Use a multivitamin containing vitamins A, D, E, and K at least 2 hours before or after orlistat, following the product label and clinician advice.
- Evidence: [DailyMed — XENICAL (orlistat) prescribing information](https://dailymed.nlm.nih.gov/dailymed/lookup.cfm?setid=6240792b-9224-2d10-e053-2a91aa0a2c3e)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 22. `DEP_ANTICONVULSANTS_FOLATE`

- Medication / class: Phenytoin (`drug:8183`)
- Nutrient: Folate (`folate`)
- Relationship: `depletion`; severity `significant`; onset `months`
- Mechanism: Long-term phenytoin therapy can lower folate status. Several mechanisms have been proposed, but this record is limited to phenytoin rather than generalized to all antiseizure medicines.
- Clinical impact: Low folate can contribute to megaloblastic anemia. In people who could become pregnant, folate planning should be discussed with the prescribing clinician.
- Recommendation: Discuss folate intake and any supplement dose with the clinician managing phenytoin. Folate supplementation can affect phenytoin concentrations in some people, so self-directed high doses are not appropriate.
- Evidence: [Phenytoin-folic acid: a review. Drug Intell Clin Pharm. 1984.](https://pubmed.ncbi.nlm.nih.gov/6370643/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 23. `DEP_ANTICONVULSANTS_VITAMINB12`

- Medication / class: Phenytoin (`drug:8183`)
- Nutrient: Vitamin B12 (`vitamin_b12`)
- Relationship: `depletion`; severity `moderate`; onset `years`
- Mechanism: A systematic review and meta-analysis found lower serum vitamin B12 in people receiving phenytoin monotherapy. The mechanism is not established, so this record does not attribute the effect to other antiseizure medicines.
- Clinical impact: Low vitamin B12 can contribute to anemia or neurologic symptoms, but deficiency should be confirmed and evaluated clinically.
- Recommendation: Discuss whether vitamin B12 testing is appropriate with the clinician managing long-term phenytoin. Treatment should follow an identified deficiency or individualized clinical advice.
- Evidence: [Effects of phenytoin on serum levels of homocysteine, vitamin B12, folate in patients with epilepsy: a systematic review and meta-analysis. Medicine (Baltimore). 2019.](https://pubmed.ncbi.nlm.nih.gov/30896627/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 24. `DEP_ANTACIDS_CALCIUM`

- Medication / class: Proton pump inhibitors (PPIs) (`class:proton_pump_inhibitors`)
- Nutrient: Calcium (`calcium`)
- Relationship: `depletion`; severity `moderate`; onset `years`
- Mechanism: Stomach acid converts insoluble calcium carbonate into absorbable ionized calcium. PPIs strongly suppress acid, so calcium carbonate taken on an empty stomach is absorbed less well. Calcium citrate does not need acid, and taking carbonate with food restores absorption.
- Clinical impact: Long-term PPI use is linked in observational studies to a modestly higher fracture risk (hip, wrist, spine), behind a 2010 FDA safety communication. The association is modest and partly confounded, and is not seen with H2 blockers.
- Recommendation: If you take a PPI long-term, prefer calcium citrate (it does not need stomach acid to absorb) or take calcium carbonate with a meal. Aim for adequate calcium and vitamin D, and ask your doctor about bone health.
- Evidence: [Recker RR. Calcium absorption and achlorhydria. N Engl J Med. 1985](https://pubmed.ncbi.nlm.nih.gov/4000241/); [O'Connell MB et al. Effects of proton pump inhibitors on calcium carbonate absorption in women: a randomized crossover trial. Am J Med. 2005](https://pubmed.ncbi.nlm.nih.gov/15989913/); [Yang YX et al. Long-term proton pump inhibitor therapy and risk of hip fracture. JAMA. 2006](https://pubmed.ncbi.nlm.nih.gov/17190895/); [Poly TN et al. Proton pump inhibitors and risk of hip fracture: a meta-analysis of observational studies. Osteoporos Int. 2019](https://pubmed.ncbi.nlm.nih.gov/30539272/); [Serfaty-Lacrosniere C et al. Hypochlorhydria from short-term omeprazole treatment does not inhibit intestinal absorption of calcium, phosphorus, magnesium or zinc from food in humans. J Am Coll Nutr. 1995](https://pubmed.ncbi.nlm.nih.gov/8568113/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 25. `DEP_SSRIS_SODIUM`

- Medication / class: SSRIs (antidepressants) (`class:ssris`)
- Nutrient: Sodium (`sodium`)
- Relationship: `monitoring_stability`; severity `significant`; onset `weeks`
- Mechanism: SSRIs can cause Syndrome of Inappropriate Antidiuretic Hormone secretion (SIADH), leading to increased water retention and dilutional hyponatremia. Serotonin directly stimulates ADH release from the hypothalamus.
- Clinical impact: Hyponatremia causes nausea, headache, confusion, seizures, and in severe cases coma. Elderly patients and those on diuretics are at highest risk. Onset is often within the first few weeks of treatment.
- Recommendation: If you are elderly or on diuretics and starting an SSRI, sodium levels should be checked within 2–4 weeks. Report symptoms of confusion, nausea, or headache to your doctor promptly. This is a monitoring concern, not a supplementation target.
- Evidence: [De Picker L et al. Antidepressants and the risk of hyponatremia: a class-by-class review of literature. Psychosomatics. 2014;55(6):536-47](https://pubmed.ncbi.nlm.nih.gov/25262043/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 26. `DEP_STATINS_COQ10`

- Medication / class: Statins (cholesterol-lowering medications) (`class:statins`)
- Nutrient: Coenzyme Q10 (`coenzyme_q10`)
- Relationship: `depletion`; severity `mild`; onset `months`
- Mechanism: Statins inhibit HMG-CoA reductase, the same early step of the mevalonate pathway the body uses to make ubiquinone (CoQ10). Placebo-controlled trials, pooled in a meta-analysis, show statin therapy lowers CoQ10 concentrations measured in blood.
- Clinical impact: Whether that lower blood level causes the muscle symptoms some people report on statins is not established, and it does not by itself indicate a tissue deficiency. Trials of CoQ10 supplements for statin-related muscle symptoms disagree: some pooled analyses report improvement, others find no benefit over placebo.
- Recommendation: Statins can lower circulating CoQ10 levels. It is uncertain whether this contributes to muscle symptoms or whether CoQ10 supplements consistently help. Discuss persistent muscle symptoms with your prescriber, and do not stop a statin on your own.
- Evidence: [Banach M et al. Statin therapy and plasma coenzyme Q10 concentrations — a systematic review and meta-analysis of placebo-controlled trials. Pharmacol Res. 2015;99:329-36](https://pubmed.ncbi.nlm.nih.gov/26192349/); [Ghirlanda G et al. Evidence of plasma CoQ10-lowering effect by HMG-CoA reductase inhibitors: a double-blind, placebo-controlled study. J Clin Pharmacol. 1993;33(3):226-9](https://pubmed.ncbi.nlm.nih.gov/8463436/); [Qu H et al. Effects of coenzyme Q10 on statin-induced myopathy: an updated meta-analysis of randomized controlled trials. J Am Heart Assoc. 2018;7(19):e009835 — reports symptom improvement](https://pubmed.ncbi.nlm.nih.gov/30371340/); [Kennedy C et al. Effect of coenzyme Q10 on statin-associated myalgia and adherence to statin therapy: a systematic review and meta-analysis. Atherosclerosis. 2020;299:1-8 — finds no benefit](https://pubmed.ncbi.nlm.nih.gov/32179207/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 27. `DEP_SULFASALAZINE_FOLATE`

- Medication / class: Sulfasalazine (inflammatory bowel disease / arthritis medication) (`drug:9524`)
- Nutrient: Folate (`folate`)
- Relationship: `depletion`; severity `significant`; onset `months`
- Mechanism: Sulfasalazine can inhibit intestinal absorption and metabolism of folic acid. This can lower functional folate availability during long-term treatment, especially when baseline folate intake is marginal.
- Clinical impact: Lower folate status can contribute to mouth soreness, anemia, elevated homocysteine, and pregnancy-related neural tube risk. This matters most with long-term therapy or pregnancy planning.
- Recommendation: Folate support should be clinician-directed with sulfasalazine, especially before pregnancy or during long-term use. Confirm the form and dose with the prescriber.
- Evidence: [DailyMed — SULFASALAZINE prescribing information](https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=48fbc535-a33a-45ee-85ff-9d1ec9b31d9c)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 28. `DEP_CORTICOSTEROIDS_CALCIUM`

- Medication / class: Systemic corticosteroids (prednisone, prednisolone, dexamethasone) (`class:corticosteroids`)
- Nutrient: Calcium (`calcium`)
- Relationship: `depletion`; severity `significant`; onset `months`
- Mechanism: Systemic glucocorticoids reduce intestinal calcium absorption and increase urinary calcium loss, while also lowering bone formation and increasing bone resorption. The net effect is negative calcium balance and bone loss, so the concern is bone strength rather than a measurable drop in blood calcium.
- Clinical impact: Prolonged systemic glucocorticoid use — more than 3 months at about 2.5 mg/day prednisone-equivalent or more — raises the risk of osteoporosis and fracture. This applies to tablets and injections taken over months, not to short courses, inhalers, creams, or a single joint injection.
- Recommendation: With prolonged systemic corticosteroid use, clinicians may assess calcium and vitamin D intake, fracture risk, and whether bone-protective treatment is needed. Guideline care is directed by your individual fracture risk rather than an automatic supplement dose.
- Evidence: [Humphrey MB et al. 2022 American College of Rheumatology Guideline for the Prevention and Treatment of Glucocorticoid-Induced Osteoporosis. Arthritis Rheumatol. 2023;75(12):2088-2102](https://pubmed.ncbi.nlm.nih.gov/37845798/); [Ferrari P. Cortisol and the renal handling of electrolytes: role in glucocorticoid-induced hypertension and bone disease. Best Pract Res Clin Endocrinol Metab. 2003;17(4):575-89](https://pubmed.ncbi.nlm.nih.gov/14687590/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 29. `DEP_CORTICOSTEROIDS_VITAMIND`

- Medication / class: Systemic corticosteroids (prednisone, prednisolone, dexamethasone) (`class:corticosteroids`)
- Nutrient: Vitamin D (`vitamin_d`)
- Relationship: `monitoring_stability`; severity `moderate`; onset `months`
- Mechanism: Long-term systemic glucocorticoid therapy increases bone loss and fracture risk, and vitamin D status is assessed as part of that bone-health management. There is no reliable evidence that corticosteroids themselves directly lower vitamin D levels — studies reporting low vitamin D in steroid-treated patients are confounded by the underlying illness and reduced sun exposure.
- Clinical impact: Vitamin D matters here because of bone health during prolonged steroid therapy, not because the medication drains it.
- Recommendation: With prolonged systemic corticosteroid use, clinicians commonly assess vitamin D status and intake as part of bone-health management. Ask your clinician whether testing or supplementation is appropriate for you — there is no universal dose.
- Evidence: [Humphrey MB et al. 2022 American College of Rheumatology Guideline for the Prevention and Treatment of Glucocorticoid-Induced Osteoporosis. Arthritis Rheumatol. 2023;75(12):2088-2102](https://pubmed.ncbi.nlm.nih.gov/37845798/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 30. `DEP_DIURETICS_ZINC`

- Medication / class: Thiazide diuretics (e.g., hydrochlorothiazide) (`class:thiazide_diuretics`)
- Nutrient: Zinc (`zinc`)
- Relationship: `depletion`; severity `mild`; onset `months`
- Mechanism: Thiazide diuretics increase urinary zinc excretion; loop diuretics have a much smaller effect. Over long-term use this can modestly lower tissue zinc, although blood zinc usually remains in the normal range.
- Clinical impact: A clear zinc deficiency from thiazides has not been established — blood zinc typically stays normal — so this is a mild, long-term consideration. It is most relevant for people whose dietary zinc is already low.
- Recommendation: A true shortfall is unlikely. If you take a thiazide long-term and eat little zinc-rich food, a modest zinc intake (10-15 mg/day) or a multivitamin is reasonable. Zinc from meat, shellfish, and legumes covers most needs.
- Evidence: [Wester PO. Urinary zinc excretion during treatment with different diuretics. Acta Med Scand. 1980](https://pubmed.ncbi.nlm.nih.gov/7001863/); [Golik A et al. Hydrochlorothiazide-amiloride causes excessive urinary zinc excretion. Clin Pharmacol Ther. 1987](https://pubmed.ncbi.nlm.nih.gov/3595066/); [Wester PO. Tissue zinc at autopsy - relation to medication with diuretics. Acta Med Scand. 1980](https://pubmed.ncbi.nlm.nih.gov/7446206/); [Mountokalakis T et al. Zinc deficiency in mild hypertensive patients treated with diuretics. J Hypertens Suppl. 1984](https://pubmed.ncbi.nlm.nih.gov/6152785/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 31. `DEP_DIURETICS_FOLATE`

- Medication / class: Triamterene (in Dyazide, Maxzide) (`drug:10763`)
- Nutrient: Folate (`folate`)
- Relationship: `functional_antagonism`; severity `mild`; onset `months`
- Mechanism: Triamterene is a structural analog of folate and a weak inhibitor of dihydrofolate reductase, the enzyme that activates folate. At usual doses cells largely compensate, so the effect on folate status is modest.
- Clinical impact: For most folate-replete people at normal doses, meaningful folate depletion is uncommon. The concern is greater in pregnancy (a class of folate-blocking drugs is linked to higher birth-defect rates), in people already low in folate, in heavy alcohol use, or when combined with another folate antagonist such as methotrexate.
- Recommendation: Most people on triamterene do not need a folate supplement. If you are pregnant, planning pregnancy, have low folate, or take methotrexate, discuss folate with your doctor.
- Evidence: [Sidhom MB et al. Monitoring the effect of triamterene and hydrochlorothiazide on dihydrofolate reductase activity. J Pharm Biomed Anal. 1989](https://pubmed.ncbi.nlm.nih.gov/2490542/); [Schalhorn A et al. Antifolate effect of triamterene on human leucocytes and on a human lymphoma cell line. Eur J Clin Pharmacol. 1981](https://pubmed.ncbi.nlm.nih.gov/7286039/); [Hernandez-Diaz S et al. Folic acid antagonists during pregnancy and the risk of birth defects. N Engl J Med. 2000](https://pubmed.ncbi.nlm.nih.gov/11096168/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 32. `DEP_ANTICONVULSANTS_LCARNITINE`

- Medication / class: Valproate (valproic acid, divalproex / Depakote) (`class:valproate`)
- Nutrient: L-Carnitine (`l_carnitine`)
- Relationship: `depletion`; severity `significant`; onset `months`
- Mechanism: Long-term valproic acid treatment can reduce carnitine availability and impair fatty-acid oxidation. A pediatric study observed an altered fuel-use pattern that improved after carnitine supplementation.
- Clinical impact: Carnitine depletion is a recognized concern in long-term valproate care, particularly in children and people with clinical risk factors. Acute valproate toxicity is a separate urgent clinical situation and is not represented by this routine monitoring record.
- Recommendation: Discuss symptoms, risk factors, and whether carnitine testing or supplementation is appropriate with the clinician managing valproate. Do not self-dose based on this record.
- Evidence: [Carnitine-dependent changes of metabolic fuel consumption during long-term treatment with valproic acid. J Pediatr. 1994.](https://pubmed.ncbi.nlm.nih.gov/8040784/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

### 33. `DEP_ANTICOAGULANTS_VITAMINK`

- Medication / class: Warfarin (anticoagulant / blood thinner) (`class:anticoagulants`)
- Nutrient: Vitamin K (`vitamin_k`)
- Relationship: `functional_antagonism`; severity `significant`; onset `weeks`
- Mechanism: Warfarin inhibits vitamin K epoxide reductase (VKORC1), blocking the recycling of vitamin K from its epoxide form back to the active hydroquinone form. This functional depletion of active vitamin K prevents carboxylation of clotting factors II, VII, IX, and X, as well as proteins C and S. This is the intended pharmacological mechanism.
- Clinical impact: While the depletion of active vitamin K is the therapeutic goal of warfarin, it also depletes vitamin K-dependent proteins involved in bone metabolism (osteocalcin, matrix Gla protein), potentially contributing to vascular calcification and osteoporosis with long-term use.
- Recommendation: Do NOT supplement with additional vitamin K without medical guidance — it will reduce warfarin's anticoagulant effect. Instead, maintain a consistent daily vitamin K intake from diet (green leafy vegetables). Sudden changes in vitamin K intake (including starting/stopping supplements) destabilize INR control.
- Evidence: [Hirsh J et al. Oral anticoagulants: mechanism of action, clinical effectiveness, and optimal therapeutic range. Chest. 2001](https://pubmed.ncbi.nlm.nih.gov/11157640/)

Reviewer disposition: ☐ approve ☐ revise ☐ suppress

## Sign-off

- Reviewer name / credentials:
- Review date:
- Approved records:
- Records requiring revision:
- Notes:
