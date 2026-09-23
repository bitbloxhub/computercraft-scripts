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

local function refuelFromLava()
	if not lava_source_converision then
		return
	end

	local bucketSlot = findBucket()
	if not bucketSlot then
		error("Lava refuelling enabled, but no bucket was found")
	end

	while fuelLevel() ~= "unlimited" and fuelLevel() < turtle.getFuelLimit() do
		while not turtle.forward() do
			os.sleep(CHECK_DELAY)
		end

		turtle.select(bucketSlot)
		while not turtle.placeDown() do
			os.sleep(CHECK_DELAY)
		end
		turtle.select(bucketSlot)
		if not turtle.refuel(1) then
			error("Collected lava, but turtle could not refuel")
		end

		while not turtle.back() do
			os.sleep(CHECK_DELAY)
		end
	end
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
	while not turtle.dig() do
		os.sleep(CHECK_DELAY)
	end
	while not turtle.forward() do
		os.sleep(CHECK_DELAY)
	end
	while not turtle.digDown() do
		os.sleep(CHECK_DELAY)
	end
end

-- Keep one free slot; dump every non-anvil item when inventory is nearly full.
local function dumpIfNeeded()
	if emptySlotCount() > MAX_EMPTY_SLOTS then
		return
	end

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

-- Recover after restart from anvil above, anvil in front, or sand below.
local function resumeFromSurroundings()
	local foundUp, blockUp = turtle.inspectUp()
	if foundUp and ANVILS[blockUp.name] then
		ensureFuel()
		while not turtle.back() do
			os.sleep(CHECK_DELAY)
		end
		waitForAnvil()
		mineAnvilAndSand()
	else
		local found, block = turtle.inspect()
		if found and ANVILS[block.name] then
			mineAnvilAndSand()
		else
			local foundDown, blockDown = turtle.inspectDown()
			if foundDown and blockDown.name == SAND then
				while not turtle.digDown() do
					os.sleep(CHECK_DELAY)
				end
			end
		end
	end

	dumpIfNeeded()
end


if not equipPickaxe() then
	error("Put an equippable pickaxe in the turtle's inventory")
end

-- Main loop: recover, wait for cobblestone, place anvil, and repeat.
while true do
	resumeFromSurroundings()
	waitForBlock(turtle.inspectDown, COBBLESTONE)

	if not selectAnvil() then
		error("Turtle ran out of anvils")
	end

	ensureFuel()
	while not turtle.placeUp() do
		os.sleep(CHECK_DELAY)
	end

	ensureFuel()
	while not turtle.back() do
		os.sleep(CHECK_DELAY)
	end

	waitForAnvil()
	mineAnvilAndSand()
	dumpIfNeeded()
end
