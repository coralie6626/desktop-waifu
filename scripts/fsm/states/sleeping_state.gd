extends PetState
## SLEEPING: lying on the taskbar with little z's drifting up, until the SleepSchedule
## wakes her in the morning (or an alarm does). Normally under her blanket; kept up past
## her limit she dozes off without one ({"blanket": false}) until you tuck her in.
## A click only half-wakes her (see PetReactions); picking her up wakes her properly.

var has_blanket := true


func enter(msg: Dictionary = {}) -> void:
	pet.position.y = pet.floor_y
	pet.lying = true
	has_blanket = msg.get("blanket", true)
	pet.play_anim(&"sleep" if has_blanket else &"doze")
	pet.zzz.start()
	SaveData.unlock_memory("first_sleep")


func exit() -> void:
	pet.lying = false
	pet.zzz.stop()


## Puts the blanket over her, with a sleepy thank-you.
func tuck_in() -> void:
	if has_blanket:
		return
	has_blanket = true
	pet.play_anim(&"sleep")
	pet.say_line(&"tucked_in")
	SaveData.unlock_memory("first_tuck_in")
	Affection.add(1)
