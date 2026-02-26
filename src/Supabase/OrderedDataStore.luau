--!strict

local Constants = require("./Constants")
local DataStore = require("./DataStore")
local DataStorePages = require("./DataStorePages")
local Validation = require("./Validation")

type InternalService = any
type SortedEntry = {
	key: string,
	value: any?,
}

local OrderedDataStore = setmetatable({}, DataStore)
OrderedDataStore.__index = OrderedDataStore

type raw_schema = {
	_service: InternalService,
	_storeType: "ordered",
	_name: string,
	_scope: string,
}

type schema = typeof(setmetatable({} :: raw_schema, OrderedDataStore))

function OrderedDataStore.new(service: InternalService, name: string, scope: string): schema
	local base = DataStore.new(service, "ordered", name, scope)
	return setmetatable(base :: any, OrderedDataStore) :: schema
end

function OrderedDataStore:SetAsync(key: string, value: number, _userIds: { number }?, _options: any?): number
	Validation.assertFiniteNumber(value, "value")
	local resolvedKey = Validation.assertKey(key)

	local nextValue = self:_updateWithTransform(resolvedKey, function()
		return value
	end, true)

	return nextValue :: number
end

function OrderedDataStore:GetSortedAsync(ascending: boolean?, pageSize: number?, minValue: number?, maxValue: number?)
	if minValue ~= nil then
		Validation.assertFiniteNumber(minValue, "minValue")
	end
	if maxValue ~= nil then
		Validation.assertFiniteNumber(maxValue, "maxValue")
	end
	if minValue ~= nil and maxValue ~= nil and minValue > maxValue then
		error("minValue cannot be greater than maxValue", 2)
	end

	local isAscending = if ascending == nil then true else ascending
	if type(isAscending) ~= "boolean" then
		error("ascending must be a boolean", 2)
	end

	local resolvedPageSize = Validation.normalizePageSize(pageSize, Constants.DEFAULT_PAGE_SIZE)
	local orderDirection = if isAscending then "asc" else "desc"

	local baseFilter = string.format(
		"store_name=eq.%s&scope=eq.%s&store_type=eq.ordered",
		self._service:_urlEncode(self._name),
		self._service:_urlEncode(self._scope)
	)

	local function fetchPage(offset: number): ({ SortedEntry }, number, boolean)
		local queryParts = {
			baseFilter,
			"select=key,value,sort_value",
			string.format("order=sort_value.%s,key.asc", orderDirection),
			string.format("limit=%d", resolvedPageSize),
			string.format("offset=%d", offset),
		}

		if minValue ~= nil and maxValue ~= nil then
			table.insert(
				queryParts,
				string.format(
					"and=(sort_value.gte.%s,sort_value.lte.%s)",
					self._service:_urlEncode(minValue),
					self._service:_urlEncode(maxValue)
				)
			)
		elseif minValue ~= nil then
			table.insert(queryParts, "sort_value=gte." .. self._service:_urlEncode(minValue))
		elseif maxValue ~= nil then
			table.insert(queryParts, "sort_value=lte." .. self._service:_urlEncode(maxValue))
		end

		local rows = self._service:_request("GET", self._service._tableName, table.concat(queryParts, "&"), nil, nil)
		local entries: { SortedEntry } = {}

		if type(rows) == "table" then
			for _, row in ipairs(rows) do
				table.insert(entries, {
					key = row.key,
					value = row.value,
				})
			end
		end

		local isFinished = #entries < resolvedPageSize
		local nextOffset = offset + #entries
		return entries, nextOffset, isFinished
	end

	return DataStorePages.new(fetchPage)
end

return OrderedDataStore
