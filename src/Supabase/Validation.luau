--!strict

local Constants = require("./Constants")

local Validation = {}

function Validation.assertNonEmptyString(value: any, fieldName: string): string
	if type(value) ~= "string" or value == "" then
		error(string.format("%s must be a non-empty string", fieldName), 3)
	end
	return value
end

function Validation.assertKey(key: any): string
	return Validation.assertNonEmptyString(key, "key")
end

function Validation.assertFiniteNumber(value: any, fieldName: string): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		error(string.format("%s must be a finite number", fieldName), 3)
	end
	return value
end

function Validation.normalizePageSize(pageSize: any, defaultValue: number): number
	local resolved = defaultValue
	if pageSize ~= nil then
		Validation.assertFiniteNumber(pageSize, "pageSize")
		resolved = math.floor(pageSize)
	end

	if resolved < 1 then
		resolved = 1
	elseif resolved > Constants.MAX_PAGE_SIZE then
		resolved = Constants.MAX_PAGE_SIZE
	end

	return resolved
end

function Validation.parseCursor(cursor: string | number?): number
	if cursor == nil then
		return 0
	end

	if type(cursor) ~= "string" and type(cursor) ~= "number" then
		error("cursor must be a string or number", 3)
	end

	local numericCursor = tonumber(cursor)
	if numericCursor == nil then
		error("cursor must be numeric", 3)
	end

	return math.max(0, math.floor(numericCursor))
end

function Validation.cloneArray<T>(items: { T }): { T }
	local clone = table.create(#items)
	for index, value in ipairs(items) do
		clone[index] = value
	end
	return clone
end

return Validation
