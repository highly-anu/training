# Training System MCP Server

A local MCP server that lets an AI agent produce new package YAML files without reading documentation. The agent queries valid values, gets templates, writes files, and validates — all via tools.

## Why

The `docs/author-guide.md` is written for humans. For an AI agent producing a new package, the efficient loop is:

1. Query what values are valid (modalities, intensity levels, etc.)
2. Get a skeleton template for the package type
3. Write the YAML files
4. Validate against schemas — get structured errors back
5. Fix and re-validate

The author-guide can't support steps 1, 3, or 4. The MCP server replaces it for agentic workflows.

---

## Setup

### Install

```bash
pip install mcp pyyaml jsonschema
```

### Register with Claude Desktop

**Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
**Windows:** `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "training": {
      "command": "python",
      "args": ["C:/Users/65469/programming/training/mcp_server.py"]
    }
  }
}
```

Restart Claude Desktop after editing the config. The server is spawned as a child process — no network exposure, no auth needed.

### Register with Claude Code (CLI)

```bash
claude mcp add --transport stdio training -- python C:/Users/65469/programming/training/mcp_server.py
```

---

## Tools to implement

### Query tools (read-only)

```python
@tool
def list_modality_ids() -> list[str]:
    """Return the 12 valid modality IDs."""

@tool
def list_philosophy_ids() -> list[str]:
    """Return IDs of all existing philosophies — use to avoid ID collisions."""

@tool
def list_framework_ids() -> list[str]:
    """Return IDs of all existing frameworks."""

@tool
def list_archetype_ids() -> list[str]:
    """Return all existing archetype IDs with their modality and package."""

@tool
def list_valid_values(field: str) -> list[str]:
    """
    Return valid enum values for a named field.
    Supported: intensity, slot_type, training_level, training_phase,
               equipment, exercise_category, intensity_model,
               progression_philosophy, movement_pattern_alias
    """
```

### Template tools

```python
@tool
def get_package_template(package_name: str) -> dict[str, str]:
    """
    Return skeleton YAML content for a new package.
    Keys are relative file paths, values are YAML strings with all
    required fields present and optional fields commented out.
    e.g. {"philosophy.yaml": "...", "frameworks/main.yaml": "..."}
    """

@tool
def get_archetype_template(modality: str, slot_type: str) -> str:
    """Return a skeleton archetype YAML for the given modality and slot type."""
```

### Validation tools

```python
@tool
def validate_yaml(entity_type: str, yaml_content: str) -> dict:
    """
    Validate a YAML string against the JSON schema for entity_type.
    entity_type: philosophy | framework | archetype | exercise | goal_profile
    Returns: {"valid": bool, "errors": [{"path": str, "message": str}]}
    """

@tool
def validate_package(package_path: str) -> dict:
    """
    Validate all files in a package directory.
    Checks: schema conformance, cross-reference integrity (modality IDs,
    philosophy IDs, framework IDs), ID uniqueness across all packages.
    Returns: {"valid": bool, "files": {filename: [errors]}}
    """

@tool
def check_id_available(entity_type: str, proposed_id: str) -> dict:
    """
    Check whether a proposed ID is already in use.
    Returns: {"available": bool, "conflict": str | null}
    """
```

### Cross-reference tools

```python
@tool
def get_package_summary(package_name: str) -> dict:
    """
    Return a summary of an existing package: philosophy fields,
    framework modalities + sessions_per_week, archetype count by modality,
    exercise count. Useful for understanding what a package contains
    before extending or referencing it.
    """
```

---

## Implementation notes

- **Server file:** `mcp_server.py` at project root
- **Schemas:** load from `docs/schemas/*.schema.json`
- **Data:** load via `src/loader.py` functions (already handles package globbing)
- **Validation:** use `jsonschema` library against the schema files
- **Cross-reference checks** (things schemas can't enforce):
  - `framework.source_philosophy` must match an existing philosophy ID
  - `archetype.modality` must be in the 12 valid modality IDs
  - `philosophy.avoid_with` items must be valid modality IDs
  - Exercise `requires`/`unlocks` must reference existing exercise IDs
  - Archetype IDs must be unique across all packages

---

## Agentic workflow (intended use)

When asked to create a new package (e.g. "add triathlon prep"):

```
1. list_philosophy_ids()          → confirm "triathlon" not taken
2. list_modality_ids()            → get valid modalities to use in scope/bias
3. get_package_template("triathlon") → get skeleton files
4. [write philosophy.yaml]
5. validate_yaml("philosophy", content) → fix any errors
6. [write frameworks/triathlon.yaml]
7. validate_yaml("framework", content)
8. [write archetypes + exercises]
9. validate_package("data/packages/triathlon") → final check
```

No doc-reading required. The agent only reads what it needs, when it needs it.

---

## Related files

- `docs/schemas/` — JSON Schema files the validator uses
- `docs/author-guide.md` — human-readable equivalent of this server
- `src/loader.py` — data loading logic the server can reuse
- `data/packages/` — package directory the server validates against
