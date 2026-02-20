@ A single choice node branching to two states.
state machine SimpleChoice {
  guard ready
  action init
  initial enter Check
  choice Check { if ready do { init } enter Go else enter Wait }
  state Go
  state Wait
}
