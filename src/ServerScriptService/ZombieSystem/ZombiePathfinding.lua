--!strict
local PathfindingService = game:GetService("PathfindingService")

local ZombiePathfinding = {}
ZombiePathfinding.__index = ZombiePathfinding

local debugSerial = 0

function ZombiePathfinding.new(humanoid: Humanoid, root: BasePart, config: {[string]: any})
	debugSerial += 1
	return setmetatable({
		humanoid = humanoid,
		root = root,
		model = root:FindFirstAncestorOfClass("Model"),
		config = config,
		token = 0,
		blockedConnection = nil,
		moveConnection = nil,
		active = false,
		computing = false,
		failures = 0,
		destination = nil,
		selectedDestination = nil,
		currentWaypoint = nil,
		currentWaypointAction = Enum.PathWaypointAction.Walk,
		lastFailureReason = nil,
		debugId = debugSerial,
		debugFolder = nil,
	}, ZombiePathfinding)
end

function ZombiePathfinding:_clearDebug()
	if self.debugFolder then self.debugFolder:ClearAllChildren() end
end

function ZombiePathfinding:_scorePath(waypoints: {PathWaypoint}, destination: Vector3, primaryDestination: Vector3): (number, number)
	local score = 0
	local jumpCount = 0
	local previous = self.root.Position
	local previousDirection: Vector3? = nil
	for _, waypoint in ipairs(waypoints) do
		local segment = waypoint.Position - previous
		local length = segment.Magnitude
		score += length + math.max(0, segment.Y) * self.config.PathClimbPenalty
		if length > 0.05 then
			local direction = segment.Unit
			if previousDirection then
				score += (1 - math.clamp(previousDirection:Dot(direction), -1, 1)) * self.config.PathTurnPenalty
			end
			previousDirection = direction
		end
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			jumpCount += 1
			score += self.config.PathJumpPenalty
		end
		previous = waypoint.Position
	end
	score += #waypoints * self.config.PathWaypointPenalty
	score += (destination - primaryDestination).Magnitude * self.config.PathDeviationPenalty
	return score, jumpCount
end

function ZombiePathfinding:_renderDebug(results: {any}, selected: any)
	self:_clearDebug()
	if not self.config.DebugMode then return end
	if not self.debugFolder then
		local folder = Instance.new("Folder")
		folder.Name = string.format("ZombieNavigationDebug_%d", self.debugId)
		folder.Parent = workspace
		self.debugFolder = folder
	end
	local showAll = self.config.DebugShowCandidatePaths == true
	for _, result in ipairs(results) do
		if result == selected or showAll then
			local chosen = result == selected
			local candidateFolder = Instance.new("Folder")
			candidateFolder.Name = string.format("Candidate_%02d_Score_%.1f", result.index, result.score)
			candidateFolder.Parent = self.debugFolder
			local previous = self.root.Position
			for waypointIndex, waypoint in ipairs(result.waypoints) do
				local waypointColor = waypoint.Action == Enum.PathWaypointAction.Jump
					and Color3.fromRGB(255, 151, 45)
					or (chosen and Color3.fromRGB(39, 221, 255) or Color3.fromRGB(116, 102, 170))
				local marker = Instance.new("Part")
				marker.Name = waypoint.Action == Enum.PathWaypointAction.Jump and "Jump" or "Waypoint"
				marker.Shape = Enum.PartType.Ball
				marker.Size = Vector3.one * (chosen and 0.48 or 0.25)
				marker.Position = waypoint.Position + Vector3.new(0, 0.2, 0)
				marker.Color = waypointColor
				marker.Material = Enum.Material.Neon
				marker.Transparency = chosen and 0.05 or 0.72
				marker.Anchored = true
				marker.CanCollide = false
				marker.CanQuery = false
				marker.CanTouch = false
				marker.CastShadow = false
				marker.Parent = candidateFolder
				local segmentLength = (waypoint.Position - previous).Magnitude
				if segmentLength > 0.1 then
					local segment = Instance.new("Part")
					segment.Name = string.format("Segment_%02d", waypointIndex)
					segment.Size = Vector3.new(chosen and 0.12 or 0.06, chosen and 0.12 or 0.06, segmentLength)
					segment.CFrame = CFrame.lookAt((previous + waypoint.Position) * 0.5, waypoint.Position)
					segment.Color = waypointColor
					segment.Material = Enum.Material.Neon
					segment.Transparency = chosen and 0.2 or 0.82
					segment.Anchored = true
					segment.CanCollide = false
					segment.CanQuery = false
					segment.CanTouch = false
					segment.CastShadow = false
					segment.Parent = candidateFolder
				end
				previous = waypoint.Position
			end
		end
	end
end

function ZombiePathfinding:Cancel(stopMovement: boolean?)
	self.token += 1
	self.active = false
	self.computing = false
	self.destination = nil
	self.selectedDestination = nil
	self.currentWaypoint = nil
	self.currentWaypointAction = Enum.PathWaypointAction.Walk
	if self.blockedConnection then self.blockedConnection:Disconnect(); self.blockedConnection = nil end
	if self.moveConnection then self.moveConnection:Disconnect(); self.moveConnection = nil end
	self:_clearDebug()
	if stopMovement ~= false and self.root.Parent then self.humanoid:MoveTo(self.root.Position) end
end

function ZombiePathfinding:NeedsNewPath(destination: Vector3): boolean
	if self.computing then return false end
	if not self.active or not self.destination then return true end
	return (self.destination - destination).Magnitude > self.config.PathGoalTolerance
end

function ZombiePathfinding:RequestRepath(reason: string)
	self.lastFailureReason = reason
	self:Cancel(false)
end

function ZombiePathfinding:_followPath(
	token: number,
	path: Path,
	waypoints: {PathWaypoint},
	primaryDestination: Vector3,
	selectedDestination: Vector3,
	onComplete: (boolean, string?, Vector3?) -> ()
)
	self.active = true
	self.computing = false
	self.destination = primaryDestination
	self.selectedDestination = selectedDestination
	self.lastFailureReason = nil
	local index = 1
	while index <= #waypoints
		and (waypoints[index].Position - self.root.Position).Magnitude <= self.config.WaypointReachDistance do
		index += 1
	end

	local function finish(success: boolean, reason: string?)
		if token ~= self.token then return end
		self.active = false
		self.computing = false
		self.currentWaypoint = nil
		self.currentWaypointAction = Enum.PathWaypointAction.Walk
		if self.blockedConnection then self.blockedConnection:Disconnect(); self.blockedConnection = nil end
		if self.moveConnection then self.moveConnection:Disconnect(); self.moveConnection = nil end
		if success then
			self.failures = 0
			self.lastFailureReason = nil
		else
			self.failures += 1
			self.lastFailureReason = reason
		end
		onComplete(success, reason, selectedDestination)
	end

	self.blockedConnection = path.Blocked:Connect(function(blockedIndex)
		if blockedIndex >= math.max(1, index - 1) then finish(false, "Blocked") end
	end)

	local function moveNext()
		if token ~= self.token or not self.active then return end
		while index <= #waypoints
			and (waypoints[index].Position - self.root.Position).Magnitude <= self.config.WaypointReachDistance do
			index += 1
		end
		local waypoint = waypoints[index]
		if not waypoint then finish(true, nil); return end
		self.currentWaypoint = waypoint.Position
		self.currentWaypointAction = waypoint.Action
		if self.moveConnection then self.moveConnection:Disconnect() end
		self.moveConnection = self.humanoid.MoveToFinished:Connect(function(reached)
			if token ~= self.token then return end
			if not reached then finish(false, "MoveToFailed"); return end
			index += 1
			moveNext()
		end)
		if waypoint.Action == Enum.PathWaypointAction.Jump
			and self.humanoid.FloorMaterial ~= Enum.Material.Air then
			self.humanoid.Jump = true
			self.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
		self.humanoid:MoveTo(waypoint.Position)
	end
	moveNext()
end

function ZombiePathfinding:GoToBest(
	primaryDestination: Vector3,
	destinations: {Vector3},
	onComplete: (boolean, string?, Vector3?) -> ()
)
	self:Cancel(false)
	if not self.config.CanUsePathfinding then onComplete(false, "Disabled", primaryDestination); return end
	if #destinations == 0 then onComplete(false, "NoCandidates", primaryDestination); return end
	local token = self.token
	local startPosition = self.root.Position
	self.destination = primaryDestination
	self.computing = true
	local pending = #destinations
	local results: {any} = {}
	local lastComputeError = "NoCandidatePath"

	local function finalize()
		if token ~= self.token then return end
		self.computing = false
		if #results == 0 then
			self.active = false
			self.failures += 1
			self.lastFailureReason = lastComputeError
			if self.model then
				self.model:SetAttribute("PathCandidateIndex", 0)
				self.model:SetAttribute("PathScore", -1)
				self.model:SetAttribute("PathWaypointCount", 0)
				self.model:SetAttribute("PathJumpCount", 0)
			end
			onComplete(false, lastComputeError, primaryDestination)
			return
		end
		table.sort(results, function(a, b)
			if math.abs(a.score - b.score) < 0.001 then return a.index < b.index end
			return a.score < b.score
		end)
		local selected = results[1]
		if self.model then
			self.model:SetAttribute("PathCandidateIndex", selected.index)
			self.model:SetAttribute("PathScore", math.round(selected.score * 10) / 10)
			self.model:SetAttribute("PathWaypointCount", #selected.waypoints)
			self.model:SetAttribute("PathJumpCount", selected.jumpCount)
			if self.model:GetAttribute("NavigationMode") == "Plan" then
				self.model:SetAttribute("NavigationMode", "Path")
			end
		end
		self:_renderDebug(results, selected)
		self:_followPath(token, selected.path, selected.waypoints, primaryDestination, selected.destination, onComplete)
	end

	for candidateIndex, destination in ipairs(destinations) do
		task.spawn(function()
			local path = PathfindingService:CreatePath({
				AgentRadius = self.config.AgentRadius,
				AgentHeight = self.config.AgentHeight,
				AgentCanJump = self.config.AgentCanJump,
				WaypointSpacing = self.config.WaypointSpacing,
				Costs = {Water = 50},
			})
			local ok, computeError = pcall(function()
				path:ComputeAsync(startPosition, destination)
			end)
			if token ~= self.token then return end
			if ok and path.Status == Enum.PathStatus.Success then
				local waypoints = path:GetWaypoints()
				if #waypoints > 0 then
					local score, jumpCount = self:_scorePath(waypoints, destination, primaryDestination)
					table.insert(results, {
						path = path,
						waypoints = waypoints,
						destination = destination,
						index = candidateIndex,
						score = score,
						jumpCount = jumpCount,
					})
				else
					lastComputeError = "EmptyPath"
				end
			else
				lastComputeError = ok and path.Status.Name or tostring(computeError)
			end
			pending -= 1
			if pending == 0 then finalize() end
		end)
	end
end

function ZombiePathfinding:GoTo(destination: Vector3, onComplete: (boolean, string?) -> ())
	self:GoToBest(destination, {destination}, function(success, reason)
		onComplete(success, reason)
	end)
end

function ZombiePathfinding:Destroy()
	self:Cancel()
	if self.debugFolder then self.debugFolder:Destroy(); self.debugFolder = nil end
end

return ZombiePathfinding