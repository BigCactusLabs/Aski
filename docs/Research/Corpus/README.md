# Corpus — research inputs

Immutable, reusable input corpora for the lab experiments. Each corpus is a
subdirectory with a `manifest.yaml` (datasheet-lite) plus its assets.

## `manifest.yaml` schema

Required: `name`, `summary`, `license`, `source`, `tags` (≥1). Optional:
`created`, `asset_count`. Flat YAML only — no inline comments.

## Governance

- No corpus without tags. No asset without provenance (corpus-level `source` +
  `license`). Heterogeneous sources → split into separate corpora.
- Git LFS threshold: track any asset > ~2 MB, or a corpus > ~50 MB total, via
  `.gitattributes`.

Validated by `swift run BuildResearchIndex --check` and `swift test`.
