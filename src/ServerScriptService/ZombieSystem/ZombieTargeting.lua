--!strict
local Players = game:GetService("Players")

local ZombieTargeting = {}

local function validCharacter(character: Model?, origin: Vector3, maximumDistance: number): (Humanoid?, BasePart?)
	if not character then return nil, nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then return nil, nil end
	if (root.Position - origin).Magnitude > maximumDistance then return nil, nil end
	return humanoid, root
end

function ZombieTargeting.GetClosest(
	zombie: Model,
	origin: Vector3,
	maximumDistance: number,
	preferred: Player?,
	requireLineOfSight: boolean?
): Player?
	if preferred then
		local character = preferred.Character
		local _, root = validCharacter(character, origin, maximumDistance)
		if root and (not requireLineOfSight
			or ZombieTargeting.HasLineOfSight(zombie, character :: Model, origin, root.Position)) then
			return preferred
		end
	end
	local closest: Player? = nil
	local closestDistance = maximumDistance
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local _, root = validCharacter(character, origin, maximumDistance)
		if root and (not requireLineOfSight
			or ZombieTargeting.HasLineOfSight(zombie, character :: Model, origin, root.Position)) then
			local distance = (root.Position - origin).Magnitude
			if distance < closestDistance then
				closest, closestDistance = player, distance
			end
		end
	end
	return closest
end

function ZombieTargeting.GetTargetRoot(player: Player?, origin: Vector3, maximumDistance: number): (Humanoid?, BasePart?)
	if not player then return nil, nil end
	return validCharacter(player.Character, origin, maximumDistance)
end

function ZombieTargeting.HasLineOfSight(zombie: Model, target: Model, origin: Vector3, targetPosition: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {zombie}
	params.IgnoreWater = true
	local hit = workspace:Raycast(origin, targetPosition - origin, params)
	return hit == nil or hit.Instance:IsDescendantOf(target)
end

return ZombieTargeting