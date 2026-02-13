#!/usr/bin/env python3
"""Test orchestrator for bibtex.vim (vim-rr edition).

Builds a manifest of test inputs, runs Vim in batch mode to produce
output JSON, then compares structurally against reference JSON.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Import test definitions from the reference generators (avoids duplication)
# ---------------------------------------------------------------------------

sys.path.insert(0, str(Path(__file__).parent))

from gen_bib_reference import INLINE_TESTS  # noqa: E402
from gen_name_reference import sample_names  # noqa: E402


def build_manifest(tests_dir: Path) -> dict:
    """Build the manifest dict consumed by run_bibtex_tests.vim."""
    repo_dir = tests_dir.parent
    data_dir = tests_dir / "data"
    output_dir = tests_dir / "output"

    manifest: dict = {
        "bibtex_path": repo_dir.as_posix() + "/R/bibtex.vim",
        "output_dir": output_dir.as_posix(),
        "bib_file_tests": [],
        "inline_tests": [],
        "name_tests": [],
    }

    # Bib file tests
    for bib_path in sorted(data_dir.glob("*.bib")):
        manifest["bib_file_tests"].append({
            "bib_path": bib_path.as_posix(),
            "output_name": f"ref_{bib_path.stem}.json",
        })

    # Inline tests
    for name, spec in INLINE_TESTS.items():
        manifest["inline_tests"].append({
            "name": name,
            "input_strings": spec["input_strings"],
            "output_name": f"ref_{name}.json",
        })

    # Name tests
    for name_str, _expected, _errs in sample_names:
        manifest["name_tests"].append({"input": name_str})

    return manifest


# ---------------------------------------------------------------------------
# Deep comparison
# ---------------------------------------------------------------------------

def deep_compare(expected, actual, path: str = "$") -> list[str]:
    """Recursively compare two JSON-like structures.

    Returns a list of human-readable diff strings.  Empty list means equal.
    """
    diffs: list[str] = []

    if isinstance(expected, dict) and isinstance(actual, dict):
        all_keys = set(expected.keys()) | set(actual.keys())
        for key in sorted(all_keys):
            child_path = f"{path}.{key}"
            if key not in expected:
                diffs.append(f"{child_path}: unexpected key in output")
            elif key not in actual:
                diffs.append(f"{child_path}: missing key in output")
            else:
                diffs.extend(deep_compare(expected[key], actual[key], child_path))
    elif isinstance(expected, list) and isinstance(actual, list):
        if len(expected) != len(actual):
            diffs.append(
                f"{path}: list length mismatch: "
                f"expected {len(expected)}, got {len(actual)}"
            )
        for i, (e, a) in enumerate(zip(expected, actual)):
            diffs.extend(deep_compare(e, a, f"{path}[{i}]"))
        # Report extra elements
        if len(actual) > len(expected):
            for i in range(len(expected), len(actual)):
                diffs.append(f"{path}[{i}]: unexpected extra element: {actual[i]!r}")
        elif len(expected) > len(actual):
            for i in range(len(actual), len(expected)):
                diffs.append(f"{path}[{i}]: missing expected element: {expected[i]!r}")
    else:
        if expected != actual:
            diffs.append(
                f"{path}: expected {expected!r}, got {actual!r}"
            )

    return diffs


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    tests_dir = Path(__file__).resolve().parent
    repo_dir = tests_dir.parent
    output_dir = tests_dir / "output"
    ref_dir = tests_dir / "reference"
    manifest_path = tests_dir / "manifest.json"

    # Build and write manifest
    manifest = build_manifest(tests_dir)
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    # Find vim executable
    vim_exe = "vim"

    # Run Vim in batch mode
    vim_script = (tests_dir / "run_bibtex_tests.vim").as_posix()
    cmd = [vim_exe, "-es", "-N", "-u", "NONE", "-i", "NONE", "-S", vim_script]

    print(f"Running: {' '.join(cmd)}")
    try:
        result = subprocess.run(
            cmd,
            cwd=str(repo_dir),
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        print("FAIL: Vim timed out after 120 seconds")
        return 1
    except FileNotFoundError:
        print(f"FAIL: Could not find '{vim_exe}' executable")
        return 1

    if result.returncode != 0:
        print(f"FAIL: Vim exited with code {result.returncode}")
        if result.stdout:
            print(f"stdout: {result.stdout[:2000]}")
        if result.stderr:
            print(f"stderr: {result.stderr[:2000]}")
        return 1

    # Compare outputs
    passed = 0
    failed = 0
    errors: list[str] = []

    # Collect all expected reference files
    test_files: list[tuple[str, Path, Path]] = []

    # Bib file tests
    for bib_path in sorted((tests_dir / "data").glob("*.bib")):
        name = f"ref_{bib_path.stem}.json"
        test_files.append((name, ref_dir / name, output_dir / name))

    # Inline tests
    for test_name in INLINE_TESTS:
        name = f"ref_{test_name}.json"
        test_files.append((name, ref_dir / name, output_dir / name))

    # Name tests
    test_files.append(("ref_names.json", ref_dir / "ref_names.json",
                        output_dir / "ref_names.json"))

    for name, ref_path, out_path in test_files:
        if not ref_path.exists():
            errors.append(f"  {name}: SKIP (no reference file)")
            continue
        if not out_path.exists():
            errors.append(f"  {name}: FAIL (no output file)")
            failed += 1
            continue

        try:
            ref_data = json.loads(ref_path.read_text(encoding="utf-8"))
            out_data = json.loads(out_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            errors.append(f"  {name}: FAIL (JSON parse error: {e})")
            failed += 1
            continue

        diffs = deep_compare(ref_data, out_data)
        if diffs:
            failed += 1
            diff_str = "\n".join(f"    {d}" for d in diffs[:20])
            extra = f"\n    ... and {len(diffs) - 20} more" if len(diffs) > 20 else ""
            errors.append(f"  {name}: FAIL\n{diff_str}{extra}")
        else:
            passed += 1

    # Report
    total = passed + failed
    print(f"\nResults: {passed}/{total} passed")

    if errors:
        print("\nFailures:")
        for e in errors:
            print(e)

    # Clean up manifest
    try:
        manifest_path.unlink()
    except OSError:
        pass

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
