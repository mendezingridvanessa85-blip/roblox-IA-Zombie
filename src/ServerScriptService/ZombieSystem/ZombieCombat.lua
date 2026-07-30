--!strict
local ZombieTargeting = require(script.Parent.ZombieTargeting)

local ZombieCombat = {}

function ZombieCombat.ApplyHit(controller: any, attackId: number)
	if controller.destroyed or controller.state ~= "Attack" or not controller.isAttacking or controller.attackId ~= attackId then return end
	local humanoid, targetRoot = ZombieTargeting.GetTargetRoot(controller.target, controller.root.Position, controller.config.AttackRange + 2)
	if not humanoid or not targetRoot or controller.target and controller.target.Character == controller.model then return end
	local box = controller.root.CFrame * controller.config.AttackHitboxOffset
	if controller.config.DebugMode then
		local debug = Instance.new("Part")
		debug.Name = "ZombieAttackDebug"
		debug.Anchored, debug.CanCollide, debug.CanQuery, debug.Transparency = true, false, false, 0.75
		debug.Color = Color3.fromRGB(255, 60, 60)
		debug.Size, debug.CFrame, debug.Parent = controller.config.AttackHitboxSize, box, workspace
		task.delay(0.12, function() if debug.Parent then debug:Destroy() end end)
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {controller.model}
	local hitCharacters: {[Model]: boolean} = {}
	for _, part in ipairs(workspace:GetPartBoundsInBox(box, controller.config.AttackHitboxSize, params)) do
		local character = part:FindFirstAncestorOfClass("Model")
		if character and not hitCharacters[character] and not character:GetAttribute("IsZombie") then
			local victim = character:FindFirstChildOfClass("Humanoid")
			local victimRoot = character:FindFirstChild("HumanoidRootPart")
			if victim and victimRoot and victim.Health > 0
				and (victimRoot.Position - controller.root.Position).Magnitude <= controller.config.AttackRange + 2
				and ZombieTargeting.HasLineOfSight(controller.model, character, controller.root.Position + Vector3.new(0, 2, 0), victimRoot.Position + Vector3.new(0, 2, 0)) then
				hitCharacters[character] = true
				victim:TakeDamage(controller.config.AttackDamage)
			end
		end
	end
end

return ZombieCombat