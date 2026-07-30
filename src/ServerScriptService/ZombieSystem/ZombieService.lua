--!strict
local ZombieController = require(script.Parent.ZombieController)

local ZombieService = {}
local controllers: {[Model]: any} = {}

local requiredParts = {"HumanoidRootPart", "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}

local function validate(model: Model): (boolean, string?)
	if not model:IsA("Model") then return false, "is not a Model" end
	if not model:FindFirstChildOfClass("Humanoid") then return false, "is missing Humanoid" end
	for _, name in ipairs(requiredParts) do
		if not model:FindFirstChild(name) then return false, "is missing R6 part " .. name end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return false, "has invalid HumanoidRootPart" end
	return true, nil
end

function ZombieService:InitializeZombie(model: Model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		warn("ZombieSystem InitializeZombie expected a Model")
		return nil
	end
	if controllers[model] then return controllers[model] end
	local valid, reason = validate(model)
	if not valid then warn("ZombieSystem skipped " .. model:GetFullName() .. ": " .. (reason or "invalid model")); return nil end
	model.PrimaryPart = model.HumanoidRootPart
	for _, instance in ipairs(model:GetDescendants()) do
		if instance:IsA("BasePart") then
			instance.Anchored = false
			pcall(function() instance:SetNetworkOwner(nil) end)
		end
	end
	local controller = ZombieController.new(model)
	controllers[model] = controller
	return controller
end

function ZombieService:DestroyZombie(model: Model)
	local controller = controllers[model]
	if controller then controller:Destroy(); controllers[model] = nil end
end

function ZombieService:GetController(model: Model)
	return controllers[model]
end

function ZombieService:Stun(model: Model, duration: number): boolean
	local controller = controllers[model]
	if type(duration) ~= "number" or duration ~= duration or duration <= 0 or duration == math.huge
		or not controller or controller.destroyed then return false end
	model:SetAttribute("Stunned", true)
	model:SetAttribute("StunEndTime", workspace:GetServerTimeNow() + duration)
	return true
end

function ZombieService:SetTarget(model: Model, player: Player): boolean
	local controller = controllers[model]
	if typeof(player) ~= "Instance" or not player:IsA("Player")
		or not controller or controller.destroyed or controller.humanoid.Health <= 0 then return false end
	controller.target = player
	model:SetAttribute("CurrentTargetUserId", player.UserId)
	if controller.state ~= "Stunned" then controller:SetState("Chase") end
	return true
end

function ZombieService:ClearTarget(model: Model)
	local controller = controllers[model]
	if not controller then return end
	controller.target = nil
	model:SetAttribute("CurrentTargetUserId", 0)
	if controller.state == "Chase" or controller.state == "Attack" then controller:SetState("Idle") end
end

return ZombieService