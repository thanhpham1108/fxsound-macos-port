"""Convert FxSound .fac factory files to portable numeric settings.

Usage: python macos/convert_presets.py "C:/Program Files/FxSound LLC/FxSound/Factsoft"
The .fac reader follows dsp/DfxDspPreset.cpp's effect and button indices.
"""
import json
import re
import sys
from pathlib import Path


def convert(path: Path) -> dict:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    name = lines[2].strip()
    main = {int(i): int(v) for v, i in re.findall(r"(?m)^\s*(-?\d+): Main (\d+)\s*$", "\n".join(lines))}
    flags = {int(i): int(v) for v, i in re.findall(r"(?m)^\s*(-?\d+): Integer\[(\d+)\]\s*$", "\n".join(lines))}
    centers = [float(v) for v in re.findall(r"(?m)^\s*([\d.]+): CF\s*$", "\n".join(lines))]
    gains = [float(v) for v in re.findall(r"(?m)^\s*(-?[\d.]+): Boost/Cut\s*$", "\n".join(lines))]
    eq_flag = re.search(r"(?m)^\s*([01]): On/Off Flag\s*$", "\n".join(lines))
    if len(centers) != 10 or len(gains) != 10 or not eq_flag:
        raise ValueError(f"expected ten EQ bands in {path}")
    effect_indices = {"fidelity": (0, 0), "surround": (1, 1), "ambience": (3, 2),
                      "dynamicBoost": (4, 3), "bass": (5, 4)}
    effects = {key: round(main[parameter] * 10 / 127, 6) if flags[button] else 0
               for key, (parameter, button) in effect_indices.items()}
    return {"name": name, "power": True, "eq": eq_flag.group(1) == "1",
            "gains": gains, "freqs": centers, **effects}


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    source = Path(sys.argv[1])
    order = ["Default", *[str(i) for i in range(1, 13)]]
    presets = [convert(source / f"{stem}.fac") for stem in order]
    output = Path(__file__).parent / "presets" / "factory.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(presets, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {len(presets)} presets to {output}")


if __name__ == "__main__":
    main()
