#!/usr/bin/env python3
"""
Generate PyPI-compatible index (PEP 503) for built wheels.
Scans wheels directory and creates HTML index for GitHub Pages.
"""

import argparse
import re
import sys
from html import escape
from pathlib import Path
from typing import Dict, Iterable, Mapping, Sequence, Tuple


def normalize_package_name(name: str) -> str:
    """
    Normalize package names according to PEP 503 by:
    - replacing runs of -, _, or . with a single dash
    - lowercasing the result
    """
    return re.sub(r"[-_.]+", "-", name).lower()


def parse_wheel_filename(filename: str) -> Dict[str, str]:
    """
    Parse wheel filename according to PEP 427.

    Example: flash_attn-2.5.0-cp312-cp312-linux_x86_64.whl
    Returns: {
        'name': 'flash-attn',
        'version': '2.5.0',
        'build': '1' | None,
        'python': 'cp312',
        'abi': 'cp312',
        'platform': 'linux_x86_64'
    }
    """
    pattern = (
        r"^(?P<name>.+?)-(?P<version>.+?)"
        r"(?:-(?P<build>\d[0-9A-Za-z\.]*))?"
        r"-(?P<python>.+?)-(?P<abi>.+?)-(?P<platform>.+?)\.whl$"
    )
    match = re.match(pattern, filename)

    if not match:
        raise ValueError(f"Invalid wheel filename: {filename}")

    parts = match.groupdict()
    normalized_name = normalize_package_name(parts["name"])

    return {
        "name": normalized_name,
        "version": parts["version"],
        "build": parts.get("build"),
        "python": parts["python"],
        "abi": parts["abi"],
        "platform": parts["platform"],
    }


def generate_package_index(
    package_name: str,
    wheels: Sequence[str],
    base_url: str,
) -> str:
    """
    Generate index.html for a specific package.

    Args:
        package_name: Normalized package name (e.g., 'flash-attn')
        wheels: Iterable of wheel filenames for this package
        base_url: Base URL for wheel downloads

    Returns:
        HTML content for package index
    """
    normalized_base = base_url.rstrip("/")

    html = [
        "<!DOCTYPE html>",
        "<html>",
        "<head>",
        f"  <title>Links for {package_name}</title>",
        "</head>",
        "<body>",
        f"  <h1>Links for {package_name}</h1>",
    ]

    for wheel in sorted(wheels):
        url = f"{normalized_base}/{wheel}"
        html.append(f'  <a href="{escape(url)}">{escape(wheel)}</a><br/>')

    html.extend(
        [
            "</body>",
            "</html>",
        ]
    )

    return "\n".join(html)


def generate_root_index(packages: Iterable[str]) -> str:
    """
    Generate root index.html listing all packages.

    Args:
        packages: Iterable of package names

    Returns:
        HTML content for root index
    """
    normalized_packages = sorted(
        {normalize_package_name(package) for package in packages}
    )

    html = [
        "<!DOCTYPE html>",
        "<html>",
        "<head>",
        "  <title>Simple Index</title>",
        "</head>",
        "<body>",
        "  <h1>Simple Index</h1>",
    ]

    for package in normalized_packages:
        html.append(f'  <a href="{package}/">{package}</a><br/>')

    html.extend(
        [
            "</body>",
            "</html>",
        ]
    )

    return "\n".join(html)


def generate_indexes(
    wheels_dir: Path,
    output_dir: Path,
    base_url: str,
) -> Mapping[str, Tuple[str, ...]]:
    """
    Generate PEP 503 indexes for wheels in a directory.

    Returns mapping with package names and wheel filenames for summary/testing.
    """
    if not wheels_dir.exists():
        raise FileNotFoundError(f"Wheels directory not found: {wheels_dir}")

    wheel_files = tuple(
        wheel
        for wheel in sorted(wheels_dir.glob("*.whl"))
        if wheel.is_file()
    )

    valid_wheels: Tuple[str, ...] = ()
    packages: Dict[str, Tuple[str, ...]] = {}

    for wheel_path in wheel_files:
        try:
            info = parse_wheel_filename(wheel_path.name)
            package_name = info["name"]
            current_wheels = packages.get(package_name, ())
            packages[package_name] = tuple(sorted(current_wheels + (wheel_path.name,)))
            valid_wheels = tuple(sorted(valid_wheels + (wheel_path.name,)))
        except ValueError as error:
            print(f"Warning: {error}", file=sys.stderr)
            continue

    output_dir.mkdir(parents=True, exist_ok=True)

    for package_name, wheels in packages.items():
        package_dir = output_dir / package_name
        package_dir.mkdir(parents=True, exist_ok=True)

        html = generate_package_index(package_name, wheels, base_url)
        (package_dir / "index.html").write_text(html, encoding="utf-8")

    root_html = generate_root_index(packages.keys())
    (output_dir / "index.html").write_text(root_html, encoding="utf-8")

    return {
        "packages": packages,
        "wheel_files": valid_wheels,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate PyPI-compatible index from wheels"
    )
    parser.add_argument(
        "--wheels-dir",
        type=Path,
        default=Path("wheels"),
        help="Directory containing wheel files",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("index/simple"),
        help="Output directory for index",
    )
    parser.add_argument(
        "--base-url",
        type=str,
        required=True,
        help="Base URL for wheel downloads (e.g., GitHub release URL)",
    )

    args = parser.parse_args()

    try:
        summary = generate_indexes(
            wheels_dir=args.wheels_dir,
            output_dir=args.output_dir,
            base_url=args.base_url,
        )
    except FileNotFoundError as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)

    if not summary["wheel_files"]:
        print(f"Warning: No wheel files found in {args.wheels_dir}")
        sys.exit(0)

    print(f"Generated index for {len(summary['packages'])} packages")
    print(f"Total wheels processed: {len(summary['wheel_files'])}")


if __name__ == "__main__":
    main()
