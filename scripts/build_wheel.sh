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
