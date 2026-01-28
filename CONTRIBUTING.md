# Contributing to python-wheels

Thank you for contributing! This guide will help you get started with development, testing, and adding new packages.

## Table of Contents

- [Development Setup](#development-setup)
- [Adding a New Package](#adding-a-new-package)
- [Testing Locally](#testing-locally)
- [Workflow Development](#workflow-development)
- [Code Style](#code-style)
- [Submitting Changes](#submitting-changes)
- [Troubleshooting](#troubleshooting)

## Development Setup

### Prerequisites

1. **Docker or Podman**: Required for building wheels locally
   ```bash
   # Install Docker (Ubuntu/Debian)
   sudo apt-get install docker.io

   # Install Podman (Fedora/RHEL)
   sudo dnf install podman
   ```

2. **Python 3.12+**: For running tests and scripts
   ```bash
   # Check Python version
   python3 --version

   # Install if needed
   sudo apt-get install python3.12 python3.12-venv
   ```

3. **PyYAML**: For config parsing
   ```bash
   pip install pyyaml
   ```

4. **GitHub CLI** (optional): For triggering workflows
   ```bash
   # Install gh CLI
   sudo apt-get install gh

   # Authenticate
   gh auth login
   ```

### Clone Repository

```bash
git clone https://github.com/DEVtheOPS/python-wheels.git
cd python-wheels
```

### Directory Structure

```
python-wheels/
├── .github/workflows/
│   └── build-wheels.yml       # Main CI/CD workflow
├── config/
│   └── packages.yml            # Package configuration
├── scripts/
│   ├── build_in_docker.sh      # Runs inside Docker to build wheel
│   ├── build_wheel.sh          # Legacy build script (deprecated)
│   ├── generate_index.py       # Generates PEP 503 index
│   └── test_build_local.sh     # Local build + test script
├── tests/
│   └── test_generate_index.py  # Unit tests for index generation
├── AGENTS.md                   # Technical documentation for AI
├── CONTRIBUTING.md             # This file
└── README.md                   # User-facing documentation
```

## Adding a New Package

### Step 1: Edit Configuration

Edit `config/packages.yml` to add your package:

```yaml
packages:
  # Existing packages...

  your-package-name:
    versions: ["1.2.3", "1.2.4"]        # List of versions to build
    build_args: "--no-build-isolation"   # Optional pip wheel arguments
    extra_deps:                          # Build-time dependencies
      - torch
      - ninja
      - packaging
      - numpy
    test_import: "your_package"          # Module name for import test
    description: "Your CUDA Package"     # Human-readable description
```

#### Configuration Fields

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `versions` | ✅ Yes | List of package versions to build | `["2.8.3"]` |
| `build_args` | ❌ No | Arguments passed to `pip wheel` | `"--no-build-isolation"` |
| `extra_deps` | ❌ No | Build dependencies installed before building | `["torch", "ninja"]` |
| `test_import` | ❌ No | Python module name to test import (defaults to package name with `-` → `_`) | `"flash_attn"` |
| `description` | ❌ No | Human-readable package description | `"Flash Attention 2"` |

#### Common Build Dependencies

- **torch**: Required for most CUDA packages (links against PyTorch)
- **ninja**: Build system for faster compilation
- **packaging**: Python packaging utilities
- **numpy**: Numerical computing library
- **psutil**: System utilities (used by some packages)

### Step 2: Test Locally

Before pushing, test the build locally:

```bash
# Test with Docker (default)
./scripts/test_build_local.sh docker your-package-name 1.2.3 3.12 12.9.1

# Test with Podman
./scripts/test_build_local.sh podman your-package-name 1.2.3 3.12 13.0.2
```

This will:
1. Pull CUDA Docker image
2. Build the wheel
3. Test import in clean container
4. Output wheel to `./wheels/`

### Step 3: Commit and Push

```bash
git add config/packages.yml
git commit -m "feat: add your-package-name 1.2.3"
git push
```

This automatically triggers a workflow build for all configured versions.

### Step 4: Monitor Build

1. Go to [Actions tab](https://github.com/DEVtheOPS/python-wheels/actions)
2. Watch the "Build Wheels" workflow
3. Check for any failures

### Step 5: Verify Release

Once the build completes:
1. Check [Releases](https://github.com/DEVtheOPS/python-wheels/releases) for new release
2. Verify wheel files are attached
3. Check [GitHub Pages](https://DEVtheOPS.github.io/python-wheels/simple/) index

## Testing Locally

### Build a Wheel

```bash
# Syntax: ./scripts/test_build_local.sh [runtime] [package] [version] [python] [cuda]

# Example: Build flash-attn with Python 3.12 and CUDA 12.9.1
./scripts/test_build_local.sh docker flash-attn 2.8.3 3.12 12.9.1

# Example: Build with Podman and CUDA 13.0.2
./scripts/test_build_local.sh podman flash-attn 2.8.3 3.13 13.0.2

# Use defaults (flash-attn 2.8.3, Python 3.12, CUDA 12.9.1)
./scripts/test_build_local.sh
```

Output appears in `./wheels/` directory.

### Run Unit Tests

```bash
# Run all tests
python -m unittest discover -s tests -p "test_*.py"

# Run specific test file
python -m unittest tests.test_generate_index

# Run specific test case
python -m unittest tests.test_generate_index.ParseWheelFilenameTests

# Run specific test method
python -m unittest tests.test_generate_index.ParseWheelFilenameTests.test_normalizes_name_and_handles_build_tag
```

### Test Index Generation

```bash
# Generate index from wheels directory
python scripts/generate_index.py \
  --wheels-dir wheels \
  --output-dir index/simple \
  --base-url "https://github.com/USER/REPO/releases/download/v2026-01-28"

# View generated structure
tree index/simple/

# Check specific package index
cat index/simple/flash-attn/index.html
```

### Test Installation from Local Index

```bash
# Start local HTTP server
cd index
python -m http.server 8000

# In another terminal, install from local index
pip install flash-attn --extra-index-url http://localhost:8000/simple/
```

## Workflow Development

### Workflow Inputs

The workflow accepts these inputs:

```yaml
inputs:
  package:           # Optional: specific package to build
  python_versions:   # Optional: comma-separated (default: "3.12,3.13")
  cuda_versions:     # Optional: comma-separated (default: "12.9.1,13.0.2")
```

### Trigger Workflow Manually

```bash
# Build all packages
gh workflow run build-wheels.yml

# Build specific package
gh workflow run build-wheels.yml -f package=flash-attn

# Build specific Python version
gh workflow run build-wheels.yml -f python_versions=3.12

# Build specific CUDA version
gh workflow run build-wheels.yml -f cuda_versions=13.0.2

# Combine filters
gh workflow run build-wheels.yml \
  -f package=flash-attn \
  -f python_versions=3.12 \
  -f cuda_versions=13.0.2
```

### Workflow Architecture

1. **Prepare Job**: Parses `config/packages.yml` and generates build matrix
2. **Build Jobs**: Run in parallel (max 2 at a time) for each combination
3. **Release Job**: Collects all wheels and creates GitHub release
4. **Deploy Job**: Generates index and deploys to GitHub Pages

### Resource Limits

To prevent runner timeouts:
- `max-parallel: 2` - Only 2 builds run concurrently
- `MAX_JOBS=2` - Limits ninja to 2 compilation processes
- `timeout-minutes: 120` - 2-hour timeout per job

### Modifying Workflow

When editing `.github/workflows/build-wheels.yml`:

1. **Test locally first** using `act` or similar tool
2. **Commit with descriptive message** following conventional commits
3. **Monitor first run** closely for errors
4. **Check runner resources** (CPU, memory, disk)

## Code Style

### Shell Scripts

- Use `set -euo pipefail` for safety
- Quote all variables: `"$VAR"`
- Use descriptive variable names in UPPER_CASE
- Add comments for complex logic
- Prefer `[[` over `[` for conditionals

Example:
```bash
#!/bin/bash
set -euo pipefail

PACKAGE="$1"
VERSION="${2:-1.0.0}"  # Default to 1.0.0

if [[ -z "$PACKAGE" ]]; then
    echo "Error: Package name required" >&2
    exit 1
fi

echo "Building $PACKAGE version $VERSION"
```

### Python Scripts

- Follow PEP 8
- Use type hints where possible
- Add docstrings for functions
- Use `argparse` for CLI arguments

Example:
```python
#!/usr/bin/env python3
"""Generate PEP 503 compliant PyPI index."""

import argparse
from pathlib import Path
from typing import List


def generate_index(wheels_dir: Path, output_dir: Path, base_url: str) -> None:
    """Generate PyPI index HTML files.

    Args:
        wheels_dir: Directory containing wheel files
        output_dir: Directory to write index HTML
        base_url: Base URL for wheel downloads
    """
    # Implementation...
```

### YAML Configuration

- Use 2-space indentation
- Add comments for complex settings
- Keep alphabetically sorted when possible

Example:
```yaml
packages:
  flash-attn:
    versions: ["2.8.3"]
    build_args: "--no-build-isolation"
    extra_deps:
      - ninja
      - numpy
      - packaging
      - psutil
      - torch
    test_import: "flash_attn"
    description: "Flash Attention 2 - Fast and memory-efficient attention"
```

## Submitting Changes

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Test changes
- `chore`: Build/tooling changes
- `ci`: CI/CD changes

Examples:
```
feat(packages): add xformers 0.0.23

fix(build): increase MAX_JOBS to prevent timeout

docs(readme): add CUDA 13.0 installation instructions

ci(workflow): limit max-parallel to 2 builds
```

### Pull Request Process

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feat/add-xformers`
3. **Make your changes** with clear commits
4. **Test locally** before pushing
5. **Push to your fork**: `git push origin feat/add-xformers`
6. **Open Pull Request** with description of changes
7. **Wait for CI** to pass
8. **Address review feedback** if any

### PR Description Template

```markdown
## Description
Brief description of changes

## Changes
- Added package X version Y.Z
- Fixed build timeout issue
- Updated documentation

## Testing
- [ ] Tested locally with Docker
- [ ] Unit tests pass
- [ ] CI workflow completes successfully

## Related Issues
Closes #123
```

## Troubleshooting

### Local Build Issues

#### Docker pull fails
```bash
# Check Docker service
sudo systemctl status docker

# Start Docker if stopped
sudo systemctl start docker

# Add user to docker group (requires logout/login)
sudo usermod -aG docker $USER
```

#### Build times out locally
```bash
# Reduce MAX_JOBS
MAX_JOBS=1 ./scripts/test_build_local.sh docker flash-attn 2.8.3 3.12 12.9.1
```

#### Import test fails
- Ensure CUDA version matches between build and test
- Check that PyTorch is installed in test container
- Verify `test_import` matches actual module name

### CI/CD Issues

#### Workflow doesn't trigger
- Ensure `config/packages.yml` is on `main` branch
- Check workflow file syntax
- Verify GitHub Actions is enabled

#### Build fails with disk space error
- Workflow includes cleanup steps
- Consider building fewer versions at once
- Use workflow `package` input to build one at a time

#### Runner lost communication
- flash-attn is very CPU intensive
- Current limit is `max-parallel: 2`
- Can reduce to `max-parallel: 1` if needed

### Getting Help

- **Check AGENTS.md** for detailed technical documentation
- **Search existing issues** on GitHub
- **Open new issue** with:
  - Clear description
  - Steps to reproduce
  - Logs/error messages
  - Your environment details

## Development Workflow Example

Complete example of adding a new package:

```bash
# 1. Create branch
git checkout -b feat/add-xformers

# 2. Edit config
cat >> config/packages.yml <<EOF
  xformers:
    versions: ["0.0.23"]
    build_args: ""
    extra_deps: ["torch", "ninja", "numpy"]
    test_import: "xformers"
    description: "Memory-efficient transformers"
EOF

# 3. Test locally
./scripts/test_build_local.sh docker xformers 0.0.23 3.12 12.9.1

# 4. Verify wheel
ls -lh wheels/
python -c "import sys; sys.path.insert(0, 'wheels'); import xformers; print(xformers.__version__)"

# 5. Run tests
python -m unittest discover -s tests

# 6. Commit
git add config/packages.yml
git commit -m "feat(packages): add xformers 0.0.23"

# 7. Push
git push origin feat/add-xformers

# 8. Open PR on GitHub
gh pr create --title "Add xformers 0.0.23" --body "Adds xformers package with CUDA support"
```

## Additional Resources

- **PEP 503**: [Simple Repository API](https://peps.python.org/pep-0503/)
- **PEP 427**: [Wheel Format](https://peps.python.org/pep-0427/)
- **GitHub Actions**: [Documentation](https://docs.github.com/en/actions)
- **Docker**: [Get Started](https://docs.docker.com/get-started/)
- **flash-attention**: [Repository](https://github.com/Dao-AILab/flash-attention)

## License

By contributing, you agree that your contributions will be licensed under the same license as this project.
