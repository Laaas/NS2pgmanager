local netvars = gModClassMap.PhaseGate.networkVars
netvars.destLocationId      = nil
netvars.destinationEndpoint = nil
netvars.targetPG            = "entityid"

AddMixinNetworkVars(OrdersMixin, netvars)

local old = PhaseGate.OnCreate
function PhaseGate:OnCreate()
	if Server then
		self:SetIncludeRelevancyMask(0)
		self.timeOfLastPhase = -1000
	end
	old(self)
	InitMixin(self, OrdersMixin, {kMoveOrderCompleteDistance = kAIMoveOrderCompleteDistance})
end

local function ComputeProperties(self)
	local target = Shared.GetEntity(self.targetPG)

	if target then
		self.destinationEndpoint = target:GetOrigin()
		self.targetYaw           = target:GetAngles().yaw

		local location = GetLocationForPoint(self.destinationEndpoint)
		if location then
			self.destLocationId = location:GetId()
		else
			self.destLocationId = Entity.invalidId
		end
	end

	return true
end

local old = PhaseGate.OnInitialized
function PhaseGate:OnInitialized()
	old(self)
	if not Server then
		self:AddFieldWatcher("targetPG", ComputeProperties)
	end
end

function PhaseGate:OnOverrideOrder(order)
	if order:GetType() == kTechId.Default then
		order:SetType(kTechId.SetTarget)
	end
end

function PhaseGate:Update()
	if not self.timeOfLastPhase then self.timeOfLastPhase = -1000 end
	self.phase   = Shared.GetTime() < self.timeOfLastPhase + 0.3

	local target = Shared.GetEntity(self.targetPG)
	self.linked  = target and GetIsUnitActive(self) and self.deployed and target.deployed

	if not target and self.deployed and GetIsUnitActive(self) then -- automatically find an available PG
		local all_pgs = GetEntitiesForTeam("PhaseGate", self:GetTeamNumber())

		local sources = {}
		for i = 1, #all_pgs do
			local target = Shared.GetEntity(all_pgs[i].targetPG)
			if target then
				sources[target] = all_pgs[i]
			end
		end

		local found_target = false
		local found_source = false

		-- find phase gate that doesn't have a source
		for i = 1, #all_pgs do
			local pg = all_pgs[i]
			if pg ~= self and GetIsUnitActive(pg) and pg.deployed and not sources[pg] then
				self.targetPG = pg:GetId()
				self.linked   = true
				ComputeProperties(self)
				found_target = true
				break
			end
		end

		-- we need to find one, even if it's already occupied
		if not found_target then
			for i = 1, #all_pgs do
				local pg = all_pgs[i]
				if pg ~= self and GetIsUnitActive(pg) and pg.deployed then
					self.targetPG = pg:GetId()
					self.linked   = true
					ComputeProperties(self)
					break
				end
			end
		end

		-- find phase gate that doesn't have a target
		for i = 1, #all_pgs do
			local pg = all_pgs[i]
			if pg ~= self and GetIsUnitActive(pg) and pg.deployed and not Shared.GetEntity(pg.targetPG) then
				pg.targetPG = self:GetId()
				pg.linked   = true
				ComputeProperties(pg)
				found_source = true
				break
			end
		end

		-- we need to find one, even if it's already occupied
		if not found_source then
			for i = #all_pgs, 1, -1 do
				local pg = all_pgs[i]
				if pg ~= self and GetIsUnitActive(pg) and pg.deployed then
					pg.targetPG = self:GetId()
					pg.linked   = true
					ComputeProperties(pg)
					break
				end
			end
		end
	end

	return true
end

function PhaseGate:OnOrderChanged()
	local order = self:GetCurrentOrder()
	if order ~= nil then
		if order:GetType() == kTechId.SetTarget then
			local target = Shared.GetEntity(order:GetParam())
			if target and target:isa "PhaseGate" then
				self.targetPG = order:GetParam()
				self.linked   = true
				ComputeProperties(self)
			end
			self:CompletedCurrentOrder()
		else
			self:ClearCurrentOrder()
		end
	end
end

local old = PhaseGate.GetTechButtons
function PhaseGate:GetTechButtons()
	local old = old(self)
	old[1] = kTechId.SetTarget -- may the gods of mod compatibility forgive me
	return old
end

function PhaseGate:GetConnectionEndPoint()
	local target = Shared.GetEntity(self.targetPG)
	if self.linked then
		return self.destinationEndpoint
	end
end

local old = PhaseGate.SetIncludeRelevancyMask
function PhaseGate:SetIncludeRelevancyMask(mask)
	old(self, bit.bor(mask, kRelevantToTeam1Unit))
end
