local netvars = gModClassMap.PhaseGate.networkVars
netvars.destLocationId      = nil
netvars.destinationEndpoint = nil
netvars.targetPG            = "entityid"

AddMixinNetworkVars(OrdersMixin, networkVars)

local old = PhaseGate.OnCreate
function PhaseGate:OnCreate()
	old(self)
	InitMixin(self, OrdersMixin, {kMoveOrderCompleteDistance = kAIMoveOrderCompleteDistance})
	if Server then
		self:SetIncludeRelevancyMask(0)
		self.timeOfLastPhase = -1000
	end
end

local function ComputeProperties(self)
	local target = Shared.GetEntity(self.targetPG)

	self.destinationEndpoint = target:GetOrigin()
	self.targetYaw           = target:GetAngles().yaw

	local location = GetLocationForPoint(self.destinationEndpoint)
	if location then
		self.destLocationId = location:GetId()
	else
		self.destLocationId = Entity.invalidId
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
	self.phase = Shared.GetTime() < self.timeOfLastPhase + 0.3
	local target = Shared.GetEntity(self.targetPG)
	self.linked = target and GetIsUnitActive(self) and self.deployed and target.deployed
	return true
end

function PhaseGate:OnOrderChanged()
	local order = self:GetCurrentOrder()
	if order ~= nil then
		if order:GetType() == kTechId.SetTarget then
			Log "Got SetTarget order"
			local target = Shared.GetEntity(order:GetParam())
			if target:isa "PhaseGate" then
				self.targetPG = order:GetParam()
				self.linked   = true
				ComputeProperties(self)
			else
				Log("%s is not a phase gate!", target)
			end
			self:CompletedCurrentOrder()
		else
			Log "Got invalid order"
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
	old(bit.bor(mask, kRelevantToTeam1Unit))
end
