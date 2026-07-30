--!strict
local ZombieAnimation = {}
ZombieAnimation.__index = ZombieAnimation

local definitions = {
	Idle = {id = "rbxassetid://80280227573629", priority = Enum.AnimationPriority.Idle, looped = true},
	Walk = {id = "rbxassetid://90858711571530", priority = Enum.AnimationPriority.Movement, looped = true},
	Run = {id = "rbxassetid://97504053196103", priority = Enum.AnimationPriority.Movement, looped = true},
	Attack1 = {id = "rbxassetid://138289101101151", priority = Enum.AnimationPriority.Action, looped = false},
	Attack2 = {id = "rbxassetid://87506175221098", priority = Enum.AnimationPriority.Action, looped = false},
}

function ZombieAnimation.new(humanoid: Humanoid)
	local self = setmetatable({}, ZombieAnimation)
	self.tracks = {}
	self.currentMovement = nil
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	for name, definition in pairs(definitions) do
		local animation = Instance.new("Animation")
		animation.Name = "Zombie" .. name
		animation.AnimationId = definition.id
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		animation:Destroy()
		if ok and track then
			track.Priority = definition.priority
			track.Looped = definition.looped
			self.tracks[name] = track
		else
			warn("Zombie animation unavailable:", name)
		end
	end
	return self
end

function ZombieAnimation:PlayMovement(name: string)
	if self.currentMovement == name then return end
	if self.currentMovement and self.tracks[self.currentMovement] then
		self.tracks[self.currentMovement]:Stop(0.15)
	end
	self.currentMovement = name
	local track = self.tracks[name]
	if track then
		track:Play(0.15)
		track:AdjustSpeed(name == "Run" and 1.35 or 1)
	end
end

function ZombieAnimation:PlayAttack(name: string)
	self:StopMovement()
	local track = self.tracks[name]
	if track then track:Play(0.08) end
end

function ZombieAnimation:StopMovement()
	if self.currentMovement and self.tracks[self.currentMovement] then
		self.tracks[self.currentMovement]:Stop(0.15)
	end
	self.currentMovement = nil
end

function ZombieAnimation:StopAttacks()
	for _, name in ipairs({"Attack1", "Attack2"}) do
		local track = self.tracks[name]
		if track then track:Stop(0.08) end
	end
end

function ZombieAnimation:StopAll()
	self:StopMovement()
	self:StopAttacks()
	for _, track in pairs(self.tracks) do track:Stop(0.08) end
end

function ZombieAnimation:Destroy()
	self:StopAll()
	table.clear(self.tracks)
end

return ZombieAnimation