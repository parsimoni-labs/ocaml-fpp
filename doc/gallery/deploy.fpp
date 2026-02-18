@ A satellite deployment sequence with nested states and choices.
state machine DeploySequence {

  action releaseLatch
  action extendBoom
  action startComms
  action runDiagnostic
  action logAnomaly
  action retryDeploy

  guard boomExtended
  guard commsAcquired
  guard diagnosticPass

  signal deploy
  signal healthCheck
  signal abort

  initial enter Stowed

  state Stowed {
    on deploy do { releaseLatch } enter Deploying
  }

  state Deploying {
    initial do { extendBoom } enter Extending

    state Extending {
      on healthCheck enter Check
    }

    choice Check {
      if boomExtended do { startComms } enter Nominal
      else do { retryDeploy } enter Extending
    }

    on abort do { logAnomaly } enter Safe
  }

  state Nominal {
    initial enter Active

    state Active {
      on healthCheck enter Verify
      on abort do { logAnomaly } enter Safe
    }

    choice Verify {
      if diagnosticPass enter Active
      else do { logAnomaly } enter Degraded
    }

    state Degraded {
      entry do { runDiagnostic }
      on healthCheck if diagnosticPass enter Active
      on abort do { logAnomaly } enter Safe
    }
  }

  state Safe
}
