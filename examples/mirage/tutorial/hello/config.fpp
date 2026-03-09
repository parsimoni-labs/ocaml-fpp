passive component Unikernel { sync input port start: serial }

instance unikernel: Unikernel base id 0

topology UnixHello {
  instance unikernel
}

topology Solo5Hello {
  instance unikernel
}
