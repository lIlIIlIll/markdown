"""Identify and link the compiled inputs of the current domain package layout."""

import hashlib
import json
from pathlib import Path


def library_inputs(directory: Path) -> dict[str, str]:
    required = ("libmarkdown.a", "libmarkdown.core.a", "libmarkdown.engine.a",
        "markdown.cjo", "markdown.core.cjo", "markdown.engine.cjo")
    if any(not (directory / name).is_file() for name in required):
        raise ValueError("the built library must contain the current core and engine domain packages")
    paths = sorted((*directory.glob("libmarkdown*.a"), *directory.glob("markdown*.cjo")))
    return {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def library_digest(directory: Path) -> str:
    encoded = json.dumps(library_inputs(directory), sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def library_link_arguments(directory: Path) -> list[str]:
    inputs = library_inputs(directory)
    return ["-L", str(directory), *["-l" + name[3:-2] for name in inputs if name.endswith(".a")]]
