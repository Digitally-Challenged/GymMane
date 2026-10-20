#!/usr/bin/env python3
"""Trace the original two-pose sheets into GymMane's native path format.

Requires ImageMagick (`magick`) and Potrace. Sources were generated for this
project using existing GymMane artwork as a style reference; they are simplified
movement illustrations, not manufacturer drawings or exact equipment replicas.
"""

import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "docs/artwork/arsenal"
SPECIAL_SLUGS = {
    "leg-extension": "arsenal-reloaded-leg-extension",
    "pendulum-squat": "arsenal-reloaded-pendulum-squat",
}
TOKEN = re.compile(r"[A-Za-z]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?")
ARITY = {"M": 2, "L": 2, "C": 6, "H": 1, "V": 1, "Z": 0}


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def flatten(path, height, scale):
    """Bake Potrace's translate/scale into coordinates for Flutter's path parser."""
    tokens = TOKEN.findall(path)
    result = []
    command = None
    index = 0
    while index < len(tokens):
        if tokens[index].isalpha():
            command = tokens[index]
            if command.upper() not in ARITY:
                raise ValueError(f"Unsupported Potrace path command: {command}")
            result.append(command)
            index += 1
            if command.upper() == "Z":
                continue
        if command is None or command.upper() == "Z":
            raise ValueError("Missing path command")
        count = ARITY[command.upper()]
        values = [float(v) for v in tokens[index:index + count]]
        if len(values) != count:
            raise ValueError("Incomplete path coordinates")
        for offset, value in enumerate(values):
            y_axis = command.upper() == "V" or (command.upper() != "H" and offset % 2 == 1)
            if y_axis:
                value = (-value * 0.1 + (height if command.isupper() else 0)) * scale
            else:
                value *= 0.1 * scale
            result.append(f"{value:.3f}".rstrip("0").rstrip(".") if value else "0")
        index += count
        # Additional coordinate pairs after moveto are implicitly lineto.
        if command.upper() == "M":
            command = "L" if command.isupper() else "l"
    return " ".join(result)


def build(name, slug, work):
    source = SOURCE_DIR / f"{name}-source.png"
    width, height = map(int, run("magick", "identify", "-format", "%w %h", str(source)).split())
    if width != 2 * height:
        raise ValueError(f"{source}: expected two square panels")
    run("magick", str(source), "-crop", "2x1@", "+repage", "-colorspace", "gray",
        "-threshold", "60%", str(work / f"{name}-%d.pbm"))
    frames = []
    for index in range(2):
        svg = work / f"{name}-{index}.svg"
        run("potrace", str(work / f"{name}-{index}.pbm"), "-s", "-t", "8", "-O", "0.4", "-o", str(svg))
        tree = ET.parse(svg)
        group = tree.find("{*}g")
        expected = f"translate(0.000000,{height:.6f}) scale(0.100000,-0.100000)"
        if group is None or group.get("transform") != expected:
            raise ValueError("Unexpected Potrace coordinate transform")
        paths = [flatten(p.attrib["d"], height, 600 / height) for p in group.findall("{*}path")]
        if not paths:
            raise ValueError("Tracing produced no artwork")
        frames.append(" ".join(paths))
    target = ROOT / "assets/art" / f"{slug}.txt"
    target.write_text("\n".join(frames) + "\n")
    print(f"{target.relative_to(ROOT)}: {len(frames)} frames")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="gymmane-art-") as directory:
        for source in sorted(SOURCE_DIR.glob("*-source.png")):
            name = source.name.removesuffix("-source.png")
            build(name, SPECIAL_SLUGS.get(name, f"arsenal-{name}"), Path(directory))
