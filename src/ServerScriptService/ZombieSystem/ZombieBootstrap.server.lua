--!strict
local Workspace = game:GetService("Workspace")
local ZombieService = require(script.Parent.ZombieService)

local observed: {[Model]: {RBXScriptConnection}} = {}

local function isCandidate(model: Model): boolean
	return model.Name == "Zombie" or model:GetAttribute("IsZombie") == true
end

local function cleanup(model: Model)
	local connections = observed[model]
	if connections then
		for _, connection in ipairs(connections) do connection:Disconnect() end
		observed[model] = nil
	end
	ZombieService:DestroyZombie(model)
end

local function consider(model: Model)
	if observed[model] or not model:IsA("Model") then return end
	observed[model] = {}
	table.insert(observed[model], model:GetAttributeChangedSignal("IsZombie"):Connect(function()
		if isCandidate(model) then ZombieService:InitializeZombie(model) end
	end))
	table.insert(observed[model], model.AncestryChanged:Connect(function(_, parent)
		if not parent then cleanup(model) end
	end))
	if isCandidate(model) then ZombieService:InitializeZombie(model) end
end

for _, descendant in ipairs(Workspace:GetDescendants()) do
	if descendant:IsA("Model") then consider(descendant) end
end

Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("Model") then consider(descendant) end
end)
