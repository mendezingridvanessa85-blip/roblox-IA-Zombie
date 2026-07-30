--!strict
local ZombieNavigationSensor = {}
ZombieNavigationSensor.__index = ZombieNavigationSensor

export type Analysis = {
	kind: string,
	jumpable: boolean,
	landing: Vector3?,
	steerPoint: Vector3?,
	timestamp: number,
}

function ZombieNavigationSensor.new(model: Model, humanoid: Humanoid, root: BasePart, config: {[string]: any})
	return setmetatable({
		model = model,
		humanoid = humanoid,
		root = root,
		config = config,
		lastAnalysisAt = 0,
		lastCrowdAt = 0,
		lastCrowdOffset = Vector3.zero,
		lastAnalysis = {
			kind = "Clear",
			jumpable = false,
			landing = nil,
			steerPoint = nil,
			timestamp = 0,
		},
	}, ZombieNavigationSensor)
end

function ZombieNavigationSensor:_rayParams(targetCharacter: Model?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: {Instance} = {self.model}
	if targetCharacter then table.insert(excluded, targetCharacter) end
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true
	return params
end

function ZombieNavigationSensor:ProjectToGround(point: Vector3, targetCharacter: Model?): Vector3?
	local params = self:_rayParams(targetCharacter)
	local origin = point + Vector3.new(0, 6, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -self.config.GroundProbeDepth, 0), params)
	if hit and hit.Normal.Y >= 0.45 then return hit.Position end
	return nil
end

function ZombieNavigationSensor:_sideSteer(
	forward: Vector3,
	right: Vector3,
	targetCharacter: Model?,
	params: RaycastParams
): Vector3?
	local bestPoint: Vector3? = nil
	local bestScore = -math.huge
	for _, sign in ipairs({-1, 1}) do
		local offset = forward * 2 + right * sign * self.config.LocalSideProbeDistance
		local cast = workspace:Raycast(self.root.Position + Vector3.new(0, 0.5, 0), offset, params)
		local score = cast and cast.Distance or offset.Magnitude
		local candidate = self.root.Position
			+ forward * self.config.LocalSteerDistance
			+ right * sign * self.config.LocalSideProbeDistance
		local ground = self:ProjectToGround(candidate, targetCharacter)
		if ground and score > bestScore then
			bestScore = score
			bestPoint = ground
		end
	end
	return bestPoint
end

function ZombieNavigationSensor:Analyze(desiredPoint: Vector3, targetCharacter: Model?): (Analysis, boolean)
	local now = workspace:GetServerTimeNow()
	if now - self.lastAnalysisAt < self.config.LocalSensorInterval then
		return self.lastAnalysis, false
	end
	self.lastAnalysisAt = now
	local offset = desiredPoint - self.root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.1 then
		self.lastAnalysis = {
			kind = "Clear",
			jumpable = false,
			landing = nil,
			steerPoint = nil,
			timestamp = now,
		}
		return self.lastAnalysis, true
	end
	local forward = flat.Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local direction = forward * self.config.LocalProbeDistance
	local params = self:_rayParams(targetCharacter)
	local lowerHit = workspace:Raycast(self.root.Position - Vector3.new(0, 0.75, 0), direction, params)
	local torsoHit = workspace:Raycast(self.root.Position + Vector3.new(0, 0.35, 0), direction, params)
	local upperHit = workspace:Raycast(self.root.Position + Vector3.new(0, 1.5, 0), direction, params)
	local groundAhead = workspace:Raycast(
		self.root.Position + direction + Vector3.new(0, 3, 0),
		Vector3.new(0, -self.config.GroundProbeDepth, 0),
		params
	)

	local kind = "Clear"
	local jumpable = false
	local landing: Vector3? = nil
	local steerPoint: Vector3? = nil
	if not groundAhead then
		kind = "Drop"
		steerPoint = self:_sideSteer(forward, right, targetCharacter, params)
	elseif lowerHit and not torsoHit and not upperHit then
		kind = "LowObstacle"
		landing = self:ProjectToGround(
			self.root.Position + forward * (self.config.LocalProbeDistance + 2),
			targetCharacter
		)
		if landing then
			local heightDelta = landing.Y - self.root.Position.Y
			jumpable = heightDelta <= self.config.MaxJumpObstacleHeight and heightDelta >= -3
		end
		if not jumpable then steerPoint = self:_sideSteer(forward, right, targetCharacter, params) end
	elseif lowerHit or torsoHit or upperHit then
		kind = "Wall"
		steerPoint = self:_sideSteer(forward, right, targetCharacter, params)
	end
	self.lastAnalysis = {
		kind = kind,
		jumpable = jumpable,
		landing = landing,
		steerPoint = steerPoint,
		timestamp = now,
	}
	return self.lastAnalysis, true
end

function ZombieNavigationSensor:GetCrowdOffset(): Vector3
	local now = workspace:GetServerTimeNow()
	if now - self.lastCrowdAt < self.config.CrowdScanInterval then return self.lastCrowdOffset end
	self.lastCrowdAt = now
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {self.model}
	params.MaxParts = 40
	local separation = Vector3.zero
	local seen: {[Model]: boolean} = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(self.root.Position, self.config.CrowdAvoidanceRadius, params)) do
		local other = part:FindFirstAncestorOfClass("Model")
		if other and not seen[other] and other:GetAttribute("IsZombie") == true then
			local otherRoot = other:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") then
				seen[other] = true
				local away = self.root.Position - otherRoot.Position
				local flat = Vector3.new(away.X, 0, away.Z)
				if flat.Magnitude > 0.05 then
					local weight = 1 - math.clamp(flat.Magnitude / self.config.CrowdAvoidanceRadius, 0, 1)
					separation += flat.Unit * weight
				else
					local ownId = self.model:GetAttribute("ZombieAgentId") or 1
					local otherId = other:GetAttribute("ZombieAgentId") or 2
					local seed = (ownId * 2.399963229728653 + otherId * 0.61803398875) % (math.pi * 2)
					separation += Vector3.new(math.cos(seed), 0, math.sin(seed))
				end
			end
		end
	end
	if separation.Magnitude < 0.05 then
		self.lastCrowdOffset = Vector3.zero
	else
		self.lastCrowdOffset = separation.Unit * math.min(
			self.config.CrowdAvoidanceStrength,
			separation.Magnitude * self.config.CrowdAvoidanceStrength
		)
	end
	return self.lastCrowdOffset
end

function ZombieNavigationSensor:Destroy()
	self.lastAnalysis = {
		kind = "Clear",
		jumpable = false,
		landing = nil,
		steerPoint = nil,
		timestamp = 0,
	}
end

return ZombieNavigationSensor