AddCSLuaFile()

--VJ L4D2 SI M16 code
function Flinch(wpn, v)
    v.NextL4DFlinchT = v.NextL4DFlinchT or 0
    if CurTime() < v.NextL4DFlinchT then return end
    local isCI = v.Zombie_CanPuke != nil
    v.Flinching = true
    v:StopAttacks(true)
    v.PlayingAttackAnimation = false
    local posF = (v:GetPos() +v:OBBCenter()) +v:GetForward() *115
    local posB = (v:GetPos() +v:OBBCenter()) +v:GetForward() *-115
    local posL = (v:GetPos() +v:OBBCenter()) +v:GetRight() *-115
    local posR = (v:GetPos() +v:OBBCenter()) +v:GetRight() *115
    local tbl = {posF,posB,posL,posR}
    local nearestDist = 9999999
    local cPos = nil
    for _,v in pairs(tbl) do
        if v:Distance(wpn:GetPos()) < nearestDist then
            nearestDist = v:Distance(wpn:GetPos())
            cPos = v
        end
    end
    if cPos == nil then return end
    if isCI && !v.Shove_Forward then
        v.Shove_Forward = "Shoved_Backward_01"
        v.Shove_Backward = "Shoved_Forward_01"
        v.Shove_Left = "Shoved_Rightward_01"
        v.Shove_Right = "Shoved_Leftward_01"
    end
    local anim = (cPos == posF && v.Shove_Forward) or (cPos == posB && v.Shove_Backward) or (cPos == posL && v.Shove_Left) or (cPos == posR && v.Shove_Right) or v.Shove_Forward or false
    if isCI then
        if anim == v.Shove_Forward then
            local tr = util.TraceHull({
                start = (v:GetPos() +v:OBBCenter()),
                endpos = posB,
                mask = MASK_SHOT,
                filter = {v},
                mins = v:OBBMins(),
                maxs = v:OBBMaxs()
            })
            if tr.Hit && tr.HitPos:Distance(v:GetPos() +v:OBBCenter()) <= 25 then
                anim = "Shoved_Backward_IntoWall_01"
            end
        elseif anim == v.Shove_Backward then
            local tr = util.TraceHull({
                start = (v:GetPos() +v:OBBCenter()),
                endpos = posF,
                mask = MASK_SHOT,
                filter = {v},
                mins = v:OBBMins(),
                maxs = v:OBBMaxs()
            })
            if tr.Hit && tr.HitPos:Distance(v:GetPos() +v:OBBCenter()) <= 25 then
                anim = "Shoved_Forward_IntoWall_02"
            end
        elseif anim == v.Shove_Left then
            local tr = util.TraceHull({
                start = (v:GetPos() +v:OBBCenter()),
                endpos = posR,
                mask = MASK_SHOT,
                filter = {v},
                mins = v:OBBMins(),
                maxs = v:OBBMaxs()
            })
            if tr.Hit && tr.HitPos:Distance(v:GetPos() +v:OBBCenter()) <= 25 then
                anim = "Shoved_Rightward_IntoWall_01"
            end
        elseif anim == v.Shove_Right then
            local tr = util.TraceHull({
                start = (v:GetPos() +v:OBBCenter()),
                endpos = posL,
                mask = MASK_SHOT,
                filter = {v},
                mins = v:OBBMins(),
                maxs = v:OBBMaxs()
            })
            if tr.Hit && tr.HitPos:Distance(v:GetPos() +v:OBBCenter()) <= 25 then
                anim = "Shoved_Leftward_IntoWall_02"
            end
        end
    end
    if !anim then return end
    if v.OnShoved then
        anim = v:OnShoved(anim,wpn.Owner)
    end
    v:VJ_ACT_PLAYACTIVITY(anim,true,false,false)
    local animdur = (v:DecideAnimationLength(anim,false))
    timer.Create("timer_act_flinching" .. v:EntIndex(),animdur,1,function() v.Flinching = false end)
    v.NextFlinchT = CurTime() +animdur
    v.NextL4DFlinchT = CurTime() +(animdur *0.25)
end

-- Aborted attempt to change bash damage here 
-- hook.Add("TFA_CanBash", "TFA_BashShove1", function( self ) 
-- 	-- self:SetStatRawL("Secondary.BashDamage", self:GetStatL("Secondary.BashDamage")* 0.2)
-- 	-- self.Secondary.BashDamage = 5
-- end)


hook.Add("TFA_GetStat", "TFA_ChangeBashDamageForVJL4D2", function( wep, stat, val ) 
	-- Wish there was a more flexible way of changing bash damage, but this will do
	if not IsValid(wep) then return end

	if stat == "Secondary.BashDamage" then
		if val > 10 then 
			return 10
		end 
	end
	
end)


hook.Add("TFA_Bash", "TFA_BashShove", function( self )

	local ply = self:GetOwner()
	local pos = ply:GetShootPos()
	local av = ply:GetAimVector()

	local slash = {}
	slash.start = pos
	slash.endpos = pos + (av * self:GetStatL("Secondary.BashLength"))
	slash.filter = ply
	slash.mins = Vector(-10, -5, 0)
	slash.maxs = Vector(10, 5, 5)
	local slashtrace = util.TraceHull(slash)

	if CLIENT then return end

	local hitNPC = slashtrace.Entity

	-- Make it so bashing doesn't immediately kill CI (not realiable) THIS IS NOW DONE IN THE ABOVE HOOK

	-- if hitNPC:IsNPC() && self:GetOwner():Visible(hitNPC) && hitNPC != self && hitNPC != owner then
	-- 	if (hitNPC.VJ_L4D2_SpecialInfected or hitNPC.Shove_Forward or hitNPC.Zombie_CanPuke != nil) && !hitNPC.VJ_NoFlinch && hitNPC:Health() > 0 then
	-- 		-- no method of setting the bash damage using TFA's SWEP methods works. This is the best I got 
	-- 		--pain = pain * 0.2
	-- 		--print(v:Health())
	-- 		--v:SetHealth(v:Health() + (self:GetStatL("Secondary.BashDamage") * 0.8))
			
	-- 	end
	-- end

	local meleeRange = self:GetStatL("Secondary.BashLength") * 1.6

	for _,v in pairs(ents.FindInSphere(self:GetOwner():GetShootPos(), meleeRange)) do
		if v:IsNPC() && self:GetOwner():Visible(v) && v != self && v != owner then
			if (v.VJ_L4D2_SpecialInfected or v.Shove_Forward or v.Zombie_CanPuke != nil) && !v.VJ_NoFlinch && v:Health() > 0 then	
				local inCone = (self:GetOwner():GetAimVector():Angle():Forward():Dot(((v:GetPos() +v:OBBCenter()) - self:GetOwner():GetShootPos()):GetNormalized()) > math.cos(math.rad((meleeRange))))
				if inCone then
					if not (sp and CLIENT) && v != hitNPC then -- remove double hit sounds 
						v:EmitSound(
							self:GetStatL("Secondary.BashHitSound_Flesh") or
							self:GetStatL("Secondary.BashHitSound"))
					end	
					---v:TakeDamageInfo(dmgInfo,self:GetOwner())
					Flinch(self, v)
				end
			else
			end 
		end
	end
	-- end of code handling VJ Base L4D2 
end)