--!strict

export type StoreType = "standard" | "ordered"

export type UpdateTransform = (currentValue: any?) -> any?

export type SupabaseOptions = {
	tableName: string?,
	onUpdatePollInterval: number?,
	updateRetries: number?,
	globalDataStoreName: string?,
}

export type EntryRow = {
	key: string,
	value: any?,
	sort_value: number?,
	version: number?,
	updated_at: string?,
}

export type StoreListItem = {
	Name: string,
	StoreType: StoreType,
	Scope: string,
	UpdatedAt: string?,
}

export type DataStoreConnection = {
	Disconnect: () -> (),
}

export type FetchPage<T> = (offset: number) -> ({ T }, number, boolean)

local Types = {}
return Types
