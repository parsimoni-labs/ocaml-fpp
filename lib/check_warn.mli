(** Warning-level analyses for state machines.

    These optional checks detect suspicious patterns that may indicate bugs but
    are not necessarily errors. Each analysis can be individually disabled via
    {!Check.skip}. Warnings never affect the exit code.

    This module is internal to the [fpp] library. *)

(** {1 Signal coverage}

    For each leaf state (no substates), checks whether every signal declared in
    the state machine has a handler -- either directly via [on signal ...] or
    inherited from an ancestor state. A missing handler means the state silently
    ignores that signal. *)

val signal_coverage :
  sm_name:string ->
  Check_env.env ->
  Ast.state_machine_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list

(** {1 Liveness}

    Detects groups of states that form a cycle with no exit path to a terminal
    state. Uses Tarjan's strongly-connected-component algorithm on the state
    transition graph. A cycle with no exit means the state machine can enter a
    livelock -- it keeps transitioning but can never reach a quiescent state. *)

val liveness :
  sm_name:string ->
  Ast.state_machine_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list

(** {1 Unused declarations}

    Reports actions, guards, and signals that are declared but never referenced
    in any transition, choice, entry action, or exit action. *)

val unused_declarations :
  sm_name:string ->
  Check_env.env ->
  Ast.state_machine_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list

(** {1 Transition shadowing}

    Warns when a child state handles a signal that an ancestor state already
    handles. The child's handler shadows (overrides) the parent's. This is valid
    in hierarchical state machines but may indicate an accidental conflict.
    Inspired by SCADE and Stateflow linting. *)

val transition_shadowing :
  sm_name:string ->
  Ast.state_machine_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list

(** {1 Guard completeness}

    Warns when a choice definition has no [else] branch. A missing else means
    that if no guard evaluates to true, the choice silently fails to transition.
    The UML specification considers models without else branches "ill-formed".
    Only the structural presence of an else branch is checked -- guard semantics
    are opaque. *)

val guard_completeness :
  sm_name:string ->
  Ast.state_machine_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list

(** {1 Deadlock detection}

    Warns about leaf states that have no outgoing transitions and no ancestor
    with a signal handler. Such states can never react to any event once entered
    -- they are potential deadlocks. Only reported when the state machine
    declares at least one signal. *)

val deadlock_states :
  sm_name:string ->
  Check_env.env ->
  Ast.state_machine_member Ast.node Ast.annotated list ->
  Check_env.diagnostic list
