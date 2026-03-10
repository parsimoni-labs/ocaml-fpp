passive component Unikernel {
  async input port start: serial
  param hello: string default "Hello World!"
}

instance unikernel: Unikernel base id 0

topology UnixHelloKey {
  instance unikernel
}

topology Solo5HelloKey {
  instance unikernel
}
