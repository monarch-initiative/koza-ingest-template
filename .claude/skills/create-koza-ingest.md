---
name: create-koza-ingest
description: Create a new Koza 2.x biological/biomedical data ingest following Monarch Initiative patterns
version: 1.0.0
triggers:
  - "create a koza ingest"
  - "new koza ingest"
  - "create monarch ingest"
---

# Create Koza Ingest Skill

You are helping to create a new Koza 2.x ingest for biological/biomedical data following the Monarch Initiative patterns.

## Workflow Overview

Follow these steps in order:

### 1. Create Project from Cookiecutter Template

Use the cookiecutter template to create a new project:

```bash
cd ~/Monarch
cookiecutter https://github.com/monarch-initiative/cookiecutter-monarch-ingest.git \
  --no-input \
  project_name="<project-name>" \
  project_description="<description>" \
  github_org="monarch-initiative" \
  __ingest_name="<ingest_name>"
```

**Ask the user for:**
- Project name (kebab-case, e.g., "omim-ingest")
- Description (e.g., "OMIM gene to disease associations")
- Ingest name (snake_case, e.g., "omim_gene_to_disease")

### 2. Install Dependencies and Download Data

```bash
cd ~/Monarch/<project-name>
poetry install
make download  # or poetry run ingest download
```

### 3. Configure download.yaml

Update `src/<project_slug>/download.yaml` with the actual data source URL and local filename.

### 4. Inspect the Downloaded Data

Examine the data file structure:
- Check number of rows: `wc -l data/<filename>`
- View first rows: `head -20 data/<filename>`
- Look for:
  - Header rows (and whether they have comment characters)
  - Column delimiters (tab, comma, etc.)
  - Comment lines
  - Data patterns

### 5. Configure transform.yaml

Update `src/<project_slug>/transform.yaml` with the proper reader configuration.

**Critical koza 2.x patterns:**

#### Handling Comment Characters with Headers

When a file has comment lines AND a header row with a comment character prefix:

```yaml
reader:
  format: "csv"
  files:
    - "../../data/<filename>"
  delimiter: "\t"
  comment_char: "#"  # Skip lines starting with #
  header_mode: 1  # After filtering comments, line 1 is the header (1-indexed)
  header_prefix: "#"  # Strip "#" prefix from header line column names
```

**Example file:**
```
# See end of file for documentation
# Phenotype	Gene Symbols	MIM Number	Cyto Location
17,20-lyase deficiency, isolated, 202110 (3)	CYP17A1, CYP17, P450C17	609300	10q24.32
```

With this config, you get clean column names: `Phenotype`, `Gene Symbols`, `MIM Number`, `Cyto Location`

**Pattern:** `comment_char` + `header_mode` + `header_prefix` is a powerful combination for messy data files.

#### Set min_edge_count/min_node_count

Based on row count in the file:
```yaml
writer:
  min_node_count: 0  # Set based on expected output
  min_edge_count: <number>  # Set slightly less than row count (e.g., 7000 for 7437 rows)
```

### 6. Test Configuration by Printing Records

Temporarily modify `transform.py` to print incoming records and verify the config is correct:

```python
@koza.transform_record()
def transform_record(koza_transform: KozaTransform, row: dict[str, Any]) -> list[Entity | Association]:
    """Test transform - prints records to verify config."""
    print(f"Row keys: {list(row.keys())}")
    print(f"Row data: {row}")
    print("-" * 80)
    return []  # Return empty list for now
```

Set `min_edge_count: 0` temporarily, then run:

```bash
poetry run ingest transform --row-limit 3
```

Verify that:
- Column names are correct
- Data is parsed properly
- No unexpected characters or issues

### 7. Research Data Format Documentation

**CRITICAL:** Before writing transform code, research the source data format documentation.

Look for:
- Official documentation from the data provider
- Meaning of symbols, brackets, special characters
- Confidence levels, qualifiers, flags
- Edge cases and special handling

**Example (OMIM morbidmap.txt):**
- Numbers in parentheses (1-4) indicate confidence levels
- `[ ]` brackets = "nondiseases"
- `{ }` braces = susceptibility to multifactorial disorders
- `?` prefix = provisional relationship

### 8. Research Biolink Model for Appropriate Predicates and Association Types

**CRITICAL:** Cross-reference data documentation with Biolink model.

#### Load Biolink Model Using SchemaView

**The pattern for researching Biolink model predicates and classes:**

```python
from importlib.resources import files
from linkml_runtime.utils.schemaview import SchemaView

# Load Biolink model from installed biolink_model package
biolink_yaml = files('biolink_model.schema') / 'biolink_model.yaml'
sv = SchemaView(str(biolink_yaml))

# Look up predicates (slots in LinkML terminology)
slot = sv.get_slot("causes")
print(f"Description: {slot.description}")
print(f"Parent: {slot.is_a}")
print(f"Exact mappings: {slot.exact_mappings}")  # RO terms here!
print(f"Domain: {slot.domain}")
print(f"Range: {slot.range}")

# Look up association classes
cls = sv.get_class("causal gene to disease association")
print(f"Description: {cls.description}")
print(f"Parent: {cls.is_a}")

# List all available predicates/slots
all_slots = sv.all_slots()
print([s for s in all_slots if 'predispose' in s.lower()])
print([s for s in all_slots if 'cause' in s.lower()])
```

**Why use SchemaView instead of docs?**
- ✅ Get exact mappings to RO terms
- ✅ See parent/child relationships between predicates
- ✅ Discover related predicates you might not know about
- ✅ Access programmatically for validation scripts
- ✅ Always reflects the installed biolink model version

**Map data semantics to Biolink:**
1. Check predicate **descriptions** - does it match your relationship?
2. Check predicate **exact_mappings** - what RO term does it map to?
3. Check predicate **parent** (is_a) - understand hierarchy
4. Determine which **association class** to use
5. Match data confidence levels/markers to appropriate predicates

**Example mapping (OMIM):**
- Confidence (3) "molecular basis known" → `CausalGeneToDiseaseAssociation` + `biolink:causes` (RO:0003303)
- Confidence (1)/(2) → `CorrelatedGeneToDiseaseAssociation` + `biolink:contributes_to` (RO:0002326)
- Susceptibility {braces} → `biolink:predisposes_to_condition`

### 8.5. Validate Predicate Choices with Relation Ontology (RO) Terms

**CRITICAL:** When choosing between similar predicates, research the actual RO terms to justify your choice.

#### Check Biolink Mappings to RO

Use SchemaView to see what RO terms predicates map to:

```python
from importlib.resources import files
from linkml_runtime.utils.schemaview import SchemaView

biolink_yaml = files('biolink_model.schema') / 'biolink_model.yaml'
sv = SchemaView(str(biolink_yaml))

# Compare candidate predicates
predisposes = sv.get_slot("predisposes to condition")
print(f"Description: {predisposes.description}")
print(f"Exact mappings: {predisposes.exact_mappings}")
print(f"Broad mappings: {predisposes.broad_mappings}")

contributes = sv.get_slot("contributes to")
print(f"Description: {contributes.description}")
print(f"Exact mappings: {contributes.exact_mappings}")
print(f"Narrow mappings: {contributes.narrow_mappings}")
```

#### Search Ontology Lookup Service (OLS) for RO Terms

Use the OLS API (available at `https://www.ebi.ac.uk/ols4/api/mcp`) to look up RO terms and their definitions.

**Use WebFetch to search OLS:**

```bash
# Search for concept-related RO terms
WebFetch: https://www.ebi.ac.uk/ols4/api/search?q=susceptibility&ontology=ro
Prompt: "List all matching RO terms with their IDs, labels, and definitions"

WebFetch: https://www.ebi.ac.uk/ols4/api/search?q=predisposition&ontology=ro
Prompt: "List all matching RO terms with their IDs, labels, and definitions"

# Look up specific RO term by ID
WebFetch: https://www.ebi.ac.uk/ols4/api/search?q=RO:0019501
Prompt: "Get full details for this RO term including definition, synonyms, and related terms"

WebFetch: https://www.ebi.ac.uk/ols4/api/search?q=RO:0002326
Prompt: "Get full details for this RO term including definition, synonyms, and related terms"
```

**Example findings from OLS:**
- **RO:0019501** "confers susceptibility to condition": "Relates a gene to condition, such that a variation in this gene predisposes to the development of a condition"
- **RO:0002326** "contributes to": General contribution relationship (e.g., enzyme subunits contributing to enzyme activity)
- **RO:0003303** "causes": Direct causation
- **RO:0004015** "is causal susceptibility factor for": Necessary but not sufficient for disease development

**Key principle:** If RO has a **specific term** for your relationship type (e.g., RO:0019501 for susceptibility), that indicates the relationship is semantically distinct and should use a specific predicate rather than a generic one.

#### Document Your Justification

Create `docs/predicate_justification.md` documenting:

1. **Each predicate choice with RO evidence**
   - What data indicator triggers this predicate
   - Which Biolink predicate you chose
   - What RO term it maps to
   - The RO term's definition

2. **Why alternative predicates were rejected**
   - What other predicates were considered
   - Why they don't fit the semantics
   - RO evidence showing the distinction

3. **Examples from your data**
   - Show actual data rows with the relationship
   - Demonstrate why the predicate choice is correct

4. **Priority rules** (if applicable)
   - When multiple indicators are present, which takes precedence
   - Justification for the priority

**Example structure:**
```markdown
# Predicate Selection Rationale

## Predicate Assignment Rules

| Data Indicator | Predicate | RO Term | Rationale |
|----------------|-----------|---------|-----------|
| Confidence (3) | biolink:causes | RO:0003303 | Molecular basis = causation |
| `{}` markers | biolink:predisposes_to_condition | RO:0019501* | Susceptibility markers |

## Critical Decision: predisposes_to_condition vs contributes_to

### RO Evidence

**RO:0019501** - "confers susceptibility to condition"
Definition: "Relates a gene to condition, such that a variation
in this gene predisposes to the development of a condition"

**RO:0002326** - "contributes to"
Definition: General contribution relationship (e.g., enzyme
subunits contributing to enzyme activity)

### Key Finding
RO explicitly separates susceptibility (RO:0019501) from general
contribution (RO:0002326), proving susceptibility is semantically
distinct and requires a specific predicate.

### Examples from Data
{?Schizophrenia susceptibility 18}, 615232 (3)
{?Breast cancer susceptibility}, 114480 (1)

All use "susceptibility" terminology explicitly.
```

**Pattern:** Strong predicate justification = Biolink description + RO term definition + data examples

### 9. Create Unit Tests with Actual Data (BEFORE Implementing Transform)

**CRITICAL: Tests come BEFORE implementation!**

Create test file with fixtures using actual data rows that cover all edge cases:

```python
import pytest
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../src'))
from biolink_model.datamodel.pydanticmodel_v2 import GeneToDiseaseAssociation
from <project_slug>.transform import transform_record

@pytest.fixture
def standard_row_entities():
    """Standard row with expected behavior."""
    row = {
        "Column1": "value1",
        "Column2": "value2",
    }
    # Pass None for koza_transform since we don't use maps/lookups
    # (Note: pass actual koza_transform if transform uses get_map())
    return transform_record(None, row)

def test_standard_case(standard_row_entities):
    """Test standard case."""
    assert standard_row_entities
    assert len(standard_row_entities) == 1

    association = standard_row_entities[0]
    assert isinstance(association, GeneToDiseaseAssociation)
    assert association.subject == "EXPECTED:ID"
    assert association.object == "EXPECTED:ID"
    assert association.predicate == "biolink:expected_predicate"
```

**Testing pattern notes:**
- Call `transform_record(None, row)` directly for transforms without maps
- Pass actual `koza_transform` object if transform uses `get_map()` for lookups
- Create fixtures for ALL edge cases found in documentation research
- Tests should FAIL initially (since transform not implemented yet)

### 10. Implement transform.py

Now implement the actual transform logic based on:
- Test expectations
- Data format documentation
- Biolink model mappings

```python
import uuid
import re
from typing import Any

import koza
from koza import KozaTransform
from biolink_model.datamodel.pydanticmodel_v2 import (
    CausalGeneToDiseaseAssociation,
    CorrelatedGeneToDiseaseAssociation
)

@koza.transform_record()
def transform_record(koza_transform: KozaTransform, row: dict[str, Any]) -> list:
    """Transform data row into Biolink entities/associations."""

    # Parse and extract IDs
    # Handle special cases (brackets, question marks, etc.)
    # Determine appropriate association type and predicate
    # Create and return associations

    return [association]
```

### 11. Run Complete Pipeline and Verify Tests Pass

```bash
# Run tests
poetry run pytest tests/ -v

# Run full transform
poetry run ingest transform

# Check output
ls -lh output/
```

### 12. Document Nodes/Edges Produced and Decisions Made

Create documentation describing:
- **What entities/associations are produced**
- **Categories used** (e.g., CausalGeneToDiseaseAssociation)
- **Predicates used** and why (reference biolink model and RO mappings)
- **Field mappings** (which input fields populate which output fields)
- **Edge cases handled** (special symbols, missing data, etc.)
- **Decisions made** (what to include/exclude, how to handle ambiguous cases)

## Key Patterns Summary

1. **Always configure YAML first, test with printed records before writing transform code**
2. **Research data format documentation thoroughly**
3. **Cross-reference with Biolink model using SchemaView**
4. **Validate predicate choices with RO terms from OLS** - if RO has a specific term for your relationship, use a specific predicate
5. **Document predicate justification** with RO evidence in `docs/predicate_justification.md`
6. **Write tests BEFORE implementation, using actual data rows**
7. **Test pattern: `transform_record(None, row)` unless using maps, then pass `koza_transform`**
8. **Comment character + header_mode + header_prefix pattern for messy headers**
9. **Document all decisions and mappings**
