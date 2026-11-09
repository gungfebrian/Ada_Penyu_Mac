#!/usr/bin/env python3
"""Generate matcher fixtures from the original I3S 4.02 C++ sources, offline.

The caller supplies an extracted official distribution. No Windows application
is launched. Only MessageBox is stubbed; the comparison sources are unchanged.
"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


HARNESS = r'''
#include <iostream>
#include <iomanip>
#include <vector>
#include "compare.hpp"
double maxAllowedDistance=0.01, minRelativeDistance=1.0, minRatioArea=0.5;
double maxAngleDiff=40.0, minRatioRatio=0.666, maxRatioToCalcAngle=0.666;
int I3S_type=2;
int main() {
    int un,kn;
    while(std::cin >> un >> kn >> maxAllowedDistance >> minRelativeDistance >> minRatioArea) {
        double ur[6],kr[6];
        for(double& v:ur) std::cin >> v;
        for(double& v:kr) std::cin >> v;
        std::vector<double> ud(un*8),kd(kn*8);
        for(double& v:ud) std::cin >> v;
        for(double& v:kd) std::cin >> v;
        FingerPrint u(ur,ud.data(),un),k(kr,kd.data(),kn);
        Pair pairs[100]; int count=0;
        Compare::compareTwo(u,k,pairs,&count);
        int featurePairs=0;
        for(int i=0;i<count;i++)
            if(pairs[i].getM1()>=3 && pairs[i].getM2()>=3) featurePairs++;
        std::cout << std::setprecision(17) << k.getScore() << " " << featurePairs << "\n";
    }
}
'''

WINDOWS_SHIM = '''#pragma once
#define MB_OK 0
#define MB_ICONWARNING 0
#define MB_APPLMODAL 0
#define MB_SETFOREGROUND 0
inline int MessageBox(void*, const char*, const char*, int) { return 0; }
'''


def controls(sample):
    values = []
    for x, y, diameter in sample["keypoints"]:
        radius = diameter / 2
        values.extend([x - radius, y, x + radius, y, x, y - radius, x, y + radius])
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path,
                        help="Extracted app/sourcecode directory containing Compare/")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--cxx", default="clang++")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    source = args.source_root.resolve() / "Compare"
    originals = [source / "src" / f"{name}.cpp" for name in ("compare", "fingerprint", "element", "affine")]
    consumed = originals + [source / "incl" / name for name in
                            ("compare.hpp", "fingerprint.hpp", "element.hpp", "point2D.hpp", "affine.h")]
    hashes = {str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest() for path in consumed}
    samples_path = repo / "Ada_Penyu_Desktop/SampleTurtles/i3s_samples.json"
    samples = json.loads(samples_path.read_text())
    rows, lines = [], []
    for query in samples:
        for candidate in samples:
            if query["side"] != candidate["side"]:
                continue
            if max(len(query["keypoints"]), len(candidate["keypoints"])) > 97:
                raise ValueError("The original C++ Pair array is limited to 100 entries including references")
            values = ([len(query["keypoints"]), len(candidate["keypoints"]), .01, 1, .5]
                      + query["ref1"] + query["ref2"] + query["ref3"]
                      + candidate["ref1"] + candidate["ref2"] + candidate["ref3"]
                      + controls(query) + controls(candidate))
            lines.append(" ".join(map(str, values)))
            rows.append({"query": query["id"], "candidate": candidate["id"]})
    with tempfile.TemporaryDirectory(prefix="i3s-reference-") as temporary:
        work = Path(temporary)
        (work / "windows.h").write_text(WINDOWS_SHIM)
        (work / "oracle.cpp").write_text(HARNESS)
        executable = work / "oracle"
        command = [args.cxx, "-std=c++11", "-O2", "-Wno-format", "-Wno-nontrivial-memcall",
                   "-include", "cstring", "-I", str(work), "-I", str(source / "incl"),
                   str(work / "oracle.cpp"), *map(str, originals), "-o", str(executable)]
        subprocess.run(command, check=True)
        result = subprocess.run([str(executable)], input="\n".join(lines) + "\n",
                                capture_output=True, text=True, check=True)
    outputs = result.stdout.splitlines()
    if len(outputs) != len(rows):
        raise RuntimeError("The C++ oracle did not answer every comparison")
    for row, output in zip(rows, outputs):
        score, pairs = output.split()
        row.update(score=float(score), pairs=int(pairs))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(rows, indent=2) + "\n")
    provenance = {
        "source_url": "https://reijns.com/wp-content/uploads/2020/01/I3SPv4.02-small_Setup.exe",
        "installer_sha256": "af30a24ffd040b874a12f8d965098e24cf35dcf37ce2422cb7ac4c363d21d49d",
        "source_sha256": hashes,
        "samples_sha256": hashlib.sha256(samples_path.read_bytes()).hexdigest(),
        "parameters": {"maxAllowedDistance": .01, "minRelativeDistance": 1, "minRatioArea": .5},
        "fixture_sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
        "oracle_scope": "Original source compiled for macOS; not execution of the shipped Windows DLL",
    }
    args.output.with_suffix(".provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"Wrote {len(rows)} reference comparisons to {args.output}")


if __name__ == "__main__":
    main()
