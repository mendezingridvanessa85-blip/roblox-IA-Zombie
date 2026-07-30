--!strict
local ZombieConfig = require(script.Parent.ZombieConfig)
local ZombieAnimation = require(script.Parent.ZombieAnimation)
local ZombieCombat = require(script.Parent.ZombieCombat)
local ZombiePathfinding = require(script.Parent.ZombiePathfinding)
local ZombieNavigationSensor = require(script.Parent.ZombieNavigationSensor)
local ZombieStateMachine = require(script.Parent.ZombieStateMachine)
local ZombieTargeting = require(script.Parent.ZombieTargeting)

local ZombieController = {}
ZombieController.__index = ZombieController

local controllerSerial = 0

local RECOVERY_DIRECTIONS = {
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
	Vector3.new(1, 0, 1).Unit,
	Vector3.new(1, 0, -1).Unit,
	Vector3.new(-1, 0, 1).Unit,
	Vector3.new(-1, 0, -1).Unit,
}

function ZombieController.new(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	controllerSerial += 1
	local self = setmetatable({}, ZombieController)
	self.agentId = controllerSerial
	self.model, self.humanoid, self.root = model, humanoid, root
	self.config = ZombieConfig.ForZombie(model)
	self.destroyed, self.isAttacking, self.attackId, self.nextAttackAt = false, false, 0, 0
	self.target, self.lastScan, self.idleUntil, self.lastStuckCheck, self.lastConfigRefresh = nil, 0, 0, 0, 0
	self.lastPosition, self.lastTargetPosition, self.lastPathAt = root.Position, nil, 0
	self.lastKnownTargetPosition, self.lastSeenAt, self.hadLineOfSight = nil, 0, false
	self.lastTargetVelocity, self.lastPredictionAt = Vector3.zero, 0
	self.stuckSamples, self.lastObstacleJump, self.recoveryAttempt, self.pathRetryAt = 0, 0, 0, 0
	self.obstacleSamples, self.lastObstacleAnalysisAt = 0, 0
	self.navigationOverride, self.currentNavigationGoal = nil, nil
	self.crowdOffset = Vector3.zero
	self.failedGoals = {}
	self.searchPoints, self.searchIndex, self.searchStartedAt, self.lastSearchAdvanceAt = {}, 0, 0, 0
	self.connections = {}
	humanoid.AutoRotate = true
	humanoid.UseJumpPower = true
	humanoid.JumpPower = self.config.JumpPower
	self.animation = ZombieAnimation.new(humanoid)
	self.path = ZombiePathfinding.new(humanoid, root, self.config)
	self.sensor = ZombieNavigationSensor.new(model, humanoid, root, self.config)
	self.machine = ZombieStateMachine.new("Idle", function(_, nextState) self:_entered(nextState) end)
	self.state = "Idle"
	model:SetAttribute("IsZombie", true)
	model:SetAttribute("ZombieAgentId", self.agentId)
	model:SetAttribute("Stunned", model:GetAttribute("Stunned") == true)
	model:SetAttribute("StunEndTime", model:GetAttribute("StunEndTime") or 0)
	model:SetAttribute("IsAttacking", false)
	model:SetAttribute("CurrentTargetUserId", 0)
	model:SetAttribute("AIState", "Idle")
	model:SetAttribute("NavigationMode", "Idle")
	model:SetAttribute("ObstacleType", "Clear")
	model:SetAttribute("PathFailures", 0)
	model:SetAttribute("PathCandidateIndex", 0)
	model:SetAttribute("PathScore", -1)
	model:SetAttribute("PathWaypointCount", 0)
	model:SetAttribute("PathJumpCount", 0)
	table.insert(self.connections, humanoid.Died:Connect(function() self:SetState("Dead") end))
	table.insert(self.connections, model.AncestryChanged:Connect(function(_, parent) if not parent then self:Destroy() end end))
	table.insert(self.connections, model:GetAttributeChangedSignal("Stunned"):Connect(function() if model:GetAttribute("Stunned") then self:SetState("Stunned") end end))
	self:_entered("Idle")
	task.spawn(function() self:_loop() end)
	return self
end

function ZombieController:SetState(nextState: string)
	if self.destroyed and nextState ~= "Dead" then return end
	if self.machine:Set(nextState) then self.state = nextState end
end

function ZombieController:_entered(nextState: string)
	if self.destroyed and nextState ~= "Dead" then return end
	self.state = nextState
	self.model:SetAttribute("AIState", nextState)
	if nextState == "Dead" then
		self.destroyed = true
		self.path:Cancel()
		self.isAttacking = false
		self.model:SetAttribute("IsAttacking", false)
		self.model:SetAttribute("NavigationMode", "Dead")
		self.humanoid.WalkSpeed = 0
		self.animation:Destroy()
		self.path:Destroy()
		self.sensor:Destroy()
		for _, connection in ipairs(self.connections) do connection:Disconnect() end
		table.clear(self.connections)
		if self.config.DestroyOnDeath then task.delay(self.config.CorpseLifetime, function() if self.model.Parent then self.model:Destroy() end end) end
		return
	end
	self.path:Cancel()
	self.isAttacking = false
	self.model:SetAttribute("IsAttacking", false)
	if nextState == "Idle" then
		self.model:SetAttribute("NavigationMode", "Idle")
		self.humanoid.WalkSpeed = 0
		self.animation:PlayMovement("Idle")
		self.idleUntil = workspace:GetServerTimeNow() + self.config.IdleDurationMin + math.random() * (self.config.IdleDurationMax - self.config.IdleDurationMin)
	elseif nextState == "Patrol" then
		self.model:SetAttribute("NavigationMode", "Patrol")
		self.humanoid.WalkSpeed = self.config.WalkSpeed
		self.animation:PlayMovement("Walk")
		self:_startPatrol()
	elseif nextState == "Chase" then
		self.model:SetAttribute("NavigationMode", "Path")
		self.humanoid.WalkSpeed = self.config.RunSpeed
		self.animation:PlayMovement("Run")
		self.lastPathAt = 0
		self.lastTargetPosition = nil
		self.stuckSamples = 0
	elseif nextState == "Attack" then
		self.model:SetAttribute("NavigationMode", "Attack")
		self.path.failures = 0
		self.recoveryAttempt = 0
		self.model:SetAttribute("PathFailures", 0)
		self.humanoid.WalkSpeed = 0
		self:_attack()
	elseif nextState == "Stunned" then
		self.model:SetAttribute("NavigationMode", "Stunned")
		self.humanoid.WalkSpeed = 0
		self.animation:PlayMovement("Idle")
	end
end

function ZombieController:_scan()
	local now = workspace:GetServerTimeNow()
	if now - self.lastScan < self.config.TargetScanInterval then return end
	self.lastScan = now
	local _, currentRoot = ZombieTargeting.GetTargetRoot(self.target, self.root.Position, self.config.LoseTargetRange)
	if currentRoot then return end
	local previousTarget = self.target
	self.target = ZombieTargeting.GetClosest(
		self.model,
		self.root.Position,
		self.config.DetectionRange,
		nil,
		true
	)
	self.model:SetAttribute("CurrentTargetUserId", self.target and self.target.UserId or 0)
	if self.target and self.target ~= previousTarget then
		local _, root = ZombieTargeting.GetTargetRoot(self.target, self.root.Position, self.config.DetectionRange)
		if root then
			self.lastKnownTargetPosition = root.Position
			self.lastSeenAt = now
			self.recoveryAttempt = 0
			self.pathRetryAt = 0
			self.searchPoints = {}
			self.searchIndex = 0
			self.searchStartedAt = 0
			table.clear(self.failedGoals)
		end
	end
end

function ZombieController:_startPatrol()
	local angle, distance = math.random() * math.pi * 2, math.random() * self.config.PatrolRadius
	local candidate = self.root.Position + Vector3.new(math.cos(angle) * distance, 8, math.sin(angle) * distance)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {self.model}
	local hit = workspace:Raycast(candidate, Vector3.new(0, -20, 0), params)
	if not hit or hit.Normal.Y < 0.7 then self:SetState("Idle"); return end
	local destination = hit.Position
	self.path:GoTo(destination, function(success)
		if not self.destroyed and self.state == "Patrol" then
			if success then task.delay(self.config.PatrolWaitTime, function() if not self.destroyed and self.state == "Patrol" then self:SetState("Idle") end end)
			else self:SetState("Idle") end
		end
	end)
end

function ZombieController:_attack()
	if self.isAttacking or not self.config.CanAttack or workspace:GetServerTimeNow() < self.nextAttackAt then self:SetState("Chase"); return end
	local targetHumanoid, targetRoot = ZombieTargeting.GetTargetRoot(self.target, self.root.Position, self.config.AttackRange + 1)
	if not targetHumanoid or not targetRoot then self:SetState("Chase"); return end
	self.isAttacking, self.attackId = true, self.attackId + 1
	self.nextAttackAt = workspace:GetServerTimeNow() + self.config.AttackCooldown
	local attackId = self.attackId
	self.model:SetAttribute("IsAttacking", true)
	self.root.CFrame = CFrame.lookAt(self.root.Position, Vector3.new(targetRoot.Position.X, self.root.Position.Y, targetRoot.Position.Z))
	self.animation:PlayAttack(math.random(1, 2) == 1 and "Attack1" or "Attack2")
	task.delay(self.config.AttackHitTime, function() ZombieCombat.ApplyHit(self, attackId) end)
	task.delay(self.config.AttackHitTime + self.config.AttackRecoveryTime, function()
		if self.destroyed or self.attackId ~= attackId then return end
		self.isAttacking = false
		self.model:SetAttribute("IsAttacking", false)
		if self.state == "Attack" then
			local _, root = ZombieTargeting.GetTargetRoot(self.target, self.root.Position, self.config.AttackRange + 1)
			self:SetState(root and "Chase" or "Idle")
		end
	end)
end

function ZombieController:_tryObstacleJump(analysis: any?): boolean
	local now = workspace:GetServerTimeNow()
	if now - self.lastObstacleJump < self.config.ObstacleJumpCooldown
		or self.humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end
	local shouldJump = self.path.currentWaypointAction == Enum.PathWaypointAction.Jump
		or (analysis and analysis.kind == "LowObstacle" and analysis.jumpable)
	if not shouldJump then return false end
	self.lastObstacleJump = now
	self.model:SetAttribute("NavigationMode", "Jump")
	self.humanoid.Jump = true
	self.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	return true
end

function ZombieController:_processLocalNavigation(pursuitGoal: Vector3, targetRoot: BasePart?)
	local targetCharacter = self.target and self.target.Character or nil
	local desiredPoint = self.path.currentWaypoint or pursuitGoal
	local analysis, updated = self.sensor:Analyze(desiredPoint, targetCharacter)
	if not updated then return end
	self.model:SetAttribute("ObstacleType", analysis.kind)
	self.lastObstacleAnalysisAt = analysis.timestamp
	if analysis.kind == "LowObstacle" and analysis.jumpable then
		self.obstacleSamples = 0
		self:_tryObstacleJump(analysis)
		return
	end
	if (analysis.kind == "Wall" or analysis.kind == "Drop") and self.path.active and not self.path.computing then
		self.obstacleSamples += 1
		if self.obstacleSamples >= self.config.ObstacleRepathSamples
			and self.stuckSamples > 0 and analysis.steerPoint then
			self.obstacleSamples = 0
			self.navigationOverride = analysis.steerPoint
			self.recoveryAttempt += 1
			self.model:SetAttribute("NavigationMode", "Avoid")
			self.path:RequestRepath("Local" .. analysis.kind)
			self.pathRetryAt = workspace:GetServerTimeNow() + self.config.PathRetryBaseDelay
			self.lastPathAt = 0
		end
	else
		self.obstacleSamples = 0
		if self.path.active and self.searchStartedAt == 0 then
			self.model:SetAttribute("NavigationMode", "Path")
		end
	end
end

function ZombieController:_goalKey(goal: Vector3): string
	local cell = self.config.FailedGoalCellSize
	return string.format(
		"%d:%d:%d",
		math.round(goal.X / cell),
		math.round(goal.Y / cell),
		math.round(goal.Z / cell)
	)
end

function ZombieController:_isFailedGoal(goal: Vector3): boolean
	local key = self:_goalKey(goal)
	local record = self.failedGoals[key]
	if not record then return false end
	if record.expiresAt <= workspace:GetServerTimeNow() then
		self.failedGoals[key] = nil
		return false
	end
	return record.count >= self.config.MaxFailedGoalUses
end

function ZombieController:_recordFailedGoal(goal: Vector3)
	local key = self:_goalKey(goal)
	local record = self.failedGoals[key]
	if not record or record.expiresAt <= workspace:GetServerTimeNow() then
		record = {count = 0, expiresAt = 0}
		self.failedGoals[key] = record
	end
	record.count += 1
	record.expiresAt = workspace:GetServerTimeNow() + self.config.FailedGoalLifetime
end

function ZombieController:_getRecoveryDestination(goal: Vector3): Vector3
	if self.navigationOverride then
		local override = self.navigationOverride
		self.navigationOverride = nil
		if not self:_isFailedGoal(override) then return override end
	end
	if self.recoveryAttempt <= 1 and not self:_isFailedGoal(goal) then return goal end
	for offset = 0, #RECOVERY_DIRECTIONS - 1 do
		local attempt = math.max(2, self.recoveryAttempt + offset)
		local offsetIndex = ((attempt - 2) % #RECOVERY_DIRECTIONS) + 1
		local ring = math.min(2, math.floor((attempt - 2) / #RECOVERY_DIRECTIONS) + 1)
		local candidate = goal + RECOVERY_DIRECTIONS[offsetIndex]
			* self.config.RecoveryDestinationRadius * ring
		local ground = self.sensor:ProjectToGround(candidate, self.target and self.target.Character or nil)
		if ground and not self:_isFailedGoal(ground) then
			self.model:SetAttribute("NavigationMode", "Recover")
			return ground
		end
	end
	return goal
end

function ZombieController:_getNavigationCandidates(goal: Vector3): {Vector3}
	local candidates: {Vector3} = {}
	local seen: {[string]: boolean} = {}
	local targetCharacter = self.target and self.target.Character or nil
	local function addCandidate(point: Vector3, projectToGround: boolean)
		local candidate = point
		if projectToGround then
			local projected = self.sensor:ProjectToGround(point, targetCharacter)
			if not projected then return end
			candidate = projected
		end
		local key = self:_goalKey(candidate)
		if seen[key] or self:_isFailedGoal(candidate) then return end
		seen[key] = true
		table.insert(candidates, candidate)
	end

	addCandidate(goal, false)
	if self.navigationOverride then
		addCandidate(self.navigationOverride, true)
		self.navigationOverride = nil
	end
	local analysis = self.sensor.lastAnalysis
	if analysis and analysis.steerPoint
		and (analysis.kind == "Wall" or analysis.kind == "Drop") then
		addCandidate(analysis.steerPoint, true)
	end
	local directionCount = math.clamp(math.floor(self.config.PathCandidateCount), 1, #RECOVERY_DIRECTIONS)
	local ringCount = math.max(1, math.floor(self.config.PathCandidateRings))
	for ring = 1, ringCount do
		local radius = self.config.RecoveryDestinationRadius * ring
		for index = 1, directionCount do
			addCandidate(goal + RECOVERY_DIRECTIONS[index] * radius, true)
		end
	end
	if #candidates == 0 then table.insert(candidates, goal) end
	return candidates
end

function ZombieController:_predictTargetPosition(targetRoot: BasePart): Vector3
	local now = workspace:GetServerTimeNow()
	local velocity = targetRoot.AssemblyLinearVelocity
	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local distance = (targetRoot.Position - self.root.Position).Magnitude
	local interceptTime = math.clamp(
		(distance / math.max(self.config.RunSpeed, 1)) * self.config.PredictionDistanceFactor,
		self.config.PredictionMinTime,
		self.config.PredictionMaxTime
	)
	local acceleration = Vector3.zero
	local deltaTime = now - self.lastPredictionAt
	if self.lastPredictionAt > 0 and deltaTime > 0.03 then
		acceleration = (horizontalVelocity - self.lastTargetVelocity) / deltaTime
		if acceleration.Magnitude > self.config.MaxTargetAcceleration then
			acceleration = acceleration.Unit * self.config.MaxTargetAcceleration
		end
	end
	self.lastTargetVelocity = horizontalVelocity
	self.lastPredictionAt = now
	local lead = horizontalVelocity * interceptTime
		+ acceleration * (0.5 * interceptTime * interceptTime * self.config.PredictionAccelerationWeight)
	if lead.Magnitude > self.config.MaxPredictionDistance then
		lead = lead.Unit * self.config.MaxPredictionDistance
	end
	local predicted = targetRoot.Position + lead
	local ground = self.sensor:ProjectToGround(predicted, self.target and self.target.Character or nil)
	return ground or predicted
end

function ZombieController:_buildSearchPoints(center: Vector3)
	self.searchPoints = {}
	self.searchIndex = 1
	self.searchStartedAt = workspace:GetServerTimeNow()
	self.lastSearchAdvanceAt = self.searchStartedAt
	for index = 1, self.config.SearchPointCount do
		local angle = (index - 1) / self.config.SearchPointCount * math.pi * 2
		local candidate = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * self.config.SearchRadius
		local ground = self.sensor:ProjectToGround(candidate, self.target and self.target.Character or nil)
		if ground and not self:_isFailedGoal(ground) then table.insert(self.searchPoints, ground) end
	end
	if #self.searchPoints == 0 then table.insert(self.searchPoints, center) end
	self.model:SetAttribute("NavigationMode", "Search")
end

function ZombieController:_getPursuitGoal(): (Vector3?, BasePart?, boolean)
	local now = workspace:GetServerTimeNow()
	local _, targetRoot = ZombieTargeting.GetTargetRoot(self.target, self.root.Position, self.config.LoseTargetRange)
	local visible = false
	if targetRoot and self.target and self.target.Character then
		visible = ZombieTargeting.HasLineOfSight(
			self.model,
			self.target.Character,
			self.root.Position + Vector3.new(0, 1.5, 0),
			targetRoot.Position + Vector3.new(0, 1.5, 0)
		)
		if visible then
			if not self.hadLineOfSight then
				self.recoveryAttempt = 0
				self.pathRetryAt = 0
			end
			self.hadLineOfSight = true
			self.lastKnownTargetPosition = self:_predictTargetPosition(targetRoot)
			self.lastSeenAt = now
			self.searchPoints = {}
			self.searchIndex = 0
			self.searchStartedAt = 0
		else
			self.hadLineOfSight = false
		end
		if not visible and not self.lastKnownTargetPosition then
			self.lastKnownTargetPosition = targetRoot.Position
			self.lastSeenAt = now
		end
	end
	if visible and self.lastKnownTargetPosition then
		return self.lastKnownTargetPosition, targetRoot, true
	end
	if self.searchStartedAt > 0 and #self.searchPoints > 0 then
		return self.searchPoints[self.searchIndex], targetRoot, false
	end
	if self.lastKnownTargetPosition then return self.lastKnownTargetPosition, targetRoot, false end
	return nil, targetRoot, false
end

function ZombieController:_chase()
	local now = workspace:GetServerTimeNow()
	local pursuitGoal, targetRoot, visible = self:_getPursuitGoal()
	if not pursuitGoal then
		self.target = nil
		self.model:SetAttribute("CurrentTargetUserId", 0)
		self:SetState("Idle")
		return
	end
	if targetRoot and visible then
		local distance = (targetRoot.Position - self.root.Position).Magnitude
		if distance <= self.config.AttackRange and now >= self.nextAttackAt then
			self:SetState("Attack")
			return
		end
	end

	local pursuitOffset = self.root.Position - pursuitGoal
	local horizontalPursuitDistance = Vector3.new(pursuitOffset.X, 0, pursuitOffset.Z).Magnitude
	if not visible and horizontalPursuitDistance <= self.config.LastKnownReachDistance then
		if self.searchStartedAt == 0 then
			self:_buildSearchPoints(self.lastKnownTargetPosition or pursuitGoal)
			pursuitGoal = self.searchPoints[self.searchIndex]
			self.path:RequestRepath("SearchStarted")
			self.lastPathAt = 0
		elseif now - self.searchStartedAt >= self.config.SearchDuration
			and now - self.lastSeenAt >= self.config.TargetMemoryDuration then
			self.target = nil
			self.lastKnownTargetPosition = nil
			self.searchPoints = {}
			self.model:SetAttribute("CurrentTargetUserId", 0)
			self:SetState("Idle")
			return
		elseif now - self.lastSearchAdvanceAt >= self.config.SearchPointHoldTime then
			self.searchIndex = self.searchIndex % #self.searchPoints + 1
			self.lastSearchAdvanceAt = now
			pursuitGoal = self.searchPoints[self.searchIndex]
			self.path:RequestRepath("SearchAdvance")
			self.lastPathAt = 0
		end
	end

	self:_processLocalNavigation(pursuitGoal, targetRoot)
	local baseGoal = pursuitGoal
	if targetRoot then
		local desiredCrowdOffset = self.sensor:GetCrowdOffset()
		self.crowdOffset = self.crowdOffset:Lerp(desiredCrowdOffset, 0.5)
		if self.crowdOffset.Magnitude > 0.15 then
			local separated = self.sensor:ProjectToGround(
				pursuitGoal + self.crowdOffset,
				self.target and self.target.Character or nil
			)
			if separated then baseGoal = separated end
		end
	else
		self.crowdOffset = Vector3.zero
	end
	local navigationGoal = baseGoal
	local navigationCandidates = self:_getNavigationCandidates(navigationGoal)
	self.currentNavigationGoal = navigationGoal
	local targetMoved = not self.lastTargetPosition
		or (pursuitGoal - self.lastTargetPosition).Magnitude >= self.config.TargetMovementThreshold
	local needsPath = self.path:NeedsNewPath(navigationGoal) or targetMoved
	if needsPath and not self.path.computing and now >= self.pathRetryAt
		and now - self.lastPathAt >= self.config.PathRecomputeInterval then
		self.lastPathAt = now
		self.lastTargetPosition = pursuitGoal
		if self.searchStartedAt == 0 then
			self.model:SetAttribute("NavigationMode", "Plan")
		end
		self.path:GoToBest(navigationGoal, navigationCandidates, function(success, _reason, selectedGoal)
			if self.destroyed or self.state ~= "Chase" then return end
			local submittedGoal = selectedGoal or navigationGoal
			self.model:SetAttribute("PathFailures", self.path.failures)
			if success then
				self.recoveryAttempt = math.max(0, self.recoveryAttempt - 1)
				self.failedGoals[self:_goalKey(submittedGoal)] = nil
				self.pathRetryAt = workspace:GetServerTimeNow() + self.config.PathRecomputeInterval
			else
				self:_recordFailedGoal(submittedGoal)
				self.recoveryAttempt += 1
				if self.recoveryAttempt > self.config.MaxPathFailures then self.recoveryAttempt = 2 end
				local exponent = math.min(3, math.max(0, self.recoveryAttempt - 1))
				local retryDelay = math.min(
					self.config.PathRetryMaxDelay,
					self.config.PathRetryBaseDelay * (2 ^ exponent)
				)
				self.pathRetryAt = workspace:GetServerTimeNow() + retryDelay
				self.lastPathAt = 0
			end
		end)
	end
end

function ZombieController:_stuckCheck()
	local now = workspace:GetServerTimeNow()
	if now - self.lastStuckCheck < self.config.StuckCheckInterval then return end
	local offset = self.root.Position - self.lastPosition
	local horizontalMovement = Vector3.new(offset.X, 0, offset.Z).Magnitude
	self.lastPosition, self.lastStuckCheck = self.root.Position, now
	if (self.state ~= "Chase" and self.state ~= "Patrol")
		or not self.path.active or self.path.computing then
		self.stuckSamples = 0
		return
	end
	if horizontalMovement >= self.config.StuckDistanceThreshold then
		self.stuckSamples = 0
		if horizontalMovement >= self.config.StuckDistanceThreshold * 2 then
			self.recoveryAttempt = math.max(0, self.recoveryAttempt - 1)
		end
		return
	end
	self.stuckSamples += 1
	if self.stuckSamples == 1 and self:_tryObstacleJump() then return end
	if self.stuckSamples >= self.config.StuckSamplesBeforeRecovery then
		self.stuckSamples = 0
		self.recoveryAttempt += 1
		if self.recoveryAttempt > self.config.MaxPathFailures then self.recoveryAttempt = 2 end
		local failedDestination = self.path.selectedDestination or self.currentNavigationGoal
		if failedDestination then self:_recordFailedGoal(failedDestination) end
		local analysis = self.sensor.lastAnalysis
		if analysis and analysis.steerPoint
			and (analysis.kind == "Wall" or analysis.kind == "Drop") then
			self.navigationOverride = analysis.steerPoint
		end
		self.model:SetAttribute("NavigationMode", "Recover")
		self.path:RequestRepath("Stuck")
		self.pathRetryAt = now + self.config.PathRetryBaseDelay
		self.lastPathAt = 0
	end
end

function ZombieController:_updateMovementAnimation()
	if self.state == "Idle" or self.state == "Stunned" then
		self.animation:PlayMovement("Idle")
	elseif self.state == "Patrol" then
		self.animation:PlayMovement("Walk")
	elseif self.state == "Chase" then
		self.animation:PlayMovement("Run")
	end
end

function ZombieController:_loop()
	while not self.destroyed do
		task.wait(0.1)
		if self.destroyed then break end
		local now = workspace:GetServerTimeNow()
		if now - self.lastConfigRefresh >= self.config.ConfigRefreshInterval then
			self.lastConfigRefresh = now
			self.config = ZombieConfig.ForZombie(self.model)
			self.path.config = self.config
			self.sensor.config = self.config
			self.humanoid.JumpPower = self.config.JumpPower
		end
		if self.humanoid.Health <= 0 then self:SetState("Dead"); break end
		local stunEnd = self.model:GetAttribute("StunEndTime")
		if self.model:GetAttribute("Stunned") == true then
			if type(stunEnd) == "number" and stunEnd > 0 and workspace:GetServerTimeNow() >= stunEnd then
				self.model:SetAttribute("Stunned", false); self.model:SetAttribute("StunEndTime", 0)
				self:SetState(self.target and "Chase" or "Idle")
			elseif self.state ~= "Stunned" then self:SetState("Stunned") end
		elseif self.state == "Stunned" then self:SetState(self.target and "Chase" or "Idle") end
		if self.state == "Stunned" then continue end
		self:_scan()
		if self.state == "Idle" then
			if self.target then self:SetState("Chase")
			elseif workspace:GetServerTimeNow() >= self.idleUntil and self.config.CanPatrol then self:SetState("Patrol") end
		elseif self.state == "Patrol" then
			if self.target then self:SetState("Chase") end
		elseif self.state == "Chase" then self:_chase()
		elseif self.state == "Attack" then
			local _, targetRoot = ZombieTargeting.GetTargetRoot(self.target, self.root.Position, self.config.AttackRange + 1)
			if not targetRoot then self:SetState("Idle") end
		end
		self:_stuckCheck()
		self:_updateMovementAnimation()
	end
end

function ZombieController:Destroy()
	if self.destroyed then return end
	self.destroyed = true
	self.path:Destroy()
	self.sensor:Destroy()
	self.animation:Destroy()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	table.clear(self.connections)
end

return ZombieController