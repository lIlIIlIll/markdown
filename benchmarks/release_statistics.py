"""Pure derivation and validation for canonical benchmark raw samples."""

from __future__ import annotations

import hashlib
import math
from pathlib import Path
import statistics
from typing import Any


HARNESS_FILES = (
    "benchmarks/measure.py",
    "benchmarks/release_statistics.py",
    "benchmarks/generate_corpus.py",
    "benchmarks/benchmark_identity.py",
)


def median_seconds(values: list[dict[str, float | int | str]]) -> float:
    return statistics.median(float(value["seconds"]) for value in values)


def geometric_mean(values: list[float]) -> float:
    return math.exp(statistics.mean(math.log(value) for value in values))


def slope(points: list[tuple[int, float]]) -> float:
    xs = [math.log(float(size)) for size, _ in points]
    ys = [math.log(duration) for _, duration in points]
    xmean = statistics.mean(xs)
    ymean = statistics.mean(ys)
    return sum((x - xmean) * (y - ymean) for x, y in zip(xs, ys)) / sum(
        (x - xmean) ** 2 for x in xs
    )


def benchmark_harness_sha256(root: Path) -> str:
    digest = hashlib.sha256(b"markdown-benchmark-harness-v1\0")
    for relative in HARNESS_FILES:
        encoded = relative.encode("utf-8")
        content = (root / relative).read_bytes()
        digest.update(len(encoded).to_bytes(8, "big"))
        digest.update(encoded)
        digest.update(len(content).to_bytes(8, "big"))
        digest.update(content)
    return digest.hexdigest()


def _matrix(section: dict[str, Any]) -> dict[str, Any]:
    ratios: dict[str, float] = {}
    for name, corpus in section["corpora"].items():
        ratios[name] = median_seconds(corpus["markdown"]) / median_seconds(corpus["reference"])
    return {"medianRatios": ratios, "geometricMeanRatio": geometric_mean(list(ratios.values()))}


def _scaling(section: dict[str, Any]) -> dict[str, Any]:
    points = sorted(
        (int(size), median_seconds(values)) for size, values in section["samples"].items()
    )
    adjacent = [points[index + 1][1] / points[index][1] for index in range(len(points) - 1)]
    return {"slope": slope(points), "adjacentRatios": adjacent}


def recompute_benchmark_statistics(report: dict[str, Any]) -> dict[str, Any]:
    commonmark = _matrix(report["commonmark"])
    gfm = _matrix(report["gfm"])
    scaling = _scaling(report["scaling"])
    pathological = _scaling(report["pathologicalScaling"])
    baseline_rss = max(int(value["peakRssKiB"]) for value in report["memory"]["baseline"])
    ten_mib_rss = max(int(value["peakRssKiB"]) for value in report["memory"]["tenMiB"])
    extra_rss = ten_mib_rss - baseline_rss

    phases: dict[str, dict[str, float]] = {}
    for name, corpus in report["phaseProfiles"]["gfm"]["corpora"].items():
        parse_median = median_seconds(corpus["gfmParse"])
        html_median = median_seconds(corpus["gfmParseHtml"])
        phases[name] = {
            "medianParseSeconds": parse_median,
            "medianParseHtmlSeconds": html_median,
            "medianParseToParseHtmlRatio": parse_median / html_median,
            "inferredMedianRenderSeconds": html_median - parse_median,
        }

    optional = report["optionalFeatures"]
    source_map_overhead = (
        median_seconds(optional["sourceMap"]) / median_seconds(optional["commonmarkHtml"]) - 1.0
    )
    cst_overhead = median_seconds(optional["cst"]) / median_seconds(optional["commonmarkParse"]) - 1.0
    ordinary = max(
        commonmark["medianRatios"]["ordinary"], gfm["medianRatios"]["ordinary"]
    )
    gates = {
        "commonmarkRatioLe2_5": commonmark["geometricMeanRatio"] <= 2.5,
        "gfmRatioLe2_5": gfm["geometricMeanRatio"] <= 2.5,
        "ordinaryRepresentativeLe5": ordinary <= 5.0,
        "growthSlopeLe1_35": scaling["slope"] <= 1.35,
        "adjacentGrowthLe3": max(scaling["adjacentRatios"]) <= 3.0,
        "pathologicalSlopeLe1_35": pathological["slope"] <= 1.35,
        "tenMiBExtraRssLe8x": extra_rss <= 80 * 1024,
    }
    return {
        "commonmark": commonmark,
        "gfm": gfm,
        "phaseProfiles": {"gfm": phases},
        "optionalFeatures": {
            "sourceMapTimeOverhead": source_map_overhead,
            "cstTimeOverhead": cst_overhead,
        },
        "scaling": scaling,
        "pathologicalScaling": pathological,
        "memory": {"extraPeakRssKiB": extra_rss},
        "gates": gates,
    }


def validate_benchmark_derivations(report: dict[str, Any]) -> list[str]:
    derived = recompute_benchmark_statistics(report)
    errors: list[str] = []

    def compare(path: str, actual: object, expected: object) -> None:
        if isinstance(expected, float):
            if not isinstance(actual, (int, float)) or not math.isclose(
                    float(actual), expected, rel_tol=1.0e-12, abs_tol=1.0e-12):
                errors.append(f"benchmark derived value mismatch: {path}")
        elif isinstance(expected, list):
            if not isinstance(actual, list) or len(actual) != len(expected):
                errors.append(f"benchmark derived value mismatch: {path}")
                return
            for index, value in enumerate(expected):
                compare(f"{path}[{index}]", actual[index], value)
        elif isinstance(expected, dict):
            if not isinstance(actual, dict) or set(actual) != set(expected):
                errors.append(f"benchmark derived value mismatch: {path}")
                return
            for key, value in expected.items():
                compare(f"{path}.{key}", actual[key], value)
        elif actual != expected:
            errors.append(f"benchmark derived value mismatch: {path}")

    for section in ("commonmark", "gfm"):
        compare(f"{section}.geometricMeanRatio", report[section].get("geometricMeanRatio"),
            derived[section]["geometricMeanRatio"])
        for name, expected in derived[section]["medianRatios"].items():
            compare(f"{section}.corpora.{name}.medianRatio",
                report[section]["corpora"][name].get("medianRatio"), expected)
    for section in ("scaling", "pathologicalScaling"):
        compare(f"{section}.slope", report[section].get("slope"), derived[section]["slope"])
        compare(f"{section}.adjacentRatios", report[section].get("adjacentRatios"),
            derived[section]["adjacentRatios"])
    for name, expected in derived["phaseProfiles"]["gfm"].items():
        for key, value in expected.items():
            compare(f"phaseProfiles.gfm.corpora.{name}.{key}",
                report["phaseProfiles"]["gfm"]["corpora"][name].get(key), value)
    for key, expected in derived["optionalFeatures"].items():
        compare(f"optionalFeatures.{key}", report["optionalFeatures"].get(key), expected)
    compare("memory.extraPeakRssKiB", report["memory"].get("extraPeakRssKiB"),
        derived["memory"]["extraPeakRssKiB"])
    compare("gates", report.get("gates"), derived["gates"])
    return errors
