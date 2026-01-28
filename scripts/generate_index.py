#!/usr/bin/env python3
"""
Generate PyPI-compatible index (PEP 503) for built wheels.
Scans wheels directory and creates HTML index for GitHub Pages.
"""

import argparse
import sys
from pathlib import Path
from typing import Dict, List
from collections import defaultdict
import re


def parse_wheel_filename(filename: str) -> Dict[str, str]:
    """
    Parse wheel filename according to PEP 427.

    Example: flash_attn-2.5.0-cp312-cp312-linux_x86_64.whl
    Returns: {
        'name': 'flash-attn',
        'version': '2.5.0',
        'python': 'cp312',
        'abi': 'cp312',
        'platform': 'linux_x86_64'
    }
    """
    pattern = r'^(.+?)-(.+?)-(.+?)-(.+?)-(.+?)\.whl$'
    match = re.match(pattern, filename)

    if not match:
        raise ValueError(f"Invalid wheel filename: {filename}")

    name, version, python, abi, platform = match.groups()

    # Normalize package name (replace _ with -)
    name = name.replace('_', '-')

    return {
        'name': name,
        'version': version,
        'python': python,
        'abi': abi,
        'platform': platform
    }


def generate_package_index(
    package_name: str,
    wheels: List[str],
    base_url: str
) -> str:
    """
    Generate index.html for a specific package.

    Args:
        package_name: Normalized package name (e.g., 'flash-attn')
        wheels: List of wheel filenames for this package
        base_url: Base URL for wheel downloads

    Returns:
        HTML content for package index
    """
    html = [
        '<!DOCTYPE html>',
        '<html>',
        '<head>',
        f'  <title>Links for {package_name}</title>',
        '</head>',
        '<body>',
        f'  <h1>Links for {package_name}</h1>',
    ]

    for wheel in sorted(wheels):
        url = f"{base_url}/{wheel}"
        html.append(f'  <a href="{url}">{wheel}</a><br/>')

    html.extend([
        '</body>',
        '</html>'
    ])

    return '\n'.join(html)


def generate_root_index(packages: List[str]) -> str:
    """
    Generate root index.html listing all packages.

    Args:
        packages: List of package names

    Returns:
        HTML content for root index
    """
    html = [
        '<!DOCTYPE html>',
        '<html>',
        '<head>',
        '  <title>Simple Index</title>',
        '</head>',
        '<body>',
        '  <h1>Simple Index</h1>',
    ]

    for package in sorted(packages):
        html.append(f'  <a href="{package}/">{package}</a><br/>')

    html.extend([
        '</body>',
        '</html>'
    ])

    return '\n'.join(html)


def main():
    parser = argparse.ArgumentParser(
        description='Generate PyPI-compatible index from wheels'
    )
    parser.add_argument(
        '--wheels-dir',
        type=Path,
        default=Path('wheels'),
        help='Directory containing wheel files'
    )
    parser.add_argument(
        '--output-dir',
        type=Path,
        default=Path('index/simple'),
        help='Output directory for index'
    )
    parser.add_argument(
        '--base-url',
        type=str,
        required=True,
        help='Base URL for wheel downloads (e.g., GitHub release URL)'
    )

    args = parser.parse_args()

    # Scan wheels directory
    wheels_dir = args.wheels_dir
    if not wheels_dir.exists():
        print(f"Error: Wheels directory not found: {wheels_dir}")
        sys.exit(1)

    wheel_files = list(wheels_dir.glob('*.whl'))
    if not wheel_files:
        print(f"Warning: No wheel files found in {wheels_dir}")
        sys.exit(0)

    print(f"Found {len(wheel_files)} wheel files")

    # Group wheels by package
    packages: Dict[str, List[str]] = defaultdict(list)

    for wheel_path in wheel_files:
        try:
            info = parse_wheel_filename(wheel_path.name)
            packages[info['name']].append(wheel_path.name)
            print(f"  - {info['name']}: {wheel_path.name}")
        except ValueError as e:
            print(f"Warning: {e}")
            continue

    # Create output directory
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    # Generate package indexes
    for package_name, wheels in packages.items():
        package_dir = output_dir / package_name
        package_dir.mkdir(exist_ok=True)

        html = generate_package_index(package_name, wheels, args.base_url)
        index_file = package_dir / 'index.html'
        index_file.write_text(html)
        print(f"Generated: {index_file}")

    # Generate root index
    root_html = generate_root_index(list(packages.keys()))
    root_index = output_dir / 'index.html'
    root_index.write_text(root_html)
    print(f"Generated: {root_index}")

    print(f"\nIndex generation complete!")
    print(f"Package count: {len(packages)}")
    print(f"Total wheels: {len(wheel_files)}")


if __name__ == '__main__':
    main()
