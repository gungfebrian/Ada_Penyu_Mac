# I3S Pattern 4.02 reference

The Swift matcher is checked against the C++ source bundled in the [official I3S distribution](https://reijns.com/i3s/download/). The local blob extractor remains an approximation of SURF. These are separate parts of the pipeline.

## Using the workspace

`Search in Database` uses the backend's MiewID/XFeat ranking. To inspect an I3S comparison, annotate the query photo or load its saved `.fgp`, open a candidate's visual comparison, and choose **Load Gallery .fgp…** for the displayed gallery photo. Both fingerprints must contain references, a closed ROI, and keypoints, and both photos must show the same side. In dual mode the comparison uses the corresponding query side.

I3S scores are distances, with lower values indicating a closer match. They are not confidence percentages and do not change the backend ranking. Editing the query or expert settings clears old I3S scores. Missing candidate photos stay unavailable; unrelated sample images and fingerprints are never substituted.

**Use Head Template** places fixed proportional coordinates. It does not locate anatomy. Check the landmarks and ROI against the actual photo. Newly extracted blob features are labeled approximate; load original fingerprints when checking compatibility with I3S.

## What was verified

REA 6.8.0 inspected the extracted desktop package, the installer's PE resources, and the native comparison DLL's exports. The DLL exports `_Java_FingerPrint_compareTwo@80`, consistent with the bundled JNI entry point. Static export inspection does not establish function-body equivalence between the DLL and the source, and the Windows application was not executed.

The source oracle compiles the original `compare.cpp`, `fingerprint.cpp`, `element.cpp`, and `affine.cpp`. A local shim replaces only the Windows error dialog and provides the standard C string include. Matching equations and search logic are unchanged. The test fixture contains all 97 same-side combinations, including self-comparisons, from the 13 bundled photographs. Swift scores match the oracle within `1e-6`, and feature-pair counts match exactly.

The repair restores perimeter-based score normalization, transformed control-point geometry, size penalties, reference-point participation, candidate-to-query nearest-neighbor matching, and exhaustive refinement over the initial accepted pairs. It also preserves the reference implementation's raw-distance subtraction when resolving duplicate pairs. The returned affine matrix composes the initial alignment with the refinement.

The separate encounter-ranking test excludes each query photo from its gallery. It checks the bundled individuals only. This is a regression check, not a held-out field evaluation or an unknown-rejection benchmark.

## Reproducing the fixture

Download `I3SPv4.02-small_Setup.exe` from the official download page and verify SHA-256:

```text
af30a24ffd040b874a12f8d965098e24cf35dcf37ce2422cb7ac4c363d21d49d
```

Extract the installer without launching it, then run:

```sh
innoextract --extract --output-dir /tmp/i3s-original /path/to/I3SPv4.02-small_Setup.exe
python3 scripts/i3s_reference_oracle.py \
  --source-root /tmp/i3s-original/app/sourcecode \
  --output /tmp/i3s-v402-reference.json
cmp Ada_Penyu_DesktopTests/Fixtures/i3s-v402-reference.json /tmp/i3s-v402-reference.json
```

The adjacent `.provenance.json` records hashes of all consumed original sources, the sample manifest, the generated fixture, and the parameter values. The generation script needs a local C++ compiler; it does not download dependencies or run the Windows DLL.

The original REA package and PE inspection records are included under `docs/evidence/i3s-rea/`. Their IDs and hashes are recorded in `docs/evidence/i3s-rea-2026-11-09.json`. REA ran through a version-pinned CLI with Node 24.22.2 in npm's cache; no agent registration was changed.

## Remaining extraction difference

The original uses OpenCV 2.4.2 upright SURF with four octaves and two octave layers, a Hessian threshold starting at 200 and reduced by `0.75` until enough filtered points are found or the threshold falls below 1, a 100-pixel ROI crop margin, and image warping that downsizes large ROIs. The Swift approximation does not reproduce that detector, interpolation, threshold schedule, or warp. Matcher compatibility on saved fingerprints does not establish extraction parity on new photos.

The adapted matching logic carries the original authors' GPL-2.0-or-later notice. The distribution's license is retained in [licenses/I3S-GPL-2.0.txt](licenses/I3S-GPL-2.0.txt).
