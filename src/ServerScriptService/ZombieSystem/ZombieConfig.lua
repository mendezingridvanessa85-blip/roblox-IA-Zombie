--!strict
local ZombieConfig = {
	DetectionRange = 60,
	LoseTargetRange = 85,
	AttackRange = 5,
	AttackDamage = 15,
	AttackCooldown = 1.5,
	AttackHitTime = 0.45,
	AttackRecoveryTime = 0.35,
	AttackHitboxSize = Vector3.new(5, 5, 5),
	AttackHitboxOffset = CFrame.new(0, 0, -3),
	WalkSpeed = 8,
	RunSpeed = 17,
	IdleDurationMin = 2,
	IdleDurationMax = 5,
	PatrolRadius = 30,
	PatrolWaitTime = 1.5,
	PathRecomputeInterval = 0.45,
	TargetMovementThreshold = 3.5,
	TargetScanInterval = 0.35,
	ConfigRefreshInterval = 0.5,
	StuckCheckInterval = 0.6,
	StuckDistanceThreshold = 0.75,
	MaxPathFailures = 8,
	WaypointReachDistance = 3,
	CorpseLifetime = 8,
	DestroyOnDeath = true,
	CanPatrol = true,
	CanAttack = true,
	CanUsePathfinding = true,
	DebugMode = false,
	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = true,
	WaypointSpacing = 3,
	ObstacleJumpProbeDistance = 3.5,
	ObstacleJumpCooldown = 0.8,
	MaxJumpObstacleHeight = 4.5,
	JumpPower = 55,
	TargetMemoryDuration = 7,
	LastKnownReachDistance = 3,
	PathRetryBaseDelay = 0.15,
	PathRetryMaxDelay = 1,
	RecoveryDestinationRadius = 5,
	StuckSamplesBeforeRecovery = 2,
	PathGoalTolerance = 2.5,
	LocalSensorInterval = 0.2,
	LocalProbeDistance = 4,
	LocalSideProbeDistance = 5,
	LocalSteerDistance = 6,
	ObstacleRepathSamples = 3,
	GroundProbeDepth = 14,
	CrowdScanInterval = 0.35,
	CrowdAvoidanceRadius = 8,
	CrowdAvoidanceStrength = 7,
	TargetPredictionTime = 0.35,
	PredictionMinTime = 0.18,
	PredictionMaxTime = 0.85,
	PredictionDistanceFactor = 0.55,
	PredictionAccelerationWeight = 0.2,
	MaxTargetAcceleration = 40,
	MaxPredictionDistance = 9,
	PathCandidateCount = 8,
	PathCandidateRings = 2,
	PathJumpPenalty = 2.75,
	PathWaypointPenalty = 0.08,
	PathTurnPenalty = 0.35,
	PathClimbPenalty = 0.2,
	PathDeviationPenalty = 1.4,
	DebugShowCandidatePaths = true,
	SearchRadius = 9,
	SearchPointCount = 8,
	SearchDuration = 6,
	SearchPointHoldTime = 0.8,
	FailedGoalCellSize = 4,
	FailedGoalLifetime = 6,
	MaxFailedGoalUses = 2,
}

local attributeOverrides = {
	"DetectionRange", "LoseTargetRange", "AttackRange", "AttackDamage", "AttackCooldown",
	"WalkSpeed", "RunSpeed", "JumpPower", "CanPatrol", "CanAttack", "CanUsePathfinding", "DebugMode",
	"PathCandidateCount", "PathCandidateRings", "DebugShowCandidatePaths",
}

function ZombieConfig.ForZombie(zombie: Model): {[string]: any}
	local values: {[string]: any} = {}
	for key, value in pairs(ZombieConfig) do
		if type(value) ~= "function" then
			values[key] = value
		end
	end
	for _, key in ipairs(attributeOverrides) do
		local override = zombie:GetAttribute(key)
		if override ~= nil and typeof(override) == typeof(values[key]) then
			values[key] = override
		end
	end
	return values
end

return ZombieConfig