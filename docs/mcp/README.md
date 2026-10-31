# Training System MCP Server

`mcp_server.py` lets an AI agent write a package folder through tools: query what values are
valid, get templates, write files that are checked before they land, validate the package, fix,
and bring it in. Every check is the push gates' own — the server has no validator of its own.

## Setup

```bash
.venv/bin/pip install mcp                      # the SDK; pyyaml and jsonschema are already there
claude mcp add --transport stdio training -- .venv/bin/python mcp_server.py   # from the checkout
```

For Claude Desktop, the same command and argument in `claude_desktop_config.json`
(`~/Library/Application Support/Claude/` on a Mac) with absolute paths. The server is a child
process: no network exposure, no auth.

It writes where the loader reads: `data/packages/`, or `TRAINING_PACKAGES_DIR` when set (a
scratch folder for a trial package). Without the SDK the tools still import, which is how
`test_authoring.py` runs them.

## Tools

| Tool | What it does |
|---|---|
| `list_modality_ids`, `list_philosophy_ids`, `list_framework_ids`, `list_archetype_ids` | What exists |
| `list_valid_values(field)` | A field's allowed values, read from the schemas (`equipment`, `slot_type`, `intensity`, `training_phase` …) or the data (`movement_pattern`, `modality`) |
| `check_id_available(entity_type, id)` | Whether an id is taken: philosophy, framework, archetype, exercise, standard |
| `get_package_template(name)`, `get_archetype_template(modality, slot_type)` | Skeleton files with every required field |
| `validate_yaml(entity_type, content, package_name?)` | One file, as the gates check it: philosophy, framework, archetype, exercise, analytics, watch, training_contract, fidelity, source_weeks, standards |
| `write_package_file(package, path, content, overwrite?)` | Writes a file after checking it as the file it will be (a file no schema covers — media, level seeds — is written as is); never outside the packages folder |
| `validate_package(name)` | Every file (`tools/validate_entities.py`), then `tools/add_package.py`'s checks: no id another package declares, every id in the commons, the files a package needs; warns of a modality in scope no archetype serves |
| `get_package_summary(name)`, `list_package_exercises(name)` | What a package has |
| `delete_package(name)` | Removes a package folder (never one outside the packages folder) |

`validate_yaml` and `write_package_file` check a file in a scratch copy of its package, so the
checks that read the other files — a philosophy's frameworks, an archetype's standard against
what its package borrows — see them.

## Agentic workflow

When asked to create a package (e.g. "add triathlon prep"), after reading the sources
(`docs/extraction-guide.md`):

```
1. check_id_available("philosophy", "triathlon")
2. list_modality_ids(), list_valid_values("equipment") …
3. get_package_template("triathlon")             → skeleton files
4. write_package_file("triathlon", "philosophy.yaml", …)   — checked before it is written
5. write frameworks, archetypes, exercises; analytics.yaml, watch.yaml, standards.yaml as needed
6. validate_package("triathlon")                 → fix what it lists
7. .venv/bin/python tools/add_package.py triathlon --check, then without --check
```

Step 7 records the package's baselines and golden programs and stubs its dossier; the record
and the dossier are then written from the sources (`docs/package-fidelity/README.md`).

## Related files

- `docs/schemas/` — the JSON schemas; `tools/validate_entities.py` — the checks beside them
- `docs/author-guide.md` — the same for a person: the package layout and each file
- `tools/add_package.py` — bringing a folder in; `src/portability.py` — what a package carries
