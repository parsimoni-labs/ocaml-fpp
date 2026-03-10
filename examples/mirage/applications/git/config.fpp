module Unikernel {
  passive component Make {
    async input port start: serial
    output port git: serial
    output port ctx: serial
  }
}

instance unikernel: Unikernel.Make base id 0

topology UnixGit {
  instance unikernel
}
