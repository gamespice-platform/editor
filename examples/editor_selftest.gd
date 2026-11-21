extends Node

## dot-editor's headless suite (res://examples/editor_selftest.tscn).
## Counts sections run to their last line as well as checks, because a script error
## aborts a section and not the run.

const EXPECTED_SECTIONS := 6
const EXPECTED_CHECKS := 50

var _passed := 0
var _failed := 0
var _sections := 0


func _ready() -> void:
	print("dot-editor")
	_config()
	_permissions()
	_edits()
	_budgets()
	_roundtrip()
	_tools()
	print("")
	_check(_sections == EXPECTED_SECTIONS, "every section ran to its last line (%d of %d)" % [_sections, EXPECTED_SECTIONS])
	_check(_passed + _failed == EXPECTED_CHECKS, "and the suite ran all %d of its checks (%d)" % [EXPECTED_CHECKS, _passed + _failed])
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _doc() -> GSEditorDocument:
	var d := GSEditorDocument.new()
	d.owner = "alice"
	return d


func _config() -> void:
	var c := GSEditorConfig.new()
	_check(c.validate().ok and c.max_items == 500, "defaults validate")
	c.max_items = -1
	_check(not c.validate().ok, "a negative limit is refused, 0 means unlimited")
	c.max_items = 5
	c.min_scale = 5.0
	c.max_scale = 1.0
	_check(not c.validate().ok, "min_scale over max_scale is refused")
	var names: Array = GSEditorConfig.profile_schemas()["editor"]["schema"].map(func(f: Dictionary) -> Variant: return f["name"])
	_check(names.has("max_cost") and names.has("allowed_props") and names.size() == c.config_keys().size(), "profile schema lists every key", str(names.size()))
	var applied := c.apply_dictionary({"max_items": 9, "grid_snap": 0.5, "allowed_props": ["crate"]})
	_check(applied.size() == 3 and c.max_items == 9 and c.grid_snap == 0.5 and c.allowed_props.size() == 1, "a dictionary layer sets ints, floats and lists", str(applied))
	_check(c.env_prefix() == "DOT_EDITOR_" and c.cli_prefix() == "--editor-", "env and command-line prefixes")
	var r := GSEditorConfig.from_files()
	_check(r.ok and (r.value as GSEditorConfig).describe().begins_with("editor"), "from_files returns a config")
	_sections += 1


func _permissions() -> void:
	var c := GSEditorConfig.new()
	var eds := PackedStringArray(["bob"])
	_check(GSEditorPermissions.may_edit(c, "alice", eds, "alice") and GSEditorPermissions.may_edit(c, "alice", eds, "bob"), "the owner and a listed editor may edit")
	_check(not GSEditorPermissions.may_edit(c, "alice", eds, "carol"), "a stranger may not")
	c.who_may_edit = GSEditorConfig.new().who_may_edit
	c.who_may_edit = 0
	_check(not GSEditorPermissions.may_edit(c, "alice", eds, "bob"), "owner-only mode shuts the list out")
	c.who_may_edit = 2
	_check(GSEditorPermissions.may_edit(c, "alice", eds, "carol") and not GSEditorPermissions.may_edit(c, "alice", eds, ""), "anyone mode still needs an identity")
	c.enabled = false
	_check(not GSEditorPermissions.may_edit(c, "alice", eds, "alice"), "a disabled editor refuses everyone")
	var d := _doc()
	var r := d.place("mallory", "crate", Vector3.ZERO)
	_check(not r.ok and r.error.code == GSError.CODE_FORBIDDEN and d.count() == 0, "the document refuses a stranger's edit")
	_sections += 1


func _edits() -> void:
	var d := _doc()
	d.config.grid_snap = 0.5
	var r := d.place("alice", "crate", Vector3(1.26, 0.0, -2.9), 370.0, 2.0)
	_check(r.ok and r.value == 1 and d.count() == 1, "place returns the item id")
	var it := d.item(1)
	_check(it["pos"] == [1.5, 0.0, -3.0] and is_equal_approx(float(it["yaw"]), 10.0) and it["by"] == "alice", "the position snaps to the grid and the yaw wraps", str(it))
	_check(d.move("alice", 1, Vector3(4, 0, 4), 90.0).ok and d.item(1)["pos"] == [4.0, 0.0, 4.0] and d.item(1)["yaw"] == 90.0, "move changes position and yaw")
	_check(d.move("alice", 1, Vector3(5, 0, 5)).ok and d.item(1)["yaw"] == 90.0, "move without a yaw keeps it")
	_check(not d.move("alice", 9, Vector3.ZERO).ok, "moving an item that is not there is refused")
	_check(not d.place("alice", "crate", Vector3(900, 0, 0)).ok, "outside bounds_m is refused, not clamped")
	_check(not d.place("alice", "crate", Vector3.ZERO, 0.0, 99.0).ok and not d.place("alice", "crate", Vector3.ZERO, 0.0, 0.01).ok, "scale outside the limits is refused")
	_check(not d.place("alice", "crate", Vector3(NAN, 0, 0)).ok, "NaN is refused")
	_check(not d.move("alice", 1, Vector3(0, 9999, 0)).ok and d.item(1)["pos"] == [5.0, 0.0, 5.0], "a refused move changes nothing")
	d.config.bounds_m = 0.0
	_check(d.place("alice", "crate", Vector3(9e5, 0, 0)).ok, "bounds_m 0 is unlimited")
	_check(d.remove("alice", 1).ok and d.count() == 1 and not d.remove("alice", 1).ok, "remove removes once")
	d.config.allowed_props = PackedStringArray(["barrel"])
	_check(not d.place("alice", "crate", Vector3.ZERO).ok and d.place("alice", "barrel", Vector3.ZERO).ok, "allowed_props narrows what may be placed")
	d.config.allowed_props = PackedStringArray()
	d.knows = func(p: String) -> bool: return p != "ghost"
	_check(not d.place("alice", "ghost", Vector3.ZERO).ok and d.place("alice", "crate", Vector3.ZERO).ok, "the catalogue Callable says which props exist")
	_check(d.set_title("alice", "Docks").ok and d.title == "Docks" and not d.set_title("alice", "x".repeat(65)).ok, "titles are bounded")
	_sections += 1


func _budgets() -> void:
	var d := _doc()
	d.config.max_items = 2
	d.place("alice", "a", Vector3.ZERO)
	d.place("alice", "a", Vector3.ZERO)
	var r := d.place("alice", "a", Vector3.ZERO)
	_check(not r.ok and r.error.code == GSError.CODE_QUOTA and d.count() == 2, "max_items refuses the item past it with a quota error")
	d.config.max_items = 0
	_check(d.place("alice", "a", Vector3.ZERO).ok, "max_items 0 is unlimited")
	var e := _doc()
	e.config.who_may_edit = 2
	e.config.max_items_per_actor = 1
	_check(e.place("bob", "a", Vector3.ZERO).ok and not e.place("bob", "a", Vector3.ZERO).ok and e.place("carol", "a", Vector3.ZERO).ok, "the per-actor limit is per actor")
	var c := _doc()
	c.config.max_cost = 10.0
	c.costs = {"tree": 6.0}
	_check(c.place("alice", "tree", Vector3.ZERO).ok and c.total_cost() == 6.0, "a prop costs what the table says")
	_check(not c.place("alice", "tree", Vector3.ZERO).ok and c.place("alice", "rock", Vector3.ZERO).ok and c.total_cost() == 7.0, "cost budget refuses what would go over, and the default cost applies")
	c.remove("alice", 1)
	_check(c.total_cost() == 1.0 and c.place("alice", "tree", Vector3.ZERO).ok, "removing frees budget")
	_sections += 1


func _roundtrip() -> void:
	var d := _doc()
	d.editors = PackedStringArray(["bob"])
	d.title = "Arena"
	d.place("alice", "crate", Vector3(1, 0, 2), 45.0)
	d.place("bob", "barrel", Vector3(3, 0, 4), 0.0, 1.5)
	d.remove("alice", 1)
	var text := JSON.stringify(d.to_dict())
	var back := _doc()
	var r := back.load_dict(JSON.parse_string(text))
	_check(r.ok and back.count() == 1 and back.title == "Arena" and back.editors == PackedStringArray(["bob"]), "a document survives JSON", str(r.error.message if not r.ok else ""))
	_check(back.item(2)["prop"] == "barrel" and back.item(2)["by"] == "bob", "ids and authors are kept")
	_check(back.place("alice", "crate", Vector3.ZERO).value == 3, "new ids continue after the highest loaded")
	var tampered := d.to_dict()
	(tampered["items"] as Array)[0]["pos"] = [9999.0, 0.0, 0.0]
	var fresh := _doc()
	fresh.place("alice", "keep", Vector3.ZERO)
	_check(not fresh.load_dict(tampered).ok and fresh.count() == 1, "a hand-edited file out of bounds is refused and the document is untouched")
	var small := _doc()
	small.config.max_items = 0
	small.config.max_cost = 1.0
	var two := {"version": 1, "owner": "alice", "items": [{"prop": "a", "pos": [0, 0, 0]}, {"prop": "a", "pos": [0, 0, 0]}]}
	_check(not small.load_dict(two).ok, "a loaded document is held to the budgets too")
	_check(not _doc().load_dict({"version": 9, "items": []}).ok and not _doc().load_dict("nope").ok, "a wrong version or shape is refused")
	_sections += 1


func _tools() -> void:
	var d := _doc()
	var events: Array = []
	d.changed.connect(func(kind: String, id: int) -> void: events.append(kind + str(id)))
	d.costs = {"crate": 2.0}
	d.place("alice", "crate", Vector3(0, 0, 0))
	d.place("alice", "barrel", Vector3(10, 0, 0))
	_check(d.total_cost() == 3.0 and d.count_by("alice") == 2 and d.revision == 2 and events == ["place1", "place2"], "running totals and the revision follow placements", str(events))
	d.costs = {}
	d.remove("alice", 1)
	_check(d.total_cost() == 1.0 and d.count_by("alice") == 1 and d.has_item(2) and not d.has_item(1), "a removal gives back the price it was placed at")
	var before := d.to_dict()
	_check(d.set_scale("alice", 2, 2.0).ok and d.item(2)["scale"] == 2.0 and not d.set_scale("alice", 2, 99.0).ok and not d.set_scale("alice", 7, 1.0).ok, "set_scale changes within limits, refuses outside")
	var dup := d.duplicate_item("alice", 2, Vector3(1, 0, 0))
	_check(dup.ok and d.item(dup.value)["pos"] == [11.0, 0.0, 0.0] and d.item(dup.value)["scale"] == 2.0 and not d.duplicate_item("alice", 9, Vector3.ZERO).ok, "duplicate_item copies an item offset, budgets apply")
	var df := d.diff_from(before)
	_check(df == {"added": [dup.value], "removed": [], "changed": [2]}, "diff_from lists added, removed and changed ids", str(df))
	_check(d.find_near(Vector3(10, 0, 0), 2.0).size() == 2 and d.find_near(Vector3(-50, 0, 0), 2.0).is_empty(), "find_near finds items within a radius")
	d.editors = PackedStringArray(["bob"])
	d.place("bob", "crate", Vector3(1, 0, 0))
	_check(not d.remove_by("carol", "alice").ok, "remove_by needs the right to edit")
	var gone := d.remove_by("alice", "bob")
	_check(gone.ok and gone.value == 1 and d.count_by("bob") == 0 and d.count() == 2, "remove_by clears one actor's items")
	_check(d.clear("alice").value == 2 and d.count() == 0 and d.total_cost() == 0.0, "clear empties the document and the totals")
	var live := _doc()
	live.config.max_items_per_actor = 1
	live.place("alice", "crate", Vector3.ZERO)
	live.remove("alice", 1)
	_check(live.place("alice", "crate", Vector3.ZERO).ok, "a per-actor quota frees up when an item is removed")
	_sections += 1


func _check(ok: bool, what: String, extra: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    ", what)
	else:
		_failed += 1
		print("  FAIL  ", what, "  ", extra)
