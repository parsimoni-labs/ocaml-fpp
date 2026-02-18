@ Choice chain: initial goes through multiple choices before reaching a state.
state machine ChoiceChain {
  action init1
  action init2
  action init3
  guard hasConfig
  guard isReady
  guard hasNetwork
  initial enter C1
  choice C1 { if hasConfig do { init1 } enter C2 else enter Fault }
  choice C2 { if isReady do { init2 } enter C3 else enter Fault }
  choice C3 { if hasNetwork do { init3 } enter Running else enter Offline }
  state Running
  state Offline
  state Fault
}
