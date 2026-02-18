@ Self-loops: a state with many do-actions on different signals.
state machine SelfLoops {
  action process
  action validate
  action retry
  guard ok
  signal tick
  signal ping
  signal poll
  initial enter Busy
  state Busy {
    on tick if ok do { process } enter Busy
    on ping do { validate } enter Busy
    on poll do { retry, process } enter Busy
    on tick enter Done
  }
  state Done
}
