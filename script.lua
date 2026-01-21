local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Terrain = workspace:FindFirstChildOfClass("Terrain")

------------------------------------------------
-- 1. fps boost
------------------------------------------------
local function applyFPSBoost()
	Lighting.GlobalShadows = false
	Lighting.Brightness = 0
	Lighting.ClockTime = 12
	Lighting.ExposureCompensation = 0
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.Ambient = Color3.fromRGB(128,128,128)
	Lighting.OutdoorAmbient = Color3.fromRGB(128,128,128)
	Lighting.Technology = Enum.Technology.Compatibility

	for _, v in pairs(Lighting:GetChildren()) do
		if v:IsA("Sky")
		or v:IsA("Atmosphere")
		or v:IsA("BloomEffect")
		or v:IsA("SunRaysEffect")
		or v:IsA("ColorCorrectionEffect")
		or v:IsA("DepthOfFieldEffect")
		or v:IsA("BlurEffect") then
			v:Destroy()
		end
	end

	if Terrain then
		Terrain.WaterWaveSize = 0
		Terrain.WaterWaveSpeed = 0
		Terrain.WaterReflectance = 0
		Terrain.WaterTransparency = 1
	end
end

------------------------------------------------
-- 2. f
------------------------------------------------
local function flatWorkspace()
	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Material = Enum.Material.Plastic
			obj.Reflectance = 0
			obj.CastShadow = false

		elseif obj:IsA("Decal") or obj:IsA("Texture") then
			obj:Destroy()

		elseif obj:IsA("ParticleEmitter")
		or obj:IsA("Trail")
		or obj:IsA("Beam")
		or obj:IsA("Fire")
		or obj:IsA("Smoke")
		or obj:IsA("Sparkles") then
			obj.Enabled = false
		end
	end
end

------------------------------------------------
-- 3. fixed
------------------------------------------------
local function stopAnimator(animator)
	for _, track in pairs(animator:GetPlayingAnimationTracks()) do
		pcall(function()
			track:Stop(0)
		end)
	end

	animator.AnimationPlayed:Connect(function(track)
		pcall(function()
			track:Stop(0)
		end)
	end)
end

local function handleAnimations(obj)
	-- Humanoid (players / NPCs)
	if obj:IsA("Humanoid") then
		local animator = obj:FindFirstChildOfClass("Animator")
		if animator then
			stopAnimator(animator)
		end

		obj.AnimationPlayed:Connect(function(track)
			pcall(function()
				track:Stop(0)
			end)
		end)
	end

	-- Animator direto (tools / pets equipados)
	if obj:IsA("Animator") then
		stopAnimator(obj)
	end

	-- AnimationController (pets / brainrot)
	if obj:IsA("AnimationController") then
		local animator = obj:FindFirstChildOfClass("Animator")
		if animator then
			stopAnimator(animator)
		end
	end
end

------------------------------------------------
-- 4. E
------------------------------------------------
applyFPSBoost()
flatWorkspace()

for _, obj in pairs(workspace:GetDescendants()) do
	handleAnimations(obj)
end

------------------------------------------------
-- 5. OBJETOS NOVOS (QUANDO EQUIPA TOOL / PET)
------------------------------------------------
workspace.DescendantAdded:Connect(function(obj)
	task.wait()

	handleAnimations(obj)

	if obj:IsA("Decal") or obj:IsA("Texture") then
		obj:Destroy()

	elseif obj:IsA("ParticleEmitter")
	or obj:IsA("Trail")
	or obj:IsA("Beam") then
		obj.Enabled = false

	elseif obj:IsA("BasePart") then
		obj.Material = Enum.Material.Plastic
		obj.CastShadow = false
	end
end)
