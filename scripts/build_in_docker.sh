#!/bin/bash
# Build wheel inside Docker container with CUDA support
# This script runs INSIDE the Docker container

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

    # Determine PyTorch index based on CUDA version
    CUDA_MAJOR=$(echo $CUDA_VERSION | cut -d'.' -f1)
    CUDA_MINOR=$(echo $CUDA_VERSION | cut -d'.' -f2)

    if [ "$CUDA_MAJOR" = "13" ]; then
        echo "==> CUDA 13.x detected - using PyTorch nightly with CUDA 13.0 support"
        # Use PyTorch nightly with CUDA 13.0 support
        pip install --quiet torch --index-url https://download.pytorch.org/whl/cu130

        # Install other dependencies normally
        OTHER_DEPS=$(echo "$EXTRA_DEPS" | sed 's/torch//g')
        if [ -n "$OTHER_DEPS" ]; then
            pip install --quiet $OTHER_DEPS
        fi
    elif [ "$CUDA_MAJOR" = "12" ]; then
        # Use PyTorch with CUDA 12.x support
        echo "==> Using PyTorch index for CUDA ${CUDA_MAJOR}.${CUDA_MINOR}"
        # Install torch from CUDA-specific index
        pip install --quiet torch --index-url https://download.pytorch.org/whl/cu${CUDA_MAJOR}${CUDA_MINOR}

        # Install other dependencies from PyPI
        OTHER_DEPS=$(echo "$EXTRA_DEPS" | sed 's/torch//g')
        if [ -n "$OTHER_DEPS" ]; then
            pip install --quiet $OTHER_DEPS
        fi
    else
        pip install --quiet $EXTRA_DEPS
    fi
fi

echo ""
echo "==> Building $PACKAGE==$VERSION"

# Set environment variables to handle CUDA version mismatches
# Build for ONLY ONE architecture to minimize memory usage
# 8.6 = Ampere (RTX 3080/3090/3090Ti, A100)
export TORCH_CUDA_ARCH_LIST="8.6"
# flash-attn-specific environment variable (space-separated, no semicolons)
export FLASH_ATTENTION_CUDA_ARCHS="86"
export MAX_JOBS="${MAX_JOBS:-1}"

# For CUDA 13.x, patch PyTorch to bypass CUDA version check
CUDA_MAJOR=$(echo $CUDA_VERSION | cut -d'.' -f1)
if [ "$CUDA_MAJOR" = "13" ]; then
    echo "==> CUDA 13.x detected: Patching PyTorch CUDA version check"

    # Create a patch to bypass the CUDA version check in torch.utils.cpp_extension
    TORCH_UTILS=$(python -c "import torch.utils.cpp_extension as m; import os; print(os.path.dirname(m.__file__))")

    if [ -f "$TORCH_UTILS/cpp_extension.py" ]; then
        # Backup original
        cp "$TORCH_UTILS/cpp_extension.py" "$TORCH_UTILS/cpp_extension.py.bak"

        # Patch the _check_cuda_version function to be a no-op
        cat > /tmp/patch_torch.py << 'EOPY'
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
