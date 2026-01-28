# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Project Overview

A GitHub-hosted PyPI index that builds and distributes pre-compiled Python wheels for CUDA-enabled packages (flash-attn, xformers, etc.) across multiple Python and CUDA versions. Eliminates the need for users to compile complex CUDA packages locally.

**Key Architecture:**
- GitHub Actions orchestrates builds using dynamic matrix strategy
- Docker containers with NVIDIA CUDA images provide build environment
- PEP 503-compliant index hosted on GitHub Pages
- Configuration-driven package definitions in `config/packages.yml`

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Essential Commands

### Local Testing

**Run tests:**
```bash
python -m unittest discover -s tests -p "test_*.py"
```

**Run specific test:**
```bash
python -m unittest tests.test_generate_index.ParseWheelFilenameTests.test_normalizes_name_and_handles_build_tag
```

**Generate PyPI index locally:**
```bash
python scripts/generate_index.py \
  --wheels-dir wheels \
  --output-dir index/simple \
  --base-url "https://github.com/USER/REPO/releases/download/TAG"
```

**Build wheel locally (requires Docker or Podman):**
```bash
# Using Docker (default)
./scripts/test_build_local.sh docker flash-attn 2.8.3 3.12 12.9.1

# Using Podman
./scripts/test_build_local.sh podman flash-attn 2.8.3 3.12 12.9.1

# Test with defaults (flash-attn 2.8.3, Python 3.12, CUDA 12.9.1)
./scripts/test_build_local.sh
```

**Legacy build script (no testing):**
```bash
./scripts/build_wheel.sh flash-attn 2.8.3 3.12 12.9.1
```

### CI/CD

**Trigger workflow manually:**
- GitHub UI → Actions → "Build Wheels" → Run workflow
- Optional: Specify package, Python versions, CUDA versions

**Automatic builds:**
- Push changes to `config/packages.yml` on main branch

## Architecture

### Build Pipeline Flow

```
config/packages.yml
    ↓
GitHub Actions Prepare Job
    ↓ (generates matrix)
Build Jobs (parallel, one per combination)
    ↓ (Docker: nvidia/cuda:*-devel-ubuntu22.04)
Wheel Artifacts
    ↓
Release Job (creates GitHub release)
    ↓
PyPI Index Generation
    ↓
GitHub Pages Deployment
```

### Package Configuration Schema

Located in `config/packages.yml`:

```yaml
packages:
  <package-name>:
    versions: ["version1", "version2"]        # Package versions to build
    build_args: "--no-build-isolation"        # pip wheel arguments
    extra_deps: ["torch", "ninja", "psutil"]  # Build dependencies
    test_import: "module_name"                # Python import to test
    description: "Package description"        # Human-readable description
```

**Critical Fields:**
- `versions`: List of exact versions to build (e.g., `["2.8.3"]`)
- `build_args`: Pass flags like `--no-build-isolation` for complex builds
- `extra_deps`: Install before building (e.g., `torch` for flash-attn)
- `test_import`: Module name for import smoke test (defaults to package name with `_`)

### Docker Build Process

Each wheel is built in isolation:

1. Pull CUDA image: `nvidia/cuda:{VERSION}-devel-ubuntu22.04`
2. Install Python from deadsnakes PPA
3. Create virtualenv with specific Python version
4. Install build dependencies (`extra_deps`)
5. Build wheel: `pip wheel {PACKAGE}=={VERSION} {BUILD_ARGS}`
6. Test import in runtime container
7. Upload artifact to GitHub

### PyPI Index Structure

Follows PEP 503 (Simple Repository API):

```
index/simple/
├── index.html                           # Root index (lists all packages)
└── {normalized-package-name}/
    └── index.html                       # Package index (lists all wheels)
```

**Wheel naming:** `{package}-{version}-{python}-{abi}-{platform}.whl`

Example: `flash_attn-2.8.3-cp312-cp312-linux_x86_64.whl`

### Script Responsibilities

**`scripts/generate_index.py`:**
- Parses wheel filenames (PEP 427)
- Normalizes package names (PEP 503: replace `[-_.]` with `-`)
- Generates HTML index files
- Validates wheel format

**`scripts/build_wheel.sh`:**
- Input validation (package name, version, Python, CUDA)
- Docker orchestration
- Wheel output collection
- Error handling with line number reporting

## Adding a New Package

1. Add entry to `config/packages.yml`:

```yaml
packages:
  my-package:
    versions: ["1.0.0"]
    build_args: ""
    extra_deps: []
    test_import: "my_package"
    description: "My CUDA package"
```

2. Commit to main branch (triggers automatic build), or manually trigger workflow

3. Verify build in Actions tab

4. Check release artifacts and GitHub Pages index

## Testing Strategy

**Unit tests** (`tests/test_generate_index.py`):
- Wheel filename parsing
- Package name normalization
- Index HTML generation
- End-to-end script execution

**CI smoke tests:**
- Import test in runtime container (validates wheel installs correctly)
- Wheel artifact upload verification

## Common Issues

**Build fails with missing CUDA:**
- Ensure using `-devel` CUDA image, not `-runtime`
- Check CUDA version matches build requirements

**Import test fails:**
- Verify `test_import` matches actual module name
- Check `extra_deps` includes runtime dependencies

**Wheel not found in index:**
- Confirm wheel filename follows PEP 427 format
- Check `generate_index.py` didn't skip it (warning in logs)

**Docker pull timeout:**
- Workflow uses `nick-invision/retry@v3` with 3 attempts
- CUDA images are large (~5GB), may need increased timeout

**Disk space exhausted during build:**
- GitHub Actions runners have limited space (~14GB free)
- Workflow includes disk cleanup steps (removes dotnet, android, etc.)
- Cleans up Docker images after each build
- If still failing, reduce parallelism by building fewer versions at once

**CUDA version mismatch with PyTorch:**
- Error: `RuntimeError: The detected CUDA version (X.X) mismatches the version that was used to compile PyTorch (Y.Y)`
- **Cause:** PyTorch (required by flash-attn) must match CUDA version
- **Solution:** Only use CUDA versions supported by PyTorch
  - CUDA 12.x: Fully supported (use default: 12.9.1)
  - CUDA 13.x: Not yet supported by stable PyTorch builds
- **Check PyTorch compatibility:** https://pytorch.org/get-started/locally/
- Workflow automatically uses matching PyTorch index for CUDA 12.x

## Workflow Permissions

Required permissions in `.github/workflows/build-wheels.yml`:
- `contents: write` - Create releases and commit to gh-pages
- `pages: write` - Deploy to GitHub Pages
- `id-token: write` - GitHub Pages deployment authentication

## Development Notes

- **Immutability:** Wheel builds are reproducible (pinned versions, Docker)
- **Fail-fast disabled:** One package failure doesn't stop other builds
- **Retention:** Wheel artifacts kept for 90 days
- **Release tags:** Date-based (`v2026-01-28`)
- **Base URL:** Points to GitHub release download URL for wheel files

## GitHub Pages Index

**Installation for users:**
```bash
pip install flash-attn --extra-index-url https://USER.github.io/REPO/simple/
```

**Index updates:**
- Automatic on successful builds
- `force_orphan: true` - Keeps gh-pages branch clean (no history)
- Deployed from `index/` directory after generation

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds



<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: Auto-syncs to JSONL for version control
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:bd-123 --json
```

**Claim and update:**

```bash
bd update bd-42 --status in_progress --json
bd update bd-42 --priority 1 --json
```

**Complete work:**

```bash
bd close bd-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task**: `bd update <id> --status in_progress`
3. **Work on it**: Implement, test, document
4. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
5. **Complete**: `bd close <id> --reason "Done"`

### Auto-Sync

bd automatically syncs with git:

- Exports to `.beads/issues.jsonl` after changes (5s debounce)
- Imports from JSONL when newer (e.g., after `git pull`)
- No manual export/import needed!

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT use external issue trackers
- ❌ Do NOT duplicate tracking systems

For more details, see README.md and docs/QUICKSTART.md.

<!-- END BEADS INTEGRATION -->
