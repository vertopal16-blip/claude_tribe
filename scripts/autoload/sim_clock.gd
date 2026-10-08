extends Node
## Simulation time source.
##
## Every simulation system reads time from here instead of the raw frame delta,
## so pause and speed controls affect the whole world consistently while the
## camera and UI keep running in real time.
##   * scaled_delta(): per-frame delta for smooth visuals (movement, animation).
##   * sim_tick: fixed-interval signal for decision making and needs.

signal sim_tick(dt: float)
signal speed_changed(time_scale: float, paused: bool)
signal day_started(day: int)

const SPEED_STEPS: Array[float] = [1.0, 2.0, 4.0, 8.0]

var time_scale: float = 1.0
var paused: bool = false
var tick_interval: float = 0.25
var max_ticks_per_frame: int = 8
var day_length: float = 240.0
## Fraction of a day (0 = midnight) at which the simulation starts.
var start_time_of_day: float = 0.29

## Total simulated seconds since the world started.
var sim_time: float = 0.0
var _accumulator: float = 0.0
var _last_day: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100


func configure(config: Resource) -> void:
	tick_interval = maxf(0.02, config.sim_tick_interval)
	max_ticks_per_frame = maxi(1, config.max_ticks_per_frame)
	day_length = maxf(10.0, config.day_length_seconds)
	start_time_of_day = clampf(config.start_time_of_day, 0.0, 0.999)
	sim_time = 0.0
	_accumulator = 0.0
	_last_day = get_day()


func _process(delta: float) -> void:
	if paused:
		return
	var sd := delta * time_scale
	sim_time += sd
	_accumulator += sd
	var ticks := 0
	while _accumulator >= tick_interval and ticks < max_ticks_per_frame:
		_accumulator -= tick_interval
		ticks += 1
		sim_tick.emit(tick_interval)
	if ticks >= max_ticks_per_frame:
		# Drop the backlog instead of spiralling when the machine can't keep up.
		_accumulator = minf(_accumulator, tick_interval)
	var day := get_day()
	if day != _last_day:
		_last_day = day
		day_started.emit(day)


func scaled_delta(real_delta: float) -> float:
	return 0.0 if paused else real_delta * time_scale


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	speed_changed.emit(time_scale, paused)


func toggle_pause() -> void:
	set_paused(not paused)


func set_time_scale(value: float) -> void:
	time_scale = clampf(value, 0.0, 32.0)
	speed_changed.emit(time_scale, paused)


## 0.0 = midnight, 0.25 = 06:00, 0.5 = noon, 0.75 = 18:00.
func get_time_of_day() -> float:
	return fposmod(start_time_of_day + sim_time / day_length, 1.0)


func get_day() -> int:
	return int(floor(start_time_of_day + sim_time / day_length)) + 1


## -1 (midnight) .. 1 (noon); 0 at sunrise / sunset.
func get_sun_height() -> float:
	return sin((get_time_of_day() - 0.25) * TAU)


## 0 at night, 1 in full daylight, smooth through dawn and dusk.
func get_daylight() -> float:
	return smoothstep(-0.15, 0.25, get_sun_height())


func is_night() -> bool:
	return get_daylight() < 0.2


func get_clock_string() -> String:
	var minutes := int(get_time_of_day() * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]
