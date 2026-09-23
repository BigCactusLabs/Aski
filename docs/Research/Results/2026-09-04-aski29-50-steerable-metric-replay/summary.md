# ASKI-29/50 exact-lattice steerable metric replay

The frozen ASTSK-42 rule was applied independently to five lower-is-better pixel losses.
MAE is the house oracle. The other metrics can reduce confidence but cannot promote a result alone.

## Current-path results

| regime | metric | aggregate | spokes | diagonals | arcs | naturals | archived KILL |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| shipping-os2 | mae | -0.1783% | -3.1689% | -0.0415% | +0.1356% | -0.4315% | HELD |
| shipping-os2 | gmsd | -0.3805% | -3.1267% | -0.0561% | +0.1754% | -0.9622% | HELD |
| shipping-os2 | one_minus_haarpsi | -0.1116% | -0.3904% | -0.0074% | -0.2024% | -0.2342% | HELD |
| shipping-os2 | cssim_loss | -0.1709% | +0.1491% | -0.2875% | +0.2748% | +0.0530% | HELD |
| shipping-os2 | milo | -1.2606% | -30.9752% | +3.2490% | +23.5317% | -21.5779% | HELD |
| historical-support | mae | -0.0154% | -0.1517% | +0.0000% | +0.0065% | -0.0543% | HELD |
| historical-support | gmsd | -0.2524% | -0.2606% | +0.0000% | -0.0019% | -1.0685% | HELD |
| historical-support | one_minus_haarpsi | +0.0195% | -0.1102% | +0.0000% | -0.0003% | +0.0912% | HELD |
| historical-support | cssim_loss | -0.0044% | -0.4773% | +0.0000% | +0.0123% | -0.0318% | HELD |
| historical-support | milo | +3.0050% | -2.0511% | +0.0000% | +0.0468% | +7.6310% | HELD |

## Panel rule

- shipping-os2: **HELD**
- historical-support: **HELD**

## Historical record kept separate

The June ASTSK-42 run used the old truncating lattice and a five-column sweep. Its GMSD deltas were: spokes +0.32%, diagonals +0.0015%, arcs +0.0022%, naturals -0.92%, aggregate -0.19% (KILL). No stored June cell-pair artifacts, MAE rows, HaarPSI rows, CSSIM rows, or MILO rows survive. This replay does not fabricate them and does not overwrite that verdict.

## Shipping column parity

Cell-height parity changes when columns become: 5, 6, 8, 9, 10, 12, 13, 14, 15, 16.
Transitions at 16 columns or above: 16.
The complete 4...80 census in `parity.csv` records the exact footprint, admitted coordinates, reachable bin indices, and zero dropped pixels for every column count.
