@ Minimal toggle: two states switching back and forth.
state machine Toggle {
  signal flip
  initial enter Off
  state Off { on flip enter On }
  state On  { on flip enter Off }
}
