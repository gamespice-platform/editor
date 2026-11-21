# GameSpice Editor

Godot 4.7+ addon for in-game build mode: place props, save the result as a map document, preview it and publish it through GameSpice Cloud, with server-authoritative permissions and budgets. Read the family [CLAUDE.md](../../CLAUDE.md) first. **The distributable is `addons/dot_editor/`**; it requires [GameSpice Core](../dot-core) only (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored).

| Path | What |
| --- | --- |
| `core/dot_editor_config.gd` | `DotEditorConfig`: every tunable, `from_files()` |
| `core/dot_editor_permissions.gd` | `DotEditorPermissions.may_edit()`: owner, listed editors, anyone |
| `core/dot_editor_document.gd` | `DotEditorDocument`: `place`/`move`/`remove`, `to_dict`/`load_dict`; permission, prop, bounds, snap, scale and budget checks |
| `examples/editor_selftest.tscn` | the suite (5 sections, 40 checks plus the two summary checks) |

- **Boundary.** dot-editor is the build-mode document, its permissions and its budgets. It is NOT dot-props (sandbox catalogue, per-player spawn limits, undo, physics gun), NOT dot-workbench (live admin edit of profiles), NOT dot-cloud (save, preview and publish, delivery) and NOT dot-map (loading a map). The catalogue is asked through `DotEditorDocument.knows`; publishing is done by the caller with dot-cloud. The server owns the document; a client's check is a hint.
- **No hard caps**: every limit is a config field, 0 means unlimited, and a refusal says why. Nothing is clamped silently.
- **No autoloads, no scene paths**, no class_name reliance in shipped scripts.
- **Validate**: `--import`, parse every `.gd`, run the suite through `hv`.
