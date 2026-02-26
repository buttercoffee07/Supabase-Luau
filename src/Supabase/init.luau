--!strict

local Constants = require("@self/Constants")
local DataStore = require("@self/DataStore")
local DataStorePages = require("@self/DataStorePages")
local HttpClient = require("@self/HttpClient")
local OrderedDataStore = require("@self/OrderedDataStore")
local Validation = require("@self/Validation")

type StoreType = "standard" | "ordered"

type SupabaseOptions = {
	tableName: string?,
	onUpdatePollInterval: number?,
	updateRetries: number?,
	globalDataStoreName: string?,
}

type EntryRow = {
	key: string,
	value: any?,
	sort_value: number?,
	version: number?,
	updated_at: string?,
}

type StoreListItem = {
	Name: string,
	StoreType: StoreType,
	Scope: string,
	UpdatedAt: string?,
}

type AnyStore = any

local Supabase = {}
Supabase.__index = Supabase

type raw_schema = {
	_http: any,
	_tableName: string,
	_onUpdatePollInterval: number,
	_updateRetries: number,
	_globalDataStoreName: string,
	_storeCache: { [string]: AnyStore },
}

type schema = typeof(setmetatable({} :: raw_schema, Supabase))

Supabase.RequiredTableSQL = Constants.REQUIRED_TABLE_SQL_TEMPLATE

function Supabase.GetRequiredTableSQL(tableName: string?): string
	local resolvedTableName = tableName or Constants.DEFAULT_TABLE_NAME
	Validation.assertNonEmptyString(resolvedTableName, "tableName")
	return string.format(Constants.REQUIRED_TABLE_SQL_TEMPLATE, resolvedTableName)
end

function Supabase.new(projectUrl: string, authToken: string, options: SupabaseOptions?): schema
	Validation.assertNonEmptyString(projectUrl, "projectUrl")
	Validation.assertNonEmptyString(authToken, "authToken")

	local opts: SupabaseOptions = options or {}
	local tableName = opts.tableName or Constants.DEFAULT_TABLE_NAME
	local onUpdatePollInterval = opts.onUpdatePollInterval or Constants.DEFAULT_ON_UPDATE_POLL_INTERVAL
	local updateRetries = opts.updateRetries or Constants.DEFAULT_UPDATE_RETRIES
	local globalDataStoreName = opts.globalDataStoreName or Constants.DEFAULT_GLOBAL_DATASTORE_NAME

	Validation.assertNonEmptyString(tableName, "options.tableName")
	Validation.assertFiniteNumber(onUpdatePollInterval, "options.onUpdatePollInterval")
	Validation.assertFiniteNumber(updateRetries, "options.updateRetries")
	Validation.assertNonEmptyString(globalDataStoreName, "options.globalDataStoreName")

	local self: schema = setmetatable({
		_http = HttpClient.new(projectUrl, authToken),
		_tableName = tableName,
		_onUpdatePollInterval = onUpdatePollInterval,
		_updateRetries = math.max(1, math.floor(updateRetries)),
		_globalDataStoreName = globalDataStoreName,
		_storeCache = {} :: { [string]: AnyStore },
	}, Supabase)

	return self
end

function Supabase:_urlEncode(value: any): string
	return self._http:urlEncode(value)
end

function Supabase:_request(method: string, path: string, queryString: string?, body: any?, prefer: string?): any
	return self._http:request(method, path, queryString, body, prefer)
end

function Supabase:_entryFilter(name: string, scope: string, storeType: StoreType, key: string): string
	return string.format(
		"store_name=eq.%s&scope=eq.%s&store_type=eq.%s&key=eq.%s",
		self:_urlEncode(name),
		self:_urlEncode(scope),
		self:_urlEncode(storeType),
		self:_urlEncode(key)
	)
end

function Supabase:_fetchEntry(name: string, scope: string, storeType: StoreType, key: string): EntryRow?
	local query = tostring(self:_entryFilter(name, scope, storeType, key))
		.. "&select=key,value,sort_value,version,updated_at"
	local result = self:_request("GET", self._tableName, query, nil, nil)

	if type(result) == "table" and #result > 0 then
		return result[1]
	end
	return nil
end

function Supabase:_updateEntryIfVersionMatches(
	name: string,
	scope: string,
	storeType: StoreType,
	key: string,
	version: number,
	payload: { [string]: any }
): boolean
	local query = tostring(self:_entryFilter(name, scope, storeType, key))
		.. "&version=eq."
		.. tostring(self:_urlEncode(version))
		.. "&select=value"

	local result = self:_request("PATCH", self._tableName, query, payload, "return=representation")
	return type(result) == "table" and #result > 0
end

function Supabase:_insertEntryIfAbsent(payload: { [string]: any }): boolean
	local result =
		self:_request("POST", self._tableName, "", payload, "resolution=ignore-duplicates,return=representation")
	return type(result) == "table" and #result > 0
end

function Supabase:_deleteEntry(name: string, scope: string, storeType: StoreType, key: string): any?
	local query = tostring(self:_entryFilter(name, scope, storeType, key)) .. "&select=value"
	local deleted = self:_request("DELETE", self._tableName, query, nil, "return=representation")
	if type(deleted) == "table" and #deleted > 0 then
		return deleted[1].value
	end
	return nil
end

function Supabase:_makeStoreCacheKey(storeType: StoreType, name: string, scope: string): string
	return string.format("%s|%s|%s", storeType, name, scope)
end

function Supabase:_getCachedStore(storeType: StoreType, name: string, scope: string): AnyStore
	local cacheKey = self:_makeStoreCacheKey(storeType, name, scope)
	local cachedStore = self._storeCache[cacheKey]
	if cachedStore ~= nil then
		return cachedStore
	end

	local store = if storeType == "ordered"
		then OrderedDataStore.new(self, name, scope)
		else DataStore.new(self, "standard", name, scope)

	self._storeCache[cacheKey] = store
	return store
end

function Supabase:GetDataStore(name: string, scope: string?)
	local resolvedName = Validation.assertNonEmptyString(name, "name")
	local resolvedScope = scope or "global"
	Validation.assertNonEmptyString(resolvedScope, "scope")
	return self:_getCachedStore("standard", resolvedName, resolvedScope)
end

function Supabase:GetGlobalDataStore()
	return self:GetDataStore(self._globalDataStoreName, "global")
end

function Supabase:GetOrderedDataStore(name: string, scope: string?)
	local resolvedName = Validation.assertNonEmptyString(name, "name")
	local resolvedScope = scope or "global"
	Validation.assertNonEmptyString(resolvedScope, "scope")
	return self:_getCachedStore("ordered", resolvedName, resolvedScope)
end

function Supabase:GetRequestBudgetForRequestType(_requestType: any): number
	return math.huge
end

function Supabase:ListDataStoresAsync(prefix: string?, pageSize: number?, cursor: string | number?)
	local resolvedPrefix = prefix or ""
	if type(resolvedPrefix) ~= "string" then
		error("prefix must be a string", 2)
	end

	local resolvedPageSize = Validation.normalizePageSize(pageSize, Constants.DEFAULT_PAGE_SIZE)
	local startOffset = Validation.parseCursor(cursor)
	local chunkSize = math.min(
		Constants.LIST_MAX_CHUNK_SIZE,
		math.max(resolvedPageSize * Constants.LIST_CHUNK_MULTIPLIER, resolvedPageSize)
	)

	local function fetchPage(offset: number): ({ StoreListItem }, number, boolean)
		local entries: { StoreListItem } = {}
		local seenStoreKeys: { [string]: boolean } = {}
		local rawOffset = offset
		local exhausted = false

		while #entries < resolvedPageSize do
			local queryParts = {
				"select=store_name,store_type,scope,updated_at",
				"order=store_name.asc,store_type.asc,scope.asc",
				string.format("limit=%d", chunkSize),
				string.format("offset=%d", rawOffset),
			}
			if resolvedPrefix ~= "" then
				table.insert(queryParts, "store_name=like." .. self:_urlEncode(resolvedPrefix .. "*"))
			end

			local rows = self:_request("GET", self._tableName, table.concat(queryParts, "&"), nil, nil)
			local rowCount = if type(rows) == "table" then #rows else 0
			if rowCount == 0 then
				exhausted = true
				break
			end

			rawOffset += rowCount

			if type(rows) == "table" then
				for _, row in ipairs(rows) do
					local uniqueKey = string.format("%s|%s|%s", row.store_name, row.store_type, row.scope)
					if not seenStoreKeys[uniqueKey] then
						local resolvedStoreType: StoreType = if row.store_type == "ordered"
							then "ordered"
							else "standard"
						seenStoreKeys[uniqueKey] = true
						table.insert(entries, {
							Name = row.store_name,
							StoreType = resolvedStoreType,
							Scope = row.scope,
							UpdatedAt = row.updated_at,
						})
						if #entries >= resolvedPageSize then
							break
						end
					end
				end
			end

			if rowCount < chunkSize then
				exhausted = true
				break
			end
		end

		return entries, rawOffset, exhausted
	end

	return DataStorePages.new(fetchPage, startOffset)
end

return Supabase
