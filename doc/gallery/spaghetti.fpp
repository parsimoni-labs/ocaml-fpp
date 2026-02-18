@ Spaghetti: every state can reach every other state — stress test for edge layout.
state machine Spaghetti {
  action log
  guard g
  signal a
  signal b
  signal c
  initial enter S1
  state S1 {
    on a if g do { log } enter S2
    on b do { log } enter S3
    on c enter S4
  }
  state S2 {
    on a enter S1
    on b if g do { log } enter S3
    on c do { log } enter S4
  }
  state S3 {
    on a do { log } enter S1
    on b enter S2
    on c if g do { log } enter S4
  }
  state S4 {
    on a if g enter S1
    on b enter S2
    on c enter S3
  }
}
