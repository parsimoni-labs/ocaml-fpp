@ A thermostat controller with heating and cooling modes.
state machine Thermostat {

  action startHeating
  action startCooling
  action stopHvac
  action logTransition

  guard tooHot
  guard tooCold

  signal tempReading
  signal modeSwitch
  signal shutdown

  initial do { logTransition } enter Idle

  state Idle {
    on tempReading if tooCold do { startHeating, logTransition } enter Heating
    on tempReading if tooHot do { startCooling, logTransition } enter Cooling
    on shutdown enter Off
  }

  state Heating {
    entry do { startHeating }
    on tempReading if tooHot do { stopHvac, startCooling, logTransition } enter Cooling
    on tempReading do { stopHvac, logTransition } enter Idle
    on shutdown do { stopHvac } enter Off
  }

  state Cooling {
    entry do { startCooling }
    on tempReading if tooCold do { stopHvac, startHeating, logTransition } enter Heating
    on tempReading do { stopHvac, logTransition } enter Idle
    on shutdown do { stopHvac } enter Off
  }

  state Off
}
