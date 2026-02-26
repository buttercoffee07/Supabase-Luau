--!strict

local Validation = require("./Validation")

type FetchPage<T> = (offset: number) -> ({ T }, number, boolean)

local DataStorePages = {}
DataStorePages.__index = DataStorePages

type raw_schema = {
	_fetchPage: FetchPage<any>,
	_nextOffset: number,
	_currentPage: { any },
	IsFinished: boolean,
}

type schema = typeof(setmetatable({} :: raw_schema, DataStorePages))

function DataStorePages.new<T>(fetchPage: FetchPage<T>, startOffset: number?): schema
	local initialOffset = startOffset or 0
	local firstPage, nextOffset, isFinished = fetchPage(initialOffset)

	local self: schema = setmetatable({
		_fetchPage = fetchPage,
		_nextOffset = nextOffset,
		_currentPage = firstPage,
		IsFinished = isFinished,
	}, DataStorePages)

	return self
end

function DataStorePages:GetCurrentPage()
	return Validation.cloneArray(self._currentPage)
end

function DataStorePages:AdvanceToNextPageAsync()
	if self.IsFinished then
		return
	end

	local nextPage, nextOffset, isFinished = self._fetchPage(self._nextOffset)
	self._currentPage = nextPage
	self._nextOffset = nextOffset
	self.IsFinished = isFinished
end

return DataStorePages
