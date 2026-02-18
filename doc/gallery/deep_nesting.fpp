@ Deep nesting: three levels of nested states with cross-level transitions.
state machine DeepNesting {
  action log
  signal go
  signal up
  signal reset
  initial enter L1
  state L1 {
    initial enter L2
    state L2 {
      initial enter L3
      state L3 {
        on go do { log } enter L3
        on up enter Done
      }
      state Done {
        on reset enter L3
      }
    }
    on up enter Top
  }
  state Top {
    on reset do { log } enter L1
  }
}
