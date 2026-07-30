--!strict
local Players = game:GetService("Players")

local ZombieService = require(script.Parent.ZombieService)
local demo = workspace:WaitForChild("ZombieAIDemo")
local startPad = demo:WaitForChild("Presentation"):WaitForChild("StartPad") :: BasePart
local playerSpawn = workspace:WaitForChild("AITestPlayerSpawn") :: SpawnLocation

local characterConnections: {[Player]: RBXScriptConnection} = {}

local function findZombie(): Model?
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") and child.Name == "Zombie" and child:FindFirstChild("HumanoidRootPart") then
			return child
		end
	end
	return nil
end

local function beginDemonstration(player: Player, character: Model)
	if demo:GetAttribute("DemoEnabled") ~= true then return end
	local targetRoot = character:WaitForChild("HumanoidRootPart", 10)
	local targetHumanoid = character:FindFirstChildOfClass("Humanoid")
	if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then return end
	character:PivotTo(playerSpawn.CFrame * CFrame.new(0, 4, 0))
	task.wait(0.1)
	local zombie = findZombie()
	if not zombie then
		warn("ZombieAIDemo could not find the Workspace.Zombie R6 model")
		return
	end
	local controller = ZombieService:GetController(zombie)
	local deadline = workspace:GetServerTimeNow() + 3
	while not controller and workspace:GetServerTimeNow() < deadline do
		task.wait(0.1)
		controller = ZombieService:GetController(zombie)
	end
	if not controller then
		warn("ZombieAIDemo could not acquire the zombie controller")
		return
	end
	local zombieRoot = zombie:FindFirstChild("HumanoidRootPart")
	local humanoid = zombie:FindFirstChildOfClass("Humanoid")
	if not zombieRoot or not humanoid or humanoid.Health <= 0 then return end
	local startPosition = startPad.Position + Vector3.new(0, 3, 0)
	zombie:PivotTo(CFrame.lookAt(startPosition, targetRoot.Position))
	ZombieService:SetTarget(zombie, player)
end

local function observePlayer(player: Player)
	if characterConnections[player] then characterConnections[player]:Disconnect() end
	characterConnections[player] = player.CharacterAdded:Connect(function(character)
		task.defer(beginDemonstration, player, character)
	end)
	if player.Character then task.defer(beginDemonstration, player, player.Character) end
end

Players.PlayerAdded:Connect(observePlayer)
Players.PlayerRemoving:Connect(function(player)
	local connection = characterConnections[player]
	if connection then connection:Disconnect(); characterConnections[player] = nil end
end)

for _, player in ipairs(Players:GetPlayers()) do observePlayer(player) end
