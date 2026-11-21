# GameSpice Editor

Godot 4.7+ addon for in-game build mode: place props, save the result as a map document, preview it and publish it through GameSpice Cloud, with server-authoritative permissions and budgets. Read the family [CLAUDE.md](../../CLAUDE.md) first. **The distributable is `addons/gs_editor/`**; it requires [GameSpice Core](../gs-core) only (`ln -s ../../gs-core/addons/gs_core addons/gs_core`, gitignored).

| Path | What |
| --- | --- |
| `core/gs_editor_config.gd` | `GSEditorConfig`: every tunable, `from_files()` |
| `core/gs_editor_permissions.gd` | `GSEditorPermissions.may_edit()`: owner, listed editors, anyone |
| `core/gs_editor_document.gd` | `GSEditorDocument`: `place`/`move`/`set_scale`/`duplicate_item`/`remove`/`remove_by`/`clear`, `find_near`, `diff_from`, `changed`+`revision`, `to_dict`/`load_dict`; permission, prop, bounds, snap, scale and budget checks |
| `examples/editor_selftest.tscn` | the suite (6 sections, 50 checks plus the two summary checks) |

- **Boundary.** gs-editor is the build-mode document, its permissions and its budgets. It is NOT gs-props (sandbox catalogue, per-player spawn limits, undo, physics gun), NOT gs-workbench (live admin edit of profiles), NOT gs-cloud (save, preview and publish, delivery) and NOT gs-map (loading a map). The catalogue is asked through `GSEditorDocument.knows`; publishing is done by the caller with gs-cloud. The server owns the document; a client's check is a hint.
- **No hard caps**: every limit is a config field, 0 means unlimited, and a refusal says why. Nothing is clamped silently.
- **No autoloads, no scene paths**, no class_name reliance in shipped scripts.
- **Validate**: `--import`, parse every `.gd`, run the suite through `hv`.
