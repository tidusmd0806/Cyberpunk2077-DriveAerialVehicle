RAV = {
	description = "RideAerodyneVehicele",
	version = "0.1",
    ready = false,
    is_debug_mode = true,
    time_resolution = 0.01,
}

-- import modules
RAV.Log = require('Modules/log.lua')
RAV.Cron = require('External/Cron.lua')
RAV.Event = require('Modules/event.lua')
RAV.Core = require('Modules/core.lua')
RAV.Debug = require('Debug/debug.lua')

-- create instances
RAV.event_obj = RAV.Event:New()
RAV.core_obj = RAV.Core:New(RAV.event_obj)
RAV.debug_obj = RAV.Debug:New(RAV.core_obj)

registerForEvent('onInit', function()

    RAV.ready = true
    RAV.Cron.Every(RAV.time_resolution, function()
        RAV.core_obj:ExcutePriodicalTask()
    end)

    -- Observe player action
    Observe("PlayerPuppet", "OnAction", function(self, action)
        local action_name = Game.NameToString(action:GetName(action))
		local action_type = action:GetType(action).value
        local action_value = action:GetValue(action)

        if RAV.is_debug_mode then
            RAV.debug_obj:PrintActionCommand(action_name, action_type, action_value)
        end

        RAV.core_obj:StorePlayerAction(action_name, action_type, action_value)

    end)

    print('[RAV] Initialization is completed')
end)

-- Debug Window
registerForEvent("onDraw", function()
    if RAV.is_debug_mode then
        RAV.debug_obj:ImGuiMain()
    end
end)

registerHotkey('CallAerodyneVehicle', 'Call Aerodyne Vehicle', function()
    RAV.core_obj:CallAerodyneVehicle()
end)

registerHotkey('ChangeAerodyneDoor', 'Change Door (TMP)', function()
    RAV.core_obj:ChangeAerodyneDoor()
end)

registerHotkey('LockAerodyneDoor', 'Lock (TMP)', function()
    RAV.core_obj:LockAerodyneDoor()
end)

registerHotkey('UnlockAerodyneDoor', 'Unlock (TMP)', function()
    RAV.core_obj:UnlockAerodyneDoor()
end)

registerHotkey('Mount', 'Mount (TMP)', function()
    RAV.core_obj:Mount()
end)

registerHotkey('Unmount', 'Unmount (TMP)', function()
    RAV.core_obj:Unmount()
end)

registerForEvent('onUpdate', function(delta)
    -- This is required for Cron to function
    RAV.Cron.Update(delta)
    RAV.event_obj:CheckInAV()
end)

-- for communication between mods
return RAV