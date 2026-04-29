-- Fluent UI Library v1.1.0 - Single File Merge
-- Original: https://github.com/dawid-scripts/Fluent

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local Players = game:GetService("Players")
local Camera = game:GetService("Workspace").CurrentCamera
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- ================================================
-- FLIPPER (Animation Library)
-- ================================================

local Signal do
	local Connection = {}
	Connection.__index = Connection

	function Connection.new(signal, handler)
		return setmetatable({ signal = signal, connected = true, _handler = handler }, Connection)
	end

	function Connection:disconnect()
		if self.connected then
			self.connected = false
			for index, connection in pairs(self.signal._connections) do
				if connection == self then
					table.remove(self.signal._connections, index)
					return
				end
			end
		end
	end

	Signal = {}
	Signal.__index = Signal

	function Signal.new()
		return setmetatable({ _connections = {}, _threads = {} }, Signal)
	end

	function Signal:fire(...)
		for _, connection in pairs(self._connections) do
			connection._handler(...)
		end
		for _, thread in pairs(self._threads) do
			coroutine.resume(thread, ...)
		end
		self._threads = {}
	end

	function Signal:connect(handler)
		local connection = Connection.new(self, handler)
		table.insert(self._connections, connection)
		return connection
	end

	function Signal:wait()
		table.insert(self._threads, coroutine.running())
		return coroutine.yield()
	end
end

local function isMotor(value)
	local motorType = tostring(value):match("^Motor%((.+)%)$")
	if motorType then return true, motorType else return false end
end

local BaseMotor = {}
BaseMotor.__index = BaseMotor

function BaseMotor.new()
	return setmetatable({
		_onStep = Signal.new(),
		_onStart = Signal.new(),
		_onComplete = Signal.new(),
	}, BaseMotor)
end

function BaseMotor:onStep(handler) return self._onStep:connect(handler) end
function BaseMotor:onStart(handler) return self._onStart:connect(handler) end
function BaseMotor:onComplete(handler) return self._onComplete:connect(handler) end

function BaseMotor:start()
	if not self._connection then
		self._connection = RunService.RenderStepped:Connect(function(deltaTime)
			self:step(deltaTime)
		end)
	end
end

function BaseMotor:stop()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

BaseMotor.destroy = BaseMotor.stop
BaseMotor.step = function() end
BaseMotor.getValue = function() end
BaseMotor.setGoal = function() end
function BaseMotor:__tostring() return "Motor" end

local Instant = {}
Instant.__index = Instant
function Instant.new(targetValue)
	return setmetatable({ _targetValue = targetValue }, Instant)
end
function Instant:step()
	return { complete = true, value = self._targetValue }
end

local Linear = {}
Linear.__index = Linear
function Linear.new(targetValue, options)
	assert(targetValue, "Missing argument #1: targetValue")
	options = options or {}
	return setmetatable({ _targetValue = targetValue, _velocity = options.velocity or 1 }, Linear)
end
function Linear:step(state, dt)
	local position = state.value
	local velocity = self._velocity
	local goal = self._targetValue
	local dPos = dt * velocity
	local complete = dPos >= math.abs(goal - position)
	position = position + dPos * (goal > position and 1 or -1)
	if complete then position = self._targetValue; velocity = 0 end
	return { complete = complete, value = position, velocity = velocity }
end

local Spring do
	local VELOCITY_THRESHOLD = 0.001
	local POSITION_THRESHOLD = 0.001
	local EPS = 0.0001

	Spring = {}
	Spring.__index = Spring

	function Spring.new(targetValue, options)
		assert(targetValue, "Missing argument #1: targetValue")
		options = options or {}
		return setmetatable({
			_targetValue = targetValue,
			_frequency = options.frequency or 4,
			_dampingRatio = options.dampingRatio or 1,
		}, Spring)
	end

	function Spring:step(state, dt)
		local d = self._dampingRatio
		local f = self._frequency * 2 * math.pi
		local g = self._targetValue
		local p0 = state.value
		local v0 = state.velocity or 0
		local offset = p0 - g
		local decay = math.exp(-d * f * dt)
		local p1, v1

		if d == 1 then
			p1 = (offset * (1 + f * dt) + v0 * dt) * decay + g
			v1 = (v0 * (1 - f * dt) - offset * (f * f * dt)) * decay
		elseif d < 1 then
			local c = math.sqrt(1 - d * d)
			local i = math.cos(f * c * dt)
			local j = math.sin(f * c * dt)
			local z
			if c > EPS then
				z = j / c
			else
				local a = dt * f
				z = a + ((a * a) * (c * c) * (c * c) / 20 - c * c) * (a * a * a) / 6
			end
			local y
			if f * c > EPS then
				y = j / (f * c)
			else
				local b = f * c
				y = dt + ((dt * dt) * (b * b) * (b * b) / 20 - b * b) * (dt * dt * dt) / 6
			end
			p1 = (offset * (i + d * z) + v0 * y) * decay + g
			v1 = (v0 * (i - z * d) - offset * (z * f)) * decay
		else
			local c = math.sqrt(d * d - 1)
			local r1 = -f * (d - c)
			local r2 = -f * (d + c)
			local co2 = (v0 - offset * r1) / (2 * f * c)
			local co1 = offset - co2
			local e1 = co1 * math.exp(r1 * dt)
			local e2 = co2 * math.exp(r2 * dt)
			p1 = e1 + e2 + g
			v1 = e1 * r1 + e2 * r2
		end

		local complete = math.abs(v1) < VELOCITY_THRESHOLD and math.abs(p1 - g) < POSITION_THRESHOLD
		return { complete = complete, value = complete and g or p1, velocity = v1 }
	end
end

local SingleMotor = setmetatable({}, BaseMotor)
SingleMotor.__index = SingleMotor

function SingleMotor.new(initialValue, useImplicitConnections)
	assert(initialValue, "Missing argument #1: initialValue")
	assert(typeof(initialValue) == "number", "initialValue must be a number!")
	local self = setmetatable(BaseMotor.new(), SingleMotor)
	self._useImplicitConnections = useImplicitConnections ~= nil and useImplicitConnections or true
	self._goal = nil
	self._state = { complete = true, value = initialValue }
	return self
end

function SingleMotor:step(deltaTime)
	if self._state.complete then return true end
	local newState = self._goal:step(self._state, deltaTime)
	self._state = newState
	self._onStep:fire(newState.value)
	if newState.complete then
		if self._useImplicitConnections then self:stop() end
		self._onComplete:fire()
	end
	return newState.complete
end

function SingleMotor:getValue() return self._state.value end

function SingleMotor:setGoal(goal)
	self._state.complete = false
	self._goal = goal
	self._onStart:fire()
	if self._useImplicitConnections then self:start() end
end

function SingleMotor:__tostring() return "Motor(Single)" end

local GroupMotor = setmetatable({}, BaseMotor)
GroupMotor.__index = GroupMotor

local function toMotor(value)
	if isMotor(value) then return value end
	local valueType = typeof(value)
	if valueType == "number" then return SingleMotor.new(value, false)
	elseif valueType == "table" then return GroupMotor.new(value, false) end
	error(("Unable to convert %q to motor; type %s is unsupported"):format(value, valueType), 2)
end

function GroupMotor.new(initialValues, useImplicitConnections)
	assert(initialValues, "Missing argument #1: initialValues")
	assert(typeof(initialValues) == "table", "initialValues must be a table!")
	assert(not initialValues.step, 'initialValues contains disallowed property "step".')
	local self = setmetatable(BaseMotor.new(), GroupMotor)
	self._useImplicitConnections = useImplicitConnections ~= nil and useImplicitConnections or true
	self._complete = true
	self._motors = {}
	for key, value in pairs(initialValues) do
		self._motors[key] = toMotor(value)
	end
	return self
end

function GroupMotor:step(deltaTime)
	if self._complete then return true end
	local allMotorsComplete = true
	for _, motor in pairs(self._motors) do
		local complete = motor:step(deltaTime)
		if not complete then allMotorsComplete = false end
	end
	self._onStep:fire(self:getValue())
	if allMotorsComplete then
		if self._useImplicitConnections then self:stop() end
		self._complete = true
		self._onComplete:fire()
	end
	return allMotorsComplete
end

function GroupMotor:setGoal(goals)
	assert(not goals.step, 'goals contains disallowed property "step".')
	self._complete = false
	self._onStart:fire()
	for key, goal in pairs(goals) do
		local motor = assert(self._motors[key], ("Unknown motor for key %s"):format(key))
		motor:setGoal(goal)
	end
	if self._useImplicitConnections then self:start() end
end

function GroupMotor:getValue()
	local values = {}
	for key, motor in pairs(self._motors) do values[key] = motor:getValue() end
	return values
end

function GroupMotor:__tostring() return "Motor(Group)" end

local Flipper = {
	SingleMotor = SingleMotor,
	GroupMotor = GroupMotor,
	Instant = Instant,
	Linear = Linear,
	Spring = Spring,
	isMotor = isMotor,
}

-- ================================================
-- THEMES
-- ================================================

local Themes = {
	Names = { "Dark", "Darker", "Light", "Aqua", "Amethyst", "Rose" },

	Dark = {
		Name = "Dark", Accent = Color3.fromRGB(96, 205, 255),
		AcrylicMain = Color3.fromRGB(60, 60, 60), AcrylicBorder = Color3.fromRGB(90, 90, 90),
		AcrylicGradient = ColorSequence.new(Color3.fromRGB(40, 40, 40), Color3.fromRGB(40, 40, 40)),
		AcrylicNoise = 0.9, TitleBarLine = Color3.fromRGB(75, 75, 75), Tab = Color3.fromRGB(120, 120, 120),
		Element = Color3.fromRGB(120, 120, 120), ElementBorder = Color3.fromRGB(35, 35, 35),
		InElementBorder = Color3.fromRGB(90, 90, 90), ElementTransparency = 0.87,
		ToggleSlider = Color3.fromRGB(120, 120, 120), ToggleToggled = Color3.fromRGB(0, 0, 0),
		SliderRail = Color3.fromRGB(120, 120, 120), DropdownFrame = Color3.fromRGB(160, 160, 160),
		DropdownHolder = Color3.fromRGB(45, 45, 45), DropdownBorder = Color3.fromRGB(35, 35, 35),
		DropdownOption = Color3.fromRGB(120, 120, 120), Keybind = Color3.fromRGB(120, 120, 120),
		Input = Color3.fromRGB(160, 160, 160), InputFocused = Color3.fromRGB(10, 10, 10),
		InputIndicator = Color3.fromRGB(150, 150, 150), Dialog = Color3.fromRGB(45, 45, 45),
		DialogHolder = Color3.fromRGB(35, 35, 35), DialogHolderLine = Color3.fromRGB(30, 30, 30),
		DialogButton = Color3.fromRGB(45, 45, 45), DialogButtonBorder = Color3.fromRGB(80, 80, 80),
		DialogBorder = Color3.fromRGB(70, 70, 70), DialogInput = Color3.fromRGB(55, 55, 55),
		DialogInputLine = Color3.fromRGB(160, 160, 160), Text = Color3.fromRGB(240, 240, 240),
		SubText = Color3.fromRGB(170, 170, 170), Hover = Color3.fromRGB(120, 120, 120), HoverChange = 0.07,
	},

	Darker = {
		Name = "Darker", Accent = Color3.fromRGB(72, 138, 182),
		AcrylicMain = Color3.fromRGB(30, 30, 30), AcrylicBorder = Color3.fromRGB(60, 60, 60),
		AcrylicGradient = ColorSequence.new(Color3.fromRGB(25, 25, 25), Color3.fromRGB(15, 15, 15)),
		AcrylicNoise = 0.94, TitleBarLine = Color3.fromRGB(65, 65, 65), Tab = Color3.fromRGB(100, 100, 100),
		Element = Color3.fromRGB(70, 70, 70), ElementBorder = Color3.fromRGB(25, 25, 25),
		InElementBorder = Color3.fromRGB(55, 55, 55), ElementTransparency = 0.82,
		DropdownFrame = Color3.fromRGB(120, 120, 120), DropdownHolder = Color3.fromRGB(35, 35, 35),
		DropdownBorder = Color3.fromRGB(25, 25, 25), Dialog = Color3.fromRGB(35, 35, 35),
		DialogHolder = Color3.fromRGB(25, 25, 25), DialogHolderLine = Color3.fromRGB(20, 20, 20),
		DialogButton = Color3.fromRGB(35, 35, 35), DialogButtonBorder = Color3.fromRGB(55, 55, 55),
		DialogBorder = Color3.fromRGB(50, 50, 50), DialogInput = Color3.fromRGB(45, 45, 45),
		DialogInputLine = Color3.fromRGB(120, 120, 120),
	},

	Light = {
		Name = "Light", Accent = Color3.fromRGB(0, 103, 192),
		AcrylicMain = Color3.fromRGB(200, 200, 200), AcrylicBorder = Color3.fromRGB(120, 120, 120),
		AcrylicGradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255)),
		AcrylicNoise = 0.96, TitleBarLine = Color3.fromRGB(160, 160, 160), Tab = Color3.fromRGB(90, 90, 90),
		Element = Color3.fromRGB(255, 255, 255), ElementBorder = Color3.fromRGB(180, 180, 180),
		InElementBorder = Color3.fromRGB(150, 150, 150), ElementTransparency = 0.65,
		ToggleSlider = Color3.fromRGB(40, 40, 40), ToggleToggled = Color3.fromRGB(255, 255, 255),
		SliderRail = Color3.fromRGB(40, 40, 40), DropdownFrame = Color3.fromRGB(200, 200, 200),
		DropdownHolder = Color3.fromRGB(240, 240, 240), DropdownBorder = Color3.fromRGB(200, 200, 200),
		DropdownOption = Color3.fromRGB(150, 150, 150), Keybind = Color3.fromRGB(120, 120, 120),
		Input = Color3.fromRGB(200, 200, 200), InputFocused = Color3.fromRGB(100, 100, 100),
		InputIndicator = Color3.fromRGB(80, 80, 80), Dialog = Color3.fromRGB(255, 255, 255),
		DialogHolder = Color3.fromRGB(240, 240, 240), DialogHolderLine = Color3.fromRGB(228, 228, 228),
		DialogButton = Color3.fromRGB(255, 255, 255), DialogButtonBorder = Color3.fromRGB(190, 190, 190),
		DialogBorder = Color3.fromRGB(140, 140, 140), DialogInput = Color3.fromRGB(250, 250, 250),
		DialogInputLine = Color3.fromRGB(160, 160, 160), Text = Color3.fromRGB(0, 0, 0),
		SubText = Color3.fromRGB(40, 40, 40), Hover = Color3.fromRGB(50, 50, 50), HoverChange = 0.16,
	},

	Aqua = {
		Name = "Aqua", Accent = Color3.fromRGB(60, 165, 165),
		AcrylicMain = Color3.fromRGB(20, 20, 20), AcrylicBorder = Color3.fromRGB(50, 100, 100),
		AcrylicGradient = ColorSequence.new(Color3.fromRGB(60, 140, 140), Color3.fromRGB(40, 80, 80)),
		AcrylicNoise = 0.92, TitleBarLine = Color3.fromRGB(60, 120, 120), Tab = Color3.fromRGB(140, 180, 180),
		Element = Color3.fromRGB(110, 160, 160), ElementBorder = Color3.fromRGB(40, 70, 70),
		InElementBorder = Color3.fromRGB(80, 110, 110), ElementTransparency = 0.84,
		ToggleSlider = Color3.fromRGB(110, 160, 160), ToggleToggled = Color3.fromRGB(0, 0, 0),
		SliderRail = Color3.fromRGB(110, 160, 160), DropdownFrame = Color3.fromRGB(160, 200, 200),
		DropdownHolder = Color3.fromRGB(40, 80, 80), DropdownBorder = Color3.fromRGB(40, 65, 65),
		DropdownOption = Color3.fromRGB(110, 160, 160), Keybind = Color3.fromRGB(110, 160, 160),
		Input = Color3.fromRGB(110, 160, 160), InputFocused = Color3.fromRGB(20, 10, 30),
		InputIndicator = Color3.fromRGB(130, 170, 170), Dialog = Color3.fromRGB(40, 80, 80),
		DialogHolder = Color3.fromRGB(30, 60, 60), DialogHolderLine = Color3.fromRGB(25, 50, 50),
		DialogButton = Color3.fromRGB(40, 80, 80), DialogButtonBorder = Color3.fromRGB(80, 110, 110),
		DialogBorder = Color3.fromRGB(50, 100, 100), DialogInput = Color3.fromRGB(45, 90, 90),
		DialogInputLine = Color3.fromRGB(130, 170, 170), Text = Color3.fromRGB(240, 240, 240),
		SubText = Color3.fromRGB(170, 170, 170), Hover = Color3.fromRGB(110, 160, 160), HoverChange = 0.04,
	},

	Amethyst = {
		Name = "Amethyst", Accent = Color3.fromRGB(97, 62, 167),
		AcrylicMain = Color3.fromRGB(20, 20, 20), AcrylicBorder = Color3.fromRGB(110, 90, 130),
		AcrylicGradient = ColorSequence.new(Color3.fromRGB(85, 57, 139), Color3.fromRGB(40, 25, 65)),
		AcrylicNoise = 0.92, TitleBarLine = Color3.fromRGB(95, 75, 110), Tab = Color3.fromRGB(160, 140, 180),
		Element = Color3.fromRGB(140, 120, 160), ElementBorder = Color3.fromRGB(60, 50, 70),
		InElementBorder = Color3.fromRGB(100, 90, 110), ElementTransparency = 0.87,
		ToggleSlider = Color3.fromRGB(140, 120, 160), ToggleToggled = Color3.fromRGB(0, 0, 0),
		SliderRail = Color3.fromRGB(140, 120, 160), DropdownFrame = Color3.fromRGB(170, 160, 200),
		DropdownHolder = Color3.fromRGB(60, 45, 80), DropdownBorder = Color3.fromRGB(50, 40, 65),
		DropdownOption = Color3.fromRGB(140, 120, 160), Keybind = Color3.fromRGB(140, 120, 160),
		Input = Color3.fromRGB(140, 120, 160), InputFocused = Color3.fromRGB(20, 10, 30),
		InputIndicator = Color3.fromRGB(170, 150, 190), Dialog = Color3.fromRGB(60, 45, 80),
		DialogHolder = Color3.fromRGB(45, 30, 65), DialogHolderLine = Color3.fromRGB(40, 25, 60),
		DialogButton = Color3.fromRGB(60, 45, 80), DialogButtonBorder = Color3.fromRGB(95, 80, 110),
		DialogBorder = Color3.fromRGB(85, 70, 100), DialogInput = Color3.fromRGB(70, 55, 85),
		DialogInputLine = Color3.fromRGB(175, 160, 190), Text = Color3.fromRGB(240, 240, 240),
		SubText = Color3.fromRGB(170, 170, 170), Hover = Color3.fromRGB(140, 120, 160), HoverChange = 0.04,
	},

	Rose = {
		Name = "Rose", Accent = Color3.fromRGB(180, 55, 90),
		AcrylicMain = Color3.fromRGB(40, 40, 40), AcrylicBorder = Color3.fromRGB(130, 90, 110),
		AcrylicGradient = ColorSequence.new(Color3.fromRGB(190, 60, 135), Color3.fromRGB(165, 50, 70)),
		AcrylicNoise = 0.92, TitleBarLine = Color3.fromRGB(140, 85, 105), Tab = Color3.fromRGB(180, 140, 160),
		Element = Color3.fromRGB(200, 120, 170), ElementBorder = Color3.fromRGB(110, 70, 85),
		InElementBorder = Color3.fromRGB(120, 90, 90), ElementTransparency = 0.86,
		ToggleSlider = Color3.fromRGB(200, 120, 170), ToggleToggled = Color3.fromRGB(0, 0, 0),
		SliderRail = Color3.fromRGB(200, 120, 170), DropdownFrame = Color3.fromRGB(200, 160, 180),
		DropdownHolder = Color3.fromRGB(120, 50, 75), DropdownBorder = Color3.fromRGB(90, 40, 55),
		DropdownOption = Color3.fromRGB(200, 120, 170), Keybind = Color3.fromRGB(200, 120, 170),
		Input = Color3.fromRGB(200, 120, 170), InputFocused = Color3.fromRGB(20, 10, 30),
		InputIndicator = Color3.fromRGB(170, 150, 190), Dialog = Color3.fromRGB(120, 50, 75),
		DialogHolder = Color3.fromRGB(95, 40, 60), DialogHolderLine = Color3.fromRGB(90, 35, 55),
		DialogButton = Color3.fromRGB(120, 50, 75), DialogButtonBorder = Color3.fromRGB(155, 90, 115),
		DialogBorder = Color3.fromRGB(100, 70, 90), DialogInput = Color3.fromRGB(135, 55, 80),
		DialogInputLine = Color3.fromRGB(190, 160, 180), Text = Color3.fromRGB(240, 240, 240),
		SubText = Color3.fromRGB(170, 170, 170), Hover = Color3.fromRGB(200, 120, 170), HoverChange = 0.04,
	},
}

-- ================================================
-- ICONS
-- ================================================

local Icons = {
	assets = {
		["lucide-accessibility"] = "rbxassetid://10709751939",
		["lucide-activity"] = "rbxassetid://10709752035",
		["lucide-air-vent"] = "rbxassetid://10709752131",
		["lucide-airplay"] = "rbxassetid://10709752254",
		["lucide-alarm-check"] = "rbxassetid://10709752405",
		["lucide-alarm-clock"] = "rbxassetid://10709752630",
		["lucide-alarm-clock-off"] = "rbxassetid://10709752508",
		["lucide-alarm-minus"] = "rbxassetid://10709752732",
		["lucide-alarm-plus"] = "rbxassetid://10709752825",
		["lucide-album"] = "rbxassetid://10709752906",
		["lucide-alert-circle"] = "rbxassetid://10709752996",
		["lucide-alert-octagon"] = "rbxassetid://10709753064",
		["lucide-alert-triangle"] = "rbxassetid://10709753149",
		["lucide-align-center"] = "rbxassetid://10709753570",
		["lucide-align-center-horizontal"] = "rbxassetid://10709753272",
		["lucide-align-center-vertical"] = "rbxassetid://10709753421",
		["lucide-align-end-horizontal"] = "rbxassetid://10709753692",
		["lucide-align-end-vertical"] = "rbxassetid://10709753808",
		["lucide-align-horizontal-distribute-center"] = "rbxassetid://10747779791",
		["lucide-align-horizontal-distribute-end"] = "rbxassetid://10747784534",
		["lucide-align-horizontal-distribute-start"] = "rbxassetid://10709754118",
		["lucide-align-horizontal-justify-center"] = "rbxassetid://10709754204",
		["lucide-align-horizontal-justify-end"] = "rbxassetid://10709754317",
		["lucide-align-horizontal-justify-start"] = "rbxassetid://10709754436",
		["lucide-align-horizontal-space-around"] = "rbxassetid://10709754590",
		["lucide-align-horizontal-space-between"] = "rbxassetid://10709754749",
		["lucide-align-justify"] = "rbxassetid://10709759610",
		["lucide-align-left"] = "rbxassetid://10709759764",
		["lucide-align-right"] = "rbxassetid://10709759895",
		["lucide-align-start-horizontal"] = "rbxassetid://10709760051",
		["lucide-align-start-vertical"] = "rbxassetid://10709760244",
		["lucide-align-vertical-distribute-center"] = "rbxassetid://10709760351",
		["lucide-align-vertical-distribute-end"] = "rbxassetid://10709760434",
		["lucide-align-vertical-distribute-start"] = "rbxassetid://10709760612",
		["lucide-align-vertical-justify-center"] = "rbxassetid://10709760814",
		["lucide-align-vertical-justify-end"] = "rbxassetid://10709761003",
		["lucide-align-vertical-justify-start"] = "rbxassetid://10709761176",
		["lucide-align-vertical-space-around"] = "rbxassetid://10709761324",
		["lucide-align-vertical-space-between"] = "rbxassetid://10709761434",
		["lucide-anchor"] = "rbxassetid://10709761530",
		["lucide-angry"] = "rbxassetid://10709761629",
		["lucide-annoyed"] = "rbxassetid://10709761722",
		["lucide-aperture"] = "rbxassetid://10709761813",
		["lucide-apple"] = "rbxassetid://10709761889",
		["lucide-archive"] = "rbxassetid://10709762233",
		["lucide-archive-restore"] = "rbxassetid://10709762058",
		["lucide-armchair"] = "rbxassetid://10709762327",
	}
}

-- ================================================
-- CREATOR
-- ================================================

local Library -- forward declare

local Creator = {
	Registry = {},
	Signals = {},
	TransparencyMotors = {},
	DefaultProperties = {
		ScreenGui = { ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling },
		Frame = { BackgroundColor3 = Color3.new(1,1,1), BorderColor3 = Color3.new(0,0,0), BorderSizePixel = 0 },
		ScrollingFrame = { BackgroundColor3 = Color3.new(1,1,1), BorderColor3 = Color3.new(0,0,0), ScrollBarImageColor3 = Color3.new(0,0,0) },
		TextLabel = { BackgroundColor3 = Color3.new(1,1,1), BorderColor3 = Color3.new(0,0,0), Font = Enum.Font.SourceSans, Text = "", TextColor3 = Color3.new(0,0,0), BackgroundTransparency = 1, TextSize = 14 },
		TextButton = { BackgroundColor3 = Color3.new(1,1,1), BorderColor3 = Color3.new(0,0,0), AutoButtonColor = false, Font = Enum.Font.SourceSans, Text = "", TextColor3 = Color3.new(0,0,0), TextSize = 14 },
		TextBox = { BackgroundColor3 = Color3.new(1,1,1), BorderColor3 = Color3.new(0,0,0), ClearTextOnFocus = false, Font = Enum.Font.SourceSans, Text = "", TextColor3 = Color3.new(0,0,0), TextSize = 14 },
		ImageLabel = { BackgroundTransparency = 1, BackgroundColor3 = Color3.new(1,1,1), BorderColor3 = Color3.new(0,0,0), BorderSizePixel = 0 },
		ImageButton = { BackgroundColor3 = Color3.new(1,1,1), BorderColor3 = Color3.new(0,0,0), AutoButtonColor = false },
		CanvasGroup = { BackgroundColor3 = Color3.new(1,1,1), BorderColor3 = Color3.new(0,0,0), BorderSizePixel = 0 },
	},
}

local function ApplyCustomProps(Object, Props)
	if Props.ThemeTag then Creator.AddThemeObject(Object, Props.ThemeTag) end
end

function Creator.AddSignal(Signal, Function)
	table.insert(Creator.Signals, Signal:Connect(Function))
end

function Creator.Disconnect()
	for Idx = #Creator.Signals, 1, -1 do
		local Connection = table.remove(Creator.Signals, Idx)
		Connection:Disconnect()
	end
end

function Creator.GetThemeProperty(Property)
	if Themes[Library.Theme] and Themes[Library.Theme][Property] then
		return Themes[Library.Theme][Property]
	end
	return Themes["Dark"][Property]
end

function Creator.UpdateTheme()
	for Instance, Object in next, Creator.Registry do
		for Property, ColorIdx in next, Object.Properties do
			Instance[Property] = Creator.GetThemeProperty(ColorIdx)
		end
	end
	for _, Motor in next, Creator.TransparencyMotors do
		Motor:setGoal(Instant.new(Creator.GetThemeProperty("ElementTransparency")))
	end
end

function Creator.AddThemeObject(Object, Properties)
	Creator.Registry[Object] = { Object = Object, Properties = Properties, Idx = #Creator.Registry + 1 }
	Creator.UpdateTheme()
	return Object
end

function Creator.OverrideTag(Object, Properties)
	Creator.Registry[Object].Properties = Properties
	Creator.UpdateTheme()
end

function Creator.New(Name, Properties, Children)
	local Object = Instance.new(Name)
	for PropName, Value in next, Creator.DefaultProperties[Name] or {} do
		Object[PropName] = Value
	end
	for PropName, Value in next, Properties or {} do
		if PropName ~= "ThemeTag" then Object[PropName] = Value end
	end
	for _, Child in next, Children or {} do
		Child.Parent = Object
	end
	ApplyCustomProps(Object, Properties)
	return Object
end

function Creator.SpringMotor(Initial, Instance, Prop, IgnoreDialogCheck, ResetOnThemeChange)
	IgnoreDialogCheck = IgnoreDialogCheck or false
	ResetOnThemeChange = ResetOnThemeChange or false
	local Motor = SingleMotor.new(Initial)
	Motor:onStep(function(value) Instance[Prop] = value end)
	if ResetOnThemeChange then table.insert(Creator.TransparencyMotors, Motor) end

	local function SetValue(Value, Ignore)
		Ignore = Ignore or false
		if not IgnoreDialogCheck then
			if not Ignore then
				if Prop == "BackgroundTransparency" and Library.DialogOpen then return end
			end
		end
		Motor:setGoal(Spring.new(Value, { frequency = 8 }))
	end

	return Motor, SetValue
end

-- ================================================
-- ASSETS
-- ================================================

local Assets = {
	Close = "rbxassetid://9886659671",
	Min = "rbxassetid://9886659276",
	Max = "rbxassetid://9886659406",
	Restore = "rbxassetid://9886659001",
}

-- ================================================
-- ACRYLIC
-- ================================================

local function map(value, inMin, inMax, outMin, outMax)
	return (value - inMin) * (outMax - outMin) / (inMax - inMin) + outMin
end

local function viewportPointToWorld(location, distance)
	local unitRay = game:GetService("Workspace").CurrentCamera:ScreenPointToRay(location.X, location.Y)
	return unitRay.Origin + unitRay.Direction * distance
end

local function getOffset()
	local viewportSizeY = game:GetService("Workspace").CurrentCamera.ViewportSize.Y
	return map(viewportSizeY, 0, 2560, 8, 56)
end

local function createAcrylic()
	local Part = Creator.New("Part", {
		Name = "Body", Color = Color3.new(0, 0, 0), Material = Enum.Material.Glass,
		Size = Vector3.new(1, 1, 0), Anchored = true, CanCollide = false, Locked = true,
		CastShadow = false, Transparency = 0.98,
	}, {
		Creator.New("SpecialMesh", { MeshType = Enum.MeshType.Brick, Offset = Vector3.new(0, 0, -0.000001) }),
	})
	return Part
end

local function createAcrylicBlur(distance)
	local cleanups = {}
	distance = distance or 0.001
	local positions = { topLeft = Vector2.new(), topRight = Vector2.new(), bottomRight = Vector2.new() }
	local model = createAcrylic()
	model.Parent = workspace

	local function updatePositions(size, position)
		positions.topLeft = position
		positions.topRight = position + Vector2.new(size.X, 0)
		positions.bottomRight = position + size
	end

	local function render()
		local res = game:GetService("Workspace").CurrentCamera
		if res then res = res.CFrame end
		local camera = res or CFrame.new()
		local topLeft3D = viewportPointToWorld(positions.topLeft, distance)
		local topRight3D = viewportPointToWorld(positions.topRight, distance)
		local bottomRight3D = viewportPointToWorld(positions.bottomRight, distance)
		local width = (topRight3D - topLeft3D).Magnitude
		local height = (topRight3D - bottomRight3D).Magnitude
		model.CFrame = CFrame.fromMatrix((topLeft3D + bottomRight3D) / 2, camera.XVector, camera.YVector, camera.ZVector)
		model.Mesh.Scale = Vector3.new(width, height, 0)
	end

	local function onChange(rbx)
		local offset = getOffset()
		local size = rbx.AbsoluteSize - Vector2.new(offset, offset)
		local position = rbx.AbsolutePosition + Vector2.new(offset / 2, offset / 2)
		updatePositions(size, position)
		task.spawn(render)
	end

	local function renderOnChange()
		local camera = game:GetService("Workspace").CurrentCamera
		if not camera then return end
		table.insert(cleanups, camera:GetPropertyChangedSignal("CFrame"):Connect(render))
		table.insert(cleanups, camera:GetPropertyChangedSignal("ViewportSize"):Connect(render))
		table.insert(cleanups, camera:GetPropertyChangedSignal("FieldOfView"):Connect(render))
		task.spawn(render)
	end

	model.Destroying:Connect(function()
		for _, item in cleanups do pcall(function() item:Disconnect() end) end
	end)

	renderOnChange()
	return onChange, model
end

local function AcrylicBlur()
	local Blur = {}
	local onChange, model = createAcrylicBlur()

	local comp = Creator.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })

	Creator.AddSignal(comp:GetPropertyChangedSignal("AbsolutePosition"), function() onChange(comp) end)
	Creator.AddSignal(comp:GetPropertyChangedSignal("AbsoluteSize"), function() onChange(comp) end)

	Blur.AddParent = function(Parent)
		Creator.AddSignal(Parent:GetPropertyChangedSignal("Visible"), function()
			Blur.SetVisibility(Parent.Visible)
		end)
	end

	Blur.SetVisibility = function(Value) model.Transparency = Value and 0.98 or 1 end
	Blur.Frame = comp
	Blur.Model = model
	return Blur
end

local function AcrylicPaint()
	local Paint = {}

	Paint.Frame = Creator.New("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.9,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0,
	}, {
		Creator.New("ImageLabel", {
			Image = "rbxassetid://8992230677", ScaleType = "Slice",
			SliceCenter = Rect.new(Vector2.new(99, 99), Vector2.new(99, 99)),
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 120, 1, 116),
			Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1,
			ImageColor3 = Color3.fromRGB(0, 0, 0), ImageTransparency = 0.7,
		}),
		Creator.New("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Creator.New("Frame", {
			BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), Name = "Background",
			ThemeTag = { BackgroundColor3 = "AcrylicMain" },
		}, { Creator.New("UICorner", { CornerRadius = UDim.new(0, 8) }) }),
		Creator.New("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.4, Size = UDim2.fromScale(1, 1),
		}, {
			Creator.New("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Creator.New("UIGradient", { Rotation = 90, ThemeTag = { Color = "AcrylicGradient" } }),
		}),
		Creator.New("ImageLabel", {
			Image = "rbxassetid://9968344105", ImageTransparency = 0.98, ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.new(0, 128, 0, 128), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		}, { Creator.New("UICorner", { CornerRadius = UDim.new(0, 8) }) }),
		Creator.New("ImageLabel", {
			Image = "rbxassetid://9968344227", ImageTransparency = 0.9, ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.new(0, 128, 0, 128), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			ThemeTag = { ImageTransparency = "AcrylicNoise" },
		}, { Creator.New("UICorner", { CornerRadius = UDim.new(0, 8) }) }),
		Creator.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, {
			Creator.New("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Creator.New("UIStroke", { Transparency = 0.5, Thickness = 1, ThemeTag = { Color = "AcrylicBorder" } }),
		}),
	})

	if Library and Library.UseAcrylic then
		local Blur = AcrylicBlur()
		Blur.Frame.Parent = Paint.Frame
		Paint.Model = Blur.Model
		Paint.AddParent = Blur.AddParent
		Paint.SetVisibility = Blur.SetVisibility
	end

	return Paint
end

local Acrylic = {}

function Acrylic.init()
	local baseEffect = Instance.new("DepthOfFieldEffect")
	baseEffect.FarIntensity = 0
	baseEffect.InFocusRadius = 0.1
	baseEffect.NearIntensity = 1

	local depthOfFieldDefaults = {}

	function Acrylic.Enable()
		for _, effect in pairs(depthOfFieldDefaults) do effect.Enabled = false end
		baseEffect.Parent = game:GetService("Lighting")
	end

	function Acrylic.Disable()
		for _, effect in pairs(depthOfFieldDefaults) do effect.Enabled = effect.enabled end
		baseEffect.Parent = nil
	end

	local function registerDefaults()
		local function register(object)
			if object:IsA("DepthOfFieldEffect") then
				depthOfFieldDefaults[object] = { enabled = object.Enabled }
			end
		end
		for _, child in pairs(game:GetService("Lighting"):GetChildren()) do register(child) end
		if game:GetService("Workspace").CurrentCamera then
			for _, child in pairs(game:GetService("Workspace").CurrentCamera:GetChildren()) do register(child) end
		end
	end

	registerDefaults()
	Acrylic.Enable()
end

Acrylic.AcrylicPaint = AcrylicPaint
Acrylic.AcrylicBlur = AcrylicBlur
Acrylic.CreateAcrylic = createAcrylic

-- ================================================
-- COMPONENTS: Button
-- ================================================

local function ComponentButton(Theme, Parent, DialogCheck)
	DialogCheck = DialogCheck or false
	local Button = {}

	Button.Title = Creator.New("TextLabel", {
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
		TextColor3 = Color3.fromRGB(200, 200, 200), TextSize = 14, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ThemeTag = { TextColor3 = "Text" },
	})

	Button.HoverFrame = Creator.New("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ThemeTag = { BackgroundColor3 = "Hover" },
	}, { Creator.New("UICorner", { CornerRadius = UDim.new(0, 4) }) })

	Button.Frame = Creator.New("TextButton", {
		Size = UDim2.new(0, 0, 0, 32), Parent = Parent, ThemeTag = { BackgroundColor3 = "DialogButton" },
	}, {
		Creator.New("UICorner", { CornerRadius = UDim.new(0, 4) }),
		Creator.New("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Transparency = 0.65, ThemeTag = { Color = "DialogButtonBorder" } }),
		Button.HoverFrame, Button.Title,
	})

	local Motor, SetTransparency = Creator.SpringMotor(1, Button.HoverFrame, "BackgroundTransparency", DialogCheck)
	Creator.AddSignal(Button.Frame.MouseEnter, function() SetTransparency(0.97) end)
	Creator.AddSignal(Button.Frame.MouseLeave, function() SetTransparency(1) end)
	Creator.AddSignal(Button.Frame.MouseButton1Down, function() SetTransparency(1) end)
	Creator.AddSignal(Button.Frame.MouseButton1Up, function() SetTransparency(0.97) end)

	return Button
end

-- ================================================
-- COMPONENTS: Element
-- ================================================

local function ComponentElement(Title, Desc, Parent, Hover)
	local Element = {}

	Element.TitleLabel = Creator.New("TextLabel", {
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
		Text = Title, TextColor3 = Color3.fromRGB(240, 240, 240), TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 1,
		ThemeTag = { TextColor3 = "Text" },
	})

	Element.DescLabel = Creator.New("TextLabel", {
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
		Text = Desc, TextColor3 = Color3.fromRGB(200, 200, 200), TextSize = 12, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14),
		ThemeTag = { TextColor3 = "SubText" },
	})

	Element.LabelHolder = Creator.New("Frame", {
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -28, 0, 0),
	}, {
		Creator.New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
		Creator.New("UIPadding", { PaddingBottom = UDim.new(0, 13), PaddingTop = UDim.new(0, 13) }),
		Element.TitleLabel, Element.DescLabel,
	})

	Element.Border = Creator.New("UIStroke", {
		Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Color3.fromRGB(0, 0, 0), ThemeTag = { Color = "ElementBorder" },
	})

	Element.Frame = Creator.New("TextButton", {
		Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 0.89,
		BackgroundColor3 = Color3.fromRGB(130, 130, 130), Parent = Parent,
		AutomaticSize = Enum.AutomaticSize.Y, Text = "", LayoutOrder = 7,
		ThemeTag = { BackgroundColor3 = "Element", BackgroundTransparency = "ElementTransparency" },
	}, {
		Creator.New("UICorner", { CornerRadius = UDim.new(0, 4) }),
		Element.Border, Element.LabelHolder,
	})

	function Element:SetTitle(Set) Element.TitleLabel.Text = Set end

	function Element:SetDesc(Set)
		if Set == nil then Set = "" end
		if Set == "" then Element.DescLabel.Visible = false
		else Element.DescLabel.Visible = true end
		Element.DescLabel.Text = Set
	end

	function Element:Destroy() Element.Frame:Destroy() end

	Element:SetTitle(Title)
	Element:SetDesc(Desc)

	if Hover then
		local Motor, SetTransparency = Creator.SpringMotor(
			Creator.GetThemeProperty("ElementTransparency"), Element.Frame, "BackgroundTransparency", false, true
		)
		Creator.AddSignal(Element.Frame.MouseEnter, function()
			SetTransparency(Creator.GetThemeProperty("ElementTransparency") - Creator.GetThemeProperty("HoverChange"))
		end)
		Creator.AddSignal(Element.Frame.MouseLeave, function()
			SetTransparency(Creator.GetThemeProperty("ElementTransparency"))
		end)
		Creator.AddSignal(Element.Frame.MouseButton1Down, function()
			SetTransparency(Creator.GetThemeProperty("ElementTransparency") + Creator.GetThemeProperty("HoverChange"))
		end)
		Creator.AddSignal(Element.Frame.MouseButton1Up, function()
			SetTransparency(Creator.GetThemeProperty("ElementTransparency") - Creator.GetThemeProperty("HoverChange"))
		end)
	end

	return Element
end

-- ================================================
-- COMPONENTS: Textbox
-- ================================================

local function ComponentTextbox(Parent, IsAcrylic)
	IsAcrylic = IsAcrylic or false
	local Textbox = {}

	Textbox.Input = Creator.New("TextBox", {
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
		TextColor3 = Color3.fromRGB(200, 200, 200), TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(10, 0),
		ThemeTag = { TextColor3 = "Text", PlaceholderColor3 = "SubText" },
	})

	Textbox.Container = Creator.New("Frame", {
		BackgroundTransparency = 1, ClipsDescendants = true,
		Position = UDim2.new(0, 6, 0, 0), Size = UDim2.new(1, -12, 1, 0),
	}, { Textbox.Input })

	Textbox.Indicator = Creator.New("Frame", {
		Size = UDim2.new(1, -4, 0, 1), Position = UDim2.new(0, 2, 1, 0), AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = IsAcrylic and 0.5 or 0,
		ThemeTag = { BackgroundColor3 = IsAcrylic and "InputIndicator" or "DialogInputLine" },
	})

	Textbox.Frame = Creator.New("Frame", {
		Size = UDim2.new(0, 0, 0, 30), BackgroundTransparency = IsAcrylic and 0.9 or 0,
		Parent = Parent, ThemeTag = { BackgroundColor3 = IsAcrylic and "Input" or "DialogInput" },
	}, {
		Creator.New("UICorner", { CornerRadius = UDim.new(0, 4) }),
		Creator.New("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Transparency = IsAcrylic and 0.5 or 0.65,
			ThemeTag = { Color = IsAcrylic and "InElementBorder" or "DialogButtonBorder" },
		}),
		Textbox.Indicator, Textbox.Container,
	})

	local function Update()
		local PADDING = 2
		local Reveal = Textbox.Container.AbsoluteSize.X
		if not Textbox.Input:IsFocused() or Textbox.Input.TextBounds.X <= Reveal - 2 * PADDING then
			Textbox.Input.Position = UDim2.new(0, PADDING, 0, 0)
		else
			local Cursor = Textbox.Input.CursorPosition
			if Cursor ~= -1 then
				local subtext = string.sub(Textbox.Input.Text, 1, Cursor - 1)
				local width = TextService:GetTextSize(subtext, Textbox.Input.TextSize, Textbox.Input.Font, Vector2.new(math.huge, math.huge)).X
				local CurrentCursorPos = Textbox.Input.Position.X.Offset + width
				if CurrentCursorPos < PADDING then
					Textbox.Input.Position = UDim2.fromOffset(PADDING - width, 0)
				elseif CurrentCursorPos > Reveal - PADDING - 1 then
					Textbox.Input.Position = UDim2.fromOffset(Reveal - width - PADDING - 1, 0)
				end
			end
		end
	end

	task.spawn(Update)
	Creator.AddSignal(Textbox.Input:GetPropertyChangedSignal("Text"), Update)
	Creator.AddSignal(Textbox.Input:GetPropertyChangedSignal("CursorPosition"), Update)

	Creator.AddSignal(Textbox.Input.Focused, function()
		Update()
		Textbox.Indicator.Size = UDim2.new(1, -2, 0, 2)
		Textbox.Indicator.Position = UDim2.new(0, 1, 1, 0)
		Textbox.Indicator.BackgroundTransparency = 0
		Creator.OverrideTag(Textbox.Frame, { BackgroundColor3 = IsAcrylic and "InputFocused" or "DialogHolder" })
		Creator.OverrideTag(Textbox.Indicator, { BackgroundColor3 = "Accent" })
	end)

	Creator.AddSignal(Textbox.Input.FocusLost, function()
		Update()
		Textbox.Indicator.Size = UDim2.new(1, -4, 0, 1)
		Textbox.Indicator.Position = UDim2.new(0, 2, 1, 0)
		Textbox.Indicator.BackgroundTransparency = 0.5
		Creator.OverrideTag(Textbox.Frame, { BackgroundColor3 = IsAcrylic and "Input" or "DialogInput" })
		Creator.OverrideTag(Textbox.Indicator, { BackgroundColor3 = IsAcrylic and "InputIndicator" or "DialogInputLine" })
	end)

	return Textbox
end

-- ================================================
-- COMPONENTS: Section
-- ================================================

local function ComponentSection(Title, Parent)
	local Section = {}

	Section.Layout = Creator.New("UIListLayout", { Padding = UDim.new(0, 5) })

	Section.Container = Creator.New("Frame", {
		Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 24), BackgroundTransparency = 1,
	}, { Section.Layout })

	Section.Root = Creator.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 7, Parent = Parent,
	}, {
		Creator.New("TextLabel", {
			RichText = true, Text = Title, TextTransparency = 0,
			FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
			TextSize = 18, TextXAlignment = "Left", TextYAlignment = "Center",
			Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(0, 2),
			ThemeTag = { TextColor3 = "Text" },
		}),
		Section.Container,
	})

	Creator.AddSignal(Section.Layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
		Section.Container.Size = UDim2.new(1, 0, 0, Section.Layout.AbsoluteContentSize.Y)
		Section.Root.Size = UDim2.new(1, 0, 0, Section.Layout.AbsoluteContentSize.Y + 25)
	end)

	return Section
end

-- ================================================
-- COMPONENTS: Notification
-- ================================================

local Notification = {}

function Notification:Init(GUI)
	Notification.Holder = Creator.New("Frame", {
		Position = UDim2.new(1, -30, 1, -30), Size = UDim2.new(0, 310, 1, -30),
		AnchorPoint = Vector2.new(1, 1), BackgroundTransparency = 1, Parent = GUI,
	}, {
		Creator.New("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 20),
		}),
	})
end

function Notification:New(Config)
	Config.Title = Config.Title or "Title"
	Config.Content = Config.Content or "Content"
	Config.SubContent = Config.SubContent or ""
	Config.Duration = Config.Duration or nil
	Config.Buttons = Config.Buttons or {}
	local NewNotification = { Closed = false }

	NewNotification.AcrylicPaint = AcrylicPaint()

	NewNotification.Title = Creator.New("TextLabel", {
		Position = UDim2.new(0, 14, 0, 17), Text = Config.Title, RichText = true,
		TextColor3 = Color3.fromRGB(255, 255, 255), TextTransparency = 0,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
		TextSize = 13, TextXAlignment = "Left", TextYAlignment = "Center",
		Size = UDim2.new(1, -12, 0, 12), TextWrapped = true, BackgroundTransparency = 1,
		ThemeTag = { TextColor3 = "Text" },
	})

	NewNotification.ContentLabel = Creator.New("TextLabel", {
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
		Text = Config.Content, TextColor3 = Color3.fromRGB(240, 240, 240), TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1, TextWrapped = true, ThemeTag = { TextColor3 = "Text" },
	})

	NewNotification.SubContentLabel = Creator.New("TextLabel", {
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
		Text = Config.SubContent, TextColor3 = Color3.fromRGB(240, 240, 240), TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1, TextWrapped = true, ThemeTag = { TextColor3 = "SubText" },
	})

	NewNotification.LabelHolder = Creator.New("Frame", {
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 40), Size = UDim2.new(1, -28, 0, 0),
	}, {
		Creator.New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 3) }),
		NewNotification.ContentLabel, NewNotification.SubContentLabel,
	})

	NewNotification.CloseButton = Creator.New("TextButton", {
		Text = "", Position = UDim2.new(1, -14, 0, 13), Size = UDim2.fromOffset(20, 20),
		AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1,
	}, {
		Creator.New("ImageLabel", {
			Image = Assets.Close, Size = UDim2.fromOffset(16, 16),
			Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1, ThemeTag = { ImageColor3 = "Text" },
		}),
	})

	NewNotification.Root = Creator.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Position = UDim2.fromScale(1, 0),
	}, {
		NewNotification.AcrylicPaint.Frame, NewNotification.Title,
		NewNotification.CloseButton, NewNotification.LabelHolder,
	})

	if Config.Content == "" then NewNotification.ContentLabel.Visible = false end
	if Config.SubContent == "" then NewNotification.SubContentLabel.Visible = false end

	NewNotification.Holder = Creator.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 200), Parent = Notification.Holder,
	}, { NewNotification.Root })

	local RootMotor = GroupMotor.new({ Scale = 1, Offset = 60 })
	RootMotor:onStep(function(Values)
		NewNotification.Root.Position = UDim2.new(Values.Scale, Values.Offset, 0, 0)
	end)

	Creator.AddSignal(NewNotification.CloseButton.MouseButton1Click, function()
		NewNotification:Close()
	end)

	function NewNotification:Open()
		local ContentSize = NewNotification.LabelHolder.AbsoluteSize.Y
		NewNotification.Holder.Size = UDim2.new(1, 0, 0, 58 + ContentSize)
		RootMotor:setGoal({ Scale = Spring.new(0, { frequency = 5 }), Offset = Spring.new(0, { frequency = 5 }) })
	end

	function NewNotification:Close()
		if not NewNotification.Closed then
			NewNotification.Closed = true
			task.spawn(function()
				RootMotor:setGoal({ Scale = Spring.new(1, { frequency = 5 }), Offset = Spring.new(60, { frequency = 5 }) })
				task.wait(0.4)
				if Library and Library.UseAcrylic then
					NewNotification.AcrylicPaint.Model:Destroy()
				end
				NewNotification.Holder:Destroy()
			end)
		end
	end

	NewNotification:Open()
	if Config.Duration then
		task.delay(Config.Duration, function() NewNotification:Close() end)
	end
	return NewNotification
end

-- ================================================
-- COMPONENTS: Dialog
-- ================================================

local Dialog = { Window = nil }

function Dialog:Init(Window)
	Dialog.Window = Window
	return Dialog
end

function Dialog:Create()
	local NewDialog = { Buttons = 0 }

	NewDialog.TintFrame = Creator.New("TextButton", {
		Text = "", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 1, Parent = Dialog.Window.Root,
	}, { Creator.New("UICorner", { CornerRadius = UDim.new(0, 8) }) })

	local TintMotor, TintTransparency = Creator.SpringMotor(1, NewDialog.TintFrame, "BackgroundTransparency", true)

	NewDialog.ButtonHolder = Creator.New("Frame", {
		Size = UDim2.new(1, -40, 1, -40), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1,
	}, {
		Creator.New("UIListLayout", {
			Padding = UDim.new(0, 10), FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	NewDialog.ButtonHolderFrame = Creator.New("Frame", {
		Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0, 0, 1, -70),
		ThemeTag = { BackgroundColor3 = "DialogHolder" },
	}, {
		Creator.New("Frame", { Size = UDim2.new(1, 0, 0, 1), ThemeTag = { BackgroundColor3 = "DialogHolderLine" } }),
		NewDialog.ButtonHolder,
	})

	NewDialog.Title = Creator.New("TextLabel", {
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
		Text = "Dialog", TextColor3 = Color3.fromRGB(240, 240, 240), TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(20, 25), BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1, ThemeTag = { TextColor3 = "Text" },
	})

	NewDialog.Scale = Creator.New("UIScale", { Scale = 1 })
	local ScaleMotor, Scale = Creator.SpringMotor(1.1, NewDialog.Scale, "Scale")

	NewDialog.Root = Creator.New("CanvasGroup", {
		Size = UDim2.fromOffset(300, 165), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), GroupTransparency = 1, Parent = NewDialog.TintFrame,
		ThemeTag = { BackgroundColor3 = "Dialog" },
	}, {
		Creator.New("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Creator.New("UIStroke", { Transparency = 0.5, ThemeTag = { Color = "DialogBorder" } }),
		NewDialog.Scale, NewDialog.Title, NewDialog.ButtonHolderFrame,
	})

	local RootMotor, RootTransparency = Creator.SpringMotor(1, NewDialog.Root, "GroupTransparency")

	function NewDialog:Open()
		Library.DialogOpen = true
		NewDialog.Scale.Scale = 1.1
		TintTransparency(0.75)
		RootTransparency(0)
		Scale(1)
	end

	function NewDialog:Close()
		Library.DialogOpen = false
		TintTransparency(1)
		RootTransparency(1)
		Scale(1.1)
		NewDialog.Root.UIStroke:Destroy()
		task.wait(0.15)
		NewDialog.TintFrame:Destroy()
	end

	function NewDialog:Button(Title, Callback)
		NewDialog.Buttons = NewDialog.Buttons + 1
		Title = Title or "Button"
		Callback = Callback or function() end

		local Button = ComponentButton("", NewDialog.ButtonHolder, true)
		Button.Title.Text = Title

		for _, Btn in next, NewDialog.ButtonHolder:GetChildren() do
			if Btn:IsA("TextButton") then
				Btn.Size = UDim2.new(1 / NewDialog.Buttons, -(((NewDialog.Buttons - 1) * 10) / NewDialog.Buttons), 0, 32)
			end
		end

		Creator.AddSignal(Button.Frame.MouseButton1Click, function()
			Library:SafeCallback(Callback)
			pcall(function() NewDialog:Close() end)
		end)

		return Button
	end

	return NewDialog
end

-- ================================================
-- COMPONENTS: TitleBar
-- ================================================

local function ComponentTitleBar(Config)
	local TitleBar = {}

	local function BarButton(Icon, Pos, Parent, Callback)
		local Button = { Callback = Callback or function() end }

		Button.Frame = Creator.New("TextButton", {
			Size = UDim2.new(0, 34, 1, -8), AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1, Parent = Parent, Position = Pos, Text = "",
			ThemeTag = { BackgroundColor3 = "Text" },
		}, {
			Creator.New("UICorner", { CornerRadius = UDim.new(0, 7) }),
			Creator.New("ImageLabel", {
				Image = Icon, Size = UDim2.fromOffset(16, 16),
				Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1, Name = "Icon", ThemeTag = { ImageColor3 = "Text" },
			}),
		})

		local Motor, SetTransparency = Creator.SpringMotor(1, Button.Frame, "BackgroundTransparency")
		Creator.AddSignal(Button.Frame.MouseEnter, function() SetTransparency(0.94) end)
		Creator.AddSignal(Button.Frame.MouseLeave, function() SetTransparency(1, true) end)
		Creator.AddSignal(Button.Frame.MouseButton1Down, function() SetTransparency(0.96) end)
		Creator.AddSignal(Button.Frame.MouseButton1Up, function() SetTransparency(0.94) end)
		Creator.AddSignal(Button.Frame.MouseButton1Click, Button.Callback)
		Button.SetCallback = function(Func) Button.Callback = Func end

		return Button
	end

	TitleBar.Frame = Creator.New("Frame", {
		Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, Parent = Config.Parent,
	}, {
		Creator.New("Frame", {
			Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 16, 0, 0), BackgroundTransparency = 1,
		}, {
			Creator.New("UIListLayout", {
				Padding = UDim.new(0, 5), FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Creator.New("TextLabel", {
				RichText = true, Text = Config.Title,
				FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
				TextSize = 12, TextXAlignment = "Left", TextYAlignment = "Center",
				Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1, ThemeTag = { TextColor3 = "Text" },
			}),
			Creator.New("TextLabel", {
				RichText = true, Text = Config.SubTitle, TextTransparency = 0.4,
				FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
				TextSize = 12, TextXAlignment = "Left", TextYAlignment = "Center",
				Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1, ThemeTag = { TextColor3 = "Text" },
			}),
		}),
		Creator.New("Frame", {
			BackgroundTransparency = 0.5, Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, 0),
			ThemeTag = { BackgroundColor3 = "TitleBarLine" },
		}),
	})

	TitleBar.CloseButton = BarButton(Assets.Close, UDim2.new(1, -4, 0, 4), TitleBar.Frame, function()
		Library.Window:Dialog({
			Title = "Close",
			Content = "Are you sure you want to unload the interface?",
			Buttons = {
				{ Title = "Yes", Callback = function() Library:Destroy() end },
				{ Title = "No" },
			},
		})
	end)
	TitleBar.MaxButton = BarButton(Assets.Max, UDim2.new(1, -40, 0, 4), TitleBar.Frame, function()
		Config.Window.Maximize(not Config.Window.Maximized)
	end)
	TitleBar.MinButton = BarButton(Assets.Min, UDim2.new(1, -80, 0, 4), TitleBar.Frame, function()
		Library.Window:Minimize()
	end)

	return TitleBar
end

-- ================================================
-- COMPONENTS: Tab
-- ================================================

local TabModule = { Window = nil, Tabs = {}, Containers = {}, SelectedTab = 0, TabCount = 0 }

function TabModule:Init(Window)
	TabModule.Window = Window
	return TabModule
end

function TabModule:GetCurrentTabPos()
	local TabHolderPos = TabModule.Window.TabHolder.AbsolutePosition.Y
	local TabPos = TabModule.Tabs[TabModule.SelectedTab].Frame.AbsolutePosition.Y
	return TabPos - TabHolderPos
end

-- ================================================
-- ELEMENTS (forward declare Elements metatable)
-- ================================================

local Elements = {}
Elements.__index = Elements
Elements.__namecall = function(Table, Key, ...)
	return Elements[Key](...)
end

-- ================================================
-- COMPONENTS: Window
-- ================================================

local function ComponentWindow(Config)
	local Window = {
		Minimized = false, Maximized = false, Size = Config.Size, CurrentPos = 0,
		Position = UDim2.fromOffset(
			Camera.ViewportSize.X / 2 - Config.Size.X.Offset / 2,
			Camera.ViewportSize.Y / 2 - Config.Size.Y.Offset / 2
		),
	}

	local Dragging, DragInput, MousePos, StartPos = false
	local Resizing, ResizePos = false
	local MinimizeNotif = false

	Window.AcrylicPaint = AcrylicPaint()

	local Selector = Creator.New("Frame", {
		Size = UDim2.fromOffset(4, 0), BackgroundColor3 = Color3.fromRGB(76, 194, 255),
		Position = UDim2.fromOffset(0, 17), AnchorPoint = Vector2.new(0, 0.5),
		ThemeTag = { BackgroundColor3 = "Accent" },
	}, { Creator.New("UICorner", { CornerRadius = UDim.new(0, 2) }) })

	local ResizeStartFrame = Creator.New("Frame", {
		Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Position = UDim2.new(1, -20, 1, -20),
	})

	Window.TabHolder = Creator.New("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScrollBarImageTransparency = 1,
		ScrollBarThickness = 0, BorderSizePixel = 0, CanvasSize = UDim2.fromScale(0, 0),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, { Creator.New("UIListLayout", { Padding = UDim.new(0, 4) }) })

	local TabFrame = Creator.New("Frame", {
		Size = UDim2.new(0, Config.TabWidth, 1, -66), Position = UDim2.new(0, 12, 0, 54),
		BackgroundTransparency = 1, ClipsDescendants = true,
	}, { Window.TabHolder, Selector })

	Window.TabDisplay = Creator.New("TextLabel", {
		RichText = true, Text = "Tab", TextTransparency = 0,
		FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
		TextSize = 28, TextXAlignment = "Left", TextYAlignment = "Center",
		Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(Config.TabWidth + 26, 56),
		BackgroundTransparency = 1, ThemeTag = { TextColor3 = "Text" },
	})

	Window.ContainerHolder = Creator.New("CanvasGroup", {
		Size = UDim2.new(1, -Config.TabWidth - 32, 1, -102),
		Position = UDim2.fromOffset(Config.TabWidth + 26, 90), BackgroundTransparency = 1,
	})

	Window.Root = Creator.New("Frame", {
		BackgroundTransparency = 1, Size = Window.Size, Position = Window.Position,
		Parent = Config.Parent, Active = true,
	}, {
		Window.AcrylicPaint.Frame, Window.TabDisplay, Window.ContainerHolder, TabFrame, ResizeStartFrame,
	})

	Window.TitleBar = ComponentTitleBar({
		Title = Config.Title, SubTitle = Config.SubTitle, Parent = Window.Root, Window = Window,
	})

	if Library.UseAcrylic then Window.AcrylicPaint.AddParent(Window.Root) end

	local SizeMotor = GroupMotor.new({ X = Window.Size.X.Offset, Y = Window.Size.Y.Offset })
	local PosMotor = GroupMotor.new({ X = Window.Position.X.Offset, Y = Window.Position.Y.Offset })

	Window.SelectorPosMotor = SingleMotor.new(17)
	Window.SelectorSizeMotor = SingleMotor.new(0)
	Window.ContainerBackMotor = SingleMotor.new(0)
	Window.ContainerPosMotor = SingleMotor.new(94)

	SizeMotor:onStep(function(values) Window.Root.Size = UDim2.new(0, values.X, 0, values.Y) end)
	PosMotor:onStep(function(values) Window.Root.Position = UDim2.new(0, values.X, 0, values.Y) end)

	local LastValue = 0
	local LastTime = 0
	Window.SelectorPosMotor:onStep(function(Value)
		Selector.Position = UDim2.new(0, 0, 0, Value + 17)
		local Now = tick()
		local DeltaTime = Now - LastTime
		if LastValue ~= nil then
			Window.SelectorSizeMotor:setGoal(Spring.new((math.abs(Value - LastValue) / (DeltaTime * 60)) + 16))
			LastValue = Value
		end
		LastTime = Now
	end)

	Window.SelectorSizeMotor:onStep(function(Value) Selector.Size = UDim2.new(0, 4, 0, Value) end)
	Window.ContainerBackMotor:onStep(function(Value) Window.ContainerHolder.GroupTransparency = Value end)
	Window.ContainerPosMotor:onStep(function(Value)
		Window.ContainerHolder.Position = UDim2.fromOffset(Config.TabWidth + 26, Value)
	end)

	local OldSizeX, OldSizeY
	Window.Maximize = function(Value, NoPos, UseInstant)
		Window.Maximized = Value
		Window.TitleBar.MaxButton.Frame.Icon.Image = Value and Assets.Restore or Assets.Max
		if Value then OldSizeX = Window.Size.X.Offset; OldSizeY = Window.Size.Y.Offset end
		local SizeX = Value and Camera.ViewportSize.X or OldSizeX
		local SizeY = Value and Camera.ViewportSize.Y or OldSizeY
		SizeMotor:setGoal({
			X = (UseInstant and Instant or Spring).new(SizeX, not UseInstant and { frequency = 6 } or nil),
			Y = (UseInstant and Instant or Spring).new(SizeY, not UseInstant and { frequency = 6 } or nil),
		})
		Window.Size = UDim2.fromOffset(SizeX, SizeY)
		if not NoPos then
			PosMotor:setGoal({
				X = Spring.new(Value and 0 or Window.Position.X.Offset, { frequency = 6 }),
				Y = Spring.new(Value and 0 or Window.Position.Y.Offset, { frequency = 6 }),
			})
		end
	end

	Creator.AddSignal(Window.TitleBar.Frame.InputBegan, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			Dragging = true
			MousePos = Input.Position
			StartPos = Window.Root.Position
			if Window.Maximized then
				StartPos = UDim2.fromOffset(
					Mouse.X - (Mouse.X * ((OldSizeX - 100) / Window.Root.AbsoluteSize.X)),
					Mouse.Y - (Mouse.Y * (OldSizeY / Window.Root.AbsoluteSize.Y))
				)
			end
			Input.Changed:Connect(function()
				if Input.UserInputState == Enum.UserInputState.End then Dragging = false end
			end)
		end
	end)

	Creator.AddSignal(Window.TitleBar.Frame.InputChanged, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch then
			DragInput = Input
		end
	end)

	Creator.AddSignal(ResizeStartFrame.InputBegan, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			Resizing = true; ResizePos = Input.Position
		end
	end)

	Creator.AddSignal(UserInputService.InputChanged, function(Input)
		if Input == DragInput and Dragging then
			local Delta = Input.Position - MousePos
			Window.Position = UDim2.fromOffset(StartPos.X.Offset + Delta.X, StartPos.Y.Offset + Delta.Y)
			PosMotor:setGoal({ X = Instant.new(Window.Position.X.Offset), Y = Instant.new(Window.Position.Y.Offset) })
			if Window.Maximized then Window.Maximize(false, true, true) end
		end
		if (Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch) and Resizing then
			local Delta = Input.Position - ResizePos
			local StartSize = Window.Size
			local TargetSize = Vector3.new(StartSize.X.Offset, StartSize.Y.Offset, 0) + Vector3.new(1, 1, 0) * Delta
			local TargetSizeClamped = Vector2.new(math.clamp(TargetSize.X, 470, 2048), math.clamp(TargetSize.Y, 380, 2048))
			SizeMotor:setGoal({ X = Instant.new(TargetSizeClamped.X), Y = Instant.new(TargetSizeClamped.Y) })
		end
	end)

	Creator.AddSignal(UserInputService.InputEnded, function(Input)
		if Resizing == true or Input.UserInputType == Enum.UserInputType.Touch then
			Resizing = false
			Window.Size = UDim2.fromOffset(SizeMotor:getValue().X, SizeMotor:getValue().Y)
		end
	end)

	Creator.AddSignal(Window.TabHolder.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
		Window.TabHolder.CanvasSize = UDim2.new(0, 0, 0, Window.TabHolder.UIListLayout.AbsoluteContentSize.Y)
	end)

	Creator.AddSignal(UserInputService.InputBegan, function(Input)
		if type(Library.MinimizeKeybind) == "table" and Library.MinimizeKeybind.Type == "Keybind" and not UserInputService:GetFocusedTextBox() then
			if Input.KeyCode.Name == Library.MinimizeKeybind.Value then Window:Minimize() end
		elseif Input.KeyCode == Library.MinimizeKey and not UserInputService:GetFocusedTextBox() then
			Window:Minimize()
		end
	end)

	function Window:Minimize()
		Window.Minimized = not Window.Minimized
		Window.Root.Visible = not Window.Minimized
		if not MinimizeNotif then
			MinimizeNotif = true
			local Key = Library.MinimizeKeybind and Library.MinimizeKeybind.Value or Library.MinimizeKey.Name
			Library:Notify({ Title = "Interface", Content = "Press " .. Key .. " to toggle the interface.", Duration = 6 })
		end
	end

	function Window:Destroy()
		if Library.UseAcrylic then Window.AcrylicPaint.Model:Destroy() end
		Window.Root:Destroy()
	end

	local DialogModuleInst = { Window = Window }
	setmetatable(DialogModuleInst, { __index = Dialog })

	function Window:Dialog(DialogConfig)
		local Dlg = Dialog:Create()
		Dlg.Title.Text = DialogConfig.Title

		local Content = Creator.New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			Text = DialogConfig.Content, TextColor3 = Color3.fromRGB(240, 240, 240), TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(20, 60),
			BackgroundTransparency = 1, Parent = Dlg.Root, ClipsDescendants = false,
			ThemeTag = { TextColor3 = "Text" },
		})

		Creator.New("UISizeConstraint", { MinSize = Vector2.new(300, 165), MaxSize = Vector2.new(620, math.huge), Parent = Dlg.Root })
		Dlg.Root.Size = UDim2.fromOffset(Content.TextBounds.X + 40, 165)
		if Content.TextBounds.X + 40 > Window.Size.X.Offset - 120 then
			Dlg.Root.Size = UDim2.fromOffset(Window.Size.X.Offset - 120, 165)
			Content.TextWrapped = true
			Dlg.Root.Size = UDim2.fromOffset(Window.Size.X.Offset - 120, Content.TextBounds.Y + 150)
		end

		for _, Btn in next, DialogConfig.Buttons do
			Dlg:Button(Btn.Title, Btn.Callback)
		end

		Dlg:Open()
	end

	local TabModuleInst = TabModule
	TabModuleInst:Init(Window)

	function Window:AddTab(TabConfig)
		return TabModuleInst:New(TabConfig.Title, TabConfig.Icon, Window.TabHolder)
	end

	function Window:SelectTab(Tab)
		TabModuleInst:SelectTab(1)
	end

	Creator.AddSignal(Window.TabHolder:GetPropertyChangedSignal("CanvasPosition"), function()
		LastValue = TabModuleInst:GetCurrentTabPos() + 16
		LastTime = 0
		Window.SelectorPosMotor:setGoal(Instant.new(TabModuleInst:GetCurrentTabPos()))
	end)

	return Window
end

-- ================================================
-- TAB MODULE: New + SelectTab (needs Window & Elements)
-- ================================================

function TabModule:New(Title, Icon, Parent)
	local Window = TabModule.Window

	TabModule.TabCount = TabModule.TabCount + 1
	local TabIndex = TabModule.TabCount

	local Tab = { Selected = false, Name = Title, Type = "Tab" }

	if Library:GetIcon(Icon) then Icon = Library:GetIcon(Icon) end
	if Icon == "" or Icon == nil then Icon = nil end

	Tab.Frame = Creator.New("TextButton", {
		Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Parent = Parent,
		ThemeTag = { BackgroundColor3 = "Tab" },
	}, {
		Creator.New("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Creator.New("TextLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = Icon and UDim2.new(0, 30, 0.5, 0) or UDim2.new(0, 12, 0.5, 0),
			Text = Title, RichText = true, TextColor3 = Color3.fromRGB(255, 255, 255), TextTransparency = 0,
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
			TextSize = 12, TextXAlignment = "Left", TextYAlignment = "Center",
			Size = UDim2.new(1, -12, 1, 0), BackgroundTransparency = 1, ThemeTag = { TextColor3 = "Text" },
		}),
		Creator.New("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(16, 16),
			Position = UDim2.new(0, 8, 0.5, 0), BackgroundTransparency = 1,
			Image = Icon and Icon or nil, ThemeTag = { ImageColor3 = "Text" },
		}),
	})

	local ContainerLayout = Creator.New("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder })

	Tab.ContainerFrame = Creator.New("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = Window.ContainerHolder, Visible = false,
		BottomImage = "rbxassetid://6889812791", MidImage = "rbxassetid://6889812721", TopImage = "rbxassetid://6276641225",
		ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255), ScrollBarImageTransparency = 0.95,
		ScrollBarThickness = 3, BorderSizePixel = 0, CanvasSize = UDim2.fromScale(0, 0),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, {
		ContainerLayout,
		Creator.New("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingLeft = UDim.new(0, 1), PaddingTop = UDim.new(0, 1), PaddingBottom = UDim.new(0, 1) }),
	})

	Creator.AddSignal(ContainerLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
		Tab.ContainerFrame.CanvasSize = UDim2.new(0, 0, 0, ContainerLayout.AbsoluteContentSize.Y + 2)
	end)

	Tab.Motor, Tab.SetTransparency = Creator.SpringMotor(1, Tab.Frame, "BackgroundTransparency")

	Creator.AddSignal(Tab.Frame.MouseEnter, function() Tab.SetTransparency(Tab.Selected and 0.85 or 0.89) end)
	Creator.AddSignal(Tab.Frame.MouseLeave, function() Tab.SetTransparency(Tab.Selected and 0.89 or 1) end)
	Creator.AddSignal(Tab.Frame.MouseButton1Down, function() Tab.SetTransparency(0.92) end)
	Creator.AddSignal(Tab.Frame.MouseButton1Up, function() Tab.SetTransparency(Tab.Selected and 0.85 or 0.89) end)
	Creator.AddSignal(Tab.Frame.MouseButton1Click, function() TabModule:SelectTab(TabIndex) end)

	TabModule.Containers[TabIndex] = Tab.ContainerFrame
	TabModule.Tabs[TabIndex] = Tab
	Tab.Container = Tab.ContainerFrame
	Tab.ScrollFrame = Tab.Container

	function Tab:AddSection(SectionTitle)
		local Section = { Type = "Section" }
		local SectionFrame = ComponentSection(SectionTitle, Tab.Container)
		Section.Container = SectionFrame.Container
		Section.ScrollFrame = Tab.Container
		setmetatable(Section, Elements)
		return Section
	end

	setmetatable(Tab, Elements)
	return Tab
end

function TabModule:SelectTab(Tab)
	local Window = TabModule.Window
	TabModule.SelectedTab = Tab

	for _, TabObject in next, TabModule.Tabs do
		TabObject.SetTransparency(1)
		TabObject.Selected = false
	end
	TabModule.Tabs[Tab].SetTransparency(0.89)
	TabModule.Tabs[Tab].Selected = true

	Window.TabDisplay.Text = TabModule.Tabs[Tab].Name
	Window.SelectorPosMotor:setGoal(Spring.new(TabModule:GetCurrentTabPos(), { frequency = 6 }))

	task.spawn(function()
		Window.ContainerPosMotor:setGoal(Spring.new(110, { frequency = 10 }))
		Window.ContainerBackMotor:setGoal(Spring.new(1, { frequency = 10 }))
		task.wait(0.15)
		for _, Container in next, TabModule.Containers do Container.Visible = false end
		TabModule.Containers[Tab].Visible = true
		Window.ContainerPosMotor:setGoal(Spring.new(94, { frequency = 5 }))
		Window.ContainerBackMotor:setGoal(Spring.new(0, { frequency = 8 }))
	end)
end

-- ================================================
-- ELEMENTS: Button
-- ================================================

local ElementButton = {}
ElementButton.__index = ElementButton
ElementButton.__type = "Button"

function ElementButton:New(Config)
	assert(Config.Title, "Button - Missing Title")
	Config.Callback = Config.Callback or function() end

	local ButtonFrame = ComponentElement(Config.Title, Config.Description, self.Container, true)

	Creator.New("ImageLabel", {
		Image = "rbxassetid://10709791437", Size = UDim2.fromOffset(16, 16),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
		BackgroundTransparency = 1, Parent = ButtonFrame.Frame, ThemeTag = { ImageColor3 = "Text" },
	})

	Creator.AddSignal(ButtonFrame.Frame.MouseButton1Click, function()
		self.Library:SafeCallback(Config.Callback)
	end)

	return ButtonFrame
end

-- ================================================
-- ELEMENTS: Toggle
-- ================================================

local ElementToggle = {}
ElementToggle.__index = ElementToggle
ElementToggle.__type = "Toggle"

function ElementToggle:New(Idx, Config)
	local Lib = self.Library
	assert(Config.Title, "Toggle - Missing Title")

	local Toggle = {
		Value = Config.Default or false,
		Callback = Config.Callback or function(Value) end,
		Type = "Toggle",
	}

	local ToggleFrame = ComponentElement(Config.Title, Config.Description, self.Container, true)
	ToggleFrame.DescLabel.Size = UDim2.new(1, -54, 0, 14)

	Toggle.SetTitle = ToggleFrame.SetTitle
	Toggle.SetDesc = ToggleFrame.SetDesc

	local ToggleCircle = Creator.New("ImageLabel", {
		AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(14, 14),
		Position = UDim2.new(0, 2, 0.5, 0), Image = "http://www.roblox.com/asset/?id=12266946128",
		ImageTransparency = 0.5, ThemeTag = { ImageColor3 = "ToggleSlider" },
	})

	local ToggleBorder = Creator.New("UIStroke", { Transparency = 0.5, ThemeTag = { Color = "ToggleSlider" } })

	local ToggleSlider = Creator.New("Frame", {
		Size = UDim2.fromOffset(36, 18), AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0), Parent = ToggleFrame.Frame,
		BackgroundTransparency = 1, ThemeTag = { BackgroundColor3 = "Accent" },
	}, {
		Creator.New("UICorner", { CornerRadius = UDim.new(0, 9) }),
		ToggleBorder, ToggleCircle,
	})

	function Toggle:OnChanged(Func) Toggle.Changed = Func; Func(Toggle.Value) end

	function Toggle:SetValue(Value)
		Value = not not Value
		Toggle.Value = Value
		Creator.OverrideTag(ToggleBorder, { Color = Toggle.Value and "Accent" or "ToggleSlider" })
		Creator.OverrideTag(ToggleCircle, { ImageColor3 = Toggle.Value and "ToggleToggled" or "ToggleSlider" })
		TweenService:Create(ToggleCircle, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.new(0, Toggle.Value and 19 or 2, 0.5, 0) }):Play()
		TweenService:Create(ToggleSlider, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundTransparency = Toggle.Value and 0 or 1 }):Play()
		ToggleCircle.ImageTransparency = Toggle.Value and 0 or 0.5
		Lib:SafeCallback(Toggle.Callback, Toggle.Value)
		Lib:SafeCallback(Toggle.Changed, Toggle.Value)
	end

	function Toggle:Destroy() ToggleFrame:Destroy(); Lib.Options[Idx] = nil end

	Creator.AddSignal(ToggleFrame.Frame.MouseButton1Click, function() Toggle:SetValue(not Toggle.Value) end)
	Toggle:SetValue(Toggle.Value)

	Lib.Options[Idx] = Toggle
	return Toggle
end

-- ================================================
-- ELEMENTS: Slider
-- ================================================

local ElementSlider = {}
ElementSlider.__index = ElementSlider
ElementSlider.__type = "Slider"

function ElementSlider:New(Idx, Config)
	local Lib = self.Library
	assert(Config.Title, "Slider - Missing Title.")
	assert(Config.Default, "Slider - Missing default value.")
	assert(Config.Min, "Slider - Missing minimum value.")
	assert(Config.Max, "Slider - Missing maximum value.")
	assert(Config.Rounding, "Slider - Missing rounding value.")

	local Slider = {
		Value = nil, Min = Config.Min, Max = Config.Max, Rounding = Config.Rounding,
		Callback = Config.Callback or function(Value) end, Type = "Slider",
	}
	local Dragging = false

	local SliderFrame = ComponentElement(Config.Title, Config.Description, self.Container, false)
	SliderFrame.DescLabel.Size = UDim2.new(1, -170, 0, 14)

	Slider.SetTitle = SliderFrame.SetTitle
	Slider.SetDesc = SliderFrame.SetDesc

	local SliderDot = Creator.New("ImageLabel", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -7, 0.5, 0),
		Size = UDim2.fromOffset(14, 14), Image = "http://www.roblox.com/asset/?id=12266946128",
		ThemeTag = { ImageColor3 = "Accent" },
	})

	local SliderRail = Creator.New("Frame", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(7, 0), Size = UDim2.new(1, -14, 1, 0),
	}, { SliderDot })

	local SliderFill = Creator.New("Frame", {
		Size = UDim2.new(0, 0, 1, 0), ThemeTag = { BackgroundColor3 = "Accent" },
	}, { Creator.New("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	local SliderDisplay = Creator.New("TextLabel", {
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"), Text = "Value",
		TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Right,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 1,
		Size = UDim2.new(0, 100, 0, 14), Position = UDim2.new(0, -4, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
		ThemeTag = { TextColor3 = "SubText" },
	})

	local SliderInner = Creator.New("Frame", {
		Size = UDim2.new(1, 0, 0, 4), AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0), BackgroundTransparency = 0.4, Parent = SliderFrame.Frame,
		ThemeTag = { BackgroundColor3 = "SliderRail" },
	}, {
		Creator.New("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Creator.New("UISizeConstraint", { MaxSize = Vector2.new(150, math.huge) }),
		SliderDisplay, SliderFill, SliderRail,
	})

	Creator.AddSignal(SliderDot.InputBegan, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			Dragging = true
		end
	end)
	Creator.AddSignal(SliderDot.InputEnded, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			Dragging = false
		end
	end)
	Creator.AddSignal(UserInputService.InputChanged, function(Input)
		if Dragging and (Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch) then
			local SizeScale = math.clamp((Input.Position.X - SliderRail.AbsolutePosition.X) / SliderRail.AbsoluteSize.X, 0, 1)
			Slider:SetValue(Slider.Min + ((Slider.Max - Slider.Min) * SizeScale))
		end
	end)

	function Slider:OnChanged(Func) Slider.Changed = Func; Func(Slider.Value) end

	function Slider:SetValue(Value)
		self.Value = Lib:Round(math.clamp(Value, Slider.Min, Slider.Max), Slider.Rounding)
		SliderDot.Position = UDim2.new((self.Value - Slider.Min) / (Slider.Max - Slider.Min), -7, 0.5, 0)
		SliderFill.Size = UDim2.fromScale((self.Value - Slider.Min) / (Slider.Max - Slider.Min), 1)
		SliderDisplay.Text = tostring(self.Value)
		Lib:SafeCallback(Slider.Callback, self.Value)
		Lib:SafeCallback(Slider.Changed, self.Value)
	end

	function Slider:Destroy() SliderFrame:Destroy(); Lib.Options[Idx] = nil end

	Slider:SetValue(Config.Default)
	Lib.Options[Idx] = Slider
	return Slider
end

-- ================================================
-- ELEMENTS: Dropdown
-- ================================================

local ElementDropdown = {}
ElementDropdown.__index = ElementDropdown
ElementDropdown.__type = "Dropdown"

function ElementDropdown:New(Idx, Config)
	local Lib = self.Library

	local Dropdown = {
		Values = Config.Values, Value = Config.Default, Multi = Config.Multi,
		Buttons = {}, Opened = false, Type = "Dropdown",
		Callback = Config.Callback or function() end,
	}

	local DropdownFrame = ComponentElement(Config.Title, Config.Description, self.Container, false)
	DropdownFrame.DescLabel.Size = UDim2.new(1, -170, 0, 14)

	Dropdown.SetTitle = DropdownFrame.SetTitle
	Dropdown.SetDesc = DropdownFrame.SetDesc

	local DropdownDisplay = Creator.New("TextLabel", {
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
		Text = "Value", TextColor3 = Color3.fromRGB(240, 240, 240), TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -30, 0, 14),
		Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 1,
		TextTruncate = Enum.TextTruncate.AtEnd, ThemeTag = { TextColor3 = "Text" },
	})

	local DropdownIco = Creator.New("ImageLabel", {
		Image = "rbxassetid://10709790948", Size = UDim2.fromOffset(16, 16),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
		BackgroundTransparency = 1, ThemeTag = { ImageColor3 = "SubText" },
	})

	local DropdownInner = Creator.New("TextButton", {
		Size = UDim2.fromOffset(160, 30), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 0.9, Parent = DropdownFrame.Frame, ThemeTag = { BackgroundColor3 = "DropdownFrame" },
	}, {
		Creator.New("UICorner", { CornerRadius = UDim.new(0, 5) }),
		Creator.New("UIStroke", { Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, ThemeTag = { Color = "InElementBorder" } }),
		DropdownIco, DropdownDisplay,
	})

	local DropdownListLayout = Creator.New("UIListLayout", { Padding = UDim.new(0, 3) })

	local DropdownScrollFrame = Creator.New("ScrollingFrame", {
		Size = UDim2.new(1, -5, 1, -10), Position = UDim2.fromOffset(5, 5), BackgroundTransparency = 1,
		BottomImage = "rbxassetid://6889812791", MidImage = "rbxassetid://6889812721", TopImage = "rbxassetid://6276641225",
		ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255), ScrollBarImageTransparency = 0.95,
		ScrollBarThickness = 4, BorderSizePixel = 0, CanvasSize = UDim2.fromScale(0, 0),
	}, { DropdownListLayout })

	local DropdownHolderFrame = Creator.New("Frame", {
		Size = UDim2.fromScale(1, 0.6), ThemeTag = { BackgroundColor3 = "DropdownHolder" },
	}, {
		DropdownScrollFrame,
		Creator.New("UICorner", { CornerRadius = UDim.new(0, 7) }),
		Creator.New("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, ThemeTag = { Color = "DropdownBorder" } }),
		Creator.New("ImageLabel", {
			BackgroundTransparency = 1, Image = "http://www.roblox.com/asset/?id=5554236805",
			ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(23, 23, 277, 277),
			Size = UDim2.fromScale(1, 1) + UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(-15, -15),
			ImageColor3 = Color3.fromRGB(0, 0, 0), ImageTransparency = 0.1,
		}),
	})

	local DropdownHolderCanvas = Creator.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(170, 300), Parent = Library.GUI, Visible = false,
	}, {
		DropdownHolderFrame,
		Creator.New("UISizeConstraint", { MinSize = Vector2.new(170, 0) }),
	})
	table.insert(Library.OpenFrames, DropdownHolderCanvas)

	local function RecalculateListPosition()
		local Add = 0
		if Camera.ViewportSize.Y - DropdownInner.AbsolutePosition.Y < DropdownHolderCanvas.AbsoluteSize.Y - 5 then
			Add = DropdownHolderCanvas.AbsoluteSize.Y - 5 - (Camera.ViewportSize.Y - DropdownInner.AbsolutePosition.Y) + 40
		end
		DropdownHolderCanvas.Position = UDim2.fromOffset(DropdownInner.AbsolutePosition.X - 1, DropdownInner.AbsolutePosition.Y - 5 - Add)
	end

	local ListSizeX = 0
	local function RecalculateListSize()
		if #Dropdown.Values > 10 then DropdownHolderCanvas.Size = UDim2.fromOffset(ListSizeX, 392)
		else DropdownHolderCanvas.Size = UDim2.fromOffset(ListSizeX, DropdownListLayout.AbsoluteContentSize.Y + 10) end
	end

	local function RecalculateCanvasSize()
		DropdownScrollFrame.CanvasSize = UDim2.fromOffset(0, DropdownListLayout.AbsoluteContentSize.Y)
	end

	RecalculateListPosition()
	RecalculateListSize()

	Creator.AddSignal(DropdownInner:GetPropertyChangedSignal("AbsolutePosition"), RecalculateListPosition)
	Creator.AddSignal(DropdownInner.MouseButton1Click, function() Dropdown:Open() end)

	Creator.AddSignal(UserInputService.InputBegan, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			local AbsPos, AbsSize = DropdownHolderFrame.AbsolutePosition, DropdownHolderFrame.AbsoluteSize
			if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then
				Dropdown:Close()
			end
		end
	end)

	local ScrollFrame = self.ScrollFrame
	function Dropdown:Open()
		Dropdown.Opened = true
		ScrollFrame.ScrollingEnabled = false
		DropdownHolderCanvas.Visible = true
		TweenService:Create(DropdownHolderFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
	end

	function Dropdown:Close()
		Dropdown.Opened = false
		ScrollFrame.ScrollingEnabled = true
		DropdownHolderFrame.Size = UDim2.fromScale(1, 0.6)
		DropdownHolderCanvas.Visible = false
	end

	function Dropdown:Display()
		local Values = Dropdown.Values
		local Str = ""
		if Config.Multi then
			for _, Value in next, Values do
				if Dropdown.Value[Value] then Str = Str .. Value .. ", " end
			end
			Str = Str:sub(1, #Str - 2)
		else
			Str = Dropdown.Value or ""
		end
		DropdownDisplay.Text = (Str == "" and "--" or Str)
	end

	function Dropdown:GetActiveValues()
		if Config.Multi then
			local T = {}
			for Value, Bool in next, Dropdown.Value do table.insert(T, Value) end
			return T
		else
			return Dropdown.Value and 1 or 0
		end
	end

	function Dropdown:BuildDropdownList()
		local Values = Dropdown.Values
		local Buttons = {}

		for _, El in next, DropdownScrollFrame:GetChildren() do
			if not El:IsA("UIListLayout") then El:Destroy() end
		end

		for Idx2, Value in next, Values do
			local Table = {}

			local ButtonSelector = Creator.New("Frame", {
				Size = UDim2.fromOffset(4, 14), BackgroundColor3 = Color3.fromRGB(76, 194, 255),
				Position = UDim2.fromOffset(-1, 16), AnchorPoint = Vector2.new(0, 0.5),
				ThemeTag = { BackgroundColor3 = "Accent" },
			}, { Creator.New("UICorner", { CornerRadius = UDim.new(0, 2) }) })

			local ButtonLabel = Creator.New("TextLabel", {
				FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
				Text = Value, TextColor3 = Color3.fromRGB(200, 200, 200), TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(10, 0), Name = "ButtonLabel",
				ThemeTag = { TextColor3 = "Text" },
			})

			local Button = Creator.New("TextButton", {
				Size = UDim2.new(1, -5, 0, 32), BackgroundTransparency = 1, ZIndex = 23,
				Text = "", Parent = DropdownScrollFrame, ThemeTag = { BackgroundColor3 = "DropdownOption" },
			}, { ButtonSelector, ButtonLabel, Creator.New("UICorner", { CornerRadius = UDim.new(0, 6) }) })

			local Selected
			if Config.Multi then Selected = Dropdown.Value[Value]
			else Selected = Dropdown.Value == Value end

			local BackMotor, SetBackTransparency = Creator.SpringMotor(1, Button, "BackgroundTransparency")
			local SelMotor, SetSelTransparency = Creator.SpringMotor(1, ButtonSelector, "BackgroundTransparency")
			local SelectorSizeMotor2 = SingleMotor.new(6)
			SelectorSizeMotor2:onStep(function(value) ButtonSelector.Size = UDim2.new(0, 4, 0, value) end)

			Creator.AddSignal(Button.MouseEnter, function() SetBackTransparency(Selected and 0.85 or 0.89) end)
			Creator.AddSignal(Button.MouseLeave, function() SetBackTransparency(Selected and 0.89 or 1) end)
			Creator.AddSignal(Button.MouseButton1Down, function() SetBackTransparency(0.92) end)
			Creator.AddSignal(Button.MouseButton1Up, function() SetBackTransparency(Selected and 0.85 or 0.89) end)

			function Table:UpdateButton()
				if Config.Multi then
					Selected = Dropdown.Value[Value]
					if Selected then SetBackTransparency(0.89) end
				else
					Selected = Dropdown.Value == Value
					SetBackTransparency(Selected and 0.89 or 1)
				end
				SelectorSizeMotor2:setGoal(Spring.new(Selected and 14 or 6, { frequency = 6 }))
				SetSelTransparency(Selected and 0 or 1)
			end

			ButtonLabel.InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
					local Try = not Selected
					if Dropdown:GetActiveValues() == 1 and not Try and not Config.AllowNull then
					else
						if Config.Multi then
							Selected = Try
							Dropdown.Value[Value] = Selected and true or nil
						else
							Selected = Try
							Dropdown.Value = Selected and Value or nil
							for _, OtherButton in next, Buttons do OtherButton:UpdateButton() end
						end
						Table:UpdateButton()
						Dropdown:Display()
						Lib:SafeCallback(Dropdown.Callback, Dropdown.Value)
						Lib:SafeCallback(Dropdown.Changed, Dropdown.Value)
					end
				end
			end)

			Table:UpdateButton()
			Dropdown:Display()
			Buttons[Button] = Table
		end

		ListSizeX = 0
		for Btn, _ in next, Buttons do
			if Btn:FindFirstChild("ButtonLabel") then
				if Btn.ButtonLabel.TextBounds.X > ListSizeX then ListSizeX = Btn.ButtonLabel.TextBounds.X end
			end
		end
		ListSizeX = ListSizeX + 30

		RecalculateCanvasSize()
		RecalculateListSize()
	end

	function Dropdown:SetValues(NewValues)
		if NewValues then Dropdown.Values = NewValues end
		Dropdown:BuildDropdownList()
	end

	function Dropdown:OnChanged(Func) Dropdown.Changed = Func; Func(Dropdown.Value) end

	function Dropdown:SetValue(Val)
		if Dropdown.Multi then
			local nTable = {}
			for Value, Bool in next, Val do
				if table.find(Dropdown.Values, Value) then nTable[Value] = true end
			end
			Dropdown.Value = nTable
		else
			if not Val then Dropdown.Value = nil
			elseif table.find(Dropdown.Values, Val) then Dropdown.Value = Val end
		end
		Dropdown:BuildDropdownList()
		Lib:SafeCallback(Dropdown.Callback, Dropdown.Value)
		Lib:SafeCallback(Dropdown.Changed, Dropdown.Value)
	end

	function Dropdown:Destroy() DropdownFrame:Destroy(); Lib.Options[Idx] = nil end

	Dropdown:BuildDropdownList()
	Dropdown:Display()

	-- Handle defaults
	local Defaults = {}
	if type(Config.Default) == "string" then
		local DIdx = table.find(Dropdown.Values, Config.Default)
		if DIdx then table.insert(Defaults, DIdx) end
	elseif type(Config.Default) == "table" then
		for _, Value in next, Config.Default do
			local DIdx = table.find(Dropdown.Values, Value)
			if DIdx then table.insert(Defaults, DIdx) end
		end
	elseif type(Config.Default) == "number" and Dropdown.Values[Config.Default] ~= nil then
		table.insert(Defaults, Config.Default)
	end

	if next(Defaults) then
		for i = 1, #Defaults do
			local Index = Defaults[i]
			if Config.Multi then Dropdown.Value[Dropdown.Values[Index]] = true
			else Dropdown.Value = Dropdown.Values[Index] end
			if not Config.Multi then break end
		end
		Dropdown:BuildDropdownList()
		Dropdown:Display()
	end

	Lib.Options[Idx] = Dropdown
	return Dropdown
end

-- ================================================
-- ELEMENTS: Input
-- ================================================

local ElementInput = {}
ElementInput.__index = ElementInput
ElementInput.__type = "Input"

function ElementInput:New(Idx, Config)
	local Lib = self.Library
	assert(Config.Title, "Input - Missing Title")
	Config.Callback = Config.Callback or function() end

	local Input = {
		Value = Config.Default or "", Numeric = Config.Numeric or false,
		Finished = Config.Finished or false, Callback = Config.Callback or function(Value) end, Type = "Input",
	}

	local InputFrame = ComponentElement(Config.Title, Config.Description, self.Container, false)
	Input.SetTitle = InputFrame.SetTitle
	Input.SetDesc = InputFrame.SetDesc

	local Textbox = ComponentTextbox(InputFrame.Frame, true)
	Textbox.Frame.Position = UDim2.new(1, -10, 0.5, 0)
	Textbox.Frame.AnchorPoint = Vector2.new(1, 0.5)
	Textbox.Frame.Size = UDim2.fromOffset(160, 30)
	Textbox.Input.Text = Config.Default or ""
	Textbox.Input.PlaceholderText = Config.Placeholder or ""

	local Box = Textbox.Input

	function Input:SetValue(Text)
		if Config.MaxLength and #Text > Config.MaxLength then Text = Text:sub(1, Config.MaxLength) end
		if Input.Numeric then
			if (not tonumber(Text)) and Text:len() > 0 then Text = Input.Value end
		end
		Input.Value = Text
		Box.Text = Text
		Lib:SafeCallback(Input.Callback, Input.Value)
		Lib:SafeCallback(Input.Changed, Input.Value)
	end

	if Input.Finished then
		Creator.AddSignal(Box.FocusLost, function(enter)
			if not enter then return end
			Input:SetValue(Box.Text)
		end)
	else
		Creator.AddSignal(Box:GetPropertyChangedSignal("Text"), function() Input:SetValue(Box.Text) end)
	end

	function Input:OnChanged(Func) Input.Changed = Func; Func(Input.Value) end
	function Input:Destroy() InputFrame:Destroy(); Lib.Options[Idx] = nil end

	Lib.Options[Idx] = Input
	return Input
end

-- ================================================
-- ELEMENTS: Keybind
-- ================================================

local ElementKeybind = {}
ElementKeybind.__index = ElementKeybind
ElementKeybind.__type = "Keybind"

function ElementKeybind:New(Idx, Config)
	local Lib = self.Library
	assert(Config.Title, "KeyBind - Missing Title")
	assert(Config.Default, "KeyBind - Missing default value.")

	local Keybind = {
		Value = Config.Default, Toggled = false, Mode = Config.Mode or "Toggle", Type = "Keybind",
		Callback = Config.Callback or function(Value) end,
		ChangedCallback = Config.ChangedCallback or function(New) end,
	}
	local Picking = false

	local KeybindFrame = ComponentElement(Config.Title, Config.Description, self.Container, true)
	Keybind.SetTitle = KeybindFrame.SetTitle
	Keybind.SetDesc = KeybindFrame.SetDesc

	local KeybindDisplayLabel = Creator.New("TextLabel", {
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
		Text = Config.Default, TextColor3 = Color3.fromRGB(240, 240, 240), TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(0, 0, 0, 14),
		Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1, ThemeTag = { TextColor3 = "Text" },
	})

	local KeybindDisplayFrame = Creator.New("TextButton", {
		Size = UDim2.fromOffset(0, 30), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 0.9, Parent = KeybindFrame.Frame, AutomaticSize = Enum.AutomaticSize.X,
		ThemeTag = { BackgroundColor3 = "Keybind" },
	}, {
		Creator.New("UICorner", { CornerRadius = UDim.new(0, 5) }),
		Creator.New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		Creator.New("UIStroke", { Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, ThemeTag = { Color = "InElementBorder" } }),
		KeybindDisplayLabel,
	})

	function Keybind:GetState()
		if UserInputService:GetFocusedTextBox() and Keybind.Mode ~= "Always" then return false end
		if Keybind.Mode == "Always" then return true
		elseif Keybind.Mode == "Hold" then
			if Keybind.Value == "None" then return false end
			local Key = Keybind.Value
			if Key == "MouseLeft" or Key == "MouseRight" then
				return Key == "MouseLeft" and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) or Key == "MouseRight" and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			else return UserInputService:IsKeyDown(Enum.KeyCode[Keybind.Value]) end
		else return Keybind.Toggled end
	end

	function Keybind:SetValue(Key, Mode)
		Key = Key or Keybind.Key; Mode = Mode or Keybind.Mode
		KeybindDisplayLabel.Text = Key; Keybind.Value = Key; Keybind.Mode = Mode
	end

	function Keybind:OnClick(Callback) Keybind.Clicked = Callback end
	function Keybind:OnChanged(Callback) Keybind.Changed = Callback; Callback(Keybind.Value) end

	function Keybind:DoClick()
		Lib:SafeCallback(Keybind.Callback, Keybind.Toggled)
		Lib:SafeCallback(Keybind.Clicked, Keybind.Toggled)
	end

	function Keybind:Destroy() KeybindFrame:Destroy(); Lib.Options[Idx] = nil end

	Creator.AddSignal(KeybindDisplayFrame.InputBegan, function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
			Picking = true
			KeybindDisplayLabel.Text = "..."
			wait(0.2)
			local Event
			Event = UserInputService.InputBegan:Connect(function(Input2)
				local Key
				if Input2.UserInputType == Enum.UserInputType.Keyboard then Key = Input2.KeyCode.Name
				elseif Input2.UserInputType == Enum.UserInputType.MouseButton1 then Key = "MouseLeft"
				elseif Input2.UserInputType == Enum.UserInputType.MouseButton2 then Key = "MouseRight" end

				local EndedEvent
				EndedEvent = UserInputService.InputEnded:Connect(function(Input3)
					if Input3.KeyCode.Name == Key or Key == "MouseLeft" and Input3.UserInputType == Enum.UserInputType.MouseButton1 or Key == "MouseRight" and Input3.UserInputType == Enum.UserInputType.MouseButton2 then
						Picking = false
						KeybindDisplayLabel.Text = Key
						Keybind.Value = Key
						Lib:SafeCallback(Keybind.ChangedCallback, Input3.KeyCode or Input3.UserInputType)
						Lib:SafeCallback(Keybind.Changed, Input3.KeyCode or Input3.UserInputType)
						Event:Disconnect()
						EndedEvent:Disconnect()
					end
				end)
			end)
		end
	end)

	Creator.AddSignal(UserInputService.InputBegan, function(Input)
		if not Picking and not UserInputService:GetFocusedTextBox() then
			if Keybind.Mode == "Toggle" then
				local Key = Keybind.Value
				if Key == "MouseLeft" or Key == "MouseRight" then
					if Key == "MouseLeft" and Input.UserInputType == Enum.UserInputType.MouseButton1 or Key == "MouseRight" and Input.UserInputType == Enum.UserInputType.MouseButton2 then
						Keybind.Toggled = not Keybind.Toggled; Keybind:DoClick()
					end
				elseif Input.UserInputType == Enum.UserInputType.Keyboard then
					if Input.KeyCode.Name == Key then Keybind.Toggled = not Keybind.Toggled; Keybind:DoClick() end
				end
			end
		end
	end)

	Lib.Options[Idx] = Keybind
	return Keybind
end

-- ================================================
-- ELEMENTS: Colorpicker
-- ================================================

local ElementColorpicker = {}
ElementColorpicker.__index = ElementColorpicker
ElementColorpicker.__type = "Colorpicker"

function ElementColorpicker:New(Idx, Config)
	local Lib = self.Library
	assert(Config.Title, "Colorpicker - Missing Title")
	assert(Config.Default, "AddColorPicker: Missing default value.")

	local Colorpicker = {
		Value = Config.Default, Transparency = Config.Transparency or 0, Type = "Colorpicker",
		Title = type(Config.Title) == "string" and Config.Title or "Colorpicker",
		Callback = Config.Callback or function(Color) end,
	}

	function Colorpicker:SetHSVFromRGB(Color)
		local H, S, V = Color3.toHSV(Color)
		Colorpicker.Hue = H; Colorpicker.Sat = S; Colorpicker.Vib = V
	end
	Colorpicker:SetHSVFromRGB(Colorpicker.Value)

	local ColorpickerFrame = ComponentElement(Config.Title, Config.Description, self.Container, true)
	Colorpicker.SetTitle = ColorpickerFrame.SetTitle
	Colorpicker.SetDesc = ColorpickerFrame.SetDesc

	local DisplayFrameColor = Creator.New("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Colorpicker.Value, Parent = ColorpickerFrame.Frame,
	}, { Creator.New("UICorner", { CornerRadius = UDim.new(0, 4) }) })

	local DisplayFrame = Creator.New("ImageLabel", {
		Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
		Parent = ColorpickerFrame.Frame, Image = "http://www.roblox.com/asset/?id=14204231522",
		ImageTransparency = 0.45, ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(40, 40),
	}, {
		Creator.New("UICorner", { CornerRadius = UDim.new(0, 4) }),
		DisplayFrameColor,
	})

	local function CreateColorDialog()
		local Dlg = Dialog:Create()
		Dlg.Title.Text = Colorpicker.Title
		Dlg.Root.Size = UDim2.fromOffset(430, 330)

		local Hue, Sat, Vib = Colorpicker.Hue, Colorpicker.Sat, Colorpicker.Vib
		local Transparency = Colorpicker.Transparency

		local function CreateInput()
			local Box = ComponentTextbox()
			Box.Frame.Parent = Dlg.Root
			Box.Frame.Size = UDim2.new(0, 90, 0, 32)
			return Box
		end

		local function CreateInputLabel(Text, Pos)
			return Creator.New("TextLabel", {
				FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
				Text = Text, TextColor3 = Color3.fromRGB(240, 240, 240), TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 32), Position = Pos,
				BackgroundTransparency = 1, Parent = Dlg.Root, ThemeTag = { TextColor3 = "Text" },
			})
		end

		local function GetRGB()
			local Value = Color3.fromHSV(Hue, Sat, Vib)
			return { R = math.floor(Value.r * 255), G = math.floor(Value.g * 255), B = math.floor(Value.b * 255) }
		end

		local SatCursor = Creator.New("ImageLabel", {
			Size = UDim2.new(0, 18, 0, 18), ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
			Image = "http://www.roblox.com/asset/?id=4805639000",
		})

		local SatVibMap = Creator.New("ImageLabel", {
			Size = UDim2.fromOffset(180, 160), Position = UDim2.fromOffset(20, 55),
			Image = "rbxassetid://4155801252", BackgroundColor3 = Colorpicker.Value,
			BackgroundTransparency = 0, Parent = Dlg.Root,
		}, { Creator.New("UICorner", { CornerRadius = UDim.new(0, 4) }), SatCursor })

		local OldColorFrame = Creator.New("Frame", {
			BackgroundColor3 = Colorpicker.Value, Size = UDim2.fromScale(1, 1), BackgroundTransparency = Colorpicker.Transparency,
		}, { Creator.New("UICorner", { CornerRadius = UDim.new(0, 4) }) })

		local OldColorFrameChecker = Creator.New("ImageLabel", {
			Image = "http://www.roblox.com/asset/?id=14204231522", ImageTransparency = 0.45,
			ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(40, 40), BackgroundTransparency = 1,
			Position = UDim2.fromOffset(112, 220), Size = UDim2.fromOffset(88, 24), Parent = Dlg.Root,
		}, {
			Creator.New("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Creator.New("UIStroke", { Thickness = 2, Transparency = 0.75 }),
			OldColorFrame,
		})

		local DialogDisplayFrame = Creator.New("Frame", {
			BackgroundColor3 = Colorpicker.Value, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0,
		}, { Creator.New("UICorner", { CornerRadius = UDim.new(0, 4) }) })

		local DialogDisplayFrameChecker = Creator.New("ImageLabel", {
			Image = "http://www.roblox.com/asset/?id=14204231522", ImageTransparency = 0.45,
			ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(40, 40), BackgroundTransparency = 1,
			Position = UDim2.fromOffset(20, 220), Size = UDim2.fromOffset(88, 24), Parent = Dlg.Root,
		}, {
			Creator.New("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Creator.New("UIStroke", { Thickness = 2, Transparency = 0.75 }),
			DialogDisplayFrame,
		})

		local SequenceTable = {}
		for Color = 0, 1, 0.1 do
			table.insert(SequenceTable, ColorSequenceKeypoint.new(Color, Color3.fromHSV(Color, 1, 1)))
		end

		local HueSliderGradient = Creator.New("UIGradient", { Color = ColorSequence.new(SequenceTable), Rotation = 90 })
		local HueDragHolder = Creator.New("Frame", { Size = UDim2.new(1, 0, 1, -10), Position = UDim2.fromOffset(0, 5), BackgroundTransparency = 1 })
		local HueDrag = Creator.New("ImageLabel", {
			Size = UDim2.fromOffset(14, 14), Image = "http://www.roblox.com/asset/?id=12266946128",
			Parent = HueDragHolder, ThemeTag = { ImageColor3 = "DialogInput" },
		})

		local HueSlider = Creator.New("Frame", {
			Size = UDim2.fromOffset(12, 190), Position = UDim2.fromOffset(210, 55), Parent = Dlg.Root,
		}, { Creator.New("UICorner", { CornerRadius = UDim.new(1, 0) }), HueSliderGradient, HueDragHolder })

		local HexInput = CreateInput(); HexInput.Frame.Position = UDim2.fromOffset(Config.Transparency and 260 or 240, 55); CreateInputLabel("Hex", UDim2.fromOffset(Config.Transparency and 360 or 340, 55))
		local RedInput = CreateInput(); RedInput.Frame.Position = UDim2.fromOffset(Config.Transparency and 260 or 240, 95); CreateInputLabel("Red", UDim2.fromOffset(Config.Transparency and 360 or 340, 95))
		local GreenInput = CreateInput(); GreenInput.Frame.Position = UDim2.fromOffset(Config.Transparency and 260 or 240, 135); CreateInputLabel("Green", UDim2.fromOffset(Config.Transparency and 360 or 340, 135))
		local BlueInput = CreateInput(); BlueInput.Frame.Position = UDim2.fromOffset(Config.Transparency and 260 or 240, 175); CreateInputLabel("Blue", UDim2.fromOffset(Config.Transparency and 360 or 340, 175))

		local AlphaInput
		if Config.Transparency then
			AlphaInput = CreateInput(); AlphaInput.Frame.Position = UDim2.fromOffset(260, 215); CreateInputLabel("Alpha", UDim2.fromOffset(360, 215))
		end

		local TransparencySlider, TransparencyDrag, TransparencyColor
		if Config.Transparency then
			local TransparencyDragHolder = Creator.New("Frame", { Size = UDim2.new(1, 0, 1, -10), Position = UDim2.fromOffset(0, 5), BackgroundTransparency = 1 })
			TransparencyDrag = Creator.New("ImageLabel", { Size = UDim2.fromOffset(14, 14), Image = "http://www.roblox.com/asset/?id=12266946128", Parent = TransparencyDragHolder, ThemeTag = { ImageColor3 = "DialogInput" } })
			TransparencyColor = Creator.New("Frame", { Size = UDim2.fromScale(1, 1) }, {
				Creator.New("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }), Rotation = 270 }),
				Creator.New("UICorner", { CornerRadius = UDim.new(1, 0) }),
			})
			TransparencySlider = Creator.New("Frame", {
				Size = UDim2.fromOffset(12, 190), Position = UDim2.fromOffset(230, 55), Parent = Dlg.Root, BackgroundTransparency = 1,
			}, {
				Creator.New("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Creator.New("ImageLabel", { Image = "http://www.roblox.com/asset/?id=14204231522", ImageTransparency = 0.45, ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(40, 40), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = Dlg.Root }, { Creator.New("UICorner", { CornerRadius = UDim.new(1, 0) }) }),
				TransparencyColor, TransparencyDragHolder,
			})
		end

		local function Display()
			SatVibMap.BackgroundColor3 = Color3.fromHSV(Hue, 1, 1)
			HueDrag.Position = UDim2.new(0, -1, Hue, -6)
			SatCursor.Position = UDim2.new(Sat, 0, 1 - Vib, 0)
			DialogDisplayFrame.BackgroundColor3 = Color3.fromHSV(Hue, Sat, Vib)
			HexInput.Input.Text = "#" .. Color3.fromHSV(Hue, Sat, Vib):ToHex()
			RedInput.Input.Text = GetRGB()["R"]
			GreenInput.Input.Text = GetRGB()["G"]
			BlueInput.Input.Text = GetRGB()["B"]
			if Config.Transparency then
				TransparencyColor.BackgroundColor3 = Color3.fromHSV(Hue, Sat, Vib)
				DialogDisplayFrame.BackgroundTransparency = Transparency
				TransparencyDrag.Position = UDim2.new(0, -1, 1 - Transparency, -6)
				AlphaInput.Input.Text = Lib:Round((1 - Transparency) * 100, 0) .. "%"
			end
		end

		Creator.AddSignal(HexInput.Input.FocusLost, function(Enter)
			if Enter then
				local Success, Result = pcall(Color3.fromHex, HexInput.Input.Text)
				if Success and typeof(Result) == "Color3" then Hue, Sat, Vib = Color3.toHSV(Result) end
			end
			Display()
		end)
		Creator.AddSignal(RedInput.Input.FocusLost, function(Enter)
			if Enter then
				local CurrentColor = GetRGB()
				local Success, Result = pcall(Color3.fromRGB, RedInput.Input.Text, CurrentColor["G"], CurrentColor["B"])
				if Success and typeof(Result) == "Color3" and tonumber(RedInput.Input.Text) <= 255 then Hue, Sat, Vib = Color3.toHSV(Result) end
			end
			Display()
		end)
		Creator.AddSignal(GreenInput.Input.FocusLost, function(Enter)
			if Enter then
				local CurrentColor = GetRGB()
				local Success, Result = pcall(Color3.fromRGB, CurrentColor["R"], GreenInput.Input.Text, CurrentColor["B"])
				if Success and typeof(Result) == "Color3" and tonumber(GreenInput.Input.Text) <= 255 then Hue, Sat, Vib = Color3.toHSV(Result) end
			end
			Display()
		end)
		Creator.AddSignal(BlueInput.Input.FocusLost, function(Enter)
			if Enter then
				local CurrentColor = GetRGB()
				local Success, Result = pcall(Color3.fromRGB, CurrentColor["R"], CurrentColor["G"], BlueInput.Input.Text)
				if Success and typeof(Result) == "Color3" and tonumber(BlueInput.Input.Text) <= 255 then Hue, Sat, Vib = Color3.toHSV(Result) end
			end
			Display()
		end)
		if Config.Transparency then
			Creator.AddSignal(AlphaInput.Input.FocusLost, function(Enter)
				if Enter then
					pcall(function()
						local Value = tonumber(AlphaInput.Input.Text)
						if Value >= 0 and Value <= 100 then Transparency = 1 - Value * 0.01 end
					end)
				end
				Display()
			end)
		end

		Creator.AddSignal(SatVibMap.InputBegan, function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
				while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
					local MinX = SatVibMap.AbsolutePosition.X; local MaxX = MinX + SatVibMap.AbsoluteSize.X; local MouseX = math.clamp(Mouse.X, MinX, MaxX)
					local MinY = SatVibMap.AbsolutePosition.Y; local MaxY = MinY + SatVibMap.AbsoluteSize.Y; local MouseY = math.clamp(Mouse.Y, MinY, MaxY)
					Sat = (MouseX - MinX) / (MaxX - MinX); Vib = 1 - ((MouseY - MinY) / (MaxY - MinY)); Display()
					RunService.RenderStepped:Wait()
				end
			end
		end)

		Creator.AddSignal(HueSlider.InputBegan, function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
				while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
					local MinY = HueSlider.AbsolutePosition.Y; local MaxY = MinY + HueSlider.AbsoluteSize.Y; local MouseY = math.clamp(Mouse.Y, MinY, MaxY)
					Hue = ((MouseY - MinY) / (MaxY - MinY)); Display()
					RunService.RenderStepped:Wait()
				end
			end
		end)

		if Config.Transparency then
			Creator.AddSignal(TransparencySlider.InputBegan, function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
						local MinY = TransparencySlider.AbsolutePosition.Y; local MaxY = MinY + TransparencySlider.AbsoluteSize.Y; local MouseY = math.clamp(Mouse.Y, MinY, MaxY)
						Transparency = 1 - ((MouseY - MinY) / (MaxY - MinY)); Display()
						RunService.RenderStepped:Wait()
					end
				end
			end)
		end

		Display()
		Dlg:Button("Done", function() Colorpicker:SetValue({ Hue, Sat, Vib }, Transparency) end)
		Dlg:Button("Cancel")
		Dlg:Open()
	end

	function Colorpicker:Display()
		Colorpicker.Value = Color3.fromHSV(Colorpicker.Hue, Colorpicker.Sat, Colorpicker.Vib)
		DisplayFrameColor.BackgroundColor3 = Colorpicker.Value
		DisplayFrameColor.BackgroundTransparency = Colorpicker.Transparency
		ElementColorpicker.Library:SafeCallback(Colorpicker.Callback, Colorpicker.Value)
		ElementColorpicker.Library:SafeCallback(Colorpicker.Changed, Colorpicker.Value)
	end

	function Colorpicker:SetValue(HSV, Trans)
		local Color = Color3.fromHSV(HSV[1], HSV[2], HSV[3])
		Colorpicker.Transparency = Trans or 0
		Colorpicker:SetHSVFromRGB(Color)
		Colorpicker:Display()
	end

	function Colorpicker:SetValueRGB(Color, Trans)
		Colorpicker.Transparency = Trans or 0
		Colorpicker:SetHSVFromRGB(Color)
		Colorpicker:Display()
	end

	function Colorpicker:OnChanged(Func) Colorpicker.Changed = Func; Func(Colorpicker.Value) end
	function Colorpicker:Destroy() ColorpickerFrame:Destroy(); Lib.Options[Idx] = nil end

	Creator.AddSignal(ColorpickerFrame.Frame.MouseButton1Click, function() CreateColorDialog() end)
	Colorpicker:Display()

	Lib.Options[Idx] = Colorpicker
	return Colorpicker
end

-- ================================================
-- ELEMENTS: Paragraph
-- ================================================

local ElementParagraph = {}
ElementParagraph.__index = ElementParagraph
ElementParagraph.__type = "Paragraph"

function ElementParagraph:New(Config)
	assert(Config.Title, "Paragraph - Missing Title")
	Config.Content = Config.Content or ""
	local Para = ComponentElement(Config.Title, Config.Content, self.Container, false)
	Para.Frame.BackgroundTransparency = 0.92
	Para.Border.Transparency = 0.6
	return Para
end

-- ================================================
-- BUILD ELEMENTS TABLE
-- ================================================

local ElementsTable = { ElementButton, ElementToggle, ElementSlider, ElementDropdown, ElementInput, ElementKeybind, ElementColorpicker, ElementParagraph }

for _, ElementComponent in ipairs(ElementsTable) do
	Elements["Add" .. ElementComponent.__type] = function(self, Idx, Config)
		ElementComponent.Container = self.Container
		ElementComponent.Type = self.Type
		ElementComponent.ScrollFrame = self.ScrollFrame
		ElementComponent.Library = Library

		return ElementComponent:New(Idx, Config)
	end
end

-- ================================================
-- LIBRARY MAIN
-- ================================================

local ProtectGui = protectgui or (syn and syn.protect_gui) or function() end

local GUI = Creator.New("ScreenGui", {
	Parent = RunService:IsStudio() and LocalPlayer.PlayerGui or game:GetService("CoreGui"),
})
ProtectGui(GUI)
Notification:Init(GUI)

Library = {
	Version = "1.1.0",
	OpenFrames = {},
	Options = {},
	Themes = Themes.Names,
	Window = nil,
	WindowFrame = nil,
	Unloaded = false,
	Theme = "Dark",
	DialogOpen = false,
	UseAcrylic = true,
	Acrylic = true,
	Transparency = true,
	MinimizeKeybind = nil,
	MinimizeKey = Enum.KeyCode.LeftControl,
	GUI = GUI,
}

-- Fix ElementColorpicker's self.Library reference
ElementColorpicker.Library = Library

function Library:SafeCallback(Function, ...)
	if not Function then return end
	local Success, Event = pcall(Function, ...)
	if not Success then
		local _, i = Event:find(":%d+: ")
		if not i then
			return Library:Notify({ Title = "Interface", Content = "Callback error", SubContent = Event, Duration = 5 })
		end
		return Library:Notify({ Title = "Interface", Content = "Callback error", SubContent = Event:sub(i + 1), Duration = 5 })
	end
end

function Library:Round(Number, Factor)
	if Factor == 0 then return math.floor(Number) end
	Number = tostring(Number)
	return Number:find("%.") and tonumber(Number:sub(1, Number:find("%.") + Factor)) or Number
end

function Library:GetIcon(Name)
	if Name ~= nil and Icons.assets["lucide-" .. Name] then return Icons.assets["lucide-" .. Name] end
	return nil
end

Library.Elements = Elements

function Library:CreateWindow(Config)
	assert(Config.Title, "Toggle - Missing Title")
	Config.SubTitle = Config.SubTitle or ""
	Config.TabWidth = Config.TabWidth or 170
	Config.Size = Config.Size or UDim2.fromOffset(590, 470)
	Config.Acrylic = Config.Acrylic ~= false
	Config.Theme = Config.Theme or "Dark"
	Config.MinimizeKey = Config.MinimizeKey or Enum.KeyCode.LeftControl

	if Library.Window then print("You cannot create more than one window."); return end

	local Window = ComponentWindow({
		Parent = GUI, Size = Config.Size, Title = Config.Title,
		SubTitle = Config.SubTitle, TabWidth = Config.TabWidth,
	})

	Library.MinimizeKey = Config.MinimizeKey
	Library.UseAcrylic = Config.Acrylic
	if Library.UseAcrylic then Acrylic.init() end

	Library.Window = Window
	Library:SetTheme(Config.Theme)
	return Window
end

function Library:SetTheme(Value)
	if Library.Window and table.find(Library.Themes, Value) then
		Library.Theme = Value
		Creator.UpdateTheme()
	end
end

function Library:Destroy()
	if Library.Window then
		Library.Unloaded = true
		if Library.UseAcrylic then Library.Window.AcrylicPaint.Model:Destroy() end
		Creator.Disconnect()
		Library.GUI:Destroy()
	end
end

function Library:ToggleAcrylic(Value)
	if Library.Window then
		if Library.UseAcrylic then
			Library.Acrylic = Value
			Library.Window.AcrylicPaint.Model.Transparency = Value and 0.98 or 1
			if Value then Acrylic.Enable() else Acrylic.Disable() end
		end
	end
end

function Library:ToggleTransparency(Value)
	if Library.Window then
		Library.Window.AcrylicPaint.Frame.Background.BackgroundTransparency = Value and 0.35 or 0
	end
end

function Library:Notify(Config)
	return Notification:New(Config)
end

if getgenv then getgenv().Fluent = Library end

-- ================================================
-- ADDONS: SaveManager
-- ================================================

local httpService = game:GetService("HttpService")

local SaveManager = {}
SaveManager.Folder = "FluentSettings"
SaveManager.Ignore = {}
SaveManager.Parser = {
	Toggle = {
		Save = function(idx, object) return { type = "Toggle", idx = idx, value = object.Value } end,
		Load = function(idx, data) if SaveManager.Options[idx] then SaveManager.Options[idx]:SetValue(data.value) end end,
	},
	Slider = {
		Save = function(idx, object) return { type = "Slider", idx = idx, value = tostring(object.Value) } end,
		Load = function(idx, data) if SaveManager.Options[idx] then SaveManager.Options[idx]:SetValue(data.value) end end,
	},
	Dropdown = {
		Save = function(idx, object) return { type = "Dropdown", idx = idx, value = object.Value, mutli = object.Multi } end,
		Load = function(idx, data) if SaveManager.Options[idx] then SaveManager.Options[idx]:SetValue(data.value) end end,
	},
	Colorpicker = {
		Save = function(idx, object) return { type = "Colorpicker", idx = idx, value = object.Value:ToHex(), transparency = object.Transparency } end,
		Load = function(idx, data) if SaveManager.Options[idx] then SaveManager.Options[idx]:SetValueRGB(Color3.fromHex(data.value), data.transparency) end end,
	},
	Keybind = {
		Save = function(idx, object) return { type = "Keybind", idx = idx, mode = object.Mode, key = object.Value } end,
		Load = function(idx, data) if SaveManager.Options[idx] then SaveManager.Options[idx]:SetValue(data.key, data.mode) end end,
	},
	Input = {
		Save = function(idx, object) return { type = "Input", idx = idx, text = object.Value } end,
		Load = function(idx, data) if SaveManager.Options[idx] and type(data.text) == "string" then SaveManager.Options[idx]:SetValue(data.text) end end,
	},
}

function SaveManager:SetIgnoreIndexes(list)
	for _, key in next, list do self.Ignore[key] = true end
end

function SaveManager:SetFolder(folder) self.Folder = folder; self:BuildFolderTree() end

function SaveManager:Save(name)
	if not name then return false, "no config file is selected" end
	local fullPath = self.Folder .. "/settings/" .. name .. ".json"
	local data = { objects = {} }
	for idx, option in next, SaveManager.Options do
		if not self.Parser[option.Type] then continue end
		if self.Ignore[idx] then continue end
		table.insert(data.objects, self.Parser[option.Type].Save(idx, option))
	end
	local success, encoded = pcall(httpService.JSONEncode, httpService, data)
	if not success then return false, "failed to encode data" end
	writefile(fullPath, encoded)
	return true
end

function SaveManager:Load(name)
	if not name then return false, "no config file is selected" end
	local file = self.Folder .. "/settings/" .. name .. ".json"
	if not isfile(file) then return false, "invalid file" end
	local success, decoded = pcall(httpService.JSONDecode, httpService, readfile(file))
	if not success then return false, "decode error" end
	for _, option in next, decoded.objects do
		if self.Parser[option.type] then
			task.spawn(function() self.Parser[option.type].Load(option.idx, option) end)
		end
	end
	return true
end

function SaveManager:IgnoreThemeSettings()
	self:SetIgnoreIndexes({ "InterfaceTheme", "AcrylicToggle", "TransparentToggle", "MenuKeybind" })
end

function SaveManager:BuildFolderTree()
	local paths = { self.Folder, self.Folder .. "/settings" }
	for i = 1, #paths do if not isfolder(paths[i]) then makefolder(paths[i]) end end
end

function SaveManager:RefreshConfigList()
	local list = listfiles(self.Folder .. "/settings")
	local out = {}
	for i = 1, #list do
		local file = list[i]
		if file:sub(-5) == ".json" then
			local pos = file:find(".json", 1, true)
			local start = pos
			local char = file:sub(pos, pos)
			while char ~= "/" and char ~= "\\" and char ~= "" do pos = pos - 1; char = file:sub(pos, pos) end
			if char == "/" or char == "\\" then
				local name = file:sub(pos + 1, start - 1)
				if not name == "options" then table.insert(out, name) end
			end
		end
	end
	return out
end

function SaveManager:SetLibrary(library) self.Library = library; self.Options = library.Options end

function SaveManager:LoadAutoloadConfig()
	if isfile(self.Folder .. "/settings/autoload.txt") then
		local name = readfile(self.Folder .. "/settings/autoload.txt")
		local success, err = self:Load(name)
		if not success then
			return self.Library:Notify({ Title = "Interface", Content = "Config loader", SubContent = "Failed to load autoload config: " .. err, Duration = 7 })
		end
		self.Library:Notify({ Title = "Interface", Content = "Config loader", SubContent = string.format("Auto loaded config %q", name), Duration = 7 })
	end
end

function SaveManager:BuildConfigSection(tab)
	assert(self.Library, "Must set SaveManager.Library")
	local section = tab:AddSection("Configuration")
	section:AddInput("SaveManager_ConfigName", { Title = "Config name" })
	section:AddDropdown("SaveManager_ConfigList", { Title = "Config list", Values = self:RefreshConfigList(), AllowNull = true })
	section:AddButton({ Title = "Create config", Callback = function()
		local name = SaveManager.Options.SaveManager_ConfigName.Value
		if name:gsub(" ", "") == "" then return self.Library:Notify({ Title = "Interface", Content = "Config loader", SubContent = "Invalid config name (empty)", Duration = 7 }) end
		local success, err = self:Save(name)
		if not success then return self.Library:Notify({ Title = "Interface", Content = "Config loader", SubContent = "Failed to save config: " .. err, Duration = 7 }) end
		self.Library:Notify({ Title = "Interface", Content = "Config loader", SubContent = string.format("Created config %q", name), Duration = 7 })
		SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
		SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
	end })
	section:AddButton({ Title = "Load config", Callback = function()
		local name = SaveManager.Options.SaveManager_ConfigList.Value
		local success, err = self:Load(name)
		if not success then return self.Library:Notify({ Title = "Interface", Content = "Config loader", SubContent = "Failed to load config: " .. err, Duration = 7 }) end
		self.Library:Notify({ Title = "Interface", Content = "Config loader", SubContent = string.format("Loaded config %q", name), Duration = 7 })
	end })
	section:AddButton({ Title = "Overwrite config", Callback = function()
		local name = SaveManager.Options.SaveManager_ConfigList.Value
		local success, err = self:Save(name)
		if not success then return self.Library:Notify({ Title = "Interface", Content = "Config loader", SubContent = "Failed to overwrite config: " .. err, Duration = 7 }) end
		self.Library:Notify({ Title = "Interface", Content = "Config loader", SubContent = string.format("Overwrote config %q", name), Duration = 7 })
	end })
	section:AddButton({ Title = "Refresh list", Callback = function()
		SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
		SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
	end })
	local AutoloadButton
	AutoloadButton = section:AddButton({ Title = "Set as autoload", Description = "Current autoload config: none", Callback = function()
		local name = SaveManager.Options.SaveManager_ConfigList.Value
		writefile(self.Folder .. "/settings/autoload.txt", name)
		AutoloadButton:SetDesc("Current autoload config: " .. name)
		self.Library:Notify({ Title = "Interface", Content = "Config loader", SubContent = string.format("Set %q to auto load", name), Duration = 7 })
	end })
	if isfile(self.Folder .. "/settings/autoload.txt") then
		local name = readfile(self.Folder .. "/settings/autoload.txt")
		AutoloadButton:SetDesc("Current autoload config: " .. name)
	end
	SaveManager:SetIgnoreIndexes({ "SaveManager_ConfigList", "SaveManager_ConfigName" })
end

SaveManager:BuildFolderTree()

-- ================================================
-- ADDONS: InterfaceManager
-- ================================================

local InterfaceManager = {}
InterfaceManager.Folder = "FluentSettings"
InterfaceManager.Settings = { Theme = "Dark", Acrylic = true, Transparency = true, MenuKeybind = "LeftControl" }

function InterfaceManager:SetFolder(folder) self.Folder = folder; self:BuildFolderTree() end
function InterfaceManager:SetLibrary(library) self.Library = library end

function InterfaceManager:BuildFolderTree()
	local paths = {}
	local parts = self.Folder:split("/")
	for idx = 1, #parts do paths[#paths + 1] = table.concat(parts, "/", 1, idx) end
	table.insert(paths, self.Folder)
	table.insert(paths, self.Folder .. "/settings")
	for i = 1, #paths do if not isfolder(paths[i]) then makefolder(paths[i]) end end
end

function InterfaceManager:SaveSettings()
	writefile(self.Folder .. "/options.json", httpService:JSONEncode(InterfaceManager.Settings))
end

function InterfaceManager:LoadSettings()
	local path = self.Folder .. "/options.json"
	if isfile(path) then
		local data = readfile(path)
		local success, decoded = pcall(httpService.JSONDecode, httpService, data)
		if success then for i, v in next, decoded do InterfaceManager.Settings[i] = v end end
	end
end

function InterfaceManager:BuildInterfaceSection(tab)
	assert(self.Library, "Must set InterfaceManager.Library")
	local Lib = self.Library
	local Settings = InterfaceManager.Settings
	InterfaceManager:LoadSettings()

	local section = tab:AddSection("Interface")
	local InterfaceTheme = section:AddDropdown("InterfaceTheme", {
		Title = "Theme", Description = "Changes the interface theme.", Values = Lib.Themes, Default = Settings.Theme,
		Callback = function(Value) Lib:SetTheme(Value); Settings.Theme = Value; InterfaceManager:SaveSettings() end,
	})
	InterfaceTheme:SetValue(Settings.Theme)

	if Lib.UseAcrylic then
		section:AddToggle("AcrylicToggle", {
			Title = "Acrylic", Description = "The blurred background requires graphic quality 8+",
			Default = Settings.Acrylic,
			Callback = function(Value) Lib:ToggleAcrylic(Value); Settings.Acrylic = Value; InterfaceManager:SaveSettings() end,
		})
	end

	section:AddToggle("TransparentToggle", {
		Title = "Transparency", Description = "Makes the interface transparent.", Default = Settings.Transparency,
		Callback = function(Value) Lib:ToggleTransparency(Value); Settings.Transparency = Value; InterfaceManager:SaveSettings() end,
	})

	local MenuKeybind = section:AddKeybind("MenuKeybind", { Title = "Minimize Bind", Default = Settings.MenuKeybind })
	MenuKeybind:OnChanged(function() Settings.MenuKeybind = MenuKeybind.Value; InterfaceManager:SaveSettings() end)
	Lib.MinimizeKeybind = MenuKeybind
end

-- ================================================
-- EXPORTS
-- ================================================

Library.SaveManager = SaveManager
Library.InterfaceManager = InterfaceManager

return Library
