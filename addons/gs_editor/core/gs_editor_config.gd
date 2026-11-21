class_name GSEditorConfig
extends GSConfig

## Every tunable of Editor. Layered like any config: defaults, `cfg/addon/gs_editor/*.yml`, the game tier, `GS_EDITOR_*` environment, then `--editor-*` flags. A value of 0 on a limit means unlimited.

const ADDON := "gs-editor"

## Master switch: off, every edit is refused.
@export var enabled: bool = true

@export_group("Permissions")
## 0 only the owner edits, 1 the owner and listed editors, 2 anyone.
@export_range(0, 2, 1) var who_may_edit: int = 1
## Prop ids that may be placed; empty allows every id the catalogue knows.
@export var allowed_props: PackedStringArray = PackedStringArray()

@export_group("Budgets")
## The most items in one document. 0 is unlimited.
@export_range(0, 1000000, 1) var max_items: int = 500
## The most items one editor may have placed. 0 is unlimited.
@export_range(0, 1000000, 1) var max_items_per_actor: int = 0
## The most total cost (sum of each item's prop cost) in one document. 0 is unlimited.
@export_range(0.0, 1000000.0, 1.0) var max_cost: float = 0.0
## Cost of a prop the cost table does not list.
@export_range(0.0, 1000.0, 0.1) var default_prop_cost: float = 1.0

@export_group("Space")
## Items must sit within this many metres of the origin on every axis. 0 is unlimited.
@export_range(0.0, 100000.0, 1.0) var bounds_m: float = 500.0
## Positions snap to this grid in metres; 0 is no snapping.
@export_range(0.0, 100.0, 0.05) var grid_snap: float = 0.0
## Scale limits of one item.
@export_range(0.01, 100.0, 0.01) var min_scale: float = 0.25
@export_range(0.01, 100.0, 0.01) var max_scale: float = 4.0
## Longest document name, in characters. 0 is unlimited.
@export_range(0, 1000, 1) var max_name_length: int = 64

func env_prefix() -> String:
	return "GS_EDITOR_"


func cli_prefix() -> String:
	return "--editor-"


func validate() -> GSResult:
	for k in ["max_items", "max_items_per_actor", "max_cost", "bounds_m", "grid_snap", "max_name_length"]:
		if float(get(k)) < 0.0:
			return GSResult.fail(GSError.CODE_INVALID, "editor %s must be 0 (unlimited) or more, got %s" % [k, get(k)])
	if min_scale > max_scale:
		return GSResult.fail(GSError.CODE_INVALID, "editor min_scale %s is over max_scale %s" % [min_scale, max_scale])
	return GSResult.success(self)

func describe() -> String:
	return "editor %s who %d items<=%d cost<=%.0f bounds %.0fm snap %.2f" % [
		"on" if enabled else "disabled", who_may_edit, max_items, max_cost, bounds_m, grid_snap]


## The `editor` profile schema (the shape of GameSpice Profile's field()), read from the exports so it cannot drift; GameSpice Profile's profile_check finds it here.
static func schema() -> Array:
	var out: Array = []
	var cfg := GSEditorConfig.new()
	for prop: Dictionary in cfg.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (int(prop["usage"]) & PROPERTY_USAGE_EDITOR):
			continue
		var type := ""
		match int(prop["type"]):
			TYPE_BOOL: type = "bool"
			TYPE_INT: type = "int"
			TYPE_FLOAT: type = "float"
			TYPE_STRING: type = "string"
			TYPE_PACKED_STRING_ARRAY: type = "list"
		if type == "":
			continue
		var key := str(prop["name"])
		var def: Variant = cfg.get(key)
		var f := {"name": key, "type": type, "default": Array(def) if def is PackedStringArray else def}
		if int(prop["hint"]) == PROPERTY_HINT_RANGE and type != "string":
			var parts := str(prop["hint_string"]).split(",")
			f["min"] = parts[0].to_int() if type == "int" else parts[0].to_float()
			f["max"] = parts[1].to_int() if type == "int" else parts[1].to_float()
		out.append(f)
	return out


## Kind to schema for GameSpice Profile's profile_check (a game's `cfg/game/<game>/editor/game.yml`).
static func profile_schemas() -> Dictionary:
	return {"editor": {"schema": schema(), "children": {}}}


## Defaults, then `cfg/addon/gs_editor/*.yml` and the game tier, then environment and command line.
static func from_files() -> GSResult:
	var cfg := GSEditorConfig.new()
	var files := GSAddonConfig.load_dir(ADDON)
	if not files.ok:
		return files
	cfg.apply_dictionary(files.value as Dictionary, "yml")
	return cfg.load_layered()


