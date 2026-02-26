--!strict

local Constants = require("./Constants")
local DataStorePages = require("./DataStorePages")
local Validation = require("./Validation")

type StoreType = "standard" | "ordered"
type UpdateTransform = (currentValue: any?) -> any?
type DataStoreConnection = {
	Disconnect: () -> (),
}

type EntryRow = {
	key: string,
	value: any?,
	sort_value: number?,
	version: number?,
	updated_at: string?,
}

type ListKeyItem = {
	KeyName: string,
}

type InternalService = any

local DataStore = {}
DataStore.__index = DataStore

type raw_schema = {
	_service: InternalService,
	_storeType: StoreType,
	_name: string,
	_scope: string,
}

type schema = typeof(setmetatable({} :: raw_schema, DataStore))

function DataStore.new(service: InternalService, storeType: StoreType, name: string, scope: string): schema
	local self: schema = setmetatable({
		_service = service,
		_storeType = storeType,
		_name = name,
		_scope = scope,
	}, DataStore)
	return self
end

function DataStore:_get(key: string): EntryRow?
	return self._service:_fetchEntry(self._name, self._scope, self._storeType, key)
end

function DataStore:_updateWithTransform(key: string, transform: UpdateTransform, setSortValue: boolean): any?
	for _ = 1, self._service._updateRetries do
		local existing = self:_get(key)
		local currentValue = if existing ~= nil then existing.value else nil
		local currentVersion = if existing ~= nil and existing.version ~= nil then tonumber(existing.version) else nil

		local nextValue = transform(currentValue)
		if nextValue == nil then
			return nil
		end

		local payload: { [string]: any } = {
			value = nextValue,
		}

		if setSortValue then
			payload.sort_value = Validation.assertFiniteNumber(nextValue, "OrderedDataStore value")
		end

		if currentVersion ~= nil then
			payload.version = currentVersion + 1
			local updated = self._service:_updateEntryIfVersionMatches(
				self._name,
				self._scope,
				self._storeType,
				key,
				currentVersion,
				payload
			)
			if updated then
				return nextValue
			end
		else
			payload.store_name = self._name
			payload.scope = self._scope
			payload.store_type = self._storeType
			payload.key = key
			payload.version = 1

			local inserted = self._service:_insertEntryIfAbsent(payload)
			if inserted then
				return nextValue
			end
		end
	end

	error(string.format("Supabase write conflict for key '%s' after retries", key), 3)
end

function DataStore:GetAsync(key: string): any?
	local resolvedKey = Validation.assertKey(key)
	local existing = self:_get(resolvedKey)
	if existing ~= nil then
		return existing.value
	end
	return nil
end

function DataStore:SetAsync(key: string, value: any, _userIds: { number }?, _options: any?): any?
	local resolvedKey = Validation.assertKey(key)
	return self:_updateWithTransform(resolvedKey, function()
		return value
	end, false)
end

function DataStore:UpdateAsync(key: string, transform: UpdateTransform): any?
	local resolvedKey = Validation.assertKey(key)
	if type(transform) ~= "function" then
		error("transform must be a function", 2)
	end
	return self:_updateWithTransform(resolvedKey, transform, self._storeType == "ordered")
end

function DataStore:IncrementAsync(key: string, delta: number?): number
	local resolvedKey = Validation.assertKey(key)
	local resolvedDelta = delta or 1
	Validation.assertFiniteNumber(resolvedDelta, "delta")

	local nextValue = self:_updateWithTransform(resolvedKey, function(currentValue)
		local baseValue = currentValue
		if baseValue == nil then
			baseValue = 0
		end
		if type(baseValue) ~= "number" then
			error("Cannot increment a non-number value", 4)
		end
		return baseValue + resolvedDelta
	end, self._storeType == "ordered")

	return nextValue :: number
end

function DataStore:RemoveAsync(key: string): any?
	local resolvedKey = Validation.assertKey(key)
	return self._service:_deleteEntry(self._name, self._scope, self._storeType, resolvedKey)
end

function DataStore:ListKeysAsync(prefix: string?, pageSize: number?, cursor: string | number?)
	local resolvedPrefix = prefix or ""
	if type(resolvedPrefix) ~= "string" then
		error("prefix must be a string", 2)
	end

	local resolvedPageSize = Validation.normalizePageSize(pageSize, Constants.DEFAULT_PAGE_SIZE)
	local startOffset = Validation.parseCursor(cursor)

	local storeFilter = string.format(
		"store_name=eq.%s&scope=eq.%s&store_type=eq.%s",
		self._service:_urlEncode(self._name),
		self._service:_urlEncode(self._scope),
		self._service:_urlEncode(self._storeType)
	)

	local function fetchPage(offset: number): ({ ListKeyItem }, number, boolean)
		local queryParts = {
			storeFilter,
			"select=key",
			"order=key.asc",
			string.format("limit=%d", resolvedPageSize),
			string.format("offset=%d", offset),
		}

		if resolvedPrefix ~= "" then
			table.insert(queryParts, "key=like." .. self._service:_urlEncode(resolvedPrefix .. "*"))
		end

		local rows = self._service:_request("GET", self._service._tableName, table.concat(queryParts, "&"), nil, nil)
		local entries: { ListKeyItem } = {}

		if type(rows) == "table" then
			for _, row in ipairs(rows) do
				table.insert(entries, {
					KeyName = row.key,
				})
			end
		end

		local isFinished = #entries < resolvedPageSize
		local nextOffset = offset + #entries
		return entries, nextOffset, isFinished
	end

	return DataStorePages.new(fetchPage, startOffset)
end

function DataStore:GetVersionAsync(_key: string, _version: string, _options: any?)
	error("GetVersionAsync is not supported by this schema. Add a version history table to enable it.", 2)
end

function DataStore:GetVersionAtTimeAsync(_key: string, _timestamp: number, _options: any?)
	error("GetVersionAtTimeAsync is not supported by this schema. Add a version history table to enable it.", 2)
end

function DataStore:GetVersionsAsync(
	_key: string,
	_sortDirection: any?,
	_minDate: number?,
	_maxDate: number?,
	_pageSize: number?
)
	error("GetVersionsAsync is not supported by this schema. Add a version history table to enable it.", 2)
end

function DataStore:RemoveVersionAsync(_key: string, _version: string)
	error("RemoveVersionAsync is not supported by this schema. Add a version history table to enable it.", 2)
end

function DataStore:OnUpdate(key: string, callback: (newValue: any?) -> ()): DataStoreConnection
	local resolvedKey = Validation.assertKey(key)
	if type(callback) ~= "function" then
		error("callback must be a function", 2)
	end

	local connected = true
	local lastVersion: number? = nil

	task.spawn(function()
		while connected do
			local ok, result = pcall(function()
				return self:_get(resolvedKey)
			end)

			if ok then
				local row = result :: EntryRow?
				local currentVersion = if row ~= nil and row.version ~= nil then tonumber(row.version) else -1
				if lastVersion ~= nil and currentVersion ~= lastVersion then
					local callbackOk, callbackError = pcall(function()
						callback(if row ~= nil then row.value else nil)
					end)
					if not callbackOk then
						warn(
							string.format("Supabase OnUpdate callback failed for '%s': %s", resolvedKey, callbackError)
						)
					end
				end
				lastVersion = currentVersion
			else
				warn(string.format("Supabase OnUpdate poll failed for '%s': %s", resolvedKey, result))
			end

			task.wait(self._service._onUpdatePollInterval)
		end
	end)

	return {
		Disconnect = function()
			connected = false
		end,
	}
end

return DataStore
