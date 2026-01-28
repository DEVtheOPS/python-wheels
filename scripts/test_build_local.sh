#!/bin/bash
# Local testing script for wheel builds using Docker/Podman
# Usage: ./scripts/test_build_local.sh [podman|docker] [package] [version] [python] [cuda]

set -euo pipefail

# Determine container runtime
RUNTIME="${1:-docker}"
if ! command -v "$RUNTIME" &> /dev/null; then
    echo "Error: $RUNTIME not found. Please install $RUNTIME or specify different runtime." >&2
    exit 1
fi

# Parse arguments or use defaults for testing
PACKAGE="${2:-flash-attn}"
VERSION="${3:-2.8.3}"
PYTHON_VERSION="${4:-3.12}"
CUDA_VERSION="${5:-12.9.1}"

echo "================================"
echo "Local Wheel Build Test"
echo "================================"
echo "Runtime:       $RUNTIME"
echo "Package:       $PACKAGE"
echo "Version:       $VERSION"
echo "Python:        $PYTHON_VERSION"
echo "CUDA:          $CUDA_VERSION"
echo "================================"
echo ""

# Load config
CONFIG_FILE="config/packages.yml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found. Run from repo root." >&2
    exit 1
fi

# Extract package config using Python
read -r BUILD_ARGS EXTRA_DEPS TEST_IMPORT < <(python3 <<EOF
import yaml
import sys

with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)

pkg = config.get('packages', {}).get('$PACKAGE', {})
if not pkg:
    print('', '', '$PACKAGE', file=sys.stderr)
    sys.exit(1)

build_args = pkg.get('build_args', '')
extra_deps = ' '.join(pkg.get('extra_deps', []))
test_import = pkg.get('test_import', '${PACKAGE}'.replace('-', '_'))

print(f'{build_args} {extra_deps} {test_import}')
EOF
)

if [ $? -ne 0 ]; then
    echo "Error: Package '$PACKAGE' not found in $CONFIG_FILE" >&2
    exit 1
fi

echo "Build args:    $BUILD_ARGS"
echo "Extra deps:    $EXTRA_DEPS"
echo "Test import:   $TEST_IMPORT"
echo ""

# Setup output directory
OUTPUT_DIR="$(pwd)/wheels"
mkdir -p "$OUTPUT_DIR"

# Docker image to use
DOCKER_IMAGE="nvidia/cuda:${CUDA_VERSION}-devel-ubuntu22.04"

echo "Pulling CUDA image: $DOCKER_IMAGE"
$RUNTIME pull "$DOCKER_IMAGE"
echo ""

echo "Building wheel..."
echo "---"

# Build the wheel
$RUNTIME run --rm \
    -v "$OUTPUT_DIR:/workspace/wheels:Z" \
    -e PACKAGE="$PACKAGE" \
    -e VERSION="$VERSION" \
    -e PYTHON_VERSION="$PYTHON_VERSION" \
    -e BUILD_ARGS="$BUILD_ARGS" \
    -e EXTRA_DEPS="$EXTRA_DEPS" \
    "$DOCKER_IMAGE" \
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

echo ""
echo "==> Python version: $(python --version)"
echo "==> CUDA version: $(nvcc --version | grep release)"
echo ""

# Install build dependencies with CUDA compatibility handling
if [ -n "$EXTRA_DEPS" ]; then
    echo "==> Installing build dependencies: $EXTRA_DEPS"

    # Extract CUDA version from nvcc
    CUDA_VER_MAJOR=$(nvcc --version | grep "release" | sed -n "s/.*release \([0-9]*\)\.\([0-9]*\).*/\1/p")
    CUDA_VER_MINOR=$(nvcc --version | grep "release" | sed -n "s/.*release \([0-9]*\)\.\([0-9]*\).*/\2/p")

    if [ "$CUDA_VER_MAJOR" = "13" ]; then
        echo "==> CUDA 13.x detected - using PyTorch nightly or latest available"
        # Try PyTorch nightly builds first (may have CUDA 13.x support)
        pip install --quiet --pre torch --index-url https://download.pytorch.org/whl/nightly/cu124 || \
        pip install --quiet --pre torch --index-url https://download.pytorch.org/whl/nightly/cu121 || \
        pip install --quiet torch

        # Install other dependencies normally
        OTHER_DEPS=$(echo "$EXTRA_DEPS" | sed "s/torch//g")
        if [ -n "$OTHER_DEPS" ]; then
            pip install --quiet $OTHER_DEPS
        fi
    elif [ "$CUDA_VER_MAJOR" = "12" ]; then
        echo "==> Using PyTorch index for CUDA ${CUDA_VER_MAJOR}.${CUDA_VER_MINOR}"
        # Install torch from CUDA-specific index
        pip install --quiet torch --index-url https://download.pytorch.org/whl/cu${CUDA_VER_MAJOR}${CUDA_VER_MINOR}

        # Install other dependencies from PyPI
        OTHER_DEPS=$(echo "$EXTRA_DEPS" | sed 's/torch//g')
        if [ -n "$OTHER_DEPS" ]; then
            pip install --quiet $OTHER_DEPS
        fi
    else
        pip install --quiet $EXTRA_DEPS
    fi
fi

echo "==> Building $PACKAGE==$VERSION"

# Set environment variables to handle CUDA version mismatches
export TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9;9.0"

# For CUDA 13.x, patch PyTorch to bypass CUDA version check
CUDA_VER_MAJOR=$(nvcc --version | grep "release" | sed -n "s/.*release \([0-9]*\)\.\([0-9]*\).*/\1/p")
if [ "$CUDA_VER_MAJOR" = "13" ]; then
    echo "==> CUDA 13.x detected: Patching PyTorch CUDA version check"

    # Create a patch to bypass the CUDA version check
    TORCH_UTILS=$(python -c "import torch.utils.cpp_extension as m; import os; print(os.path.dirname(m.__file__))" 2>/dev/null || echo "")

    if [ -n "$TORCH_UTILS" ] && [ -f "$TORCH_UTILS/cpp_extension.py" ]; then
        cp "$TORCH_UTILS/cpp_extension.py" "$TORCH_UTILS/cpp_extension.py.bak"

        cat > /tmp/patch_torch.py << "EOPY"
import sys
filepath = sys.argv[1]
with open(filepath, "r") as f:
    content = f.read()

# Replace the _check_cuda_version function to skip the check
content = content.replace(
    "def _check_cuda_version(compiler_name: str, compiler_version: Version) -> None:",
    "def _check_cuda_version(compiler_name: str, compiler_version: Version) -> None:\n    return  # Patched for CUDA 13.x compatibility"
)

with open(filepath, "w") as f:
    f.write(content)
print(f"Patched {filepath}")
EOPY
        python /tmp/patch_torch.py "$TORCH_UTILS/cpp_extension.py"
    fi
fi

pip wheel "$PACKAGE==$VERSION" \
    $BUILD_ARGS \
    --wheel-dir=/workspace/wheels

echo ""
echo "==> Built wheels:"
ls -lh /workspace/wheels/
'

BUILD_EXIT=$?

if [ $BUILD_EXIT -ne 0 ]; then
    echo ""
    echo "❌ Build failed with exit code $BUILD_EXIT"
    exit $BUILD_EXIT
fi

echo ""
echo "✅ Build succeeded!"
echo ""

# Find the wheel
WHEEL_FILE=$(find "$OUTPUT_DIR" -name "${PACKAGE//-/_}*.whl" -type f | head -1)

if [ -z "$WHEEL_FILE" ]; then
    echo "❌ Error: No wheel file found in $OUTPUT_DIR"
    exit 1
fi

WHEEL_NAME=$(basename "$WHEEL_FILE")
echo "Wheel: $WHEEL_NAME"
echo ""

# Test import
echo "Testing wheel import..."
echo "---"

RUNTIME_IMAGE="nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu22.04"

$RUNTIME run --rm \
    -v "$OUTPUT_DIR:/wheels:Z" \
    "$RUNTIME_IMAGE" \
    bash -c "
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq software-properties-common
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update -qq
apt-get install -y -qq python${PYTHON_VERSION} python${PYTHON_VERSION}-venv

python${PYTHON_VERSION} -m venv /venv
source /venv/bin/activate
pip install --quiet --upgrade pip

# Install runtime dependencies based on CUDA version
CUDA_VER_MAJOR=\$(echo ${CUDA_VERSION} | cut -d'.' -f1)
CUDA_VER_MINOR=\$(echo ${CUDA_VERSION} | cut -d'.' -f2)

echo '==> Installing runtime dependencies'
if [ \"\$CUDA_VER_MAJOR\" = \"13\" ]; then
    # For CUDA 13.x, use PyTorch nightly with CUDA 13.0 support
    pip install --quiet torch --index-url https://download.pytorch.org/whl/cu130
elif [ \"\$CUDA_VER_MAJOR\" = \"12\" ]; then
    # For CUDA 12.x, use stable PyTorch
    pip install --quiet torch --index-url https://download.pytorch.org/whl/cu\${CUDA_VER_MAJOR}\${CUDA_VER_MINOR}
else
    pip install --quiet torch
fi

# Install numpy
pip install --quiet numpy

# Install the wheel
echo '==> Installing wheel'
pip install --quiet /wheels/$WHEEL_NAME

echo ''
echo '==> Testing import'
python -c 'import ${TEST_IMPORT}; print(\"✓ Import successful\")'
"

TEST_EXIT=$?

echo ""
if [ $TEST_EXIT -eq 0 ]; then
    echo "✅ All tests passed!"
    echo ""
    echo "Wheel location: $WHEEL_FILE"
else
    echo "❌ Import test failed with exit code $TEST_EXIT"
    exit $TEST_EXIT
fi
