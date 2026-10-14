class_name AI
extends RefCounted
## Computer opponent. Picks shots with the ghost-ball method; the two top
## levels also play every candidate through the simulation and judge where
## the cue ball ends up. Safe to run on a worker thread.

const LEVELS := {
	1: {"n": 0.03, "pn": 0.3, "miss": 0.3, "pick": 99, "place": 1, "look": false},
	2: {"n": 0.012, "pn": 0.15, "miss": 0.1, "pick": 3, "place": 20, "look": false},
	3: {"n": 0.005, "pn": 0.06, "miss": 0.02, "pick": 1, "place": 50, "look": true},
	4: {"n": 0.0018, "pn": 0.025, "miss": 0.0, "pick": 1, "place": 100, "look": true},
}


static func targets(sim: Sim, group: String) -> Array:
	var out := []
	for i in sim.num.size():
		var n := sim.num[i]
		if sim.alive[i] == 0 or n == 0:
			continue
		if group == "" and n != 8:
			out.append(i)
		elif group != "" and Rules.group_of(n) == group:
			out.append(i)
	if out.is_empty():
		var e := sim.index_of(8)
		if e >= 0 and sim.alive[e] == 1:
			out.append(e)
	return out


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l := ab.length_squared()
	if l == 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Returns [score, angle, power] candidates, best first.
static func plan(sim: Sim, cue: Vector2, tg: Array) -> Array:
	var out := []
	var br := Sim.BR
	for ti in tg:
		var t := Vector2(sim.px[ti], sim.py[ti])
		for pk in Sim.AIM_POINTS:
			var to_pocket: Vector2 = pk - t
			var d2 := to_pocket.length()
			if d2 < 1.0:
				continue
			var dir := to_pocket / d2
			var ghost := t - dir * 2 * br
			if ghost.x < Sim.PL + br or ghost.x > Sim.PR - br or ghost.y < Sim.PT + br or ghost.y > Sim.PB - br:
				continue
			var to_ghost := ghost - cue
			var d1 := to_ghost.length()
			if d1 < 0.001:
				continue
			var cut := to_ghost.dot(dir) / d1
			if cut < 0.25:
				continue
			var blocked := false
			for i in sim.num.size():
				if i == 0 or i == ti or sim.alive[i] == 0:
					continue
				var o := Vector2(sim.px[i], sim.py[i])
				if _seg_dist(o, cue, ghost) < 2 * br - 1 or _seg_dist(o, t, pk) < 2 * br - 1:
					blocked = true
					break
			if blocked:
				continue
			var score := cut * 100.0 - (d1 + d2) * 0.05
			var power := clampf(0.22 + (d1 + d2) / 1100.0 / maxf(cut, 0.5), 0.3, 1.0)
			out.append([score, to_ghost.angle(), power])
	out.sort_custom(func(a, b): return a[0] > b[0])
	return out


## Plays a shot through on a copy and scores the outcome for the shooter.
static func look_ahead(sim: Sim, group: String, on_eight: bool, a: float, p: float) -> float:
	var s := sim.copy()
	s.shoot(a, p)
	s.run_to_rest(900)
	var j := Rules.judge(s, group, on_eight, false)
	if j.eight:
		return 1000.0 if (not j.foul and on_eight) else -1000.0
	if j.foul:
		return -300.0
	var g := group
	if g == "" and j.pots.size() > 0:
		g = Rules.group_of(j.pots[0])
	var keeps: bool = (group != "" and j.own > 0) or (group == "" and j.pots.size() > 0)
	if not keeps:
		return -100.0
	var nxt := plan(s, Vector2(s.px[0], s.py[0]), targets(s, g))
	return 200.0 + (nxt[0][0] if nxt.size() > 0 else -80.0)


static func think(sim: Sim, group: String, on_eight: bool, hand: bool, kitchen: bool, is_break: bool, level: int, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var P: Dictionary = LEVELS[level]
	var res := {}
	var tg := targets(sim, group)
	if hand:
		var best := -1e9
		var bp := Vector2.ZERO
		var found := false
		var tries := 1 if is_break else int(P.place)
		var i := 0
		while i < 200 and (i < tries or not found):
			i += 1
			var x := rng.randf_range(Sim.PL + 20, Sim.PR - 20)
			var y := rng.randf_range(Sim.HEAD_Y + 10 if kitchen else Sim.PT + 20, Sim.PB - 20)
			if is_break:
				x = Sim.CX + rng.randf_range(-60, 60)
			if not sim.valid_cue_pos(x, y, kitchen):
				continue
			var L := plan(sim, Vector2(x, y), tg)
			var sc: float = L[0][0] if L.size() > 0 else -500.0
			if not found or sc > best:
				best = sc
				bp = Vector2(x, y)
				found = true
		if not found:
			bp = Sim.CUE_START
		sim.place_cue(bp.x, bp.y)
		res.place = bp
	var cue := Vector2(sim.px[0], sim.py[0])
	var a := 0.0
	var pw := 0.0
	if is_break:
		a = (Sim.FOOT - cue).angle() + rng.randfn() * 0.01
		pw = 1.0
	else:
		var L := plan(sim, cue, tg)
		if L.size() > 0 and rng.randf() >= P.miss:
			if P.look:
				var best_v := -1e9
				for c in L.slice(0, 4):
					for f in [0.75, 1.0, 1.3]:
						var p2 := clampf(c[2] * f, 0.2, 1.0)
						var v: float = look_ahead(sim, group, on_eight, c[1], p2) + c[0] * 0.3
						if v > best_v:
							best_v = v
							a = c[1]
							pw = p2
			else:
				var c2: Array = L[rng.randi_range(0, mini(int(P.pick), L.size()) - 1)]
				a = c2[1]
				pw = c2[2]
		else:
			var ti: int = tg[rng.randi_range(0, tg.size() - 1)]
			a = (Vector2(sim.px[ti], sim.py[ti]) - cue).angle() + rng.randf_range(-0.15, 0.15)
			pw = rng.randf_range(0.3, 0.8)
	res.a = a + rng.randfn() * P.n
	res.p = clampf(pw * (1.0 + rng.randfn() * P.pn), 0.15, 1.0)
	return res
