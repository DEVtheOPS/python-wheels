# python-wheels

A GitHub-hosted PyPI index for pre-compiled Python wheels of CUDA-enabled packages. Build once, install anywhere - no local compilation required.

## Why?

Building packages like `flash-attn` and `xformers` from source takes 30+ minutes and requires CUDA toolkit, build tools, and significant CPU/memory. This repository:

- ✅ **Pre-builds wheels** for multiple Python and CUDA versions
- ✅ **Hosts a PEP 503 index** on GitHub Pages
- ✅ **Eliminates local compilation** - just `pip install`
- ✅ **Supports CUDA 12.x and 13.x** via PyTorch nightly builds

## Supported Packages

Current packages available:
- **flash-attn** 2.8.3

**GPU Compatibility:** Wheels are compiled for CUDA compute capability 8.9+ (RTX 4000 series, H100, and newer GPUs). This limitation is necessary to fit compilation within GitHub Actions runner memory constraints.

See `config/packages.yml` for full configuration.

## Installation

Install pre-built wheels using pip's `--extra-index-url`:

```bash
# Install PyTorch first (required for CUDA packages)
# For CUDA 12.9:
pip install torch --index-url https://download.pytorch.org/whl/cu129

# For CUDA 13.0:
pip install torch --index-url https://download.pytorch.org/whl/cu130

# Then install the package from this index
pip install flash-attn --extra-index-url https://DEVtheOPS.github.io/python-wheels/simple/
```

### Available Configurations

| Package | Version | Python | CUDA |
|---------|---------|--------|------|
| flash-attn | 2.8.3 | 3.12, 3.13 | 12.9.1, 13.0.2 |

## Triggering a Build

### Via GitHub Actions UI

1. Go to the [Actions tab](https://github.com/DEVtheOPS/python-wheels/actions)
2. Click **"Build Wheels"** workflow
3. Click **"Run workflow"** button
4. (Optional) Customize parameters:
   - **Package**: Leave empty to build all, or specify one (e.g., `flash-attn`)
   - **Python versions**: Comma-separated (default: `3.12,3.13`)
   - **CUDA versions**: Comma-separated (default: `12.9.1,13.0.2`)
5. Click **"Run workflow"**

### Automatic Builds

Builds trigger automatically when you:
- Push changes to `config/packages.yml` on the `main` branch

### Via GitHub CLI

```bash
# Build all packages with defaults
gh workflow run build-wheels.yml

# Build specific package
gh workflow run build-wheels.yml -f package=flash-attn

# Build for specific Python version
gh workflow run build-wheels.yml -f python_versions=3.12

# Build for specific CUDA version
gh workflow run build-wheels.yml -f cuda_versions=13.0.2

# Combine options
gh workflow run build-wheels.yml \
  -f package=flash-attn \
  -f python_versions=3.12 \
  -f cuda_versions=13.0.2
```

## Adding New Packages

1. Edit `config/packages.yml`:

```yaml
packages:
  my-package:
    versions: ["1.0.0"]
    build_args: "--no-build-isolation"  # Optional
    extra_deps: ["torch", "ninja"]       # Build dependencies
    test_import: "my_package"            # Module name for import test
    description: "My CUDA package"       # Human-readable description
```

2. Commit and push to `main` branch (triggers automatic build)
3. Or manually trigger workflow via Actions UI

## Project Structure

```
python-wheels/
├── .github/workflows/
│   └── build-wheels.yml      # CI/CD workflow
├── config/
│   └── packages.yml           # Package definitions
├── scripts/
│   ├── build_in_docker.sh     # Docker build script
│   ├── generate_index.py      # PyPI index generator
│   └── test_build_local.sh    # Local testing script
├── tests/
│   └── test_generate_index.py # Unit tests
├── AGENTS.md                  # Technical documentation for AI assistants
├── CONTRIBUTING.md            # Development guide
└── README.md                  # This file
```

## How It Works

1. **Matrix Generation**: Workflow reads `config/packages.yml` and generates build matrix
2. **Docker Build**: Each combination builds in CUDA Docker container
3. **Wheel Creation**: `pip wheel` compiles package with CUDA support
4. **Import Test**: Verifies wheel loads successfully in clean environment
5. **Release**: Creates GitHub release with wheels attached
6. **Index Generation**: Generates PEP 503 index HTML
7. **GitHub Pages**: Deploys index for pip consumption

## Architecture

- **Build Environment**: `nvidia/cuda:{VERSION}-devel-ubuntu22.04`
- **Test Environment**: `nvidia/cuda:{VERSION}-runtime-ubuntu22.04`
- **Python**: Installed from deadsnakes PPA
- **PyTorch**: Version-matched to CUDA (12.x stable, 13.x nightly)
- **Index Format**: PEP 503 compliant, hosted on GitHub Pages

## Troubleshooting

### Build fails with disk space error

GitHub Actions runners have limited space. The workflow includes cleanup steps, but you can:
- Build fewer packages at once using the `package` parameter
- Reduce Python/CUDA version combinations

### Build timeout / runner lost communication

flash-attn compilation is extremely CPU/memory intensive. The workflow runs builds **sequentially** (`max-parallel: 1`) to prevent overwhelming runners. This means:
- ⏱️ Each build takes 60-90 minutes
- ⏱️ All 4 combinations take ~4-6 hours total
- ✅ Builds complete successfully without timeouts

To speed up for testing:
- Build one package at a time using the `package` parameter
- Build one Python version at a time
- Build one CUDA version at a time

### Import test fails

Common causes:
- **Missing runtime dependencies**: Package needs PyTorch + numpy installed
- **CUDA version mismatch**: Ensure PyTorch CUDA version matches wheel's CUDA version
- **Wrong PyTorch version**: CUDA 13.x requires PyTorch nightly from `cu130` index

See `AGENTS.md` for detailed troubleshooting.

## Local Testing

You can test wheel builds locally before pushing to CI:

### Prerequisites

- Docker or Podman installed
- Python 3.12+ with PyYAML (`pip install pyyaml`)

### Build and Test a Wheel

```bash
# Using Docker (default)
./scripts/test_build_local.sh docker flash-attn 2.8.3 3.12 12.9.1

# Using Podman
./scripts/test_build_local.sh podman flash-attn 2.8.3 3.12 13.0.2

# With defaults (flash-attn 2.8.3, Python 3.12, CUDA 12.9.1)
./scripts/test_build_local.sh
```

The script will:
1. ✅ Read package config from `config/packages.yml`
2. ✅ Pull CUDA Docker image
3. ✅ Build the wheel in Docker
4. ✅ Run import test in clean container
5. ✅ Report success/failure

Wheels are output to `./wheels/` directory.

### Test Index Generation

```bash
# Generate index HTML from wheels directory
python scripts/generate_index.py \
  --wheels-dir wheels \
  --output-dir index/simple \
  --base-url "https://github.com/USER/REPO/releases/download/TAG"

# View generated index
ls -R index/simple/
```

### Run Unit Tests

```bash
# Run all tests
python -m unittest discover -s tests -p "test_*.py"

# Run specific test
python -m unittest tests.test_generate_index.ParseWheelFilenameTests
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

See [LICENSE](LICENSE) file for details.

## Related Projects

- [flash-attention](https://github.com/Dao-AILab/flash-attention) - The original flash-attn implementation
- [xformers](https://github.com/facebookresearch/xformers) - Memory-efficient transformers
- [pytorch](https://pytorch.org) - The foundation for all CUDA packages

## Support

- **Issues**: [GitHub Issues](https://github.com/DEVtheOPS/python-wheels/issues)
- **Releases**: [GitHub Releases](https://github.com/DEVtheOPS/python-wheels/releases)
- **Index**: [GitHub Pages](https://DEVtheOPS.github.io/python-wheels/simple/)
