module Fw {

  port Time

  port Tlm

}

passive component C {

  time get port timeGetOut

  telemetry port tlmOut

  telemetry T: U32

}

instance c1: C base id 0x100

instance c2: C base id 0x200

instance c3: C base id 0x300

instance c4: C base id 0x400

topology T1 {

  instance c1
  instance c2
  instance c3
  instance c4

  telemetry packets P1 {

    packet P1 id 0 group 0 {
      c1.T
      c2.T
    }

    packet P2 group 1 {
      c1.T
      c1.T
    }

  } omit {
    c3.T
    c4.T
  }

  telemetry packets P2 {

    packet P1 id 0 group 0 {
      c1.T
      c2.T
      c3.T
      c4.T
    }

  }

}

topology T2 {

}
