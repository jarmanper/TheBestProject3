class_name MonsterRules
extends RefCounted
## The timers behind the three GDD monster rules plus the mimicry/abduction
## schedule. Pure logic (no nodes, no physics) so every rule is unit-tested.
## The values themselves are the constants at the top of monster.gd.
##
##   Rule 1  tick_sprint / start_winded / tick_winded
##   Rule 2  is_reveal_condition / tick_reveal / start_reveal_cooldown
##   Rule 3  update_view / should_stage_sighting / note_sighting_attempt

const EPSILON := 0.000001

var rng := RandomNumberGenerator.new()

# Rule 1: 13-second sprint.
var sprint_time := 0.0              ## seconds sprinted since the last rest
var winded_left := 0.0              ## > 0 while winded

# Rule 2: turns after lingering in range.
var reveal_progress := 0.0          ## seconds the player has lingered (decays at half speed)
var reveal_cooldown_left := 0.0     ## after a chase: no reveal until this runs out

# Rule 3: appears to the player at least once.
var has_been_sighted := false
var sightings := 0
var in_view := false                ## debounced "the player has seen it" (a sighting is on)
var _out_of_view_time := 0.0
var _perceive_time := 0.0           ## seconds the player has made it out without a break
var sighting_retry_left := 0.0

# Mimicry / abduction schedule (counts down only from the start hour).
var next_mimic_in := 0.0
var next_abduction_in := 0.0
var abductions := 0


func _init() -> void:
	next_mimic_in = _roll(Monster.MIMIC_INTERVAL)
	next_abduction_in = _roll(Monster.ABDUCT_INTERVAL)


# --- Rule 1 ------------------------------------------------------------------

## Advances the sprint timer. Returns true the moment it reaches SPRINT_MAX_TIME.
## Not sprinting recovers the timer at the same rate.
func tick_sprint(delta: float, sprinting: bool) -> bool:
	if not sprinting:
		sprint_time = maxf(sprint_time - delta, 0.0)
		return false
	sprint_time += delta
	return sprint_time >= Monster.SPRINT_MAX_TIME - EPSILON


func start_winded() -> void:
	winded_left = Monster.WINDED_TIME


func is_winded() -> bool:
	return winded_left > 0.0


## Returns true when the winded time is over; the sprint timer starts fresh.
func tick_winded(delta: float) -> bool:
	if winded_left <= 0.0:
		return false
	winded_left -= delta
	if winded_left > EPSILON:
		return false
	winded_left = 0.0
	sprint_time = 0.0
	return true


func reset_sprint() -> void:
	sprint_time = 0.0
	winded_left = 0.0


# --- Rule 2 ------------------------------------------------------------------

## The player is lingering: not hidden, within REVEAL_RANGE, in line of sight.
static func is_reveal_condition(distance: float, has_los: bool, player_hidden: bool) -> bool:
	return has_los and not player_hidden and distance <= Monster.REVEAL_RANGE


## Accumulates while `lingering`, decays at half speed otherwise. Returns true
## (and resets) when the player lingered REVEAL_TIME. Never during the cooldown.
func tick_reveal(delta: float, lingering: bool) -> bool:
	if reveal_cooldown_left > 0.0:
		reveal_cooldown_left = maxf(reveal_cooldown_left - delta, 0.0)
		lingering = false
	if not lingering:
		reveal_progress = maxf(reveal_progress - delta * 0.5, 0.0)
		return false
	reveal_progress += delta
	if reveal_progress >= Monster.REVEAL_TIME - EPSILON:
		reveal_progress = 0.0
		return true
	return false


func start_reveal_cooldown() -> void:
	reveal_cooldown_left = Monster.REVEAL_COOLDOWN
	reveal_progress = 0.0


## 0..1 progress toward the reveal (debug display, "staring" tell).
func get_reveal_fraction() -> float:
	return clampf(reveal_progress / Monster.REVEAL_TIME, 0.0, 1.0)


# --- Rule 3 ------------------------------------------------------------------

## Feed whether the player can make the monster out this frame (close, near the middle of the
## view, lit: Monster._is_perceivable_at). Returns true on a new sighting: PERCEIVE_TIME of
## unbroken perception, the first time or after SIGHTING_GAP without any.
func update_view(perceived_now: bool, delta: float) -> bool:
	sighting_retry_left = maxf(sighting_retry_left - delta, 0.0)
	if not perceived_now:
		_perceive_time = 0.0
		_out_of_view_time += delta
		if _out_of_view_time >= Monster.SIGHTING_GAP:
			in_view = false
		return false
	_out_of_view_time = 0.0
	_perceive_time += delta
	if in_view or _perceive_time < Monster.PERCEIVE_TIME - EPSILON:
		return false
	in_view = true
	has_been_sighted = true
	sightings += 1
	return true


## True when the monster must stage a sighting: the deadline hour has come and
## the player has never seen it (and no attempt is waiting to retry).
func should_stage_sighting(hour: int) -> bool:
	return hour >= Monster.SIGHTING_DEADLINE_HOUR and not has_been_sighted \
		and sighting_retry_left <= 0.0


## Call when a staged sighting starts; another try waits SIGHTING_RETRY_DELAY
## in case the player never looks at it.
func note_sighting_attempt() -> void:
	sighting_retry_left = Monster.SIGHTING_RETRY_DELAY


# --- Mimicry / abductions ----------------------------------------------------

func tick_schedules(delta: float, hour: int) -> void:
	if hour >= Monster.MIMIC_START_HOUR:
		next_mimic_in -= delta
	if hour >= Monster.ABDUCT_EARLIEST_HOUR and abductions < Monster.MAX_ABDUCTIONS:
		next_abduction_in -= delta


func mimic_due() -> bool:
	return next_mimic_in <= 0.0


func mimic_done() -> void:
	next_mimic_in = _roll(Monster.MIMIC_INTERVAL)


func delay_mimic(seconds: float) -> void:
	next_mimic_in = maxf(next_mimic_in, seconds)


func abduction_due() -> bool:
	return abductions < Monster.MAX_ABDUCTIONS and next_abduction_in <= 0.0


func abduction_done() -> void:
	abductions += 1
	next_abduction_in = _roll(Monster.ABDUCT_INTERVAL)


func delay_abduction(seconds: float) -> void:
	next_abduction_in = maxf(next_abduction_in, seconds)


func _roll(interval: Vector2) -> float:
	return rng.randf_range(interval.x, interval.y)
