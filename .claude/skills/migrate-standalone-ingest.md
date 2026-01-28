# Migrate Standalone Ingest to New Template Format

## Overview

This skill guides in-place migration of standalone koza ingest repos from the old cookiecutter format to the new copier template format.

**Use when:** Migrating existing repos like clinvar-ingest, ncbi-gene, biogrid-ingest, etc. to match the new template structure.

**Do NOT use for:**
- Creating new ingests from scratch (use create-koza-ingest skill)
- Extracting ingests from monarch-ingest monolith (different workflow)

## Pre-flight Checks

Before starting migration, gather information:

### 1. Confirm repo structure

Verify this is an old cookiecutter repo:
```
repo/
├── src/<package_name>/     # Package directory (e.g., src/clinvar_ingest/)
│   ├── __init__.py
│   ├── cli.py              # Old CLI - will be deleted
│   ├── download.yaml
│   ├── metadata.yaml       # Will be deleted
│   ├── transform.py
│   └── transform.yaml
├── Makefile                # Will be replaced by justfile
├── mkdocs.yaml             # Will be deleted
├── poetry.lock             # Will be deleted
└── pyproject.toml          # Will be rewritten
```

### 2. Detect koza version

Check `pyproject.toml` for koza dependency:
- `koza = ">=0.5.0"` or `koza = ">=0.6.0"` or `koza = "0.7.x"` → **koza 0.x/1.x** (needs code upgrade later)
- `koza = ">=2.0.0"` → **koza 2.x** (can fully verify)

Also check cli.py for old API patterns:
- `from koza.cli_utils import transform_source` → old API

### 3. Identify components

Catalog what exists:
- **Transforms**: List all `.py`/`.yaml` pairs in `src/<package>/`
- **Supporting modules**: Any additional `.py` files (e.g., `taxon_lookup.py`)
- **Preprocessing**: Check Makefile for steps before transform (VCF conversion, aggregation scripts)
- **Postprocessing**: Check Makefile for steps after transform (`koza split`, report generation)
- **Custom dependencies**: Note non-standard deps in pyproject.toml (e.g., `vcf-kit`, `dotenv`)

### 4. Report findings

Before proceeding, summarize:
```
Package name: <package_name>
Koza version: 0.x/1.x or 2.x
Transforms: <list>
Supporting modules: <list or none>
Preprocessing: <describe or none>
Postprocessing: <describe or none>
Custom dependencies: <list or none>
```

Confirm with user before proceeding.

---

## Phase 1: Delete Obsolete Files

Delete these files/directories:

```bash
# Inside src/<package>/
rm src/<package>/cli.py
rm src/<package>/metadata.yaml
rm src/<package>/__init__.py

# Root level
rm Makefile
rm mkdocs.yaml
rm poetry.lock
rm CONTRIBUTING.md
rm .cruft.json

# Directories
rm -rf docs/
```

### Handle scripts/ directory

Review `scripts/` before deleting:
- **Delete** (boilerplate): `generate-rdf.py`, `generate-report.py`, `get-latest-report.py`, `mkdocs-macros.py`
- **Preserve** (custom): Any preprocessing scripts (e.g., `aggregate_gene_disease.py`, `preprocess.py`)

If preserving custom scripts, move them to `scripts/` in the new structure (or inline into justfile if simple).

---

## Phase 2: Restructure

### Move download.yaml to root

```bash
mv src/<package>/download.yaml ./download.yaml
```

### Move transforms to flat src/

For each transform `.py`/`.yaml` pair:
```bash
mv src/<package>/transform.py src/transform.py
mv src/<package>/transform.yaml src/transform.yaml
```

For multi-transform repos, move all pairs:
```bash
mv src/<package>/gene_to_phenotype.py src/
mv src/<package>/gene_to_phenotype.yaml src/
# etc.
```

### Move supporting modules

```bash
mv src/<package>/taxon_lookup.py src/
# etc.
```

### Remove empty package directory

```bash
rmdir src/<package>/
```

---

## Phase 3: Update Configurations

### Update transform.yaml paths

Edit each `src/*.yaml` transform config:

1. **Remove metadata reference** (delete this line):
   ```yaml
   metadata: "./src/<package>/metadata.yaml"  # DELETE
   ```

2. **Verify data paths** (should remain unchanged):
   ```yaml
   files:
     - "./data/somefile.tsv"  # This is correct - relative to repo root
   ```

### Rewrite pyproject.toml

Replace Poetry format with hatch/uv format:

```toml
[build-system]
requires = ["hatchling", "uv-dynamic-versioning"]
build-backend = "hatchling.build"

[project]
name = "<project_slug>"
description = "<description from original>"
authors = [
  {name = "Monarch Initiative", email = "info@monarchinitiative.org"},
]
license = "<license from original>"
license-files = ["LICENSE"]
readme = "README.md"
requires-python = ">=3.10,<4.0"
dynamic = ["version"]

dependencies = [
  "koza>=0.6.0",
  "biolink-model>=4.0.0",
  # PRESERVE custom dependencies from original:
  # e.g., "vcf-kit>=0.2.9" for clinvar
  # e.g., "python-dotenv>=1.0.0" for ncbi-gene
]

[dependency-groups]
dev = [
    "pytest>=8.0.0",
    "pytest-cov>=4.1.0",
    "ruff>=0.4.8",
]

[tool.hatch.build.targets.wheel]
packages = ["src"]

[tool.hatch.version]
source = "uv-dynamic-versioning"

[tool.uv-dynamic-versioning]
vcs = "git"
style = "pep440"
fallback-version = "0.0.0"

[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["src"]

[tool.ruff]
line-length = 120
target-version = "py310"

[tool.ruff.lint]
select = ["E", "F", "I", "W"]
```

### Update test imports

Edit `tests/test_*.py` to use flat src/ imports:

```python
# Old (may have worked via package install):
from <package>.transform import some_function

# New (works via pythonpath = ["src"]):
from transform import some_function
```

---

## Phase 4: Create New Files

### Create justfile

Create `justfile` in repo root:

```just
# <project_name> justfile

# Package directory
PKG := "src"

# Explicitly enumerate transforms (adjust for this repo)
TRANSFORMS := "transform"  # Or: "gene_to_phenotype genotype_to_phenotype" for multi-transform

# List all commands
_default:
    @just --list

# ============== Project Management ==============

# Install dependencies
[group('project management')]
install:
    uv sync --group dev

# ============== Ingest Pipeline ==============

# Full pipeline: download -> preprocess -> transform -> postprocess
[group('ingest')]
run: download preprocess transform-all postprocess
    @echo "Done!"

# Download source data
[group('ingest')]
download:
    uv run koza download download.yaml

# Preprocess data (no-op if not needed)
[group('ingest')]
preprocess:
    @echo "No preprocessing required"

# Run all transforms
[group('ingest')]
transform-all:
    #!/usr/bin/env bash
    set -euo pipefail
    for t in {{TRANSFORMS}}; do
        if [ -n "$t" ]; then
            echo "Transforming $t..."
            uv run koza transform {{PKG}}/$t.yaml
        fi
    done

# Run specific transform
[group('ingest')]
transform NAME:
    uv run koza transform {{PKG}}/{{NAME}}.yaml

# Postprocess data (no-op if not needed)
[group('ingest')]
postprocess:
    @echo "No postprocessing required"

# ============== Development ==============

# Run tests
[group('development')]
test:
    uv run pytest

# Run tests with coverage
[group('development')]
test-cov:
    uv run pytest --cov=. --cov-report=term-missing

# Lint code
[group('development')]
lint:
    uv run ruff check .

# Format code
[group('development')]
format:
    uv run ruff format .

# Clean output directory
[group('development')]
clean:
    rm -rf output/
```

**Customize for preprocessing** (e.g., clinvar VCF→TSV):
```just
[group('ingest')]
preprocess:
    gunzip -f data/clinvar.vcf.gz || true
    uv run vk vcf2tsv wide --print-header data/clinvar.vcf > data/clinvar.tsv
```

**Customize for postprocessing** (e.g., ncbi-gene koza split):
```just
[group('ingest')]
postprocess:
    uv run koza split output/ncbi_gene_nodes.tsv in_taxon --remove-prefixes --output-dir output/by_taxon
```

### Create .copier-answers.yml

```yaml
_commit: <get latest commit hash from cookiecutter-monarch-ingest copier-migration branch>
_src_path: cookiecutter-monarch-ingest
copyright_year: '2026'
email: info@monarchinitiative.org
full_name: Monarch Initiative
github_handle: monarch-initiative
github_org: monarch-initiative
license: <from original - BSD-3-Clause or MIT>
project_description: <from original pyproject.toml>
project_name: <repo-name>
project_slug: <package_name>
```

### Create CLAUDE.md

```markdown
# <project_name>

This is a Koza ingest repository for transforming biological/biomedical data into Biolink model format.

## Project Structure

- `download.yaml` - Configuration for downloading source data
- `src/` - Transform code and configuration
  - `*.py` / `*.yaml` pairs - Transform code and koza config for each ingest
- `tests/` - Unit tests for transforms
- `output/` - Generated nodes and edges (gitignored)
- `data/` - Downloaded source data (gitignored)

## Key Commands

- `just run` - Full pipeline (download -> preprocess -> transform -> postprocess)
- `just download` - Download source data
- `just transform-all` - Run all transforms
- `just transform <name>` - Run specific transform
- `just test` - Run tests

## Adding New Ingests

Use the create-koza-ingest skill in `.claude/skills/`
```

### Consolidate README.md

Read both `docs/index.md` (if it existed) and `README.md`. Create new README with ingest-specific content only.

**Discard** (template boilerplate):
- "Getting Started" / "Quick Start" about using the template
- Instructions for `poetry install`, `make download`, `make run`
- Generic CLI usage
- "How to add a new transform" guidance

**Keep** (ingest-specific):
- What data source this processes
- What the data contains
- What entities/associations are produced
- Special requirements (API keys, env vars)
- Data licensing/attribution

**New README structure:**
```markdown
# <project_name>

<Brief description of what this ingest does>

## Data Source

<Where data comes from, what it contains>

## Output

<What nodes/edges are produced>

## Usage

```bash
just install    # Install dependencies
just run        # Full pipeline
just test       # Run tests
```

## Development

<Any special setup, env vars, etc.>

## License

<License info>
```

If little/no ingest-specific content found, flag for manual documentation.

---

## Phase 5: Update CI

### Delete old workflows

```bash
rm .github/workflows/deploy-docs.yaml
rm .github/workflows/update-docs.yaml
```

### Replace test.yaml

Copy from zfin-ingest or xenbase-ingest and use as-is:

```yaml
name: Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.10", "3.11", "3.12"]

    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v4
        with:
          version: "latest"

      - name: Set up Python ${{ matrix.python-version }}
        run: uv python install ${{ matrix.python-version }}

      - name: Install dependencies
        run: uv sync --group dev

      - name: Run linting
        run: uv run ruff check .

      - name: Run tests
        run: uv run pytest -v
```

### Replace release.yaml (create-release.yaml)

Copy from zfin-ingest and update:
- `TRANSFORMS` env var for this repo
- Release body text

---

## Phase 6: Verify or Flag

### For koza 2.x repos:

Run verification:
```bash
uv sync --group dev
just test
```

If tests pass, migration is complete. Commit changes.

### For koza 0.x/1.x repos:

**Do NOT run tests** - they will fail due to koza API changes.

**Do NOT commit** - leave working copy in migrated state.

Output message:
```
Structure migration complete for <repo>.
This repo uses koza 0.x/1.x and needs code upgrade before testing.

Next steps:
1. Upgrade koza dependency to >=2.0.0
2. Update transform code to koza 2.x API
3. Update tests for new API
4. Run `just test` to verify
5. Commit all changes
```

---

## Checklist Summary

### Pre-flight
- [ ] Confirm old cookiecutter structure
- [ ] Detect koza version
- [ ] Identify transforms, modules, pre/post processing
- [ ] Report findings and get confirmation

### Phase 1: Delete
- [ ] Delete cli.py, metadata.yaml, __init__.py
- [ ] Delete Makefile, mkdocs.yaml, poetry.lock
- [ ] Delete docs/, CONTRIBUTING.md, .cruft.json
- [ ] Review scripts/ - preserve custom, delete boilerplate

### Phase 2: Restructure
- [ ] Move download.yaml to root
- [ ] Move transforms to flat src/
- [ ] Move supporting modules to src/
- [ ] Remove empty package directory

### Phase 3: Update Configs
- [ ] Update transform.yaml (remove metadata reference)
- [ ] Rewrite pyproject.toml (Poetry → hatch/uv)
- [ ] Update test imports

### Phase 4: Create Files
- [ ] Create justfile (customize pre/post processing)
- [ ] Create .copier-answers.yml
- [ ] Create CLAUDE.md
- [ ] Consolidate README.md

### Phase 5: Update CI
- [ ] Delete deploy-docs.yaml, update-docs.yaml
- [ ] Replace test.yaml with uv version
- [ ] Replace/update release.yaml

### Phase 6: Verify/Flag
- [ ] If koza 2.x: run tests, commit
- [ ] If koza 0.x/1.x: skip tests, don't commit, flag for upgrade
