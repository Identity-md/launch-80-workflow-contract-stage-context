#!/usr/bin/env python3
"""Regenerate deliverable ABIs from local Foundry artifacts without network access."""
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
subprocess.run(["forge", "build", "--offline"], cwd=root, check=True)
destination = root / "docs" / "abi"
destination.mkdir(parents=True, exist_ok=True)
for name in ("Splitwise", "TipSplitter"):
    artifact = json.loads((root / "out" / f"{name}.sol" / f"{name}.json").read_text())
    (destination / f"{name}.json").write_text(json.dumps(artifact["abi"], indent=2) + "\n")
