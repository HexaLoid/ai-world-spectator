extends Panel

## Renders GameState.chat_message lines (see ChatLines.format), newest at the
## bottom, trimmed to the last MAX_LINES.

const MAX_LINES := 60
const BODY_COLOR := Color(0.93, 0.88, 0.75, 1.0)

@onready var body: RichTextLabel = $Body

var line_count := 0

func _ready() -> void:
	# Dark panel (like the character sheet) so the channel colors stay readable.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.09, 0.05, 0.9)
	style.set_border_width_all(2)
	style.border_color = Color(0.55, 0.4, 0.15, 1.0)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	body.add_theme_color_override("default_color", BODY_COLOR)
	GameState.chat_message.connect(_on_chat_message)

func _on_chat_message(channel: String, speaker: String, text: String) -> void:
	if line_count >= MAX_LINES:
		body.remove_paragraph(0)
	else:
		line_count += 1
	body.append_text(ChatLines.format(channel, speaker, text) + "\n")
