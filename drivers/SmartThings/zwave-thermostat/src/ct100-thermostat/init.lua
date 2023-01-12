-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
--- @type st.zwave.CommandClass.ThermostatMode
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({ version = 2 })
--- @type st.zwave.CommandClass.ThermostatOperatingState
local ThermostatOperatingState = (require "st.zwave.CommandClass.ThermostatOperatingState")({ version = 1 })
--- @type st.zwave.CommandClass.ThermostatSetpoint
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({ version = 1 })

local heatingSetpointDefaults = require "st.zwave.defaults.thermostatHeatingSetpoint"
local coolingSetpointDefaults = require "st.zwave.defaults.thermostatCoolingSetpoint"

local CT100_THERMOSTAT_FINGERPRINTS = {
  { manufacturerId = 0x0098, productType = 0x6401, productId = 0x0107 }, -- 2Gig CT100 Programmable Thermostat
  { manufacturerId = 0x0098, productType = 0x6501, productId = 0x000C }, -- Iris Thermostat
}

local function poll_after_setpoint_set(self, device, cmd)
  device:send(SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE}))
  device:send(ThermostatOperatingState:Get({}))
end

local function heat_setpoint_handler(self, device, cmd)
  heatingSetpointDefaults.capability_handlers[capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint](self, device, cmd)

  device.thread:call_with_delay(2, poll_after_setpoint_set)
end

local function cool_setpoint_handler(self, device, cmd)
  coolingSetpointDefaults.capability_handlers[capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint](self, device, cmd)

  device.thread:call_with_delay(2, poll_after_setpoint_set)
end

local function can_handle_ct100_thermostat(opts, driver, device, cmd, ...)
  for _, fingerprint in ipairs(CT100_THERMOSTAT_FINGERPRINTS) do
    if device:id_match( fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end

  return false
end

local function thermostat_mode_report_handler(self, device, cmd)
  local event = nil

  local mode = cmd.args.mode
  if mode == ThermostatMode.mode.OFF then
    event = capabilities.thermostatMode.thermostatMode.off()
  elseif mode == ThermostatMode.mode.HEAT then
    event = capabilities.thermostatMode.thermostatMode.heat()
  elseif mode == ThermostatMode.mode.COOL then
    event = capabilities.thermostatMode.thermostatMode.cool()
  elseif mode == ThermostatMode.mode.AUTO then
    event = capabilities.thermostatMode.thermostatMode.auto()
  elseif mode == ThermostatMode.mode.AUXILIARY_HEAT then
    event = capabilities.thermostatMode.thermostatMode.emergency_heat()
  end

  if (event ~= nil) then
    device:emit_event(event)
  end

  local heating_setpoint = device:get_latest_state("main", capabilities.thermostatHeatingSetpoint.ID, capabilities.thermostatHeatingSetpoint.heatingSetpoint.NAME, 0)
  local cooling_setpoint = device:get_latest_state("main", capabilities.thermostatCoolingSetpoint.ID, capabilities.thermostatCoolingSetpoint.coolingSetpoint.NAME, 0)
  local current_temperature = device:get_latest_state("main", capabilities.temperatureMeasurement.ID, capabilities.temperatureMeasurement.temperature.NAME, 0)

  device:send(ThermostatOperatingState:Get({}))
  if mode == ThermostatMode.mode.COOL or
    ((mode == ThermostatMode.mode.AUTO or mode == ThermostatMode.mode.OFF) and (current_temperature > (heating_setpoint + cooling_setpoint) / 2)) then
    device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1}))
    device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
  else
    device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
    device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1}))
  end
end

local ct100_thermostat = {
  NAME = "CT100 thermostat",
  zwave_handlers = {
    [cc.THERMOSTAT_MODE] = {
      [ThermostatMode.REPORT] = thermostat_mode_report_handler
    }
  },
  capability_handlers = {
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = heat_setpoint_handler
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = cool_setpoint_handler
    }
  },
  can_handle = can_handle_ct100_thermostat,
}

return ct100_thermostat
