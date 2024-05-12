-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
Game = Game or nil
Counter = Counter or 0
-- 固定目标
FixTarget = FixTarget or nil
-- 目标敌人的process id，为nil则为暂时没有目标
LockingTarget = LockingTarget or nil
Logs = Logs or {}

DirectionMap = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
  local rangeX, rangeY = 0, 0
  if math.abs(x1 - x2) > 20 then
    rangeX = 41 - math.abs(x1 - x2)
  else
    rangeX = math.abs(x1 - x2)
  end

  if math.abs(y1 - y2) > 20 then
    rangeY = 41 - math.abs(y1 - y2)
  else
    rangeY = math.abs(y1 - y2)
  end
  return rangeX <= range and rangeY <= range
end

function adjustPosition(n1, n2)
  if math.abs(n1 - n2) > 20 then
    if n1 < 20 and n2 >= 20 then
      n2 = n2 - 40
    end
    
    if n1 >= 20 and n2 < 20 then
      n1 = n1 - 40
    end
  end

  return n1, n2
end

local function getDirections(x1, y1, x2, y2, isAway)
  if isAway == nil then
    isAway = false
  end

  x1, x2 = adjustPosition(x1, x2)
  y1, y2 = adjustPosition(y1, y2)
--  print("x1: " .. x1 .. " y1:" .. y1 .. " x2: " .. x2 .. " y2: " .. y2)
  local dx, dy = x2 - x1, y2 - y1
  local dirX, dirY = "", ""
--  print("dx:" .. dx .. " dy:" .. dy)

  if isAway then
    if dx > 0 then dirX = "Left" else dirX = "Right" end
    if dy > 0 then dirY = "Up" else dirY = "Down" end
  else
    if dx > 0 then dirX = "Right" else dirX = "Left" end
    if dy > 0 then dirY = "Down" else dirY = "Up" end
  end
  
  print(dirY .. dirX)
  return dirY .. dirX
end
-- 锁定最弱的敌人
function findWeakPlayer()
  local heathValue = 100
  local energyValue = 100
  local weakPlayer = nil
  for pid, player in pairs(LatestGameState.Players) do
    if pid ~= ao.id and player.health < heathValue then
      heathValue = player.health
      energyValue = player.energy
      weakPlayer = pid
    elseif player.health == heathValue and player.energy < energyValue then
      weakPlayer = pid
    end
  end
  if FixTarget ~= nil and FixTarget ~= weakPlayer  then
    weakPlayer = FixTarget
  end
  
  print(Colors.gray .. "findWeakPlayer:" .. weakPlayer .. Colors.reset)
  LockingTarget = weakPlayer
end

-- Decides the next action based on player proximity and energy.
-- If any player is within range, it initiates an attack; otherwise, moves randomly.
function decideNextAction()

  local me = LatestGameState.Players[ao.id]
  local player = LatestGameState.Players[LockingTarget]

  if LockingTarget == nil then
    findWeakPlayer()
  end

  -- 没有目标，每次都重新找敌人
  if player == nil or player == undefined then
    findWeakPlayer()
    player = LatestGameState.Players[LockingTarget]
  end
  
  if me.energy > 10 then
    moveToTarget(me, player)
  else
    print("You energy is " .. me.energy)
    print(Colors.red .. "No enongh energy. But you are safe now. random move." .. Colors.reset)
    randomMove()
  end

  InAction = false
  print("LockingTarget:" .. LockingTarget)
end

-- 向目标移动，在攻击范围，则进行攻击
function moveToTarget(me, player)
  if inRange(me.x, me.y, player.x, player.y, 1) then
    attack()
    print(Colors.red .. "Target in range, Attacking!" .. Colors.reset)
  else
    local moveDir = getDirections(me.x, me.y, player.x, player.y, false)
    print(Colors.red .. "Approaching the enemy. Move " .. moveDir .. Colors.reset)
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = moveDir})
  end
end

-- 攻击
function attack()
  local playerEnergy = LatestGameState.Players[ao.id].energy
  if playerEnergy == nil then
    print(Colors.red .. "Attack-Failed. Unable to read energy." .. Colors.reset)
  else
    ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy)})
    print(Colors.red .. "Attacked." .. Colors.reset)
  end
end

-- 随机移动
function randomMove()
  print("Moving randomly.")
  local randomIndex = math.random(#DirectionMap)
  ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = DirectionMap[randomIndex]})
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    ao.send({Target = Game, Action = "GetGameState"})
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    print("Location: " .. "row: " .. LatestGameState.Players[ao.id].x .. ' col: ' .. LatestGameState.Players[ao.id].y)

  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
      -- print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    --print("Game state updated. Print \'LatestGameState\' for detailed view.")
    print("Location: " .. "row: " .. LatestGameState.Players[ao.id].x .. ' col: ' .. LatestGameState.Players[ao.id].y)
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    --print("Deciding next action...")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    local playerEnergy = LatestGameState.Players[ao.id].energy
    if playerEnergy == undefined then
      print(colors.red .. "Unable to read energy." .. colors.reset)
      ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
    elseif playerEnergy > 10 then
      print(colors.red .. "Player has insufficient energy." .. colors.reset)
      ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
    else
      print(colors.red .. "Returning attack..." .. colors.reset)
      ao.send({Target = Game, Action = "PlayerAttack", AttackEnergy = tostring(playerEnergy)})
    end
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

Prompt = function () return Name .. "> " end
