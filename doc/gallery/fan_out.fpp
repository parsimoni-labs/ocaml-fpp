@ Fan-out: one source state with many guarded transitions to different targets.
state machine FanOut {
  action log
  guard hot
  guard cold
  guard windy
  guard rainy
  signal weather
  initial enter Center
  state Center {
    on weather if hot do { log } enter Hot
    on weather if cold do { log } enter Cold
    on weather if windy do { log } enter Windy
    on weather if rainy do { log } enter Rainy
  }
  state Hot { on weather enter Center }
  state Cold { on weather enter Center }
  state Windy { on weather enter Center }
  state Rainy { on weather enter Center }
}
