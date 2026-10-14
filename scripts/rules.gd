class_name Rules
extends RefCounted
## 8-ball rules: judges a finished shot. Groups are "", "solid" or "stripe".


static func group_of(n: int) -> String:
	if n == 0:
		return "cue"
	if n == 8:
		return "eight"
	return "solid" if n < 8 else "stripe"


static func other_group(g: String) -> String:
	return "stripe" if g == "solid" else "solid"


static func group_left(sim: Sim, g: String) -> int:
	return sim.count_alive(func(n): return group_of(n) == g)


static func judge(sim: Sim, group: String, on_eight: bool, is_break: bool) -> Dictionary:
	var why := ""
	var eight := sim.potted.has(8)
	var pots := []
	for n in sim.potted:
		if n != 0 and n != 8:
			pots.append(n)
	if sim.potted.has(0):
		why = "Cue ball potted"
	elif sim.first_hit < 0:
		why = "Hit nothing"
	elif group == "" and sim.first_hit == 8 and not is_break:
		why = "Hit the 8 too early"
	elif group != "" and not (group_of(sim.first_hit) == group or (sim.first_hit == 8 and on_eight)):
		why = "Wrong ball first"
	elif pots.is_empty() and not eight and not sim.rail_after and not is_break:
		why = "No rail after contact"
	var own := 0
	if group != "":
		for n in pots:
			if group_of(n) == group:
				own += 1
	return {"foul": why != "", "why": why, "eight": eight, "pots": pots, "own": own}
