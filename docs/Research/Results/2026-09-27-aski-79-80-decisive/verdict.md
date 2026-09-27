## P reproduction check (rule §2)

Baseline P rows compared: 43. Columns compared: cells, glyphs, mae, rmse, ssim, gmsd, haarpsi, glyphsUsed, blankShare, runMean, runP95, runMax, run5Share, shapeQueryPolarity, footprint, stride, oversample. Mismatches: 0.

## Arm 1 (A1) — rule §4.1

### Item 1 — defect removed (per fixture, A1 blankShare < 1.0)

| fixture | cols | minimal | dots | diagonal | cross | diamond |
|---|---|---|---|---|---|---|
| nasa-steerable-v1__earth-limb-sunrise | 80 | 0.9229 | 0.0000 | 0.9740 | 0.9785 | 0.9878 |
| nasa-steerable-v1__earth-limb-sunrise | 288 | 0.9345 | 0.0133 | 0.9807 | 0.9834 | 0.9903 |
| nasa-steerable-v1__sahara-dunes | 80 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| nasa-steerable-v1__sahara-dunes | 288 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| nasa-steerable-v1__vavilov-crater | 80 | 0.1108 | 0.0000 | 0.2309 | 0.2566 | 0.3483 |
| nasa-steerable-v1__vavilov-crater | 288 | 0.1417 | 0.0000 | 0.2420 | 0.2693 | 0.3566 |
| nasa-structure-v1__earth-limb-sunrise | 80 | 0.0000 | 0.0000 | 0.4976 | 0.5424 | 0.6191 |
| nasa-structure-v1__earth-limb-sunrise | 288 | 0.0000 | 0.0000 | 0.5038 | 0.5550 | 0.6181 |
| nasa-structure-v1__phoenix-night-grid | 80 | 0.0000 | 0.0000 | 0.1712 | 0.2094 | 0.3490 |
| nasa-structure-v1__phoenix-night-grid | 288 | 0.0000 | 0.0000 | 0.2501 | 0.3002 | 0.4481 |
| nasa-structure-v1__vavilov-crater | 80 | 0.1125 | 0.0000 | 0.2316 | 0.2562 | 0.3472 |
| nasa-structure-v1__vavilov-crater | 288 | 0.1419 | 0.0000 | 0.2425 | 0.2698 | 0.3564 |

Item 1: **PASS**

### Items 2, 3, 5 — `standard`

| corpus | cols | MAE P | MAE A1 | R | bar | item 2 | GMSD P | GMSD A1 | G | item 3 | run5 P | run5 A1 | item 5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| nasa-steerable-v1 | 80 | 0.240806 | 0.250995 | 1.0423 | ≤ 1.0000 | FAIL | 0.199776 | 0.284875 | 1.4260 | FAIL | 0.5779 | 0.5835 | pass |
| nasa-steerable-v1 | 288 | 0.240072 | 0.248333 | 1.0344 | ≤ 1.0000 | FAIL | 0.201817 | 0.274709 | 1.3612 | FAIL | 0.5975 | 0.5269 | pass |
| nasa-structure-v1 | 80 | 0.253468 | 0.261090 | 1.0301 | ≤ 1.0100 | FAIL | 0.242464 | 0.277818 | 1.1458 | FAIL | 0.5789 | 0.5527 | pass |
| nasa-structure-v1 | 288 | 0.250117 | 0.258571 | 1.0338 | ≤ 1.0100 | FAIL | 0.256589 | 0.298845 | 1.1647 | FAIL | 0.5541 | 0.5483 | pass |

Item 2: **FAIL**. Item 3: **FAIL**. Item 5: **PASS**.

### Item 4 — no harm elsewhere (R ≤ 1.0100; near-vacuous on the PNG corpora, about 0% orthogonal)

| corpus | charset | cols | MAE P | MAE A1 | R | G (reported) | changedVsP A1 | result |
|---|---|---|---|---|---|---|---|---|
| nasa-steerable-v1 | blocks | 80 | 0.564175 | 0.564175 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-steerable-v1 | blocks | 288 | 0.564106 | 0.564106 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-steerable-v1 | lines | 80 | 0.298205 | 0.298205 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-steerable-v1 | lines | 288 | 0.298176 | 0.298176 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-steerable-v1 | mixed | 80 | 0.287861 | 0.287861 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-steerable-v1 | mixed | 288 | 0.287796 | 0.287796 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-steerable-v1 | braille | 80 | 0.240840 | 0.240840 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-steerable-v1 | braille | 288 | 0.240135 | 0.240135 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-structure-v1 | blocks | 80 | 0.562470 | 0.562470 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-structure-v1 | blocks | 288 | 0.563345 | 0.563252 | 0.9998 | 1.0000 | 0.0002 | pass |
| nasa-structure-v1 | lines | 80 | 0.302778 | 0.302778 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-structure-v1 | lines | 288 | 0.302820 | 0.302795 | 0.9999 | 1.0000 | 0.0002 | pass |
| nasa-structure-v1 | mixed | 80 | 0.292989 | 0.292989 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-structure-v1 | mixed | 288 | 0.292934 | 0.292874 | 0.9998 | 1.0000 | 0.0002 | pass |
| nasa-structure-v1 | braille | 80 | 0.257193 | 0.257193 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-structure-v1 | braille | 288 | 0.255432 | 0.255433 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-steerable-v1 | blocks | 76 | 0.564061 | 0.564061 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-structure-v1 | blocks | 76 | 0.562023 | 0.562023 | 1.0000 | 1.0000 | 0.0000 | pass |
| nasa-occupancy-v1 | blocks | 76 | 0.600182 | 0.519197 | 0.8651 | 1.1667 | 0.1276 | pass |

Item 4: **PASS**

### Item 6 — sparse-set gain (structural; equals the arm-F ratio; not deciding)

| charset | MAE P | MAE A1 | R(A1/P) | R(F/P) | A1 == F (MAE) | result |
|---|---|---|---|---|---|---|
| minimal | 0.245248 | 0.241294 | 0.9839 | 0.9839 | True | FAIL |
| dots | 0.245248 | 0.255943 | 1.0436 | 1.0436 | True | FAIL |
| diagonal | 0.245248 | 0.245320 | 1.0003 | 1.0003 | True | FAIL |
| cross | 0.245248 | 0.242182 | 0.9875 | 0.9875 | True | FAIL |
| diamond | 0.245248 | 0.243387 | 0.9924 | 0.9924 | True | FAIL |

Item 6: **FAIL**

**Arm 1 verdict: KILL** — KILL clauses: R(standard) 1.0423 > 1.0300 on nasa-steerable-v1 at 80; R(standard) 1.0344 > 1.0300 on nasa-steerable-v1 at 288; R(standard) 1.0301 > 1.0300 on nasa-structure-v1 at 80; R(standard) 1.0338 > 1.0300 on nasa-structure-v1 at 288

## Arm 2 (A2, strength 1.0) — rule §4.2

| corpus | charset | run5 A1 | run5 A2 | fall | ≥ 0.10 | used A1 | used A2 | rises | R(A2/A1) | ≤ 1.0100 | G(A2/A1) | ≤ 1.0100 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| nasa-steerable-v1 | standard | 0.5269 | 0.1796 | 0.3473 | yes | 48 | 48 | no | 0.9896 | yes | 0.9245 | yes |
| nasa-steerable-v1 | braille | 0.5619 | 0.1797 | 0.3822 | yes | 13 | 13 | no | 1.0136 | no | 1.1428 | no |
| nasa-structure-v1 | standard | 0.5483 | 0.2761 | 0.2721 | yes | 77 | 77 | no | 0.9932 | yes | 0.9787 | yes |
| nasa-structure-v1 | braille | 0.5071 | 0.2342 | 0.2729 | yes | 20 | 21 | yes | 0.9934 | yes | 0.9783 | yes |

**Arm 2 verdict: INCONCLUSIVE** (KILL clause read on nasa-steerable-v1 at 288 for both conditions: fall < 0.10 on both charsets = False; R(A2/A1) > 1.0300 on either = False)

