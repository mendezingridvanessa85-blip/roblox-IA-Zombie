--!strict
local ZombieStateMachine = {}
ZombieStateMachine.__index = ZombieStateMachine

local allowed = {
	Idle = {Patrol = true, Chase = true, Stunned = true, Dead = true},
	Patrol = {Idle = true, Chase = true, Stunned = true, Dead = true},
	Chase = {Idle = true, Attack = true, Stunned = true, Dead = true},
	Attack = {Chase = true, Idle = true, Stunned = true, Dead = true},
	Stunned = {Idle = true, Chase = true, Dead = true},
	Dead = {},
}

function ZombieStateMachine.new(initial: string, changed: (string, string) -> ())
	return setmetatable({state = initial, changed = changed}, ZombieStateMachine)
end

function ZombieStateMachine:Set(nextState: string): boolean
	if self.state == nextState then return false end
	if not (allowed[self.state] and allowed[self.state][nextState]) then return false end
	local previous = self.state
	self.state = nextState
	self.changed(previous, nextState)
	return true
end

return ZombieStateMachine