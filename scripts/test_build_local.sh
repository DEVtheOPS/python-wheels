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

# Install build dependencies with matching CUDA version
if [ -n "$EXTRA_DEPS" ]; then
    echo "==> Installing build dependencies: $EXTRA_DEPS"

    # Extract CUDA version from nvcc
    CUDA_VER_MAJOR=$(nvcc --version | grep "release" | sed -n "s/.*release \([0-9]*\)\.\([0-9]*\).*/\1/p")
    CUDA_VER_MINOR=$(nvcc --version | grep "release" | sed -n "s/.*release \([0-9]*\)\.\([0-9]*\).*/\2/p")

    if [ "$CUDA_VER_MAJOR" = "13" ]; then
        echo "WARNING: CUDA 13.x detected. PyTorch may not support this version yet."
        echo "Build may fail with CUDA version mismatch error."
        pip install --quiet $EXTRA_DEPS
    elif [ "$CUDA_VER_MAJOR" = "12" ]; then
        echo "Using PyTorch index for CUDA ${CUDA_VER_MAJOR}.${CUDA_VER_MINOR}"
        pip install --quiet $EXTRA_DEPS --index-url https://download.pytorch.org/whl/cu${CUDA_VER_MAJOR}${CUDA_VER_MINOR}
    else
        pip install --quiet $EXTRA_DEPS
    fi
fi

echo "==> Building $PACKAGE==$VERSION"
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
