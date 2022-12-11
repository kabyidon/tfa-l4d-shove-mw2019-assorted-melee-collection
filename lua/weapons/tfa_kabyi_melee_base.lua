if SERVER then
	AddCSLuaFile()
end

DEFINE_BASECLASS("tfa_melee_base")

local l_CT = CurTime

local att = {}
local attack
local ind
local tr = {}
local traceres = {}
local pos, ang, mdl, ski, prop
local fwd, eang, scl, dirv
local strikedir = Vector()
local srctbl
SWEP.hpf = false
SWEP.hpw = false
local lim_up_vec = Vector(1, 1, 0.05)


function SWEP:StrikeThink()
	if self:GetSprinting() and not self:GetStatL("AllowSprintAttack", false) then
		self:SetComboCount(0)
		--return
	end

	if self:IsSafety() then
		self:SetComboCount(0)

		return
	end

	if not IsFirstTimePredicted() then return end
	if self:GetStatus() ~= TFA.Enum.STATUS_SHOOTING then return end
	if self.up_hat then return end

	if self.AttackSoundTime ~= -1 and CurTime() > self.AttackSoundTime then
		ind = self:GetMelAttackID() or 1
		srctbl = (ind < 0) and self.Secondary_TFA.Attacks or self.Primary_TFA.Attacks
		attack = srctbl[math.abs(ind)]
		self:EmitSound(attack.snd)

		if self:GetOwner().Vox then
			self:GetOwner():Vox("bash", 4)
		end

		self.AttackSoundTime = -1
	end

	if self:GetOwner().Vox and self.VoxSoundTime ~= -1 and CurTime() > self.VoxSoundTime - self:GetOwner():Ping() * 0.001 then
		if self:GetOwner().Vox then
			self:GetOwner():Vox("bash", 4)
		end

		self.VoxSoundTime = -1
	end

	if CurTime() > self:GetStatusEnd() then
		ind = self:GetMelAttackID() or 1
		srctbl = (ind < 0) and self.Secondary_TFA.Attacks or self.Primary_TFA.Attacks
		attack = srctbl[math.abs(ind)]
		self.DamageType = attack.dmgtype
		--Just attacked, so don't do it again
		self.up_hat = true
		self:SetStatus(TFA.Enum.STATUS_IDLE, math.huge)

		if self:GetComboCount() > 0 then
			self:SetNextPrimaryFire(self:GetNextPrimaryFire() - (attack.combotime or 0))
			self:SetNextSecondaryFire(self:GetNextSecondaryFire() - (attack.combotime or 0))
		end

		self:Strike(attack, self.Precision)
	end
end

local totalResults = {}

local function TraceHitFlesh(b)
	return b.MatType == MAT_FLESH or b.MatType == MAT_ALIENFLESH or (IsValid(b.Entity) and b.Entity.IsNPC and (b.Entity:IsNPC() or b.Entity:IsPlayer() or b.Entity:IsRagdoll()))
end

function SWEP:Strike(attk, precision)
	local hitWorld, hitNonWorld, hitFlesh, needsCB
	local distance, direction, maxhull
	local ow = self:GetOwner()
	if not IsValid(ow) then return end
	distance = attk.len
	direction = attk.dir
	maxhull = attk.hull
	table.Empty(totalResults)
	eang = ow:EyeAngles()
	fwd = ow:EyeAngles():Forward()
	tr.start = ow:GetShootPos()
	scl = direction:Length() / precision / 2
	tr.maxs = Vector(scl, scl, scl)
	tr.mins = -tr.maxs
	tr.mask = MASK_SHOT

	tr.filter = function(ent)
		if ent == ow or ent == self then return false end

		return true
	end

	hitWorld = false
	hitNonWorld = false
	hitFlesh = false

	if attk.callback then
		needsCB = true
	else
		needsCB = false
	end

	if maxhull then
		tr.maxs.x = math.min(tr.maxs.x, maxhull / 2)
		tr.maxs.y = math.min(tr.maxs.y, maxhull / 2)
		tr.maxs.z = math.min(tr.maxs.z, maxhull / 2)
		tr.mins = -tr.maxs
	end

	strikedir:Zero()
	strikedir:Add(direction.x * eang:Right())
	strikedir:Add(direction.y * eang:Forward())
	strikedir:Add(direction.z * eang:Up())
	local strikedirfull = strikedir * 1

	if ow:IsPlayer() and ow:IsAdmin() and GetConVarNumber("developer") > 0 then
		local spos, epos = tr.start + Vector(0, 0, -1) + fwd * distance / 2 - strikedirfull / 2, tr.start + Vector(0, 0, -1) + fwd * distance / 2 + strikedirfull / 2
		debugoverlay.Line(spos, epos, 5, Color(255, 0, 0))
		debugoverlay.Cross(spos, 8, 5, Color(0, 255, 0), true)
		debugoverlay.Cross(epos, 4, 5, Color(0, 255, 255), true)
	end

	if SERVER and not game.SinglePlayer() and ow:IsPlayer() then
		ow:LagCompensation(true)
	end

	for i = 1, precision do
		dirv = LerpVector((i - 0.5) / precision, -direction / 2, direction / 2)
		strikedir:Zero()
		strikedir:Add(dirv.x * eang:Right())
		strikedir:Add(dirv.y * eang:Forward())
		strikedir:Add(dirv.z * eang:Up())
		tr.endpos = tr.start + distance * fwd + strikedir
		traceres = util.TraceLine(tr)
		table.insert(totalResults, traceres)
	end

	if SERVER and not game.SinglePlayer() and ow:IsPlayer() then
		ow:LagCompensation(false)
	end

	local forcevec = strikedirfull:GetNormalized() * (attack.force or attack.dmg / 4) * 128
	local damage = DamageInfo()
	damage:SetAttacker(self:GetOwner())
	damage:SetInflictor(self)
	damage:SetDamage(attk.dmg)
	damage:SetDamageType(attk.dmgtype or DMG_SLASH)
	damage:SetDamageForce(forcevec)
	local fleshHits = 0

	-- Keep track of hitNPCs so don't play double hit sound 
	local hitNPCs = {} 
	--Handle flesh
	for _, v in ipairs(totalResults) do
		if v.Hit and IsValid(v.Entity) and TraceHitFlesh(v) and (not v.Entity.TFA_HasMeleeHit) then
			hitNPCs[v.Entity:EntIndex()] = true 
			self:ApplyDamage(v, damage, attk)
			self:SmackEffect(v, damage)
			v.Entity.TFA_HasMeleeHit = true
			fleshHits = fleshHits + 1
			if fleshHits >= (attk.maxhits or 3) then break end

			if attk.hitflesh and not hitFlesh then
				self:EmitSoundNet(attk.hitflesh)
			end

			if attk.callback and needsCB then
				attk.callback(attack, self, v)
				needsCB = false
			end

			hitFlesh = true
		end
		--debugoverlay.Sphere( v.HitPos, 5, 5, color_white )
	end

	--Handle non-world
	for _, v in ipairs(totalResults) do
		if v.Hit and (not TraceHitFlesh(v)) and (not v.Entity.TFA_HasMeleeHit) then
			self:ApplyDamage(v, damage, attk)
			v.Entity.TFA_HasMeleeHit = true

			if not hitNonWorld then
				self:SmackEffect(v, damage)

				if attk.hitworld and not hitFlesh then
					self:EmitSoundNet(attk.hitworld)
				end

				if attk.callback and needsCB then
					attk.callback(attack, self, v)
					needsCB = false
				end

				self:BurstDoor(v.Entity, damage)
				hitNonWorld = true
			end
		end
	end

	-- Handle world
	if not hitNonWorld and not hitFlesh then
		for _, v in ipairs(totalResults) do
			if v.Hit and v.HitWorld and not hitWorld then
				hitWorld = true

				if attk.hitworld then
					self:EmitSoundNet(attk.hitworld)
				end

				self:SmackEffect(v, damage)

				if attk.callback and needsCB then
					attk.callback(attack, self, v)
					needsCB = false
				end
			end
		end
	end

	--Handle empty + cleanup
	for _, v in ipairs(totalResults) do
		if needsCB then
			attk.callback(attack, self, v)
			needsCB = false
		end

		if IsValid(v.Entity) then
			v.Entity.TFA_HasMeleeHit = false
		end
	end

	if attack.kickback and (hitFlesh or hitNonWorld or hitWorld) then
		self:SendViewModelAnim(attack.kickback)
	end

	-- Handle VJ L4D CI flinching and play sound 

	-- glancing blow -- hit in cone but not hit by trace 
	local damage_glance  = DamageInfo()
	damage_glance:SetAttacker(self:GetOwner())
	damage_glance:SetInflictor(self)
	damage_glance:SetDamage(attk.dmg)
	damage_glance:SetDamageType(attk.dmgtype or DMG_SLASH)
	damage_glance:SetDamageForce(forcevec)

	if SERVER then

		local meleeRange = self:GetStatL("Secondary.BashLength") * 1
		for _,v in pairs(ents.FindInSphere(self:GetOwner():GetShootPos(), meleeRange)) do
			if v:IsNPC() && self:GetOwner():Visible(v) && v != self && v != owner then
				if (v.VJ_L4D2_SpecialInfected or v.Shove_Forward or v.Zombie_CanPuke != nil) && !v.VJ_NoFlinch && v:Health() > 0 then	
					local inCone = (self:GetOwner():GetAimVector():Angle():Forward():Dot(((v:GetPos() +v:OBBCenter()) - self:GetOwner():GetShootPos()):GetNormalized()) > math.cos(math.rad((meleeRange))))
					if inCone then
						-- print(v:EntIndex())
						-- PrintTable(hitNPCs)

						if not (sp and CLIENT) && not hitNPCs[v:EntIndex()] then -- remove double hit sounds 
							
							v:TakeDamageInfo(damage_glance, self:GetOwner())
						end	
						self:EmitSoundNet(attk.hitflesh)
						Flinch(self, v)
					end
				else
				end 
			end
		end

		
	end

end

function SWEP:PlaySwing(act)
	self:SendViewModelAnim(act)

	return true, act
end

local lvec, ply, targ
lvec = Vector()

function SWEP:PrimaryAttack()
	local ow = self:GetOwner()

	if IsValid(ow) and ow:IsNPC() then
		local keys = table.GetKeys(self:GetStatL("Primary.Attacks"))
		table.RemoveByValue(keys, "BaseClass")
		local attk = self:GetStatL("Primary.Attacks")[table.Random(keys)]
		local owv = self:GetOwner()

		timer.Simple(0.5, function()
			if IsValid(self) and IsValid(owv) and owv:IsCurrentSchedule(SCHED_MELEE_ATTACK1) then
				attack = attk
				self:Strike(attk, 5)
			end
		end)

		self:SetNextPrimaryFire(CurTime() + attk["end"] or 1)

		timer.Simple(self:GetNextPrimaryFire() - CurTime(), function()
			if IsValid(owv) then
				owv:ClearSchedule()
			end
		end)

		self:GetOwner():SetSchedule(SCHED_MELEE_ATTACK1)
		return
	end

	if self:GetSprinting() and not self:GetStatL("AllowSprintAttack", false) then return end
	if self:IsSafety() then return end
	if not self:VMIV() then return end
	if CurTime() <= self:GetNextPrimaryFire() then return end
	if not TFA.Enum.ReadyStatus[self:GetStatus()] then return end
	if self:GetComboCount() >= self.Primary_TFA.MaxCombo and self.Primary_TFA.MaxCombo > 0 then return end
	table.Empty(att)
	local founddir = false

	if self.Primary_TFA.Directional then
		ply = self:GetOwner()
		--lvec = WorldToLocal(ply:GetVelocity(), Angle(0, 0, 0), vector_origin, ply:EyeAngles()):GetNormalized()
		lvec.x = 0
		lvec.y = 0

		if ply:KeyDown(IN_MOVERIGHT) then
			lvec.y = lvec.y - 1
		end

		if ply:KeyDown(IN_MOVELEFT) then
			lvec.y = lvec.y + 1
		end

		if ply:KeyDown(IN_FORWARD) or ply:KeyDown(IN_JUMP) then
			lvec.x = lvec.x + 1
		end

		if ply:KeyDown(IN_BACK) or ply:KeyDown(IN_DUCK) then
			lvec.x = lvec.x - 1
		end

		lvec.z = 0

		--lvec:Normalize()
		if lvec.y > 0.3 then
			targ = "L"
		elseif lvec.y < -0.3 then
			targ = "R"
		elseif lvec.x > 0.5 then
			targ = "F"
		elseif lvec.x < -0.1 then
			targ = "B"
		else
			targ = ""
		end

		for k, v in pairs(self.Primary_TFA.Attacks) do
			if (not self:GetSprinting() or v.spr) and v.direction and string.find(v.direction, targ) then
				if string.find(v.direction, targ) then
					founddir = true
				end

				table.insert(att, #att + 1, k)
			end
		end
	end

	if not self.Primary_TFA.Directional or #att <= 0 or not founddir then
		for k, v in pairs(self.Primary_TFA.Attacks) do
			if (not self:GetSprinting() or v.spr) and v.dmg then
				table.insert(att, #att + 1, k)
			end
		end
	end

	if #att <= 0 then return end
	ind = att[self:SharedRandom(1, #att, "PrimaryAttack")]
	attack = self.Primary_TFA.Attacks[ind]
	--We have attack isolated, begin attack logic
	self:PlaySwing(attack.act)

	if not attack.snd_delay or attack.snd_delay <= 0 then
		if IsFirstTimePredicted() then
			self:EmitSound(attack.snd)

			if self:GetOwner().Vox then
				self:GetOwner():Vox("bash", 4)
			end
		end

		self:GetOwner():ViewPunch(attack.viewpunch)
	elseif attack.snd_delay then
		if IsFirstTimePredicted() then
			self.AttackSoundTime = CurTime() + attack.snd_delay / self:GetAnimationRate(attack.act)
			self.VoxSoundTime = CurTime() + attack.snd_delay / self:GetAnimationRate(attack.act)
		end

		--[[
		timer.Simple(attack.snd_delay, function()
			if IsValid(self) and self:IsValid() and SERVER then
				self:EmitSound(attack.snd)

				if self:OwnerIsValid() and self:GetOwner().Vox then
					self:GetOwner():Vox("bash", 4)
				end
			end
		end)
		]]
		--
		self:SetVP(true)
		self:SetVPPitch(attack.viewpunch.p)
		self:SetVPYaw(attack.viewpunch.y)
		self:SetVPRoll(attack.viewpunch.r)
		self:SetVPTime(CurTime() + attack.snd_delay / self:GetAnimationRate(attack.act))
		self:GetOwner():ViewPunch(-Angle(attack.viewpunch.p / 2, attack.viewpunch.y / 2, attack.viewpunch.r / 2))
	end

	self.up_hat = false
	self:ScheduleStatus(TFA.Enum.STATUS_SHOOTING, attack.delay / self:GetAnimationRate(attack.act))
	self:SetMelAttackID(ind)
	self:SetNextPrimaryFire(CurTime() + attack["end"] / self:GetAnimationRate(attack.act))
	self:GetOwner():SetAnimation(PLAYER_ATTACK1)
	self:SetComboCount(self:GetComboCount() + 1)
end

function SWEP:SecondaryAttack()
	if self:GetSprinting() and not self:GetStatL("AllowSprintAttack", false) then return end
	if self:IsSafety() then return end
	if not self:VMIV() then return end
	if CurTime() <= self:GetNextPrimaryFire() then return end
	if not TFA.Enum.ReadyStatus[self:GetStatus()] then return end
	if self:GetComboCount() >= self.Secondary_TFA.MaxCombo and self.Secondary_TFA.MaxCombo > 0 then return end
	table.Empty(att)
	local founddir = false

	if not self.Secondary_TFA.Attacks or #self.Secondary_TFA.Attacks == 0 then
		self.Secondary_TFA.Attacks = self.Primary_TFA.Attacks
	end

	if self.Secondary_TFA.Directional then
		ply = self:GetOwner()
		--lvec = WorldToLocal(ply:GetVelocity(), Angle(0, 0, 0), vector_origin, ply:EyeAngles()):GetNormalized()
		lvec.x = 0
		lvec.y = 0

		if ply:KeyDown(IN_MOVERIGHT) then
			lvec.y = lvec.y - 1
		end

		if ply:KeyDown(IN_MOVELEFT) then
			lvec.y = lvec.y + 1
		end

		if ply:KeyDown(IN_FORWARD) or ply:KeyDown(IN_JUMP) then
			lvec.x = lvec.x + 1
		end

		if ply:KeyDown(IN_BACK) or ply:KeyDown(IN_DUCK) then
			lvec.x = lvec.x - 1
		end

		lvec.z = 0

		--lvec:Normalize()
		if lvec.y > 0.3 then
			targ = "L"
		elseif lvec.y < -0.3 then
			targ = "R"
		elseif lvec.x > 0.5 then
			targ = "F"
		elseif lvec.x < -0.1 then
			targ = "B"
		else
			targ = ""
		end

		for k, v in pairs(self.Secondary_TFA.Attacks) do
			if (not self:GetSprinting() or v.spr) and v.direction and string.find(v.direction, targ) then
				if string.find(v.direction, targ) then
					founddir = true
				end

				table.insert(att, #att + 1, k)
			end
		end
	end

	if not self.Secondary_TFA.Directional or #att <= 0 or not founddir then
		for k, v in pairs(self.Secondary_TFA.Attacks) do
			if (not self:GetSprinting() or v.spr) and v.dmg then
				table.insert(att, #att + 1, k)
			end
		end
	end

	if #att <= 0 then return end
	ind = att[self:SharedRandom(1, #att, "SecondaryAttack")]
	attack = self.Secondary_TFA.Attacks[ind]
	--We have attack isolated, begin attack logic
	self:PlaySwing(attack.act)

	if not attack.snd_delay or attack.snd_delay <= 0 then
		if IsFirstTimePredicted() then
			self:EmitSound(attack.snd)

			if self:GetOwner().Vox then
				self:GetOwner():Vox("bash", 4)
			end
		end

		self:GetOwner():ViewPunch(attack.viewpunch)
	elseif attack.snd_delay then
		if IsFirstTimePredicted() then
			self.AttackSoundTime = CurTime() + attack.snd_delay / self:GetAnimationRate(attack.act)
			self.VoxSoundTime = CurTime() + attack.snd_delay / self:GetAnimationRate(attack.act)
		end

		--[[
		timer.Simple(attack.snd_delay, function()
			if IsValid(self) and self:IsValid() and SERVER then
				self:EmitSound(attack.snd)

				if self:OwnerIsValid() and self:GetOwner().Vox then
					self:GetOwner():Vox("bash", 4)
				end
			end
		end)
		]]
		--
		self:SetVP(true)
		self:SetVPPitch(attack.viewpunch.p)
		self:SetVPYaw(attack.viewpunch.y)
		self:SetVPRoll(attack.viewpunch.r)
		self:SetVPTime(CurTime() + attack.snd_delay / self:GetAnimationRate(attack.act))
		self:GetOwner():ViewPunch(-Angle(attack.viewpunch.p / 2, attack.viewpunch.y / 2, attack.viewpunch.r / 2))
	end

	self.up_hat = false
	self:ScheduleStatus(TFA.Enum.STATUS_SHOOTING, attack.delay / self:GetAnimationRate(attack.act))
	self:SetMelAttackID(-ind)
	self:SetNextPrimaryFire(CurTime() + attack["end"] / self:GetAnimationRate(attack.act))
	self:GetOwner():SetAnimation(PLAYER_ATTACK1)
	self:SetComboCount(self:GetComboCount() + 1)
end

function SWEP:AltAttack()
	if self.CanBlock then
		if self.Secondary_TFA.CanBash and self.CanBlock and self:GetOwner():KeyDown(IN_USE) then
			BaseClass.AltAttack(self)

			return
		end
	else
		if not self:VMIV() then return end
		if not TFA.Enum.ReadyStatus[self:GetStatus()] then return end
		if not self.Secondary_TFA.CanBash then return end
		if self:IsSafety() then return end

		return BaseClass.AltAttack(self)
	end
end

function SWEP:Reload(released, ovr, ...)
	if not self:VMIV() then return end
	if ovr then return BaseClass.Reload(self, released, ...) end

	if self:GetOwner().GetInfoNum and self:GetOwner():GetInfoNum("cl_tfa_keys_inspect", 0) > 0 then
		return
	end

	if (self.SequenceEnabled[ACT_VM_FIDGET] or self.InspectionActions) and self:GetStatus() == TFA.Enum.STATUS_IDLE then
		local _, tanim, ttype = self:ChooseInspectAnim()
		self:ScheduleStatus(TFA.Enum.STATUS_FIDGET, self:GetActivityLength(tanim, false, ttype))
	end
end

function SWEP:CycleSafety()
end

TFA.FillMissingMetaValues(SWEP)
