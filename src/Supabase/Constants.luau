--!strict

local Constants = {
	DEFAULT_TABLE_NAME = "roblox_datastore_entries",
	DEFAULT_ON_UPDATE_POLL_INTERVAL = 5,
	DEFAULT_UPDATE_RETRIES = 6,
	DEFAULT_GLOBAL_DATASTORE_NAME = "__global__",
	DEFAULT_PAGE_SIZE = 50,
	MAX_PAGE_SIZE = 100,
	LIST_CHUNK_MULTIPLIER = 5,
	LIST_MAX_CHUNK_SIZE = 500,
	REQUIRED_TABLE_SQL_TEMPLATE = [[
create table if not exists %s (
    store_name text not null,
    scope text not null default 'global',
    store_type text not null check (store_type in ('standard', 'ordered')),
    key text not null,
    value jsonb,
    sort_value double precision,
    version bigint not null default 0,
    updated_at timestamptz not null default timezone('utc', now()),
    primary key (store_name, scope, store_type, key)
);
]],
}

return Constants
