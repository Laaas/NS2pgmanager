local netvars = gModClassMap.PhaseGate.networkVars
netvars.destLocationId      = nil
netvars.destinationEndpoint = nil
netvars.targetYaw           = nil
netvars.targetPG            = "entityid"

AddMixinNetworkVars(OrdersMixin, netvars)

local pg_order = {} -- Only for server

local function computeProperties(self)
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

local function isActive(pg)
	return pg and pg.deployed and GetIsUnitActive(pg)
end

local old = PhaseGate.OnCreate
function PhaseGate:OnCreate()
	if Server then
		self:SetIncludeRelevancyMask(0)
		self.timeOfLastPhase = -1000
		table.insert(pg_order, self:GetId())
	end
	self.destinationEndpoint = Vector()
	self.targetYaw = 0
	self.destLocationId = Entity.invalidId
	old(self)
	InitMixin(self, OrdersMixin, {kMoveOrderCompleteDistance = kAIMoveOrderCompleteDistance})
end

if not Server then
	local old = PhaseGate.OnInitialized
	function PhaseGate:OnInitialized()
		old(self)
		self.destinationEndpoint = Vector()
		self.targetYaw = 0
		self.destLocationId = Entity.invalidId
		self:AddFieldWatcher("targetPG", computeProperties)
	end
end

if Server then
	local old = assert(PhaseGate.OnDestroy)
	function PhaseGate:OnDestroy()
		old(self)
		table.removevalue(pg_order, self:GetId())
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
end

local last = -1000
Event.Hook("UpdateServer", function()
	if Shared.GetTime() - last < .1 then return end

	local stop = #pg_order
	local last
	for i = stop, 1, -1 do
		local pg = Shared.GetEntity(pg_order[i])
		if pg and pg.deployed and GetIsUnitActive(pg) then
			last = pg
			stop = i
			break
		else
			pg.linked = false
		end
	end

	if stop == 1 and last then
		last.linked = false
	else
		for i = 1, stop do
			local id = pg_order[i]
			local pg = Shared.GetEntity(id)
			if pg then
				if pg.deployed and GetIsUnitActive(pg) then
					pg.linked = true
					if last.targetPG ~= id then
						last.targetPG = id
						computeProperties(last)
					end
					last = pg
				else
					pg.linked = false
				end
			end
		end
	end
end)

function PhaseGate:OnOrderChanged()
	local order = self:GetCurrentOrder()
	if order ~= nil then
		if order:GetType() == kTechId.SetTarget then
			local target = Shared.GetEntity(order:GetParam())
			if target and target:isa "PhaseGate" and target ~= self then
				table.removevalue(pg_order, target:GetId())
				table.insert(pg_order, table.find(pg_order, self:GetId())+1, target:GetId())
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
	if self.linked then
		return self.destinationEndpoint
	end
end

function PhaseGate:GetDestinationLocationName()
	local target = Shared.GetEntity(self.targetPG)
	local target_target = target and Shared.GetEntity(target.targetPG)
	if target then
		local a = Shared.GetEntity(self.destLocationId)
		a = a and a:GetName() or "<unknown>"
		if target_target and target_target ~= self then
			local b = Shared.GetEntity(target.destLocationId)
			b = b and b:GetName() or "<unknown>"
			return a .. "\n" .. b
		else
			return a
		end
	end
end

local old = PhaseGate.SetIncludeRelevancyMask
function PhaseGate:SetIncludeRelevancyMask(mask)
	old(self, bit.bor(mask, kRelevantToTeam1Unit))
end
