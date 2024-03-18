local Aerodyne = require("Modules/aerodyne.lua")
local Player = require("Modules/player.lua")
local Def = require("Modules/def.lua")
local Event = require("Modules/event.lua")
local Log = require("Tools/log.lua")
local Queue = require("Tools/queue.lua")
local Utils = require("Tools/utils.lua")

local Core = {}
Core.__index = Core

function Core:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Core")
    obj.queue_obj = Queue:New()
    obj.av_obj = nil
    obj.player_obj = nil
    obj.event_obj = nil

    obj.av_model_path = "Data/default_model.json"
    obj.input_path = "Data/input.json"

    -- set default parameters
    obj.input_table = {}

    return setmetatable(obj, self)
end

function Core:Init()

    local model_info = {1, 1}
    local all_models = self:GetAllModel()
    self.input_table = self:GetInputTable(self.input_path)

    if all_models == nil then
        self.log_obj:Record(LogLevel.Error, "Model is nil")
        return
    end

    self.player_obj = Player:New(Game.GetPlayer())
    self.player_obj:Init()

    self.av_obj = Aerodyne:New(all_models)
    self.av_obj:SetModel(model_info)

    self.event_obj = Event:New(self.av_obj)
    self.event_obj:Init(model_info[1])

    DAV.Cron.Every(DAV.time_resolution, function()
        self.event_obj:CheckAllEvents()
        self:GetActions()
    end)
end

function Core:GetAllModel()
    local model = Utils:ReadJson(self.av_model_path)
    if model == nil then
        self.log_obj:Record(LogLevel.Error, "Default Model is nil")
        return nil
    end
    return model
end

function Core:GetInputTable(input_path)
    local input = Utils:ReadJson(input_path)
    if input == nil then
        self.log_obj:Record(LogLevel.Error, "Input is nil")
        return nil
    end
    return input
end

function Core:StorePlayerAction(action_name, action_type, action_value)
    local action_value_type = "ZERO"
    if action_value > 0.1 then
        action_value_type = "POSITIVE"
    elseif action_value < -0.1 then
        action_value_type = "NEGATIVE"
    else
        action_value_type = "ZERO"
    end

    local cmd = self:ConvertActionList(action_name, action_type, action_value_type)

    if cmd ~= Def.ActionList.Nothing then
        self.queue_obj:Enqueue(cmd)
    end

end

function Core:ConvertActionList(action_name, action_type, action_value)
    local action_command = Def.ActionList.Nothing
    local action_dist = {name = action_name, type = action_type, value = action_value}

    if Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_ACCELERTOR) then
        action_command = Def.ActionList.Up
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_DOWN) then
        action_command = Def.ActionList.Down
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_FORWARD_MOVE) then
        action_command = Def.ActionList.Forward
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_BACK_MOVE) then
        action_command = Def.ActionList.Backward
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_RIGHT_MOVE) then
        action_command = Def.ActionList.Right
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_LEFT_MOVE) then
        action_command = Def.ActionList.Left
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_RIGHT_ROTATE) then
        action_command = Def.ActionList.TurnRight
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_LEFT_ROTATE) then
        action_command = Def.ActionList.TurnLeft
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_WORLD_ENTER_AV) then
        action_command = Def.ActionList.Enter
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_EXIT_AV) then
        action_command = Def.ActionList.Exit
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_CAMERA) then
        action_command = Def.ActionList.ChangeCamera
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_OPEN_DOOR) then
        action_command = Def.ActionList.ChangeDoor1
    else
        action_command = Def.ActionList.Nothing
    end

    return action_command
end

function Core:GetActions()
    local actions = {}
    if self.queue_obj:IsEmpty() then
        local action = Def.ActionList.Nothing
        table.insert(actions, action)
    else
        while not self.queue_obj:IsEmpty() do
            local action = self.queue_obj:Dequeue()
            if action >= Def.ActionList.Enter then
                self:SetEvent(action)
            else
                table.insert(actions, action)
            end
        end
    end
    if actions == {} then
        local action = Def.ActionList.Nothing
        table.insert(actions, action)
    end
    self:OperateAerodyneVehicle(actions)
end

function Core:CallAerodyneVehicle()
    self.av_obj:SpawnToSky()
    local times = 150
    DAV.Cron.Every(0.01, { tick = 1 }, function(timer)
        timer.tick = timer.tick + 1
        if timer.tick == times then
            self.av_obj:LockDoor()
        elseif timer.tick > times then
            if not self.av_obj:Move(0.0, 0.0, -0.5, 0.0, 0.0, 0.0) then
            DAV.Cron.Halt(timer)
            end
        end
    end)
end

function Core:ChangeAerodyneDoor()
    self.av_obj:ChangeDoorState(1, Def.DoorOperation.Change)
end

function Core:LockAerodyneDoor()
    -- self.av_obj:LockDoor()
    self.av_obj:Despawn()
    -- local audioEvent = SoundPlayEvent.new()

    -- audioEvent.soundName = StringToName("v_av_rayfield_excalibur_traffic_engine_01_av_dplr_01")
    -- print("sound")
    -- Game.GetPlayer():QueueEvent(audioEvent)

    DAV.hudCarController:HideRequest()
    DAV.hudCarController:OnCameraModeChanged(false)
end

function Core:UnlockAerodyneDoor()
    self.av_obj:UnlockDoor()

    Game.GetCallbackSystem():RegisterCallback(CName.new("Input/Key"), DAV.inputListener:Target(), DAV.inputListener:Function("OnKeyInput"))
    
end

function Core:Mount()
    self.av_obj:TakeOn(self.player_obj)
    self.av_obj:Mount(3)
end

function Core:Unmount()
    self.av_obj:Unmount()
end

function Core:OperateAerodyneVehicle(actions)
    if self.event_obj:IsInVehicle() then
        for _, action_command in ipairs(actions) do
            self.av_obj:Operate(action_command)
        end
    end
end

function Core:SetEvent(action)
    if action == Def.ActionList.Enter or action == Def.ActionList.Exit then
        self.event_obj:EnterOrExitVehicle(self.player_obj)
    elseif action == Def.ActionList.ChangeCamera then
        self.event_obj:ToggleCamera()
    elseif action == Def.ActionList.ChangeDoor1 then
        self.event_obj:ChangeDoor(1)
    end
end

return Core
