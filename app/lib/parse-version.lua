local normalize = require('semver').normalize
return function (item)
  -- split out name and version
  local name = string.match(item, "^([^@]+)")
  if not name then
    error("Missing name in dep: " .. item)
  end
  local version = string.sub(item, #name + 2)
  if #version == 0 then
    version = nil
  else
    version = normalize(version)
  end
  return name, version
end
