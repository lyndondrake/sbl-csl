# Maintenance Scripts

These scripts are for maintainers and contributors working on the SBL citation data. They require Python 3.10+ with the dependencies in `requirements.txt`.

## Scripts

| Script | Purpose |
|--------|---------|
| `generate-annote.py` | Generate `annote` values from entrysubtype templates. Run with `--apply` to write to YAML, `--validate` to check existing values. |
| `add-annote.py` | Add `annote` fields for specific non-standard entry types (ancient texts, lexicons, etc.). |
| `add-short-fields.py` | Populate `container-title-short` and `collection-title-short` from the `sbl:` note metadata. |
| `add-title-short.py` | Add `title-short` fields based on subsequent note expected values. |
| `diagnose-failures.py` | Categorise test failures by root cause (spacing, structural, data, CSL limitation). |
| `fix-expected-values.py` | Fix PDF extraction artefacts in test expected values (collapsed words, missing spaces, hyphenation). |
| `extract-fresh-citations.py` | Extract citation text from a freshly compiled biblatex-sbl PDF for verification. Requires PyMuPDF. |

## Typical workflows

### Adding a new classical text entry

```bash
# 1. Add the entry to sbl-examples.yaml with entrysubtype: classical
# 2. Generate the annote:
python scripts/generate-annote.py --apply
# 3. Run tests to verify:
TMPDIR=.tmp/ python -m pytest tests/ -k "sbl-fullnote" --tb=short
```

### Verifying expected values against biblatex-sbl

```bash
# 1. Compile the biblatex-sbl examples (requires TeX Live):
cd .tmp/tex-build && lualatex biblatex-sbl-examples.tex && biber biblatex-sbl-examples && lualatex biblatex-sbl-examples.tex
# 2. Extract and compare:
python scripts/extract-fresh-citations.py
```

### Diagnosing test failures

```bash
python scripts/diagnose-failures.py
```
