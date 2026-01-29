# koza-ingest-copier

A copier template for modular Koza ingests following Monarch Initiative patterns.

This template creates multi-ingest repositories where each data source can have multiple transform pipelines. It uses modern tooling: `uv` for dependency management, `just` for task running, and GitHub Actions for CI/CD.

## Getting Started

### Prerequisites

- [uv](https://docs.astral.sh/uv/) - Python package manager
- [just](https://just.systems/) - Command runner
- [copier](https://copier.readthedocs.io/) - Template engine

### Create a New Ingest Repository

```bash
# Using uvx (recommended)
uvx --with jinja2-time copier copy https://github.com/monarch-initiative/cookiecutter-monarch-ingest.git my-source-ingest

# Or if copier is installed
copier copy https://github.com/monarch-initiative/cookiecutter-monarch-ingest.git my-source-ingest
```

This will prompt for:
- `project_name`: Name of your project (e.g., `xenbase-ingest`)
- `project_description`: Brief description
- `github_org`: GitHub organization (default: `monarch-initiative`)
- `full_name`: Your name
- `email`: Your email
- `license`: Choose from MIT, BSD-3-Clause, Apache-2.0, etc.

### Initialize the Project

```bash
cd my-source-ingest
just setup
```

This will:
1. Initialize a git repository
2. Install dependencies with uv
3. Create an initial commit

## Multi-Ingest Repository Pattern

Unlike single-ingest templates, this creates a flat structure where each ingest is a `.py`/`.yaml` pair at the repository root:

```
my-source-ingest/
├── download.yaml          # All data source URLs
├── gene_to_phenotype.py   # Transform code for ingest 1
├── gene_to_phenotype.yaml # Koza config for ingest 1
├── orthologs.py           # Transform code for ingest 2
├── orthologs.yaml         # Koza config for ingest 2
├── tests/
│   ├── test_gene_to_phenotype.py
│   └── test_orthologs.py
├── justfile               # TRANSFORMS list updated as ingests are added
├── pyproject.toml
└── README.md
```

## Adding Ingests

After creating the repository, use the `create-koza-ingest` Claude skill to add ingests:

```
"Add a new koza ingest for xenbase gene-to-phenotype associations"
```

The skill guides you through:
1. Configuring data download
2. Setting up the reader
3. Researching Biolink model predicates
4. Writing tests (TDD)
5. Implementing the transform

## Common Commands

```bash
# Download all source data
just download

# Run all transforms
just transform-all

# Run specific transform
just transform gene_to_phenotype

# Run tests
just test

# Lint code
just lint
```

## Keeping Up to Date

Update your project when the template changes:

```bash
copier update
```

## License

BSD-3-Clause
