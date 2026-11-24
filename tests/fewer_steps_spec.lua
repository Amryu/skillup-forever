-- Run from the repository root: luajit tests/fewer_steps_spec.lua
-- The "Fewer route steps" setting (snapshot.fewerSteps): a route may cost a share more than the cheapest one
-- when that hands a step to a neighbouring recipe. Off, the route is the cheapest one, step for step.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local ns = {}
assert(loadfile("Core/Model.lua"))("SkillUpForever", ns)
local Model = ns.Model

---@param route SkillUpRoute
---@return string
local function Steps(route)
	local steps = {}
	for index, segment in ipairs(route.segments) do
		steps[index] = string.format("%d:%d-%d", segment.recipeID, segment.fromSkill, segment.toSkill)
	end
	return table.concat(steps, " ")
end

-- Recipe 1 is orange the whole way; recipe 2 is learned at 10 and `second` copper a craft.
---@param share number?
---@param second number
---@param more table?
---@return SkillUpSnapshot
local function Snapshot(share, second, more)
	local snapshot = {
		skill = 1,
		target = 30,
		fewerSteps = share,
		recipes = {
			{ recipeID = 1, thresholds = { 1, 40, 50, 60 }, netCost = 1000, reagentCost = 1000, skillUps = 1 },
			{ recipeID = 2, thresholds = { 10, 40, 50, 60 }, netCost = second, reagentCost = second, skillUps = 1 },
		},
	}
	for key, value in pairs(more or {}) do
		snapshot.recipes[2][key] = value
	end
	return snapshot
end

equal(Steps(Model.PlanRoute(Snapshot(nil, 990))), "1:1-10 2:10-30", "off, a recipe a little cheaper takes its points")
equal(Steps(Model.PlanRoute(Snapshot(0, 990))), "1:1-10 2:10-30", "zero is off")
local simple = Model.PlanRoute(Snapshot(0.02, 990))
equal(Steps(simple), "1:1-30", "a small allowance hands the step to the recipe before it")
local cheapest = Model.PlanRoute(Snapshot(0, 990))
assert(simple.expectedCost > cheapest.expectedCost, "the simpler route costs more")
assert(simple.expectedCost <= cheapest.expectedCost * 1.02, "but within the allowance")
equal(Steps(Model.PlanRoute(Snapshot(0.02, 500))), "1:1-10 2:10-30", "a step worth more than the allowance stays")
equal(Steps(Model.PlanRoute(Snapshot(0.6, 500))), "1:1-30", "until the allowance covers it")
equal(
	Steps(Model.PlanRoute(Snapshot(0.02, 990, { preference = 1 }))),
	"1:1-10 2:10-30",
	"a pinned recipe keeps its step"
)
-- Recipe 2 sells above its reagents: the planner does not chase the profit, but handing its step over would
-- give the profit up, so the allowance is measured against the route's money too.
local profitable = { netCost = -5000, reagentCost = 990 }
equal(Steps(Model.PlanRoute(Snapshot(0.02, 990, profitable))), "1:1-10 2:10-30", "a profit is not given up as free")

-- A step is only handed to a recipe that gains skill over all of it: recipe 2 is not learned below 10, so
-- whatever the allowance, the first step is never handed to it.
local wide = Model.PlanRoute(Snapshot(10, 990, { preference = 1 }))
equal(Steps(wide), "1:1-10 2:10-30", "a recipe never takes a step below the skill it is learned at")

-- A trained recipe the simpler route no longer uses is not paid for.
local trained = Snapshot(0.02, 990)
local service = table.remove(trained.recipes, 2)
service.fee = 5
local withTraining = Model.PlanWithTraining(trained, { service })
equal(Steps(withTraining), "1:1-30", "training a recipe for a step the allowance hands over is skipped")
equal(withTraining.trainingCost, 0, "and its fee is not charged")

Client.report("fewer_steps_spec")
