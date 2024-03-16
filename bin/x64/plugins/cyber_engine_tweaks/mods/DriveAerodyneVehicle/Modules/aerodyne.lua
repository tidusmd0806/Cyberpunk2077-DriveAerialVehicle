local Position = require("Modules/position.lua")
local Engine = require("Modules/engine.lua")
local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
local Aerodyne = {}
Aerodyne.__index = Aerodyne

VehicleModel = {
	Excalibur = "Vehicle.av_rayfield_excalibur",
	Manticore = "Vehicle.av_militech_manticore",
	Atlus = "Vehicle.av_zetatech_atlus"
}

ActionList = {
    Nothing = 0,
    Up = 1,
    Down = 2,
    Forward = 3,
    Backward = 4,
    Right = 5,
    Left = 6,
    TurnRight = 7,
    TurnLeft = 8,
    Hover = 9,
	---------
	EnterOrExit= 100,
	ChangeDoor = 101,
	ChangeCamera = 102,
}

function Aerodyne:New(all_models)
	local obj = {}
	obj.position_obj = Position:New(all_models)
	obj.engine_obj = Engine:New(obj.position_obj, all_models)
	obj.log_obj = Log:New()
	obj.log_obj:SetLevel(LogLevel.Info, "Aerodyne")
	obj.player_obj = nil

	for key, value in pairs(Movement) do
		if ActionList[key] ~= value then
			obj.log_obj:Record(LogLevel.Critical, "ActionList is not equal to Movement /" .. key .. " : " .. value)
		end
	end
	obj.all_models = all_models
	obj.spawn_distance = 5.5
	obj.spawn_high = 50
	obj.spawn_wait_count = 150
	obj.down_time_count = 300
	obj.land_offset = - 1.0

	-- set default parameters
	obj.entity_id = nil
	obj.vehicle_model_tweakdb_id = nil
	obj.vehicle_model_type = nil
	obj.is_player_in = false
	obj.is_default_mount = nil
	obj.is_default_seat_position = nil
	obj.sit_pose = nil
	obj.seat_position = nil
	obj.active_seat = nil
	obj.active_door = nil

	return setmetatable(obj, self)
end

function Aerodyne:SetModel(list)
	local index = list[1]
	local type_number = list[2]
	self.vehicle_model_tweakdb_id = self.all_models[index].tweakdb_id
	self.vehicle_model_type = self.all_models[index].type[type_number]
	self.is_default_mount = self.all_models[index].is_default_mount
	self.is_default_seat_position = self.all_models[index].is_default_seat_position
	self.sit_pose = self.all_models[index].sit_pose
	self.seat_position = self.all_models[index].seat_position
	self.active_seat = self.all_models[index].active_seat
	self.active_door = self.all_models[index].active_door
	self.engine_obj:SetModel(index)
	self.position_obj:SetModel(index)
end

function Aerodyne:IsPlayerIn()
	return self.is_player_in
end

function Aerodyne:Spawn(position, angle)
	if self.entity_id ~= nil then
		self.log_obj:Record(LogLevel.Info, "Entity already spawned")
		return false
	end

	local entity_system = Game.GetDynamicEntitySystem()
	local entity_spec = DynamicEntitySpec.new()

	entity_spec.recordID = self.vehicle_model_tweakdb_id
	entity_spec.appearanceName = self.vehicle_model_type
	entity_spec.position = position
	entity_spec.orientation = angle
	entity_spec.persistState = false
	self.entity_id = entity_system:CreateEntity(entity_spec)

	-- set entity id to position object
	DAV.Cron.Every(0.1, {tick = 1}, function(timer)
		local entity = Game.FindEntityByID(self.entity_id)
		if entity ~= nil then
			self.position_obj:SetEntity(entity)
			self.engine_obj:Init()
			DAV.Cron.Halt(timer)
		end
	end)

	return true
end

function Aerodyne:SpawnToSky()
	local position = self.position_obj:GetSpawnPosition(self.spawn_distance, 0.0)
	position.z = position.z + self.spawn_high
	local angle = self.position_obj:GetSpawnOrientation(90.0)
	self:Spawn(position, angle)
	DAV.Cron.Every(0.01, { tick = 1 }, function(timer)
		timer.tick = timer.tick + 1
		if timer.tick == self.spawn_wait_count then
			self:LockDoor()
		elseif timer.tick > self.spawn_wait_count then
			if not self:Move(0.0, 0.0, Utils:CalculationQuadraticFuncSlope(self.down_time_count, self.land_offset ,self.spawn_high , timer.tick - self.spawn_wait_count + 1), 0.0, 0.0, 0.0) then
				DAV.Cron.Halt(timer)
			elseif timer.tick >= self.spawn_wait_count + self.down_time_count then
				DAV.Cron.Halt(timer)
			end
		end
	end)
end

function Aerodyne:Despawn()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to despawn")
		return false
	end
	local entity_system = Game.GetDynamicEntitySystem()
	entity_system:DeleteEntity(self.entity_id)
	self.entity_id = nil
	return true
end

function Aerodyne:UnlockDoor()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change door lock")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	vehicle_ps:UnlockAllVehDoors()
	return true
end

function Aerodyne:LockDoor()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change door lock")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	vehicle_ps:QuestLockAllVehDoors()
	return true
end

function Aerodyne:ChangeDoorState(door_number)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change door state")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	local state = vehicle_ps:GetDoorState(0).value -- front left door: 0 / front right door: 1
	local door_event = nil
	if state == "Closed" then
		door_event = VehicleDoorOpen.new()
	elseif state == "Open" then
		door_event = VehicleDoorClose.new()
	else
		self.log_obj:Record(LogLevel.Error, "Door state is not valid : " .. state)
		return false
	end
	door_event.slotID = self.active_door[door_number]
	door_event.forceScene = false
	vehicle_ps:QueuePSEvent(vehicle_ps, door_event)
	return true
end

function Aerodyne:Mount(seat_number)

	self.log_obj:Record(LogLevel.Debug, "Mount Aerodyne Vehicle : " .. seat_number)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to mount")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local player = Game.GetPlayer()
	local ent_id = entity:GetEntityID()
	local seat = self.active_seat[seat_number]
	-- local seat = "passenger_seat_e"


	local data = NewObject('handle:gameMountEventData')
	data.isInstant = false
	data.slotName = seat
	data.mountParentEntityId = ent_id
	data.entryAnimName = "forcedTransition"


	local slot_id = NewObject('gamemountingMountingSlotId')
	slot_id.id = seat

	local mounting_info = NewObject('gamemountingMountingInfo')
	mounting_info.childId = player:GetEntityID()
	mounting_info.parentId = ent_id
	mounting_info.slotId = slot_id

	local mounting_request = NewObject('handle:gamemountingMountingRequest')
	mounting_request.lowLevelMountingInfo = mounting_info
	mounting_request.mountData = data

	Game.GetMountingFacility():Mount(mounting_request)

	self.position_obj:ChangePosition()

	-- return position near mounted vehicle	
	DAV.Cron.Every(0.1, {tick = 1}, function(timer)
		local entity = Game['GetMountedVehicle;GameObject'](Game.GetPlayer())
		if entity ~= nil then
			self.position_obj:SetEntity(entity)
			DAV.Cron.After(0.5, function()
				if not self.is_default_seat_position then
					self:SitCorrectPosition(3)
				end
				self.player_obj:ActivateTPPHead(true)
				self.is_player_in = true
			end)
			DAV.Cron.Halt(timer)
		end
	end)

	return true

end

function Aerodyne:Unmount()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to unmount")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local player = Game.GetPlayer()
	local ent_id = entity:GetEntityID()
	local seat = "seat_back_left"

	local data = NewObject('handle:gameMountEventData')
	data.isInstant = true
	data.slotName = seat
	data.mountParentEntityId = ent_id
	data.entryAnimName = "forcedTransition"

	local slotID = NewObject('gamemountingMountingSlotId')
	slotID.id = seat

	local mounting_info = NewObject('gamemountingMountingInfo')
	mounting_info.childId = player:GetEntityID()
	mounting_info.parentId = ent_id
	mounting_info.slotId = slotID

	local mount_event = NewObject('handle:gamemountingUnmountingRequest')
	mount_event.lowLevelMountingInfo = mounting_info
	mount_event.mountData = data

	Game.GetMountingFacility():Unmount(mount_event)

	-- set entity id to position object
	DAV.Cron.Every(0.1, {tick = 1}, function(timer)
		local entity = Game.FindEntityByID(self.entity_id)
		if entity ~= nil then
			local angle = player:GetWorldOrientation():ToEulerAngles()
			local position = self.position_obj:GetExitPosition()
			self.position_obj:SetEntity(entity)
			Game.GetTeleportationFacility():Teleport(player, Vector4.new(position.x, position.y, position.z, 1.0), angle)
			DAV.Cron.After(3, function()
				self.player_obj:ActivateTPPHead(false)
			end)
			self.is_player_in = false
			DAV.Cron.Halt(timer)
		end
	end)

	return true
end

function Aerodyne:TakeOn(player_obj)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to take on")
		return false
	end
	self.player_obj = player_obj
	return true
end

function Aerodyne:TakeOff()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to take on")
		return false
	end
	self.player_obj = nil
	return true
end

function Aerodyne:SitCorrectPosition(seat_number)
	if self.player_obj.gender == "famale" then
		self.player_obj:PlayPose(self.sit_pose.famele)
	else
		self.player_obj:PlayPose(self.sit_pose.male)
	end
	local left_seat_cordinate = Vector4.new(self.seat_position[seat_number].x, self.seat_position[seat_number].y, self.seat_position[seat_number].z, 1.0)
	local pos = self.position_obj:GetPosition()
	local foward = self.position_obj:GetFoword()
	local Backward = Vector4.RotateAxis(foward ,Vector4.new(0, 0, 1, 0), 180 / 180.0 * Pi())
	local rot = self.position_obj:GetQuaternion()

	local rotated = Utils:RotateVectorByQuaternion(left_seat_cordinate, rot)

	DAV.Cron.Every(0.1, {tick = 1}, function(timer)
        local dummy_entity = Game.FindEntityByID(self.player_obj.dummy_entity_id)
        if dummy_entity ~= nil then
            Game.GetTeleportationFacility():Teleport(dummy_entity, Vector4.new(pos.x + rotated.x, pos.y + rotated.y, pos.z + rotated.z, 1.0), Vector4.ToRotation(Backward))
			DAV.Cron.Halt(timer)
        end
    end)
	return true
end

function Aerodyne:Move(x, y, z, roll, pitch, yaw)

	if not self.position_obj:SetNextPosition(x, y, z, roll, pitch, yaw) then
		return false
	end

	return true
end

function Aerodyne:Operate(action_command)

	if action_command ~= ActionList.Nothing then
		self.log_obj:Record(LogLevel.Debug, "Operate Aerodyne Vehicle : " .. action_command)
	end

	local x, y, z, roll, pitch, yaw = self.engine_obj:GetNextPosition(action_command)

	if x == 0 and y == 0 and z == 0 and roll == 0 and pitch == 0 and yaw == 0 then
		return false
	end

	if not self.position_obj:SetNextPosition(x, y, z, roll, pitch, yaw) then
		self.engine_obj:SetSpeedAfterRebound()
		return false
	end

	return true
end

return Aerodyne