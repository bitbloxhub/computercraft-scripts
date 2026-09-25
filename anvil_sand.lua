-- Anvil crusher loop for Carpet Extra's renewableSand mechanic.
-- Layout:
-- y:   [chest]           [air]             [air]             [turtle]          [air]
-- y-1:                   [water source]    [water flowing]   [cobblestone]     [lava source]
-- Turtle returns to its cobblestone position after every dump.
local COBBLESTONE = "minecraft:cobblestone"
local ANVILS = {
	["minecraft:anvil"] = true,
	["easyanvils:minecraft/anvil"] = true,
}
local SAND = "minecraft:sand"
local CHECK_DELAY = 1
local MAX_EMPTY_SLOTS = 1
local DUMP_BACK_STEPS = 2
local lava_source_converision = true
local LOW_FUEL_LEVEL = 100
local STATE_FILE = "anvil_sand.state"
local BUCKETS = {
	["minecraft:bucket"] = true,
	["minecraft:lava_bucket"] = true,
}

local function fuelLevel()
	return turtle.getFuelLevel()
end

local function findBucket()
	for slot = 1, 16 do
		local item = turtle.getItemDetail(slot)
		if item and item.name == "minecraft:bucket" then
			return slot
		end
	end
	return nil
end

local function findLavaBucket()
	for slot = 1, 16 do
		local item = turtle.getItemDetail(slot)
		if item and item.name == "minecraft:lava_bucket" then
			return slot
		end
	end
	return nil
end

local function setState(state)
	local file = fs.open(STATE_FILE, "w")
	file.write(state)
	file.close()
end

local function getState()
	if not fs.exists(STATE_FILE) then
		return nil
	end

	local file = fs.open(STATE_FILE, "r")
	local state = file.readAll()
	file.close()
	return state
end

local function clearState()
	if fs.exists(STATE_FILE) then
		fs.delete(STATE_FILE)
	end
end

local function refuelFromLava()
	if not lava_source_converision then
		return
	end

	local parentState = getState() or "idle"
	while fuelLevel() ~= "unlimited" and fuelLevel() < turtle.getFuelLimit() do
		setState("refueling:" .. parentState)
		while not turtle.forward() do
			os.sleep(CHECK_DELAY)
		end

		local foundDown, blockDown = turtle.inspectDown()
		if foundDown and blockDown.name == "minecraft:lava" then
			local bucketSlot = findBucket()
			if not bucketSlot then
				error("Collected lava, but no empty bucket was found")
			end
			turtle.select(bucketSlot)
			while not turtle.placeDown() do
				os.sleep(CHECK_DELAY)
			end
		end

		local lavaBucketSlot = findLavaBucket()
		if lavaBucketSlot then
			turtle.select(lavaBucketSlot)
			if not turtle.refuel(1) then
				error("Collected lava, but turtle could not refuel")
			end
		end

		while not turtle.back() do
			os.sleep(CHECK_DELAY)
		end
		if parentState == "idle" then
			clearState()
		else
			setState(parentState)
		end
	end
end

local function resumeRefueling()
	local state = getState()
	if not state or not state:find("^refueling:") then
		return nil
	end
	local parentState = state:sub(#"refueling:" + 1)

	local foundDown, blockDown = turtle.inspectDown()
	if foundDown and blockDown.name == COBBLESTONE then
		if parentState == "idle" then
			clearState()
		else
			setState(parentState)
		end
		return parentState
	end
	if foundDown and blockDown.name == "minecraft:lava" then
		local bucketSlot = findBucket()
		if not bucketSlot then
			error("Resuming refuelling, but no empty bucket was found")
		end
		turtle.select(bucketSlot)
		while not turtle.placeDown() do
			os.sleep(CHECK_DELAY)
		end
	end

	local lavaBucketSlot = findLavaBucket()
	if lavaBucketSlot then
		turtle.select(lavaBucketSlot)
		if not turtle.refuel(1) then
			error("Resumed lava collection, but turtle could not refuel")
		end
	end

	while not turtle.back() do
		os.sleep(CHECK_DELAY)
	end
	if parentState == "idle" then
		clearState()
	else
		setState(parentState)
	end
	return parentState
end

local function ensureFuel()
	local level = fuelLevel()
	if level == "unlimited" or level >= LOW_FUEL_LEVEL then
		return
	end
	refuelFromLava()
end

-- Wait until a particular block appears on one side.
local function waitForBlock(side, name)
	while true do
		local found, block = side()
		if found and block.name == name then
			return
		end
		os.sleep(CHECK_DELAY)
	end
end

-- Falling anvils are detected in front after the turtle backs up.
local function waitForAnvil()
	while true do
		local found, block = turtle.inspect()
		if found and ANVILS[block.name] then
			return
		end
		os.sleep(CHECK_DELAY)
	end
end

-- Supports vanilla anvils and EasyAnvils' namespaced anvil item.
local function selectAnvil()
	for slot = 1, 16 do
		local item = turtle.getItemDetail(slot)
		if item and ANVILS[item.name] then
			turtle.select(slot)
			return true
		end
	end
	return false
end

-- Equip the first pickaxe accepted by either turtle upgrade slot.
local function equipPickaxe()
	local left = turtle.getEquippedLeft()
	local right = turtle.getEquippedRight()
	if (left and left.name:find("pickaxe", 1, true)) or (right and right.name:find("pickaxe", 1, true)) then
		return true
	end

	for slot = 1, 16 do
		local item = turtle.getItemDetail(slot)
		if item and item.name:find("pickaxe", 1, true) then
			turtle.select(slot)
			if turtle.equipLeft() or turtle.equipRight() then
				return true
			end
		end
	end

	return false
end

local function emptySlotCount()
	local empty = 0
	for slot = 1, 16 do
		if turtle.getItemCount(slot) == 0 then
			empty = empty + 1
		end
	end
	return empty
end

-- The chest is two blocks behind the work position, so back up twice.
local function dumpInventory()
	turtle.turnRight()
	turtle.turnRight()

	for slot = 1, 16 do
		local item = turtle.getItemDetail(slot)
		if item and not ANVILS[item.name] and not BUCKETS[item.name] then
			turtle.select(slot)
			while turtle.getItemCount(slot) > 0 do
				if turtle.drop() then
					break
				end
				os.sleep(CHECK_DELAY)
			end
		end
	end

	turtle.turnRight()
	turtle.turnRight()
end

-- Remove the fallen anvil, move into its position, then mine sand below.
local function mineAnvilAndSand()
	setState("mining_anvil")
	local found, block = turtle.inspect()
	if found and ANVILS[block.name] then
		while not turtle.dig() do
			os.sleep(CHECK_DELAY)
		end
	end

	setState("moving_to_sand")
	local foundDown, blockDown = turtle.inspectDown()
	if not foundDown or blockDown.name ~= SAND then
		while not turtle.forward() do
			os.sleep(CHECK_DELAY)
		end
	end

	setState("mining_sand")
	foundDown, blockDown = turtle.inspectDown()
	if foundDown and blockDown.name == SAND then
		while not turtle.digDown() do
			os.sleep(CHECK_DELAY)
		end
	end
end

-- Keep one free slot; dump every non-anvil item when inventory is nearly full.
local function dumpIfNeeded()
	if emptySlotCount() > MAX_EMPTY_SLOTS then
		return
	end

	setState("dumping")
	ensureFuel()
	for _ = 1, DUMP_BACK_STEPS do
		while not turtle.back() do
			os.sleep(CHECK_DELAY)
		end
	end
	dumpInventory()
	for _ = 1, DUMP_BACK_STEPS do
		while not turtle.forward() do
			os.sleep(CHECK_DELAY)
		end
	end
end

local function resumeState()
	local state = getState()
	if not state then
		return false
	end

	local refuelingParent = resumeRefueling()
	if refuelingParent then
		state = refuelingParent
	end

	if state == "placing_anvil" then
		local found, block = turtle.inspectUp()
		if not found or not ANVILS[block.name] then
			if not selectAnvil() then
				error("Turtle ran out of anvils")
			end
			ensureFuel()
			while not turtle.placeUp() do
				os.sleep(CHECK_DELAY)
			end
		end
		setState("backing_up")
		state = "backing_up"
	end

	if state == "backing_up" then
		local found, block = turtle.inspectUp()
		if found and ANVILS[block.name] then
			ensureFuel()
			while not turtle.back() do
				os.sleep(CHECK_DELAY)
			end
		end
		setState("waiting_anvil")
		state = "waiting_anvil"
	end

	if state == "waiting_anvil" then
		waitForAnvil()
		setState("mining_anvil")
		state = "mining_anvil"
	end

	if state == "mining_anvil" or state == "moving_to_sand" or state == "mining_sand" then
		mineAnvilAndSand()
		state = "dumping"
	end

	if state == "dumping" then
		dumpIfNeeded()
		clearState()
	end
	return true
end


if not equipPickaxe() then
	error("Put an equippable pickaxe in the turtle's inventory")
end

-- Main loop: recover, wait for cobblestone, place anvil, and repeat.
while true do
	resumeState()
	waitForBlock(turtle.inspectDown, COBBLESTONE)

	setState("placing_anvil")
	if not selectAnvil() then
		error("Turtle ran out of anvils")
	end
	ensureFuel()
	while not turtle.placeUp() do
		os.sleep(CHECK_DELAY)
	end

	setState("backing_up")
	ensureFuel()
	while not turtle.back() do
		os.sleep(CHECK_DELAY)
	end

	setState("waiting_anvil")
	waitForAnvil()

	mineAnvilAndSand()

	setState("dumping")
	dumpIfNeeded()
	clearState()
end
