# Wheel Builder Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a GitHub repository that automatically compiles Python wheels for CUDA packages across multiple Python/CUDA versions and distributes them via GitHub Pages.

**Architecture:** Docker-based builds in GitHub Actions matrix, wheels stored in GitHub Releases, PyPI-compatible index on GitHub Pages.

**Tech Stack:** GitHub Actions, Docker (nvidia/cuda images), Python, Bash, YAML

---

## Task 1: Repository Structure Setup

**Files:**
- Create: `.gitignore`
- Create: `config/.gitkeep`
- Create: `scripts/.gitkeep`
- Create: `index/.gitkeep`
- Create: `.github/workflows/.gitkeep`

**Step 1: Create .gitignore**

Create `.gitignore` to exclude build artifacts:

```gitignore
# Build artifacts
wheels/
*.whl
__pycache__/
*.pyc
*.pyo
*.egg-info/
dist/
build/

# OS files
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.swp
*.swo

# Temporary files
*.log
*.tmp
```

**Step 2: Create directory structure**

Run:
```bash
mkdir -p config scripts index .github/workflows
touch config/.gitkeep scripts/.gitkeep index/.gitkeep .github/workflows/.gitkeep
```

Expected: Directories created with placeholder files

**Step 3: Verify structure**

Run: `tree -L 2 -a`

Expected output:
```
.
├── .gitignore
├── .github
│   └── workflows
├── config
├── docs
├── index
└── scripts
```

**Step 4: Commit structure**

```bash
git add .gitignore config/ scripts/ index/ .github/
git commit -m "feat: initialize repository structure

- Add .gitignore for build artifacts
- Create config, scripts, index directories
- Set up .github/workflows directory

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Package Configuration File

**Files:**
- Create: `config/packages.yml`

**Step 1: Create packages.yml schema**

Create `config/packages.yml`:

```yaml
# Package definitions for wheel building
# Each package specifies versions, build configuration, and test imports

packages:
  flash-attn:
    versions:
      - "2.5.0"
      - "2.5.6"
    build_args: "--no-build-isolation"
    extra_deps:
      - "packaging"
      - "ninja"
      - "torch"
    test_import: "flash_attn"
    description: "Fast and memory-efficient exact attention"
```

**Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('config/packages.yml'))"`

Expected: No errors (silent success)

**Step 3: Commit configuration**

```bash
git add config/packages.yml
git commit -m "feat: add package configuration schema

- Define flash-attn with versions 2.5.0, 2.5.6
- Include build args and dependencies
- Add test import for validation

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Docker Build Script

**Files:**
- Create: `scripts/build_wheel.sh`

**Step 1: Create build script skeleton**

Create `scripts/build_wheel.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Build a Python wheel inside a CUDA Docker container
# Usage: ./build_wheel.sh <package> <version> <python> <cuda>
# Example: ./build_wheel.sh flash-attn 2.5.0 3.12 12.1.0

PACKAGE="$1"
VERSION="$2"
PYTHON_VERSION="$3"
CUDA_VERSION="$4"

# Validate arguments
if [ -z "$PACKAGE" ] || [ -z "$VERSION" ] || [ -z "$PYTHON_VERSION" ] || [ -z "$CUDA_VERSION" ]; then
    echo "Usage: $0 <package> <version> <python> <cuda>"
    echo "Example: $0 flash-attn 2.5.0 3.12 12.1.0"
    exit 1
fi

echo "Building $PACKAGE==$VERSION for Python $PYTHON_VERSION with CUDA $CUDA_VERSION"

# Configuration
DOCKER_IMAGE="nvidia/cuda:${CUDA_VERSION}-devel-ubuntu22.04"
WORK_DIR="/workspace"
OUTPUT_DIR="$(pwd)/wheels"
mkdir -p "$OUTPUT_DIR"

# Parse package config from packages.yml
CONFIG_FILE="$(pwd)/config/packages.yml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: config/packages.yml not found"
    exit 1
fi

echo "Docker image: $DOCKER_IMAGE"
echo "Output directory: $OUTPUT_DIR"
echo ""

# Build wheel in Docker container
docker run --rm \
    -v "$OUTPUT_DIR:$WORK_DIR/wheels" \
    -e PACKAGE="$PACKAGE" \
    -e VERSION="$VERSION" \
    -e PYTHON_VERSION="$PYTHON_VERSION" \
    "$DOCKER_IMAGE" \
    bash -c '
set -euo pipefail

echo "==> Installing Python $PYTHON_VERSION"
apt-get update -qq
apt-get install -y -qq software-properties-common
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update -qq
apt-get install -y -qq \
    python$PYTHON_VERSION \
    python$PYTHON_VERSION-dev \
    python$PYTHON_VERSION-venv \
    python3-pip \
    git \
    build-essential

# Create venv and upgrade pip
python$PYTHON_VERSION -m venv /venv
source /venv/bin/activate
pip install --upgrade pip wheel setuptools

echo ""
echo "==> Python version:"
python --version

echo ""
echo "==> Building $PACKAGE==$VERSION"

# Install build dependencies (will be read from config in next task)
pip install packaging ninja torch

# Build wheel
pip wheel "$PACKAGE==$VERSION" \
    --no-build-isolation \
    --wheel-dir=/workspace/wheels \
    --no-deps

echo ""
echo "==> Built wheels:"
ls -lh /workspace/wheels/
'

echo ""
echo "==> Build complete!"
echo "Wheels saved to: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"
```

**Step 2: Make script executable**

Run: `chmod +x scripts/build_wheel.sh`

Expected: Script has execute permissions

**Step 3: Verify script syntax**

Run: `bash -n scripts/build_wheel.sh`

Expected: No syntax errors (silent success)

**Step 4: Commit build script**

```bash
git add scripts/build_wheel.sh
git commit -m "feat: add Docker-based wheel build script

- Build wheels in CUDA Docker containers
- Install Python via deadsnakes PPA
- Support for custom build arguments
- Output wheels to ./wheels directory

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: PyPI Index Generator

**Files:**
- Create: `scripts/generate_index.py`

**Step 1: Create index generator**

Create `scripts/generate_index.py`:

```python
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
```

**Step 2: Make script executable**

Run: `chmod +x scripts/generate_index.py`

Expected: Script has execute permissions

**Step 3: Test with dummy wheel**

Run:
```bash
mkdir -p wheels
touch wheels/flash_attn-2.5.0-cp312-cp312-linux_x86_64.whl
python3 scripts/generate_index.py --base-url "https://example.com"
```

Expected: Creates `index/simple/index.html` and `index/simple/flash-attn/index.html`

**Step 4: Verify generated index**

Run: `cat index/simple/flash-attn/index.html`

Expected: Valid HTML with link to wheel

**Step 5: Clean up test files**

Run: `rm -rf wheels index/simple`

**Step 6: Commit index generator**

```bash
git add scripts/generate_index.py
git commit -m "feat: add PyPI index generator

- Parse wheel filenames (PEP 427)
- Generate PEP 503 compliant HTML index
- Support for GitHub Release URLs
- Create per-package and root indexes

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 5: GitHub Actions Workflow - Part 1 (Structure)

**Files:**
- Create: `.github/workflows/build-wheels.yml`

**Step 1: Create workflow file with triggers**

Create `.github/workflows/build-wheels.yml`:

```yaml
name: Build Wheels

on:
  workflow_dispatch:
    inputs:
      package:
        description: 'Specific package to build (optional, builds all if empty)'
        required: false
        type: string
      python_versions:
        description: 'Python versions (comma-separated)'
        required: false
        default: '3.12,3.13'
        type: string
      cuda_versions:
        description: 'CUDA versions (comma-separated)'
        required: false
        default: '12.1.0,13.0'
        type: string

  push:
    paths:
      - 'config/packages.yml'
    branches:
      - main

permissions:
  contents: write
  pages: write
  id-token: write

jobs:
  prepare:
    name: Prepare Build Matrix
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set-matrix.outputs.matrix }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install PyYAML
        run: pip install pyyaml

      - name: Generate build matrix
        id: set-matrix
        run: |
          python3 << 'EOF'
          import json
          import os
          import yaml

          # Read package config
          with open('config/packages.yml') as f:
              config = yaml.safe_load(f)

          packages = config.get('packages', {})

          # Filter by input if specified
          package_filter = '${{ inputs.package }}'
          if package_filter:
              packages = {k: v for k, v in packages.items() if k == package_filter}

          # Parse versions from inputs
          python_versions = '${{ inputs.python_versions }}'.split(',') if '${{ inputs.python_versions }}' else ['3.12', '3.13']
          cuda_versions = '${{ inputs.cuda_versions }}'.split(',') if '${{ inputs.cuda_versions }}' else ['12.1.0', '13.0']

          # Generate matrix
          matrix_entries = []
          for pkg_name, pkg_config in packages.items():
              for version in pkg_config.get('versions', []):
                  for python in python_versions:
                      for cuda in cuda_versions:
                          matrix_entries.append({
                              'package': pkg_name,
                              'version': version,
                              'python': python.strip(),
                              'cuda': cuda.strip(),
                              'build_args': pkg_config.get('build_args', ''),
                              'extra_deps': ' '.join(pkg_config.get('extra_deps', [])),
                              'test_import': pkg_config.get('test_import', pkg_name.replace('-', '_'))
                          })

          matrix = {'include': matrix_entries}

          # Write to GitHub output
          with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
              f.write(f"matrix={json.dumps(matrix)}\n")

          print(f"Generated matrix with {len(matrix_entries)} jobs")
          print(json.dumps(matrix, indent=2))
          EOF
```

**Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-wheels.yml'))"`

Expected: No errors

**Step 3: Commit workflow structure**

```bash
git add .github/workflows/build-wheels.yml
git commit -m "feat: add GitHub Actions workflow structure

- Add workflow triggers (manual + push)
- Implement matrix generation from packages.yml
- Support filtering by package/Python/CUDA version

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 6: GitHub Actions Workflow - Part 2 (Build Job)

**Files:**
- Modify: `.github/workflows/build-wheels.yml`

**Step 1: Add build job to workflow**

Append to `.github/workflows/build-wheels.yml` after the `prepare` job:

```yaml
  build:
    name: Build ${{ matrix.package }} (py${{ matrix.python }}, CUDA ${{ matrix.cuda }})
    runs-on: ubuntu-latest
    needs: prepare
    if: needs.prepare.outputs.matrix != '{"include":[]}'

    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.prepare.outputs.matrix) }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Pull CUDA Docker image
        uses: nick-invision/retry@v3
        with:
          timeout_minutes: 10
          max_attempts: 3
          command: docker pull nvidia/cuda:${{ matrix.cuda }}-devel-ubuntu22.04

      - name: Build wheel
        id: build
        run: |
          set -euo pipefail

          PACKAGE="${{ matrix.package }}"
          VERSION="${{ matrix.version }}"
          PYTHON="${{ matrix.python }}"
          CUDA="${{ matrix.cuda }}"
          BUILD_ARGS="${{ matrix.build_args }}"
          EXTRA_DEPS="${{ matrix.extra_deps }}"

          echo "Building $PACKAGE==$VERSION for Python $PYTHON with CUDA $CUDA"

          OUTPUT_DIR="$(pwd)/wheels"
          mkdir -p "$OUTPUT_DIR"

          # Build wheel in Docker
          docker run --rm \
            -v "$OUTPUT_DIR:/workspace/wheels" \
            -e PACKAGE="$PACKAGE" \
            -e VERSION="$VERSION" \
            -e PYTHON_VERSION="$PYTHON" \
            -e BUILD_ARGS="$BUILD_ARGS" \
            -e EXTRA_DEPS="$EXTRA_DEPS" \
            nvidia/cuda:${CUDA}-devel-ubuntu22.04 \
            bash -c '
          set -euo pipefail

          echo "==> Installing Python $PYTHON_VERSION"
          export DEBIAN_FRONTEND=noninteractive
          apt-get update -qq
          apt-get install -y -qq software-properties-common
          add-apt-repository -y ppa:deadsnakes/ppa
          apt-get update -qq
          apt-get install -y -qq \
              python${PYTHON_VERSION} \
              python${PYTHON_VERSION}-dev \
              python${PYTHON_VERSION}-venv \
              python3-pip \
              git \
              build-essential

          # Create venv
          python${PYTHON_VERSION} -m venv /venv
          source /venv/bin/activate
          pip install --quiet --upgrade pip wheel setuptools

          echo "==> Python version: $(python --version)"
          echo "==> CUDA version: $(nvcc --version | grep release)"

          # Install build dependencies
          if [ -n "$EXTRA_DEPS" ]; then
              echo "==> Installing build dependencies: $EXTRA_DEPS"
              pip install --quiet $EXTRA_DEPS
          fi

          echo "==> Building $PACKAGE==$VERSION"
          pip wheel "$PACKAGE==$VERSION" \
              $BUILD_ARGS \
              --wheel-dir=/workspace/wheels

          echo "==> Built wheels:"
          ls -lh /workspace/wheels/
          '

          # Find the built wheel
          WHEEL_FILE=$(ls wheels/*.whl | head -1)
          if [ -z "$WHEEL_FILE" ]; then
              echo "Error: No wheel file found"
              exit 1
          fi

          echo "wheel_file=$WHEEL_FILE" >> $GITHUB_OUTPUT
          echo "wheel_name=$(basename $WHEEL_FILE)" >> $GITHUB_OUTPUT

      - name: Test wheel import
        run: |
          WHEEL_FILE="${{ steps.build.outputs.wheel_file }}"
          TEST_IMPORT="${{ matrix.test_import }}"
          CUDA="${{ matrix.cuda }}"
          PYTHON="${{ matrix.python }}"

          echo "Testing import of $TEST_IMPORT"

          docker run --rm \
            -v "$(pwd)/wheels:/wheels" \
            nvidia/cuda:${CUDA}-runtime-ubuntu22.04 \
            bash -c "
          set -euo pipefail

          export DEBIAN_FRONTEND=noninteractive
          apt-get update -qq
          apt-get install -y -qq software-properties-common
          add-apt-repository -y ppa:deadsnakes/ppa
          apt-get update -qq
          apt-get install -y -qq python${PYTHON} python${PYTHON}-venv

          python${PYTHON} -m venv /venv
          source /venv/bin/activate
          pip install --quiet /wheels/*.whl

          echo '==> Testing import'
          python -c 'import ${TEST_IMPORT}; print(\"✓ Import successful\")'
          "

      - name: Upload wheel artifact
        uses: actions/upload-artifact@v4
        with:
          name: wheel-${{ matrix.package }}-${{ matrix.version }}-py${{ matrix.python }}-cuda${{ matrix.cuda }}
          path: wheels/*.whl
          if-no-files-found: error
          retention-days: 90
```

**Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-wheels.yml'))"`

Expected: No errors

**Step 3: Commit build job**

```bash
git add .github/workflows/build-wheels.yml
git commit -m "feat: add wheel build job to workflow

- Build wheels in CUDA Docker containers
- Install Python via deadsnakes PPA
- Test wheel imports after building
- Upload wheels as artifacts (90 days)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 7: GitHub Actions Workflow - Part 3 (Release & Index)

**Files:**
- Modify: `.github/workflows/build-wheels.yml`

**Step 1: Add release job**

Append to `.github/workflows/build-wheels.yml`:

```yaml
  release:
    name: Create Release and Update Index
    runs-on: ubuntu-latest
    needs: build
    if: github.ref == 'refs/heads/main'

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Download all wheel artifacts
        uses: actions/download-artifact@v4
        with:
          path: wheels-artifacts
          pattern: wheel-*
          merge-multiple: true

      - name: Organize wheels
        run: |
          mkdir -p wheels
          find wheels-artifacts -name '*.whl' -exec mv {} wheels/ \;
          ls -lh wheels/

      - name: Generate release tag
        id: tag
        run: |
          TAG="v$(date +%Y-%m-%d)"
          echo "tag=$TAG" >> $GITHUB_OUTPUT
          echo "Release tag: $TAG"

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          tag_name: ${{ steps.tag.outputs.tag }}
          name: Wheels ${{ steps.tag.outputs.tag }}
          body: |
            ## Built Wheels

            Wheels built on $(date +%Y-%m-%d) for:
            - Python versions: 3.12, 3.13
            - CUDA versions: 12.1.0, 13.0

            ### Installation

            ```bash
            pip install <package> --extra-index-url https://${{ github.repository_owner }}.github.io/${{ github.event.repository.name }}/simple/
            ```

            ### Available Packages

            See attached wheel files below.
          files: wheels/*.whl
          draft: false
          prerelease: false

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Generate PyPI index
        run: |
          BASE_URL="https://github.com/${{ github.repository }}/releases/download/${{ steps.tag.outputs.tag }}"
          python3 scripts/generate_index.py \
            --wheels-dir wheels \
            --output-dir index/simple \
            --base-url "$BASE_URL"

      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./index
          publish_branch: gh-pages
          force_orphan: true
```

**Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-wheels.yml'))"`

Expected: No errors

**Step 3: Commit release job**

```bash
git add .github/workflows/build-wheels.yml
git commit -m "feat: add release and index deployment

- Create GitHub Release with date-based tags
- Attach all built wheels to release
- Generate PyPI-compatible index
- Deploy index to GitHub Pages

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Main README Documentation

**Files:**
- Modify: `README.md`

**Step 1: Write comprehensive README**

Replace contents of `README.md`:

```markdown
# Python Wheels for CUDA Packages

Pre-built Python wheels for PyTorch ecosystem packages that require CUDA compilation.

## Quick Start

Install packages using pip with our custom index:

```bash
pip install flash-attn --extra-index-url https://YOUR_USERNAME.github.io/wheels/simple/
```

Replace `YOUR_USERNAME` with your GitHub username.

## Why Use This?

Building packages like `flash-attn` and `xformers` from source requires:
- CUDA toolkit installation
- Matching CUDA versions with PyTorch
- Significant compilation time (20-60 minutes)
- Proper build dependencies

Our pre-built wheels eliminate these requirements.

## Available Packages

| Package | Versions | Python | CUDA |
|---------|----------|--------|------|
| flash-attn | 2.5.0, 2.5.6 | 3.12, 3.13 | 12.1, 13.0 |

## Installation Examples

### Install latest version

```bash
pip install flash-attn --extra-index-url https://YOUR_USERNAME.github.io/wheels/simple/
```

### Install specific version

```bash
pip install flash-attn==2.5.0 --extra-index-url https://YOUR_USERNAME.github.io/wheels/simple/
```

### Use in requirements.txt

```txt
--extra-index-url https://YOUR_USERNAME.github.io/wheels/simple/
flash-attn==2.5.0
torch>=2.0.0
```

### Verify CUDA compatibility

Check your CUDA version:

```bash
python -c "import torch; print(f'CUDA: {torch.version.cuda}')"
```

Ensure your CUDA version matches the wheel you're installing (12.1 or 13.0).

## Contributing

### Request a New Package

Submit a PR adding your package to `config/packages.yml`:

```yaml
packages:
  your-package:
    versions:
      - "1.0.0"
    build_args: ""
    extra_deps:
      - "torch"
    test_import: "your_package"
    description: "Package description"
```

### Build Locally

Test building a wheel locally before submitting:

```bash
./scripts/build_wheel.sh flash-attn 2.5.0 3.12 12.1.0
```

Arguments: `<package> <version> <python-version> <cuda-version>`

## How It Works

1. **Configuration**: Packages defined in `config/packages.yml`
2. **Build**: GitHub Actions builds wheels in CUDA Docker containers
3. **Test**: Each wheel is tested via import validation
4. **Release**: Wheels attached to GitHub Releases (date-based tags)
5. **Index**: PyPI-compatible index deployed to GitHub Pages
6. **Install**: pip downloads wheels from GitHub Releases via custom index

## Architecture

- **Docker-based builds**: `nvidia/cuda:*-devel-ubuntu22.04` images
- **No GPU required**: Compilation only, no runtime GPU needed
- **Matrix builds**: All Python × CUDA combinations in parallel
- **PEP 503 index**: Standard PyPI simple repository format

## Troubleshooting

### Import fails after installation

Ensure CUDA runtime libraries are installed:

```bash
# Check CUDA availability
python -c "import torch; print(torch.cuda.is_available())"
```

### Wrong CUDA version

Reinstall with correct CUDA version:

```bash
pip uninstall flash-attn
pip install flash-attn --extra-index-url https://YOUR_USERNAME.github.io/wheels/simple/ --force-reinstall
```

### Build failures

Check [Actions tab](../../actions) for build logs. Common issues:
- Upstream package changes
- Missing build dependencies
- CUDA compatibility issues

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

Built with:
- [GitHub Actions](https://github.com/features/actions)
- [NVIDIA CUDA Docker images](https://hub.docker.com/r/nvidia/cuda)
- [deadsnakes PPA](https://launchpad.net/~deadsnakes/+archive/ubuntu/ppa)
```

**Step 2: Commit README**

```bash
git add README.md
git commit -m "docs: add comprehensive README

- Add quick start guide
- Document installation methods
- Include troubleshooting section
- Explain architecture and workflow

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 9: Detailed Usage Documentation

**Files:**
- Create: `docs/README.md`

**Step 1: Create detailed usage guide**

Create `docs/README.md`:

```markdown
# Detailed Usage Guide

## Table of Contents

1. [Installation Scenarios](#installation-scenarios)
2. [Verifying CUDA Version](#verifying-cuda-version)
3. [Contributing New Packages](#contributing-new-packages)
4. [Local Development](#local-development)
5. [CI/CD Integration](#cicd-integration)

## Installation Scenarios

### Scenario 1: Using in a New Project

```bash
# Create virtual environment
python3.12 -m venv venv
source venv/bin/activate

# Install with custom index
pip install \
  torch \
  flash-attn \
  --extra-index-url https://YOUR_USERNAME.github.io/wheels/simple/
```

### Scenario 2: Docker Container

```dockerfile
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y \
    python3.12 \
    python3-pip

RUN pip install \
    torch \
    flash-attn \
    --extra-index-url https://YOUR_USERNAME.github.io/wheels/simple/
```

### Scenario 3: Jupyter Notebook

```bash
# In notebook cell
!pip install flash-attn --extra-index-url https://YOUR_USERNAME.github.io/wheels/simple/
```

### Scenario 4: Poetry

Add to `pyproject.toml`:

```toml
[[tool.poetry.source]]
name = "cuda-wheels"
url = "https://YOUR_USERNAME.github.io/wheels/simple/"
priority = "supplemental"

[tool.poetry.dependencies]
python = "^3.12"
torch = "^2.0.0"
flash-attn = "^2.5.0"
```

### Scenario 5: pip-tools

In `requirements.in`:

```txt
--extra-index-url https://YOUR_USERNAME.github.io/wheels/simple/
torch>=2.0.0
flash-attn==2.5.0
```

Compile:

```bash
pip-compile requirements.in
pip-sync requirements.txt
```

## Verifying CUDA Version

### Check System CUDA

```bash
nvcc --version
nvidia-smi
```

### Check PyTorch CUDA

```python
import torch

print(f"PyTorch version: {torch.__version__}")
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"CUDA version: {torch.version.cuda}")
print(f"cuDNN version: {torch.backends.cudnn.version()}")
print(f"Device count: {torch.cuda.device_count()}")

if torch.cuda.is_available():
    print(f"Device name: {torch.cuda.get_device_name(0)}")
```

### Verify Package Installation

```python
import flash_attn

print(f"flash-attn version: {flash_attn.__version__}")

# Test basic functionality
import torch
x = torch.randn(1, 16, 512, 64).cuda()
print("✓ flash-attn imported successfully")
```

## Contributing New Packages

### Step 1: Research Package Requirements

Check package documentation for:
- Build dependencies
- Required CUDA versions
- Python version compatibility
- Build flags/arguments

### Step 2: Add to packages.yml

```yaml
packages:
  your-package:
    versions:
      - "1.0.0"
      - "1.1.0"
    build_args: "--no-build-isolation"
    extra_deps:
      - "torch>=2.0.0"
      - "packaging"
      - "ninja"
    test_import: "your_package"
    description: "Brief package description"
```

### Step 3: Test Locally

```bash
./scripts/build_wheel.sh your-package 1.0.0 3.12 12.1.0
```

Verify the wheel builds and installs:

```bash
pip install wheels/your_package-*.whl
python -c "import your_package"
```

### Step 4: Submit PR

1. Fork the repository
2. Create branch: `git checkout -b add-your-package`
3. Add to `config/packages.yml`
4. Test locally
5. Commit: `git commit -m "feat: add your-package"`
6. Push: `git push origin add-your-package`
7. Create Pull Request

## Local Development

### Building a Single Wheel

```bash
./scripts/build_wheel.sh <package> <version> <python> <cuda>

# Example
./scripts/build_wheel.sh flash-attn 2.5.0 3.12 12.1.0
```

### Generating Index Locally

```bash
# Build some wheels first
./scripts/build_wheel.sh flash-attn 2.5.0 3.12 12.1.0

# Generate index
python3 scripts/generate_index.py \
  --wheels-dir wheels \
  --output-dir index/simple \
  --base-url "https://github.com/USER/REPO/releases/download/v2026-01-27"

# View index
open index/simple/index.html  # macOS
xdg-open index/simple/index.html  # Linux
```

### Testing Workflow Changes

1. Make changes to `.github/workflows/build-wheels.yml`
2. Push to a branch
3. Manually trigger workflow from Actions tab
4. Monitor build progress
5. Download artifacts to test wheels

## CI/CD Integration

### GitHub Actions

```yaml
name: Test
on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        run: |
          pip install torch --index-url https://download.pytorch.org/whl/cu121
          pip install flash-attn --extra-index-url https://YOUR_USERNAME.github.io/wheels/simple/

      - name: Run tests
        run: pytest
```

### GitLab CI

```yaml
test:
  image: nvidia/cuda:12.1.0-runtime-ubuntu22.04
  script:
    - apt-get update && apt-get install -y python3.12 python3-pip
    - pip install torch flash-attn --extra-index-url https://YOUR_USERNAME.github.io/wheels/simple/
    - pytest
```

### Jenkins

```groovy
pipeline {
    agent {
        docker {
            image 'nvidia/cuda:12.1.0-runtime-ubuntu22.04'
        }
    }
    stages {
        stage('Install') {
            steps {
                sh 'apt-get update && apt-get install -y python3.12 python3-pip'
                sh 'pip install torch flash-attn --extra-index-url https://YOUR_USERNAME.github.io/wheels/simple/'
            }
        }
        stage('Test') {
            steps {
                sh 'pytest'
            }
        }
    }
}
```

## Advanced Topics

### Custom CUDA Versions

To add support for additional CUDA versions, update the workflow:

```yaml
# .github/workflows/build-wheels.yml
on:
  workflow_dispatch:
    inputs:
      cuda_versions:
        default: '11.8.0,12.1.0,12.4.0,13.0'
```

### Caching Build Dependencies

Add caching to speed up builds:

```yaml
- name: Cache pip packages
  uses: actions/cache@v3
  with:
    path: ~/.cache/pip
    key: ${{ runner.os }}-pip-${{ hashFiles('config/packages.yml') }}
```

### Notifications

Add Slack/Discord notifications on build failures:

```yaml
- name: Notify on failure
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
```
```

**Step 2: Commit detailed docs**

```bash
git add docs/README.md
git commit -m "docs: add detailed usage guide

- Add installation scenarios (Docker, Poetry, etc.)
- Document CUDA verification steps
- Explain contribution process
- Include CI/CD integration examples

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 10: License and Final Setup

**Files:**
- Create: `LICENSE`
- Create: `.github/PULL_REQUEST_TEMPLATE.md`

**Step 1: Add MIT License**

Create `LICENSE`:

```
MIT License

Copyright (c) 2026 [Your Name]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Step 2: Add PR template**

Create `.github/PULL_REQUEST_TEMPLATE.md`:

```markdown
## Description

Brief description of the changes in this PR.

## Type of Change

- [ ] New package addition
- [ ] Package version update
- [ ] Bug fix
- [ ] Documentation update
- [ ] Workflow improvement

## New Package Checklist

If adding a new package, confirm:

- [ ] Added to `config/packages.yml` with all required fields
- [ ] Tested locally: `./scripts/build_wheel.sh <package> <version> <python> <cuda>`
- [ ] Verified wheel installs: `pip install wheels/<package>-*.whl`
- [ ] Verified import works: `python -c "import <package>"`
- [ ] Package requires CUDA (not a pure Python package)
- [ ] Checked upstream PyPI for build requirements

## Package Configuration

```yaml
# Copy your packages.yml entry here
```

## Testing

Describe how you tested these changes:

```bash
# Commands run
./scripts/build_wheel.sh ...
```

## Additional Notes

Any additional context or screenshots.
```

**Step 3: Commit license and templates**

```bash
git add LICENSE .github/PULL_REQUEST_TEMPLATE.md
git commit -m "chore: add license and PR template

- Add MIT License
- Create PR template for contributions
- Include checklist for new packages

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 11: Final Verification and Push

**Files:**
- None (verification only)

**Step 1: Verify all files created**

Run:
```bash
tree -L 3 -a -I '.git'
```

Expected structure:
```
.
├── .github
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows
│       └── build-wheels.yml
├── .gitignore
├── LICENSE
├── README.md
├── config
│   └── packages.yml
├── docs
│   ├── README.md
│   └── plans
│       ├── 2026-01-27-wheel-builder-design.md
│       └── 2026-01-27-wheel-builder-implementation.md
├── index
└── scripts
    ├── build_wheel.sh
    └── generate_index.py
```

**Step 2: Verify scripts are executable**

Run:
```bash
ls -l scripts/
```

Expected: Both scripts have execute permissions (`-rwxr-xr-x`)

**Step 3: Run local validation**

Run:
```bash
# Validate YAML files
python3 -c "import yaml; yaml.safe_load(open('config/packages.yml'))"
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-wheels.yml'))"

# Check Python script syntax
python3 -m py_compile scripts/generate_index.py

# Check Bash script syntax
bash -n scripts/build_wheel.sh
```

Expected: All validation passes without errors

**Step 4: Review git status**

Run: `git status`

Expected: Working tree clean (all changes committed)

**Step 5: Review commit history**

Run: `git log --oneline`

Expected: ~11 commits following conventional commits format

**Step 6: Push to GitHub**

```bash
git remote add origin https://github.com/YOUR_USERNAME/wheels.git
git push -u origin main
```

---

## Post-Implementation Steps

After implementation is complete:

### 1. Enable GitHub Pages

1. Go to repository Settings → Pages
2. Source: Deploy from a branch
3. Branch: `gh-pages` / `root`
4. Save

### 2. Test Workflow

1. Go to Actions tab
2. Select "Build Wheels" workflow
3. Click "Run workflow"
4. Leave all inputs default
5. Monitor build progress

### 3. Verify Release

After workflow completes:
1. Check Releases tab
2. Verify wheels are attached
3. Check GitHub Pages: `https://YOUR_USERNAME.github.io/wheels/simple/`

### 4. Test Installation

```bash
python3.12 -m venv test-env
source test-env/bin/activate
pip install flash-attn --extra-index-url https://YOUR_USERNAME.github.io/wheels/simple/
python -c "import flash_attn; print(flash_attn.__version__)"
```

## Success Criteria

- ✅ All files created with correct structure
- ✅ Scripts are executable and validated
- ✅ YAML files are syntactically correct
- ✅ Git history is clean with conventional commits
- ✅ Workflow triggers on manual dispatch
- ✅ Wheels build for all matrix combinations
- ✅ PyPI index generated and deployed
- ✅ Packages installable via pip with custom index

---

**Implementation Notes:**

- Each task is independent and can be completed in sequence
- Tasks 1-4: Core infrastructure (scripts and config)
- Tasks 5-7: GitHub Actions workflow (can test incrementally)
- Tasks 8-9: Documentation
- Task 10-11: Final setup and validation
- Frequent commits ensure progress is saved
- All code includes error handling and validation
- Scripts follow immutability principles (no mutation of external state)
