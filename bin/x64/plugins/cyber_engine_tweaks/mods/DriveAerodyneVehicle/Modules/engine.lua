local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
Engine = {}
Engine.__index = Engine

Movement = {
    Nothing = 0,
    Up = 1,
    Down = 2,
    Forward = 3,
    Backward = 4,
    Right = 5,
    Left = 6,
    TurnRight = 7,
    TurnLeft = 8,
    Hover = 9
}

function Engine:New(position_obj, vehicle_model)
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Engine")
    obj.position_obj = position_obj

    -- set pyhsical parameters
    obj.roll_speed = vehicle_model.roll_speed
    obj.pitch_speed = vehicle_model.pitch_speed
    obj.yaw_speed = vehicle_model.yaw_speed
    obj.roll_restore_speed = vehicle_model.roll_restore_speed
    obj.pitch_restore_speed = vehicle_model.pitch_restore_speed
    obj.max_roll = vehicle_model.max_roll
    obj.min_roll = vehicle_model.min_roll
    obj.max_pitch = vehicle_model.max_pitch
    obj.min_pitch = vehicle_model.min_pitch

    obj.gravity_constant = 9.8
    obj.mess = vehicle_model.mess
    obj.air_resistance_constant = vehicle_model.air_resistance_constant
    obj.max_lift_force = obj.mess * obj.gravity_constant + vehicle_model.max_lift_force
    obj.min_lift_force = obj.mess * obj.gravity_constant - vehicle_model.min_lift_force
    obj.lift_force = obj.min_lift_force
    obj.time_to_max = vehicle_model.time_to_max
    obj.time_to_min = vehicle_model.time_to_min
    obj.rebound_constant = vehicle_model.rebound_constant

    -- set default parameters
    obj.next_indication = {roll = 0, pitch = 0, yaw = 0}
    obj.base_angle = nil
    obj.is_finished_init = false
    obj.is_power_on = false
    obj.is_hover = false
    obj.horizenal_x_speed = 0
    obj.horizenal_y_speed = 0
    obj.vertical_speed = 0
    obj.clock = 0
    obj.dynamic_lift_force = obj.min_lift_force

    return setmetatable(obj, self)
end

function Engine:Init()
    if not self.is_finished_init then
        DAV.Cron.Every(1, {tick = 1}, function(timer)
            self.clock = self.clock + 1
        end)
        self.base_angle = self.position_obj:GetEulerAngles()
    end
    self.is_power_on = false
    self.is_hover = false
    self.horizenal_x_speed = 0
    self.horizenal_y_speed = 0
    self.vertical_speed = 0
    self.clock = 0
    self.is_finished_init = true
end

function Engine:GetNextPosition(movement)
    -- wait for init
    if not self.is_finished_init then
        return 0, 0, 0, 0, 0, 0
    end

    local roll, pitch, yaw = self:CalcurateIndication(movement)
    self:CalcuratePower(movement)
    local x, y, z = self:CalcureteVelocity()

    return x, y, z, roll, pitch, yaw
end

function Engine:CalcurateIndication(movement)

    local actually_indication = self.position_obj:GetEulerAngles()
    self.next_indication["roll"] = actually_indication.roll
    self.next_indication["pitch"] = actually_indication.pitch
    self.next_indication["yaw"] = actually_indication.yaw

    -- set indication
    if movement == Movement.Forward then
        self.next_indication["pitch"] = actually_indication.pitch - self.pitch_speed
    elseif movement == Movement.Backward then
        self.next_indication["pitch"] = actually_indication.pitch + self.pitch_speed
    elseif movement == Movement.Right then
        self.next_indication["roll"] = actually_indication.roll + self.roll_speed
    elseif movement == Movement.Left then
        self.next_indication["roll"] = actually_indication.roll - self.roll_speed
    elseif movement == Movement.TurnRight then
        self.next_indication["yaw"] = actually_indication.yaw + self.yaw_speed
    elseif movement == Movement.TurnLeft then
        self.next_indication["yaw"] = actually_indication.yaw - self.yaw_speed
    else
        -- set roll restoration
        if math.abs(self.next_indication["roll"] - self.base_angle.roll) > self.roll_restore_speed then
            if self.next_indication["roll"] > self.base_angle.roll then
                self.next_indication["roll"] = actually_indication.roll - self.roll_restore_speed
            else
                self.next_indication["roll"] = actually_indication.roll + self.roll_restore_speed
            end
        else
            self.next_indication["roll"] = self.base_angle.roll
        end

        -- set pitch restoration
        if math.abs(self.next_indication["pitch"] - self.base_angle.pitch) > self.pitch_restore_speed then
            if self.next_indication["pitch"] > self.base_angle.pitch then
                self.next_indication["pitch"] = actually_indication.pitch - self.pitch_restore_speed
            else
                self.next_indication["pitch"] = actually_indication.pitch + self.pitch_restore_speed
            end
        else
            self.next_indication["pitch"] = self.base_angle.pitch
        end

    end

    -- check limitation
    if self.next_indication["roll"] > self.max_roll then
        self.next_indication["roll"] = self.max_roll
    elseif self.next_indication["roll"] < self.min_roll then
        self.next_indication["roll"] = self.min_roll
    end
    if self.next_indication["pitch"] > self.max_pitch then
        self.next_indication["pitch"] = self.max_pitch
    elseif self.next_indication["pitch"] < self.min_pitch then
        self.next_indication["pitch"] = self.min_pitch
    end

    -- calculate delta
    local roll = self.next_indication["roll"] - actually_indication.roll
    local pitch = self.next_indication["pitch"] - actually_indication.pitch
    local yaw = self.next_indication["yaw"] - actually_indication.yaw

    return roll, pitch, yaw

end

function Engine:CalcuratePower(movement)
    if movement == Movement.Down then
        self.log_obj:Record(LogLevel.Trace, "Change Power Off")
        self.clock = 0
        self.dynamic_lift_force = self.lift_force
        self.is_power_on = false
        self.position_obj:SetEngineState(self.is_power_on)
    elseif movement == Movement.Up or self.is_power_on then
        if not self.is_power_on then
            self.log_obj:Record(LogLevel.Trace, "Change Power On")
            self.clock = 0
            self.dynamic_lift_force = self.lift_force
            self.is_power_on = true
            self.is_hover = false
            self.position_obj:SetEngineState(self.is_power_on)
        else
            self:SetPowerUpCurve(self.clock)
        end
    elseif not self.is_power_on then
        self:SetPowerDownCurve(self.clock)
    elseif movement == Movement.Hover then
        self.is_hover = true
    end
end

function Engine:SetPowerUpCurve(time)
    if time <= self.time_to_max then
        self.lift_force = self.dynamic_lift_force + (self.max_lift_force - self.min_lift_force) * (time / self.time_to_max)
        if self.lift_force > self.max_lift_force then
            self.lift_force = self.max_lift_force
        end
    else
        self.lift_force = self.max_lift_force
    end
end

function Engine:SetPowerDownCurve(time)
    if time <= self.time_to_min then
        self.lift_force = self.dynamic_lift_force - (self.max_lift_force - self.min_lift_force) * (time / self.time_to_min)
        if self.lift_force < self.min_lift_force then
            self.lift_force = self.min_lift_force
        end
    else
        self.lift_force = self.min_lift_force
    end
end

function Engine:CalcureteVelocity()
    local quot = self.position_obj:GetQuaternion()
    local force_local = {x = 0, y = 0, z = self.lift_force}

    -- calculate vertical list force of av in world coordinate
    local force_quat = {r = 0, i = force_local.x, j = force_local.y, k = force_local.z}
    local q_conj = Utils:QuaternionConjugate(quot)
    local temp = Utils:QuaternionMultiply(quot, force_quat)
    local force_world = Utils:QuaternionMultiply(temp, q_conj)

    self.horizenal_x_speed = self.horizenal_x_speed + (DAV.time_resolution / self.mess) * (force_world.i - self.air_resistance_constant * self.horizenal_x_speed)
    self.horizenal_y_speed = self.horizenal_y_speed + (DAV.time_resolution / self.mess) * (force_world.j - self.air_resistance_constant * self.horizenal_y_speed)
    self.vertical_speed = self.vertical_speed + (DAV.time_resolution / self.mess) * (force_world.k - self.mess * self.gravity_constant - self.air_resistance_constant * self.vertical_speed)

    local x, y, z = self.horizenal_x_speed * DAV.time_resolution, self.horizenal_y_speed * DAV.time_resolution, self.vertical_speed * DAV.time_resolution

    return x, y, z
end

function Engine:SetSpeedAfterRebound()
    self.horizenal_x_speed = -self.horizenal_x_speed * self.rebound_constant
    self.horizenal_y_speed = -self.horizenal_y_speed * self.rebound_constant
    self.vertical_speed = -self.vertical_speed * self.rebound_constant
end

return Engine
