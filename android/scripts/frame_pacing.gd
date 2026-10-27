extends RefCounted
## Observed foreground callback intervals, not compositor/GPU timings.
const CAPACITY := 180
var intervals := PackedFloat64Array()
var cursor := 0
var last_usec := -1

func reset() -> void:
	intervals.clear()
	cursor = 0
	last_usec = -1

func record(now_usec: int) -> void:
	if last_usec >= 0 and now_usec > last_usec:
		add_interval(float(now_usec - last_usec) / 1000000.0)
	last_usec = now_usec

func add_interval(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0: return
	if intervals.size() < CAPACITY:
		intervals.append(seconds)
	else:
		intervals[cursor] = seconds
		cursor = (cursor + 1) % CAPACITY

func summary(target_fps: int) -> Dictionary:
	if intervals.is_empty():
		return {"count": 0, "mean_ms": 0.0, "p95_ms": 0.0, "late_percent": 0.0}
	var sorted := intervals.duplicate()
	sorted.sort()
	var total := 0.0
	var late := 0
	var threshold := 1.5 / float(maxi(1, target_fps))
	for seconds in sorted:
		total += seconds
		if seconds > threshold + 0.000001: late += 1
	return {
		"count": sorted.size(),
		"mean_ms": total * 1000.0 / sorted.size(),
		"p95_ms": sorted[ceili(sorted.size() * 0.95) - 1] * 1000.0,
		"late_percent": late * 100.0 / sorted.size(),
	}
