# Not Sure Review Flow — Open-Set Multi-Branch Experiment & Ideal UX Spec

**Date:** 2026-11-20  
**Target:** `Ada_Penyu_Desktop` (`NotSureWorkspaceView`, `NotSureReview`, `AppStore`)  
**Upstream Matcher:** Paired Open-Set **MiewID-msv3 + XFeat/LighterGlue** (`77.8%` acc, `65.5%` F1) and **Geometric Consensus 5% risk budget** (`82.9%` enrolled ID, `4.0%` false ID on unknown turtles, `87.7%` F1). Real gallery has **zero I3S `.fgp` files**.

---

## 1. End-to-End Mobile → Desktop Flow

1. **Mobile App (Field Ranger)**: Uploads Left &/or Right photo → Open-Set Matcher returns Top-K candidates.
   - **Sure** → Confirmed sighting (catalog & map).
   - **No** → New / non-matching individual.
   - **Not Sure** → Escalates sighting (with both sides if captured + Top-K candidates + real open-set scores) to Desktop **Not Sure** queue.
2. **Desktop App (Scientist / Senior Ranger)** — Structured by **Obvious · Easy · Possible**:
   - **Obvious (0 clicks, zero scroll):** Full-height clean photo comparison (`Sighting` left, `Candidate` right), slim right candidate rail (`268pt`) with 1-click reject & auto-advance, and 3 direct open-set verdicts (**Same turtle** / **New turtle** / **Needs photo**) mirroring mobile.
   - **Easy (1 click):** 3-mode stage capsule (`Compare` | `Contours #` | `Align`), inline `Left | Right` toggle for paired mobile uploads, `Blink / Overlay` blend, queue stepper (`‹ 1/N ›`), and 1-tap reason chips in the confirmation sheet.
   - **Possible (Single `⋯` FigCraft popup):** `Lines only` (cuts water glare), `Contour detail` slider, and `Crop head & Re-search` (crops wide ocean background and re-queries the live open-set matcher).

---

## 2. Multi-Branch Experiment Findings

Three isolated branches were implemented, compiled, and benchmarked on ADA Penyu's 13 real raw sea turtle photographs (zero `.fgp` files):

| Branch | Approach Tested | Empirical Result | Key Finding |
| :--- | :--- | :--- | :--- |
| `exp/notsure-v1-visual-compare` | Pure visual + Blink/Overlay + Paired L/R + 3-outcome bar | `0 ms` setup; 16/16 tests pass; cleanest UX & lowest text density | Solves obvious cases in `<10s`, but eyes lose track of homologous scales under `15°–30°` tilt or Rank-1 lookalikes. |
| `exp/notsure-v2-numbered-contours` | Zero-`.fgp` auto-numbered scale contours (`PatternContourEngine`) | **13/13 raw JPGs**: mean **`826 ms`** (`727–1000 ms`), **`14–23`** numbered scales (`mean 18.3`), `42.0` suture vertices | Works reliably with **zero `.fgp` files** and exposes tilt-invariant polygon side counts (`4s/5s/6s/7s`), though numbering is local per image. |
| `exp/notsure-v3-human-assisted` | 3-tap human anchor alignment + centroid consensus score + head-crop re-search | **Critical open-set discovery:** Zero-`.fgp` auto-pair scored impostors **higher** than genuine (`68.8%`, `5/6` false "Strong fit" vs `67.6%`, `2/7`); 3-anchor centroid residuals still gave `4/6` impostors false "Strong fit" (`2.76%` vs `2.21%`) | **Never display a client-side centroid "Strong fit" score!** Dense cheek scale mosaics overlap in 2D ROI space across different turtles, causing automation bias. Instead, use the 3 taps **strictly to warp Sighting contours onto Candidate's photo** (`Warped overlay` + `Blink`) so human vision verifies topology with ~100% precision, plus sanity guards for flipped/stretched anchors and `Crop & Re-search` for the real backend open-set matcher. |

---

## 3. Why I3S & Manual Full-Polygon Drawing Were Excluded

- **I3S (`.fgp`)**: Real dataset has no `.fgp` files; even on pre-annotated pairs, genuine distances (`3.28–15.55`) overlapped impostors (`11.16–22.35`); breaks above `30°` head yaw/pitch; costs `60–120s` per photo. Keep strictly outside the Not Sure queue.
- **Full Manual Polygon Drawing**: Too slow (`60–120s/photo`) and adds multi-row toolbars; replaced by zero-setup `Contours #` + 8-second 3-tap `Align` + optional `Crop head & Re-search`.

---

## 4. Winning Refined Architecture (`feat/notsure-ideal-flow`)

Synthesizes the best of all 3 branches into [NotSureWorkspaceView.swift](../../../Ada_Penyu_Desktop/Views/NotSureWorkspaceView.swift) + [NotSureReview.swift](../../../Ada_Penyu_Desktop/NotSureReview.swift) + [AppStore.swift](../../../Ada_Penyu_Desktop/AppStore.swift):
1. **Default `Compare`**: Clean side-by-side + synced zoom/pan + `Blink / Overlay` + inline `Left | Right` switcher.
2. **1-Click `Contours #`**: Off-main-thread zero-`.fgp` numbered scale polygons + tap-to-inspect polygon side count (`#4 · 5-sided`).
3. **1-Click `Align`**: Tap 3 matching numbered scales → instant 2D affine **Warped overlay** + `Blink` proof + reflection/stretch guard (zero misleading client-side match scores).
4. **Progressive Disclosure (`slider.horizontal.3` FigCraft popup)**: `Lines only`, `Contour detail`, `Crop head & Re-search` (`NotSureHeadCropper` → live `findNotSureCandidates(for:overridePhotoData:)`).
5. **Open-Set Verdict Bar**: `Needs photo` · `New turtle` · `Same turtle` with 1-tap reason chips and backward-compatible JSON persistence.
