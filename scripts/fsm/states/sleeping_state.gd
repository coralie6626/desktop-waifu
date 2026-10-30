extends PetState
## SLEEPING: lying on the taskbar under her blanket, little z's drifting up, until the
## SleepSchedule wakes her in the morning (or an alarm does). A click only half-wakes
## her (see PetReactions); picking her up wakes her properly.


func enter(_msg: Dictionary = {}) -> void:
	pet.position.y = pet.floor_y
	pet.lying = true
	pet.play_anim(&"sleep")
	pet.zzz.start()


func exit() -> void:
	pet.lying = false
	pet.zzz.stop()
