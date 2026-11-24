-- Run from the repository root: luajit tests/row_text_width_spec.lua
-- A recipe row's value text is capped so a wide value truncates instead of drawing over the recipe name (#979).
local function noop() end

local rowCallback
local box = {}
function box.RegisterCallback(_) end
function box.GetDataProvider()
	return nil
end
function box.SetDataProvider(_) end
function box.ForEachFrame(_) end

local recipeList = { ScrollBox = box, width = 304, visible = true }
function recipeList:GetWidth()
	return self.width
end
function recipeList:IsVisible()
	return self.visible
end
function recipeList.CreateFontString()
	return { Hide = noop }
end

local frame = { CraftingPage = { RecipeList = recipeList }, width = 673 }
function frame:GetWidth()
	return self.width
end
function frame:SetWidth(width)
	self.width = width
end

local ns = {
	L = {},
	db = { showRowText = true },
	Readable = function(value)
		return value
	end,
	GamepadUI = function()
		return false
	end,
	WhenEvent = noop,
	WhenStale = noop,
	Describe = function()
		return { chance = 1, perSkillUp = 8 }
	end,
	FormatRow = function()
		return "100% (+3) · 1g 20s 30c · 8 per skill-up"
	end,
	RowColor = function()
		return { GetRGB = noop }
	end,
	SkillContext = function()
		return {}
	end,
	ShowRecipeTooltip = noop,
	AttachRoute = noop,
	AttachGear = noop,
	AttachAuctionSearch = noop,
	AttachDetailsBar = noop,
	AttachRecipePreview = function()
		return noop
	end,
	Print = function(message)
		error(message)
	end,
	SetSortMode = function()
		error("unexpected sort failure")
	end,
}

local env = setmetatable({
	ProfessionsFrame = frame,
	Professions = {
		GetHighestLearnedRecipe = function(info)
			return info
		end,
	},
	C_TradeSkillUI = {
		GetCraftableCount = function()
			return 0
		end,
	},
	ScrollUtil = {
		AddInitializedFrameCallback = function(_, callback)
			rowCallback = callback
		end,
		AddReleasedFrameCallback = noop,
	},
	EventRegistry = { RegisterCallback = noop },
	Menu = { ModifyMenu = noop },
	hooksecurefunc = function()
		error("native recipe methods must stay unhooked")
	end,
}, { __index = _G })

setfenv(assert(loadfile("UI/RecipeList.lua")), env)("SkillUpForever", ns)
ns.AttachRecipeList()
assert(rowCallback, "the row callback must be registered")

-- One recipe row, with a value FontString whose natural (drawn) width is what the spec sets.
local function Row(valueWidth)
	local row = { valueWidth = valueWidth }
	function row.GetWidth()
		return 304
	end
	row.Label = { width = 100 }
	function row.Label:GetWidth()
		return self.width
	end
	function row.Label:SetWidth(width)
		self.width = width
	end
	row.Count = {
		IsShown = function()
			return false
		end,
		GetStringWidth = function()
			return 0
		end,
		Hide = noop,
	}
	row.LockedIcon = {
		IsShown = function()
			return false
		end,
		GetWidth = function()
			return 0
		end,
	}
	row.SkillUps = {
		GetWidth = function()
			return 0
		end,
	}
	function row:CreateFontString()
		local text = { naturalWidth = self.valueWidth, width = nil }
		function text.ClearAllPoints() end
		function text.SetPoint() end
		function text.SetJustifyH() end
		function text.SetText() end
		function text.SetTextColor() end
		function text.Show() end
		-- The client's GetStringWidth is bounded by the width the string carries; GetUnboundedStringWidth is
		-- the one that answers the string's own width (#979).
		function text.GetStringWidth(font)
			if font.width and font.width > 0 then
				return math.min(font.naturalWidth, font.width)
			end
			return font.naturalWidth
		end
		function text.GetUnboundedStringWidth(font)
			return font.naturalWidth
		end
		function text.SetWidth(font, width)
			font.width = width
		end
		row.text = text
		return text
	end
	return row
end

local data = {
	GetData = function()
		return { recipeInfo = { recipeID = 1, name = "Elixir of a Very Long Name", learned = true } }
	end,
}

local function decorate(valueWidth)
	local row = Row(valueWidth)
	rowCallback(box, row, data)
	return row
end

-- 1. A wide value text is capped to leave the label its 40: 304 - 14 - 40 = 250.
local wide = decorate(400)
assert(wide.Label.width >= 40, "the wide value text must leave the label at least 40")
assert(wide.text.width ~= nil, "the wide value text must be given a width")
assert(wide.text.width <= 304 - 14 - 40, "the wide value text is capped at the row's remaining space")

-- 2. A narrow value text keeps auto width: SetWidth(0) is the client's natural-width restore.
local narrow = decorate(100)
assert(narrow.text.width == 0, "a short value text keeps its natural width, got " .. tostring(narrow.text.width))

-- 3. The label is never clamped below 40, however wide the value text is.
local huge = decorate(4000)
assert(huge.Label.width == 40, "the label keeps its 40 floor, got " .. tostring(huge.Label.width))
assert(huge.text.width <= 304 - 14 - 40, "the widest value text still leaves the label its 40")

-- 4. A recycled row decorated again with the same wide value keeps its cap: the bounded GetStringWidth must not
-- read the truncated value as short and hand its width back.
local recycled = Row(400)
rowCallback(box, recycled, data)
local firstWidth = recycled.text.width
rowCallback(box, recycled, data)
assert(firstWidth and firstWidth <= 304 - 14 - 40, "the recycled row's value is capped, got " .. tostring(firstWidth))
assert(recycled.text.width == firstWidth, "the cap survives a second decoration, got " .. tostring(recycled.text.width))

print("row_text_width_spec: value text capped, short values auto-width, label floor kept: ok")
