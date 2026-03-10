passive component Git_store {
  import Git.S
  async input port connect: serial
}

passive component Git_ctx {
  async input port connect: serial
}

module Unikernel {
  passive component Make {
    async input port start: serial
    output port git: serial
    output port ctx: serial
    param branch: string default "refs/heads/master"
    external param remote: string
  }
}

instance git_store: Git_store base id 0
instance git_ctx: Git_ctx base id 0
instance unikernel: Unikernel.Make base id 0

topology UnixGit {
  instance git_store
  instance git_ctx
  instance unikernel

  connections Start {
    unikernel.git -> git_store.connect
    unikernel.ctx -> git_ctx.connect
  }
}
