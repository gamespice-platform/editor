extends Node
## Walk-through: build, copy, diff and clear a document.


func _ready() -> void:
	var d := DotEditorDocument.new()
	d.owner = "alice"
	d.changed.connect(func(kind: String, id: int) -> void: print("changed ", kind, " ", id))
	var crate := d.place("alice", "crate", Vector3(2, 0, 3), 45.0)
	if not crate.ok:
		push_error(crate.error.message)
		return
	var copy := d.duplicate_item("alice", crate.value, Vector3(1, 0, 0))
	var sent := d.to_dict()
	d.set_scale("alice", copy.value, 2.0)
	print("diff: ", d.diff_from(sent))
	print("near: ", d.find_near(Vector3(2, 0, 3), 5.0))
	d.clear("alice")
