passive component Unikernel { sync input port start: serial }

instance unikernel: Unikernel base id 0

topology UnixHelloKey {
  instance unikernel
}
