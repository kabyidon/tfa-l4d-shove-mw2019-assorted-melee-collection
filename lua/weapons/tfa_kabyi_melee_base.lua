if SERVER then
	AddCSLuaFile()
end

DEFINE_BASECLASS("tfa_melee_base")

function SWEP:PrimaryAttack()
	-- Pretty much exactly the same as TFA melee base, just need to run the 
	local self2 = self:GetTable()
	local ply = self:GetOwner()
	if not IsValid(ply) then return end

	if not IsValid(self) then return end
	if ply:IsPlayer() and not self:VMIV() then return end

	self:PrePrimaryAttack()

	if hook.Run("TFA_PrimaryAttack", self) then return end

	BaseClass.PrimaryAttack(self) 
	
	self:PostPrimaryAttack()
	hook.Run("TFA_PostPrimaryAttack", self)
end