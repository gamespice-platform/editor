class_name DotEditorDocument
extends RefCounted

## A map document under construction: the items a build mode has placed, and the one door every edit goes
## through. [method place], [method move] and [method remove] check the actor's right, the prop, the
## bounds, the scale and the budgets, and refuse with a reason; nothing is clamped silently. The document
## is plain data ([method to_dict] / [method from_dict]), so a server holds the truth and a client shows it,
## and publishing is GameSpice Cloud's job, not this class's.
##
## Item: {id: int, prop: String, pos: [x, y, z], yaw: float, scale: float, by: String}

const VERSION := 1

var config: DotEditorConfig = DotEditorConfig.new()
var title: String = ""
var owner: String = ""
var editors: PackedStringArray = PackedStringArray()
## prop id to cost; a prop not listed costs config.default_prop_cost.
var costs: Dictionary = {}
## Optional Callable(prop: String) -> bool; the catalogue (GameSpice Props, a pack) says which ids exist. Empty accepts any id the config allows.
var knows: Callable = Callable()

var _items: Dictionary = {}
var _next_id: int = 1


func count() -> int:
	return _items.size()


func item(id: int) -> Dictionary:
	return (_items.get(id, {}) as Dictionary).duplicate()


func items() -> Array:
	var out: Array = []
	var ids: Array = _items.keys()
	ids.sort()
	for id: int in ids:
		out.append((_items[id] as Dictionary).duplicate())
	return out


func total_cost() -> float:
	var c := 0.0
	for id: int in _items:
		c += cost_of(str((_items[id] as Dictionary)["prop"]))
	return c


func cost_of(prop: String) -> float:
	return float(costs.get(prop, config.default_prop_cost))


func count_by(actor: String) -> int:
	var n := 0
	for id: int in _items:
		if str((_items[id] as Dictionary)["by"]) == actor:
			n += 1
	return n


func set_title(actor: String, text: String) -> DotResult:
	var gate := _gate(actor)
	if not gate.ok:
		return gate
	if config.max_name_length > 0 and text.length() > config.max_name_length:
		return DotResult.fail(DotError.CODE_INVALID, "a title is at most %d characters" % config.max_name_length)
	title = text
	return DotResult.success(text)


## Success carries the new item's id.
func place(actor: String, prop: String, pos: Vector3, yaw: float = 0.0, scale: float = 1.0) -> DotResult:
	var gate := _gate(actor)
	if not gate.ok:
		return gate
	if prop.is_empty() or (not config.allowed_props.is_empty() and not config.allowed_props.has(prop)) or (knows.is_valid() and not bool(knows.call(prop))):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "prop '%s' cannot be placed here" % prop)
	var shape := _shape(pos, scale)
	if not shape.ok:
		return shape
	if config.max_items > 0 and _items.size() >= config.max_items:
		return DotResult.fail(DotError.CODE_QUOTA, "the document is full: %d items" % config.max_items)
	if config.max_items_per_actor > 0 and count_by(actor) >= config.max_items_per_actor:
		return DotResult.fail(DotError.CODE_QUOTA, "%s has placed %d items already" % [actor, config.max_items_per_actor])
	if config.max_cost > 0.0 and total_cost() + cost_of(prop) > config.max_cost:
		return DotResult.fail(DotError.CODE_QUOTA, "over the budget: %.1f of %.1f" % [total_cost() + cost_of(prop), config.max_cost])
	var id := _next_id
	_next_id += 1
	var p := shape.value as Vector3
	_items[id] = {"id": id, "prop": prop, "pos": [p.x, p.y, p.z], "yaw": fposmod(yaw, 360.0), "scale": scale, "by": actor}
	return DotResult.success(id)


func move(actor: String, id: int, pos: Vector3, yaw: float = NAN) -> DotResult:
	var gate := _gate(actor)
	if not gate.ok:
		return gate
	if not _items.has(id):
		return DotResult.fail(DotError.CODE_INVALID, "no item %d" % id)
	var it: Dictionary = _items[id]
	var shape := _shape(pos, float(it["scale"]))
	if not shape.ok:
		return shape
	var p := shape.value as Vector3
	it["pos"] = [p.x, p.y, p.z]
	if not is_nan(yaw):
		it["yaw"] = fposmod(yaw, 360.0)
	return DotResult.success(id)


func remove(actor: String, id: int) -> DotResult:
	var gate := _gate(actor)
	if not gate.ok:
		return gate
	if not _items.has(id):
		return DotResult.fail(DotError.CODE_INVALID, "no item %d" % id)
	_items.erase(id)
	return DotResult.success(id)


func to_dict() -> Dictionary:
	return {"version": VERSION, "title": title, "owner": owner, "editors": Array(editors), "items": items()}


## Loads a document that came off a disk or the wire. Every item is checked like a fresh placement
## (without the actor's right), so a hand-edited file cannot slip past the bounds or the budgets.
func load_dict(d: Variant) -> DotResult:
	if not d is Dictionary or int((d as Dictionary).get("version", 0)) != VERSION or not (d as Dictionary).get("items") is Array:
		return DotResult.fail(DotError.CODE_PARSE, "not a version %d editor document" % VERSION)
	var doc: Dictionary = d
	var fresh := DotEditorDocument.new()
	fresh.config = config
	fresh.costs = costs
	fresh.knows = knows
	fresh.title = str(doc.get("title", ""))
	fresh.owner = str(doc.get("owner", ""))
	for e: Variant in doc.get("editors", []):
		fresh.editors.append(str(e))
	if fresh.owner.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "a document needs an owner")
	var top := 0
	for raw: Variant in doc["items"]:
		if not raw is Dictionary or not (raw as Dictionary).get("pos") is Array or ((raw as Dictionary)["pos"] as Array).size() != 3:
			return DotResult.fail(DotError.CODE_INVALID, "an item needs a prop and a three number pos")
		var r: Dictionary = raw
		var pa: Array = r["pos"]
		var by := str(r.get("by", fresh.owner))
		var placed := fresh._place_as_owner(by, str(r.get("prop", "")), Vector3(float(pa[0]), float(pa[1]), float(pa[2])), float(r.get("yaw", 0.0)), float(r.get("scale", 1.0)))
		if not placed.ok:
			return placed
		var id := int(r.get("id", 0))
		if id > 0 and id != int(placed.value) and not fresh._items.has(id):
			var it: Dictionary = fresh._items[int(placed.value)]
			fresh._items.erase(int(placed.value))
			it["id"] = id
			fresh._items[id] = it
		top = maxi(top, id)
	fresh._next_id = maxi(fresh._next_id, top + 1)
	title = fresh.title
	owner = fresh.owner
	editors = fresh.editors
	_items = fresh._items
	_next_id = fresh._next_id
	return DotResult.success(_items.size())


func _place_as_owner(by: String, prop: String, pos: Vector3, yaw: float, scale: float) -> DotResult:
	var saved := owner
	owner = by
	var r := place(by, prop, pos, yaw, scale)
	owner = saved
	return r


func _gate(actor: String) -> DotResult:
	if not DotEditorPermissions.may_edit(config, owner, editors, actor):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "%s may not edit this document" % (actor if not actor.is_empty() else "nobody"))
	return DotResult.success()


func _shape(pos: Vector3, scale: float) -> DotResult:
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z) or is_nan(scale):
		return DotResult.fail(DotError.CODE_INVALID, "a position and scale must be numbers")
	if scale < config.min_scale or scale > config.max_scale:
		return DotResult.fail(DotError.CODE_INVALID, "scale %.2f is outside %.2f to %.2f" % [scale, config.min_scale, config.max_scale])
	var p := pos
	if config.grid_snap > 0.0:
		p = (pos / config.grid_snap).round() * config.grid_snap
	if config.bounds_m > 0.0 and maxf(absf(p.x), maxf(absf(p.y), absf(p.z))) > config.bounds_m:
		return DotResult.fail(DotError.CODE_INVALID, "position %s is outside %.0f m of the origin" % [p, config.bounds_m])
	return DotResult.success(p)
