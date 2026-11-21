class_name DotEditorPermissions
extends RefCounted

## Who may change a document. The server asks this before every edit; a client's own check is only a hint.

const OWNER_ONLY := 0
const LISTED := 1
const ANYONE := 2


static func may_edit(cfg: DotEditorConfig, owner: String, editors: PackedStringArray, actor: String) -> bool:
	if not cfg.enabled or actor.is_empty():
		return false
	if actor == owner:
		return true
	match cfg.who_may_edit:
		LISTED: return editors.has(actor)
		ANYONE: return true
	return false
