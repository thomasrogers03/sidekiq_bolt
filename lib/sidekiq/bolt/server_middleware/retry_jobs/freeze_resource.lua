local namespace = table.remove(KEYS, 1)
local resource_name = table.remove(ARGV, 1)
local defrost_time = table.remove(ARGV, 1)
local resource_frozen_key = namespace .. 'resource:frozen:' .. resource_name
local frozen_resource_set_key = namespace .. 'bolt:frozen_resource'
local is_frozen = redis.call('get', resource_frozen_key)

redis.call('set', resource_frozen_key, 'true')
if not is_frozen then redis.call('zadd', frozen_resource_set_key, defrost_time, resource_name) end
