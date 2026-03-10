passive component Unikernel { async input port start: serial }

instance unikernel: Unikernel base id 0

topology UnixClock {
  instance unikernel
}

topology Solo5Clock {
  instance unikernel
}
