extends SceneTree
## Headless check: the AI plays itself on every level. Verifies that games end,
## balls get potted and the look-ahead stays fast enough.
## Run: godot --headless --path . --script tests/sim_test.gd


func _init() -> void:
	var ok := true
	for level in [1, 2, 3, 4]:
		var wins := 0
		var shots_total := 0
		var fouls := 0
		var finished := 0
		var think_ms := [0]
		var games := 6
		for g in games:
			var r := _play(level, 1000 + g * 17 + level, func(ms): think_ms[0] += ms)
			shots_total += r.shots
			fouls += r.fouls
			if r.done:
				finished += 1
		print("level %d: %d/%d finished, %.1f shots/game, %.0f%% fouls, %.0f ms think/shot" % [
			level, finished, games, shots_total / float(games), 100.0 * fouls / maxf(1, shots_total), think_ms[0] / maxf(1, shots_total)])
		if finished < games:
			ok = false
	_physics_checks()
	print("RESULT: ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)


func _play(level: int, seed: int, timer: Callable) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sim := Sim.new()
	sim.setup(Sim.rack_order(rng))
	var groups := {0: "", 1: ""}
	var turn := 0
	var hand := false
	var kitchen := false
	var is_break := true
	var shots := 0
	var fouls := 0
	while shots < 250:
		var g: String = groups[turn]
		var on_eight := g != "" and Rules.group_left(sim, g) == 0
		var t0 := Time.get_ticks_msec()
		var res := AI.think(sim.copy(), g, on_eight, hand, kitchen, is_break, level, rng.randi())
		timer.call(Time.get_ticks_msec() - t0)
		if res.has("place"):
			sim.place_cue(res.place.x, res.place.y)
		sim.shoot(res.a, res.p)
		sim.run_to_rest(3000)
		shots += 1
		var j := Rules.judge(sim, g, on_eight, is_break)
		var was_break := is_break
		is_break = false
		kitchen = false
		if j.foul:
			fouls += 1
		if j.eight:
			if was_break:
				sim.respot(8)
			else:
				return {"done": true, "shots": shots, "fouls": fouls}
		if not j.foul and g == "" and not was_break and j.pots.size() > 0:
			g = Rules.group_of(j.pots[0])
			groups[turn] = g
			groups[1 - turn] = Rules.other_group(g)
			j = Rules.judge(sim, g, on_eight, false)
		var keep: bool = not j.foul and ((g != "" and j.own > 0) or (was_break and j.pots.size() > 0))
		hand = j.foul
		if not keep:
			turn = 1 - turn
	return {"done": false, "shots": shots, "fouls": fouls}


func _physics_checks() -> void:
	# Straight shot into the top-left corner along the diagonal must pot.
	var s := Sim.new()
	s.setup([1, 2, 3, 4, 8, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15])
	for i in range(1, s.num.size()):
		s.alive[i] = 0
	s.place_cue(200, 200)
	s.shoot(atan2(-1, -1), 0.6)
	s.run_to_rest()
	print("corner pot: ", s.potted.has(0))
	# Ball rolled along the side rail into the side pocket region.
	s.place_cue(Sim.PL + Sim.BR, 800)
	s.shoot(-PI / 2, 0.5)
	s.run_to_rest()
	print("side rail roll pots: ", s.potted.has(0), " pocket ", s.pocket_of.get(0))
	# Full-power shot distance on an empty table.
	s.place_cue(Sim.CX, Sim.PB - 20)
	var total := 0.0
	s.shoot(-PI / 2 + 0.3, 1.0)
	var last := Vector2(s.px[0], s.py[0])
	while s.moving():
		s.step()
		var now := Vector2(s.px[0], s.py[0])
		total += now.distance_to(last)
		last = now
		if s.alive[0] == 0:
			break
	print("full power travel: %.0f units (table length 932)" % total)
	# Determinism: same shot twice gives identical result.
	var a := Sim.new()
	var b := Sim.new()
	var nums := Sim.rack_order(RandomNumberGenerator.new())
	a.setup(nums)
	b.setup(nums)
	a.shoot(-PI / 2 + 0.01, 1.0)
	b.shoot(-PI / 2 + 0.01, 1.0)
	a.run_to_rest(5000)
	b.run_to_rest(5000)
	print("deterministic: ", a.px == b.px and a.py == b.py and a.potted == b.potted)
