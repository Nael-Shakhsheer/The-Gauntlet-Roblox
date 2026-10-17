--!nonstrict
-- Turns a model of loose parts into a welded rig around `root` so limbs can be animated on the client
-- by changing Weld.C0 (client changes never replicate back, so animation costs the server nothing).
-- Parts are named by role: "Leg_A"/"Leg_B" and "Arm_A"/"Arm_B" swing in opposite phase, "Head" bobs.
local Rig = {}

function Rig.weld(model: Model, root: BasePart)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			part.Anchored = false
			part.Massless = true
			local weld = Instance.new("Weld")
			weld.Name = "Rig"
			weld.Part0 = root
			weld.Part1 = part
			weld.C0 = root.CFrame:ToObjectSpace(part.CFrame)
			weld.Parent = part
		end
	end
end

return Rig
