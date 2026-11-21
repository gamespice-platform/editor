class_name GSEditorDocument
extends RefCounted

## A map document under construction: the items a build mode has placed, and the one door every edit goes
## through. [method place], [method move] and [method remove] check the actor's right, the prop, the
## bounds, the scale and the budgets, and refuse with a reason; nothing is clamped silently. The document
## is plain data ([method to_dict] / [method from_dict]), so a server holds the truth and a client shows it,
## and publishing is GameSpice Cloud's job, not this class's.
##
## Item: {id: int, prop: String, pos: [x, y, z], yaw: float, scale: float, by: String}

const VERSION := 1

## An item was placed, moved, scaled or removed (`kind` is "place", "move", "scale" or "remove"), or the document was cleared or loaded (id 0).
signal changed(kind: String, id: int)

var config: GSEditorConfig = GSEditorConfig.new()
var title: String = ""
var owner: String = ""
var editors: PackedStringArray = PackedStringArray()
## prop id to cost; a prop not listed costs config.default_prop_cost.
var costs: Dictionary = {}
## Optional Callable(prop: String) -> bool; the catalogue (GameSpice Props, a pack) says which ids exist. Empty accepts any id the config allows.
var knows: Callable = Callable()

## Counts every change; a client that remembers it knows whether its copy is stale.
var revision: int = 0

var _items: Dictionary = {}
var _next_id: int = 1
# Running totals, so a placement does not walk every item to check its budgets.
var _item_cost: Dictionary = {}
var _total: float = 0.0
var _per_actor: Dictionary = {}


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


func has_item(id: int) -> bool:
	return _items.has(id)


## Cost of everything placed, as it was priced when each item went in.
func total_cost() -> float:
	return _total


func cost_of(prop: String) -> float:
	return float(costs.get(prop, config.default_prop_cost))


func count_by(actor: String) -> int:
	return int(_per_actor.get(actor, 0))


## Ids of the items within `radius` metres of `pos`, in no fixed order.
func find_near(pos: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r2 := radius * radius
	for id: int in _items:
		var a: Array = (_items[id] as Dictionary)["pos"]
		var dx := float(a[0]) - pos.x
		var dy := float(a[1]) - pos.y
		var dz := float(a[2]) - pos.z
		if dx * dx + dy * dy + dz * dz <= r2:
			out.append(id)
	return out


func set_title(actor: String, text: String) -> GSResult:
	var gate := _gate(actor)
	if not gate.ok:
		return gate
	if config.max_name_length > 0 and text.length() > config.max_name_length:
		return GSResult.fail(GSError.CODE_INVALID, "a title is at most %d characters" % config.max_name_length)
	title = text
	return GSResult.success(text)


## Success carries the new item's id.
func place(actor: String, prop: String, pos: Vector3, yaw: float = 0.0, scale: float = 1.0) -> GSResult:
	var gate := _gate(actor)
	if not gate.ok:
		return gate
	if prop.is_empty() or (not config.allowed_props.is_empty() and not config.allowed_props.has(prop)) or (knows.is_valid() and not bool(knows.call(prop))):
		return GSResult.fail(GSError.CODE_FORBIDDEN, "prop '%s' cannot be placed here" % prop)
	var shape := _shape(pos, scale)
	if not shape.ok:
		return shape
	if config.max_items > 0 and _items.size() >= config.max_items:
		return GSResult.fail(GSError.CODE_QUOTA, "the document is full: %d items" % config.max_items)
	if config.max_items_per_actor > 0 and count_by(actor) >= config.max_items_per_actor:
		return GSResult.fail(GSError.CODE_QUOTA, "%s has placed %d items already" % [actor, config.max_items_per_actor])
	var price := cost_of(prop)
	if config.max_cost > 0.0 and _total + price > config.max_cost:
		return GSResult.fail(GSError.CODE_QUOTA, "over the budget: %.1f of %.1f" % [_total + price, config.max_cost])
	var id := _next_id
	_next_id += 1
	var p := shape.value as Vector3
	_items[id] = {"id": id, "prop": prop, "pos": [p.x, p.y, p.z], "yaw": fposmod(yaw, 360.0), "scale": scale, "by": actor}
	_item_cost[id] = price
	_total += price
	_per_actor[actor] = int(_per_actor.get(actor, 0)) + 1
	_touch("place", id)
	return GSResult.success(id)


func move(actor: String, id: int, pos: Vector3, yaw: float = NAN) -> GSResult:
	var gate := _gate(actor)
	if not gate.ok:
		return gate
	if not _items.has(id):
		return GSResult.fail(GSError.CODE_INVALID, "no item %d" % id)
	var it: Dictionary = _items[id]
	var shape := _shape(pos, float(it["scale"]))
	if not shape.ok:
		return shape
	var p := shape.value as Vector3
	it["pos"] = [p.x, p.y, p.z]
	if not is_nan(yaw):
		it["yaw"] = fposmod(yaw, 360.0)
	_touch("move", id)
	return GSResult.success(id)


## Changes an item's scale, within the scale limits.
func set_scale(actor: String, id: int, scale: float) -> GSResult:
	var gate := _gate(actor)
	if not gate.ok:
		return gate
	if not _items.has(id):
		return GSResult.fail(GSError.CODE_INVALID, "no item %d" % id)
	var it: Dictionary = _items[id]
	var p: Array = it["pos"]
	var shape := _shape(Vector3(float(p[0]), float(p[1]), float(p[2])), scale)
	if not shape.ok:
		return shape
	it["scale"] = scale
	_touch("scale", id)
	return GSResult.success(id)


## Places a copy of an item `offset` away, as `actor`. Success carries the new id; budgets apply.
func duplicate_item(actor: String, id: int, offset: Vector3) -> GSResult:
	if not _items.has(id):
		return GSResult.fail(GSError.CODE_INVALID, "no item %d" % id)
	var it: Dictionary = _items[id]
	var p: Array = it["pos"]
	return place(actor, str(it["prop"]), Vector3(float(p[0]), float(p[1]), float(p[2])) + offset, float(it["yaw"]), float(it["scale"]))


## Removes every item `who` placed (a player who left). Success carries how many went.
func remove_by(actor: String, who: String) -> GSResult:
	var gate := _gate(actor)
	if not gate.ok:
		return gate
	var gone := 0
	for id: int in _items.keys():
		if str((_items[id] as Dictionary)["by"]) == who:
			_drop(id)
			gone += 1
	if gone > 0:
		_touch("remove", 0)
	return GSResult.success(gone)


## Removes everything. Success carries how many items went.
func clear(actor: String) -> GSResult:
	var gate := _gate(actor)
	if not gate.ok:
		return gate
	var n := _items.size()
	_reset_items()
	_touch("remove", 0)
	return GSResult.success(n)


## What changed from `older` (a [method to_dict] result) to now: `{added: [ids], removed: [ids], changed: [ids]}`,
## so a server can send a client only the difference.
func diff_from(older: Dictionary) -> Dictionary:
	var before := {}
	for raw: Variant in older.get("items", []):
		if raw is Dictionary and (raw as Dictionary).has("id"):
			before[int((raw as Dictionary)["id"])] = raw
	var added: Array = []
	var changed_ids: Array = []
	for id: int in _items:
		if not before.has(id):
			added.append(id)
		elif (before[id] as Dictionary).hash() != (_items[id] as Dictionary).hash():
			changed_ids.append(id)
	var removed: Array = []
	for id: int in before:
		if not _items.has(id):
			removed.append(id)
	added.sort()
	removed.sort()
	changed_ids.sort()
	return {"added": added, "removed": removed, "changed": changed_ids}


func remove(actor: String, id: int) -> GSResult:
	var gate := _gate(actor)
	if not gate.ok:
		return gate
	if not _items.has(id):
		return GSResult.fail(GSError.CODE_INVALID, "no item %d" % id)
	_drop(id)
	_touch("remove", id)
	return GSResult.success(id)


func to_dict() -> Dictionary:
	return {"version": VERSION, "title": title, "owner": owner, "editors": Array(editors), "items": items()}


## Loads a document that came off a disk or the wire. Every item is checked like a fresh placement
## (without the actor's right), so a hand-edited file cannot slip past the bounds or the budgets.
func load_dict(d: Variant) -> GSResult:
	if not d is Dictionary or int((d as Dictionary).get("version", 0)) != VERSION or not (d as Dictionary).get("items") is Array:
		return GSResult.fail(GSError.CODE_PARSE, "not a version %d editor document" % VERSION)
	var doc: Dictionary = d
	var fresh := GSEditorDocument.new()
	fresh.config = config
	fresh.costs = costs
	fresh.knows = knows
	fresh.title = str(doc.get("title", ""))
	fresh.owner = str(doc.get("owner", ""))
	for e: Variant in doc.get("editors", []):
		fresh.editors.append(str(e))
	if fresh.owner.is_empty():
		return GSResult.fail(GSError.CODE_INVALID, "a document needs an owner")
	var top := 0
	for raw: Variant in doc["items"]:
		if not raw is Dictionary or not (raw as Dictionary).get("pos") is Array or ((raw as Dictionary)["pos"] as Array).size() != 3:
			return GSResult.fail(GSError.CODE_INVALID, "an item needs a prop and a three number pos")
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
			fresh._item_cost[id] = fresh._item_cost[int(placed.value)]
			fresh._item_cost.erase(int(placed.value))
		top = maxi(top, id)
	fresh._next_id = maxi(fresh._next_id, top + 1)
	title = fresh.title
	owner = fresh.owner
	editors = fresh.editors
	_items = fresh._items
	_item_cost = fresh._item_cost
	_total = fresh._total
	_per_actor = fresh._per_actor
	_next_id = fresh._next_id
	_touch("load", 0)
	return GSResult.success(_items.size())


func _touch(kind: String, id: int) -> void:
	revision += 1
	changed.emit(kind, id)


func _drop(id: int) -> void:
	var by := str((_items[id] as Dictionary)["by"])
	_total -= float(_item_cost.get(id, 0.0))
	_item_cost.erase(id)
	_items.erase(id)
	var n := int(_per_actor.get(by, 0)) - 1
	if n > 0:
		_per_actor[by] = n
	else:
		_per_actor.erase(by)


func _reset_items() -> void:
	_items.clear()
	_item_cost.clear()
	_per_actor.clear()
	_total = 0.0


func _place_as_owner(by: String, prop: String, pos: Vector3, yaw: float, scale: float) -> GSResult:
	var saved := owner
	owner = by
	var r := place(by, prop, pos, yaw, scale)
	owner = saved
	return r


func _gate(actor: String) -> GSResult:
	if not GSEditorPermissions.may_edit(config, owner, editors, actor):
		return GSResult.fail(GSError.CODE_FORBIDDEN, "%s may not edit this document" % (actor if not actor.is_empty() else "nobody"))
	return GSResult.success()


func _shape(pos: Vector3, scale: float) -> GSResult:
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z) or is_nan(scale):
		return GSResult.fail(GSError.CODE_INVALID, "a position and scale must be numbers")
	if scale < config.min_scale or scale > config.max_scale:
		return GSResult.fail(GSError.CODE_INVALID, "scale %.2f is outside %.2f to %.2f" % [scale, config.min_scale, config.max_scale])
	var p := pos
	if config.grid_snap > 0.0:
		p = (pos / config.grid_snap).round() * config.grid_snap
	if config.bounds_m > 0.0 and maxf(absf(p.x), maxf(absf(p.y), absf(p.z))) > config.bounds_m:
		return GSResult.fail(GSError.CODE_INVALID, "position %s is outside %.0f m of the origin" % [p, config.bounds_m])
	return GSResult.success(p)
