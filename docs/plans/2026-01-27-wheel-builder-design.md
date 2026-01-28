# Python Wheel Builder for CUDA Packages - Design Document

**Date:** 2026-01-27
**Status:** Approved

## Overview

A public GitHub repository that automatically builds Python wheels for hard-to-compile packages (flash-attn, xformers, etc.) across multiple Python and CUDA versions. Wheels are distributed via a PyPI-compatible index hosted on GitHub Pages.

## Goals

1. Provide pre-built wheels for packages requiring CUDA compilation (flash-attn, xformers, etc.)
2. Support multiple Python versions (3.12, 3.13) and CUDA versions (12.1.0, 13.0)
3. Easy installation via pip with custom index URL
4. Extensible for adding new packages via config file
5. Reproducible builds using Docker

## Repository Structure

```
wheels/
├── .github/
│   └── workflows/
│       └── build-wheels.yml       # Main workflow with matrix strategy
├── config/
│   └── packages.yml                # Package definitions and build configs
├── scripts/
│   ├── build_wheel.sh              # Docker build wrapper script
│   └── generate_index.py           # PyPI index HTML generator
├── wheels/                         # Built wheels (gitignored locally)
├── index/                          # Generated PyPI index (for review)
├── docs/
│   ├── plans/                      # Design documents
│   └── README.md                   # Usage instructions
└── README.md                       # Main documentation
```

## Package Configuration

Packages are defined in `config/packages.yml`:

```yaml
packages:
  flash-attn:
    versions: ["2.5.0", "2.5.6"]
    build_args: "--no-build-isolation"
    extra_deps: ["packaging", "ninja"]
    test_import: "flash_attn"

  xformers:
    versions: ["0.0.23"]
    build_args: ""
    extra_deps: []
    test_import: "xformers"
```

**Fields:**
- `versions`: List of package versions to build
- `build_args`: Additional arguments passed to pip wheel
- `extra_deps`: Build dependencies to install before building
- `test_import`: Module name to import for smoke testing

## Build Strategy

### Triggers

The workflow supports both automated and manual builds:

```yaml
on:
  workflow_dispatch:
    inputs:
      package:
        description: 'Specific package to build (optional, builds all if empty)'
        required: false
      python_versions:
        description: 'Python versions (comma-separated)'
        default: '3.12,3.13'
      cuda_versions:
        description: 'CUDA versions (comma-separated)'
        default: '12.1.0,13.0'
  push:
    paths:
      - 'config/packages.yml'
    branches: [main]
```

**Usage:**
- Manual: Trigger via GitHub UI, optionally specify package to build
- Automatic: Builds all packages when `packages.yml` is updated on main branch

### Matrix Strategy

```yaml
strategy:
  fail-fast: false
  matrix:
    python: ["3.12", "3.13"]
    cuda: ["12.1.0", "13.0"]
    package: [determined from config file]
```

Each combination runs as a parallel job:
- flash-attn × Python 3.12 × CUDA 12.1.0
- flash-attn × Python 3.12 × CUDA 13.0
- flash-attn × Python 3.13 × CUDA 12.1.0
- flash-attn × Python 3.13 × CUDA 13.0
- (same for each package)

### Build Environment

**Docker-based builds:**
- Base image: `nvidia/cuda:{cuda-version}-devel-ubuntu22.04`
- Python installed via deadsnakes PPA
- No GPU required at build time (compilation only)
- Reproducible across environments

**Build process:**
1. Parse `packages.yml` to get package list
2. For each matrix combination:
   - Pull CUDA Docker image
   - Install Python version
   - Install build dependencies
   - Build wheel with `pip wheel`
   - Run smoke test (import package)
   - Upload wheel as artifact

## Distribution Strategy

### GitHub Releases

Wheels stored as GitHub Release assets:
- Tag format: `v2026-01-27` (date-based)
- Multiple packages per release
- No repository size limits
- Direct download URLs

### PyPI-Compatible Index

Hosted on GitHub Pages (`gh-pages` branch):

```
simple/
├── index.html                          # Root index listing all packages
├── flash-attn/
│   └── index.html                      # Links to all flash-attn wheels
└── xformers/
    └── index.html                      # Links to all xformers wheels
```

**Index generation:**
1. `generate_index.py` scans built wheels
2. Parses wheel filenames (PEP 427)
3. Generates PEP 503 compliant HTML
4. Links point to GitHub Release download URLs

**index.html format (PEP 503):**
```html
<!DOCTYPE html>
<html>
  <body>
    <h1>Links for flash-attn</h1>
    <a href="https://github.com/user/wheels/releases/download/v2026-01-27/flash_attn-2.5.0-cp312-cp312-linux_x86_64.whl">
      flash_attn-2.5.0-cp312-cp312-linux_x86_64.whl
    </a><br/>
    <a href="https://github.com/user/wheels/releases/download/v2026-01-27/flash_attn-2.5.0-cp313-cp313-linux_x86_64.whl">
      flash_attn-2.5.0-cp313-cp313-linux_x86_64.whl
    </a><br/>
  </body>
</html>
```

### User Installation

```bash
pip install flash-attn \
  --extra-index-url https://youruser.github.io/wheels/simple/
```

pip will:
1. Check PyPI for flash-attn (may fail or have wrong CUDA version)
2. Check custom index for compatible wheel
3. Download and install from GitHub Release

## Error Handling

### Build Failures

- `fail-fast: false` ensures other matrix jobs continue
- Failed builds logged in workflow summary
- Build logs uploaded as artifacts for debugging
- Release notes indicate which builds succeeded/failed

### Retry Logic

```yaml
- name: Pull Docker image
  uses: nick-invision/retry@v2
  with:
    timeout_minutes: 10
    max_attempts: 3
    command: docker pull nvidia/cuda:${{ matrix.cuda }}-devel-ubuntu22.04
```

### Validation

After each wheel build:
1. Install wheel in clean container
2. Import the package
3. For flash-attn: run minimal forward pass to verify CUDA linking
4. Mark wheel as validated in release notes

## Testing Strategy

### Smoke Tests (in workflow)

```python
# After building wheel
docker run --rm \
  -v $(pwd)/wheels:/wheels \
  nvidia/cuda:{cuda}-runtime-ubuntu22.04 \
  python3 -c "import flash_attn; print(flash_attn.__version__)"
```

### Local Testing

```bash
./scripts/build_wheel.sh flash-attn 2.5.0 3.12 12.1.0
```

Builds a single wheel for local validation before pushing config changes.

## Documentation

### README.md (Main)

```markdown
# Python Wheels for CUDA Packages

Pre-built wheels for PyTorch ecosystem packages requiring CUDA compilation.

## Quick Start

pip install flash-attn --extra-index-url https://youruser.github.io/wheels/simple/

## Available Packages

| Package | Versions | Python | CUDA |
|---------|----------|--------|------|
| flash-attn | 2.5.0, 2.5.6 | 3.12, 3.13 | 12.1, 13.0 |
| xformers | 0.0.23 | 3.12, 3.13 | 12.1, 13.0 |

## Requesting New Packages

Submit a PR adding your package to `config/packages.yml`.

## Building Locally

./scripts/build_wheel.sh <package> <version> <python> <cuda>

## License

MIT
```

### docs/README.md (Detailed Usage)

- Installation instructions for different scenarios
- Troubleshooting common issues
- How to verify CUDA version
- How to contribute new packages

## Implementation Plan (Next Steps)

1. Initialize repository and create basic structure
2. Implement `build_wheel.sh` script
3. Implement `generate_index.py` script
4. Create GitHub Actions workflow
5. Add initial `packages.yml` with flash-attn
6. Test workflow with manual trigger
7. Set up GitHub Pages
8. Document usage in README

## Success Criteria

- ✅ Wheels build successfully for all matrix combinations
- ✅ PyPI index is valid and pip can discover wheels
- ✅ Installation works: `pip install flash-attn --extra-index-url ...`
- ✅ Imported package works with CUDA
- ✅ New packages can be added via config PR
- ✅ Build process is reproducible locally

## Future Enhancements

- Support for more CUDA versions (11.8, 12.4, etc.)
- Windows and macOS wheels
- Automatic upstream version detection
- Issue-based wheel requests
- Wheel signing for security
- Build time optimization (caching)
