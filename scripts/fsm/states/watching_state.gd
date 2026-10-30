extends PetState
## WATCHING: a game or full-screen app is in front (see GameWatcher). She lies on the
## taskbar in comfy clothes and watches quietly: no wandering and no chatter, though
## she still answers when clicked. GameWatcher sends her back to IDLE afterwards.


func enter(_msg: Dictionary = {}) -> void:
	pet.position.y = pet.floor_y
	pet.lying = true
	pet.play_anim(&"lie")


func exit() -> void:
	pet.lying = false
