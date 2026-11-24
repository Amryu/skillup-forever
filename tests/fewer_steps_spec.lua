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

-- The allowance is kept on the cost the route shows, with the spare crafts each step carries for an unlucky run.
-- Handing 2's step to 4 here costs 1.8% more before the spares and 2.8% more with them (#1010).
---@param share number
---@return SkillUpRoute
local function Spares(share)
	return Model.PlanRoute({
		skill = 1,
		target = 70,
		fewerSteps = share,
		recipes = {
			{ recipeID = 1, thresholds = { 20, 31, 51, 73 }, netCost = 1300, reagentCost = 1300, skillUps = 1 },
			{ recipeID = 2, thresholds = { 4, 31, 35, 46 }, netCost = 3000, reagentCost = 3000, skillUps = 1 },
			{ recipeID = 3, thresholds = { 1, 19, 32, 41 }, netCost = 3600, reagentCost = 3600, skillUps = 1 },
			{ recipeID = 4, thresholds = { 1, 17, 32, 47 }, netCost = 3100, reagentCost = 3100, skillUps = 1 },
		},
	})
end
local spareCheapest, spareTwo, spareThree = Spares(0), Spares(0.02), Spares(0.03)
equal(Steps(spareCheapest), "4:1-4 2:4-20 1:20-70", "the cheapest route takes three steps")
equal(Steps(spareTwo), Steps(spareCheapest), "2% does not cover the hand-over once the spares are counted")
equal(Steps(spareThree), "4:1-20 1:20-70", "3% does")
assert(spareThree.expectedCost <= spareCheapest.expectedCost * 1.03, "and the shown cost stays within it")

-- A sweep of seeded routes: whatever the shape, the shown cost stays within the share of the cheapest route's.
local seed = 20261124
local function Random(low, high)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return low + seed % (high - low + 1)
end
for round = 1, 300 do
	local recipes = {}
	for recipeID = 1, Random(3, 7) do
		local orange = Random(1, 40)
		local yellow = orange + Random(5, 25)
		local green = yellow + Random(3, 20)
		local cost = Random(500, 5000)
		recipes[recipeID] = {
			recipeID = recipeID,
			thresholds = { orange, yellow, green, green + Random(3, 25) },
			netCost = cost,
			reagentCost = cost,
			skillUps = 1,
		}
	end
	recipes[1].thresholds[1] = 1
	local share = Random(1, 10) / 100
	local function Sweep(fewerSteps)
		return Model.PlanRoute({ skill = 1, target = 70, fewerSteps = fewerSteps, recipes = recipes })
	end
	local cheap, fewer = Sweep(0), Sweep(share)
	equal(fewer.reachedSkill, cheap.reachedSkill, "round " .. round .. " reaches as far")
	assert(#fewer.segments <= #cheap.segments, "round " .. round .. " never adds a step")
	assert(
		fewer.expectedCost <= cheap.expectedCost * (1 + share) + 1e-6,
		string.format("round %d: %.0f over %.0f at %d%%", round, fewer.expectedCost, cheap.expectedCost, share * 100)
	)
end

Client.report("fewer_steps_spec")
