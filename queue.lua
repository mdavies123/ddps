-- the donage-beerware license (version 69):
--
-- donage-stormrage(us) wrote this code 
-- as long as you retain this notice, you can do whatever you want with this code
-- if we meet someday, and you think this stuff is worth it, you can buy me a beer in return

local first     = -1
local last      = -1
local damage    = false
local time      = true
local pool      = {}
local pool_size = #pool

ddps_queue = {}

function ddps_queue.new(size)
  pool_size = size
  for i = pool_size,1,-1 do
    pool[i] = { [damage] = 0.0, [time] = 0.0 }
  end
  first = 1
  last = 0
end

function ddps_queue.first()
  local s = pool[first]
  return s[damage], s[time]
end

function ddps_queue.pop()
  if first == pool_size then 
    first = 1
  else
    first = first + 1
  end
  local s = pool[first]
  return s[damage], s[time]
end

function ddps_queue.push(d, t)
  if last == pool_size then
    last = 1
  else
    last = last + 1
  end
  local s = pool[last]
  s[damage] = d
  s[time] = t
end

function ddps_queue.clear()
  first = 1
  last = 0
  local s = pool[first]
  s[damage] = 0.0
  s[time] = 0.0
end
