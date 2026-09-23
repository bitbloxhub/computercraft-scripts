-- Anvil crusher loop for Carpet Extra's renewableSand mechanic.
-- Place a chest two blocks behind the turtle's cobblestone position.
-- The turtle returns to its cobblestone position after every dump.
local COBBLESTONE = "minecraft:cobblestone"
local ANVILS = {
	["minecraft:anvil"] = true,
	["easyanvils:minecraft/anvil"] = true,
}
local SAND = "minecraft:sand"
local CHECK_DELAY = 1
local MAX_EMPTY_SLOTS = 1
local DUMP_BACK_STEPS = 2

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
		if item and not ANVILS[item.name] then
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

-- Recover after restart based on anvil in front or sand below.
local function resumeFromSurroundings()
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

	while not turtle.placeUp() do
		os.sleep(CHECK_DELAY)
	end

	while not turtle.back() do
		os.sleep(CHECK_DELAY)
	end

	waitForAnvil()
	mineAnvilAndSand()
	dumpIfNeeded()
end
