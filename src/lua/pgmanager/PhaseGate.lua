local netvars = gModClassMap.PhaseGate.networkVars
netvars.destLocationId      = nil
netvars.destinationEndpoint = nil
netvars.targetPG            = "entityid"

AddMixinNetworkVars(OrdersMixin, netvars)

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

local pg_order = {} -- Only for server

local function isActive(pg)
	return pg and pg.deployed and GetIsUnitActive(pg)
end

local old = PhaseGate.OnCreate
function PhaseGate:OnCreate()
	if Server then
		self:SetIncludeRelevancyMask(0)
		self.timeOfLastPhase = -1000
		table.insert(pg_order, self)
		self.pg_index = #pg_order
	end
	old(self)
	InitMixin(self, OrdersMixin, {kMoveOrderCompleteDistance = kAIMoveOrderCompleteDistance})
end

local old = PhaseGate.OnInitialized
function PhaseGate:OnInitialized()
	old(self)
	if not Server then
		self:AddFieldWatcher("targetPG", ComputeProperties)
	end
end

local old = assert(PhaseGate.OnDestroy)
function PhaseGate:OnDestroy()
	old(self)
	if self.pgindex then
		table.remove(pg_order, self.pgindex)
	end
end

function PhaseGate:OnOverrideOrder(order)
	if order:GetType() == kTechId.Default then
		order:SetType(kTechId.SetTarget)
	end
end

function PhaseGate:Update()
	if not self.timeOfLastPhase then self.timeOfLastPhase = -1000 end
	self.phase = Shared.GetTime() < self.timeOfLastPhase + 0.3

	if isActive(self) then
		local i = self.pg_index
		while true do
			if i == #pg_order then
				i = 1
			else
				i = i + 1
			end
			if i == self.pg_index then
				self.linked = false
				break
			elseif isActive(pg_order[i]) then
				self.targetPG = pg_order[i]:GetId()
				self.linked = true
				break
			end
		end
	else
		self.linked = false
	end

	return true
end

function PhaseGate:OnOrderChanged()
	do return end -- TODO: REMOVE
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
