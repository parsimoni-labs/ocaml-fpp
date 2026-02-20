@ Entry and exit actions on states.
state machine EntryExit {
  action open
  action close
  action log
  signal start
  signal stop
  initial enter Idle
  state Idle { on start do { log } enter Running }
  state Running {
    entry do { open }
    exit do { close }
    on stop do { log } enter Idle
  }
}
