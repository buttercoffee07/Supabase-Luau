# Supabase Module Docs

This module provides a Supabase-backed API shaped like Roblox `DataStoreService`.

Module location in this project:
- `ServerScriptService.Supabase`

## Security Warning

- Never commit or ship `service_role` keys.
- Keep secrets in server-only scripts or secure deployment variables.
- Do not place Supabase keys in client scripts, `ReplicatedStorage`, or public repositories.
- If a key is exposed, rotate it immediately in Supabase dashboard.

## Quick Start

```luau
local ServerScriptService = game:GetService("ServerScriptService")
local Supabase = require(ServerScriptService.Supabase)

local client = Supabase.new(
	"https://YOUR_PROJECT_REF.supabase.co",
	"YOUR_SERVICE_ROLE_OR_ANON_KEY"
)

local store = client:GetDataStore("PlayerData")
store:SetAsync("user_123", { coins = 100, level = 5 })
print(store:GetAsync("user_123"))
```

## Prerequisites

1. Enable `Http Requests` in Roblox Studio game settings.
2. Create the backing table in Supabase SQL editor.
3. Use a server script for secrets.

## Schema Setup

Option A (recommended): run this helper once and execute its output SQL:

```luau
print(Supabase.GetRequiredTableSQL())
```

Option B: run SQL manually:

```sql
create table if not exists public.roblox_datastore_entries (
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
```

If PostgREST still reports missing table, refresh schema cache:

```sql
select pg_notify('pgrst', 'reload schema');
```

## Constructor

```luau
local client = Supabase.new(projectUrl, authToken, options?)
```

Arguments:
- `projectUrl: string`  
  Example: `https://zltwwewnhefrdyczsrbw.supabase.co`
- `authToken: string`  
  Supabase API key (`service_role` preferred on server).
- `options: table?`
  - `tableName: string?` default `roblox_datastore_entries`
  - `onUpdatePollInterval: number?` default `5`
  - `updateRetries: number?` default `6`
  - `globalDataStoreName: string?` default `__global__`

## Service API

### `Supabase.GetRequiredTableSQL(tableName?) -> string`
Returns SQL for the required table definition.

### `client:GetDataStore(name, scope?) -> DataStore`
Gets a standard store.

### `client:GetGlobalDataStore() -> DataStore`
Gets the configured global store.

### `client:GetOrderedDataStore(name, scope?) -> OrderedDataStore`
Gets an ordered store.

### `client:ListDataStoresAsync(prefix?, pageSize?, cursor?) -> DataStorePages`
Lists available stores in pages.

### `client:GetRequestBudgetForRequestType(...) -> number`
Compatibility stub. Returns `math.huge`.

## DataStore API

### `store:GetAsync(key) -> any?`
Gets current value for a key.

### `store:SetAsync(key, value, userIds?, options?) -> any?`
Sets value for a key.

### `store:UpdateAsync(key, transformFn) -> any?`
Atomic read-modify-write with optimistic concurrency.

### `store:IncrementAsync(key, delta?) -> number`
Increments numeric value. Defaults to `+1`.

### `store:RemoveAsync(key) -> any?`
Deletes key and returns previous value if present.

### `store:ListKeysAsync(prefix?, pageSize?, cursor?) -> DataStorePages`
Lists keys in pages.

### `store:OnUpdate(key, callback) -> { Disconnect: () -> () }`
Polling-based subscription. Calls callback when version changes.

### Version methods (currently not implemented)
- `GetVersionAsync`
- `GetVersionAtTimeAsync`
- `GetVersionsAsync`
- `RemoveVersionAsync`

These currently throw an explicit error because version-history storage is not implemented.

## OrderedDataStore API

### `orderedStore:SetAsync(key, value, userIds?, options?) -> number`
Sets numeric value only.

### `orderedStore:GetSortedAsync(ascending?, pageSize?, minValue?, maxValue?) -> DataStorePages`
Returns pages of sorted entries:

```luau
local pages = orderedStore:GetSortedAsync(false, 20)
local page = pages:GetCurrentPage()
for _, item in ipairs(page) do
	print(item.key, item.value)
end
```

Each entry contains:
- `key: string`
- `value: any?`

## DataStorePages API

### `pages:GetCurrentPage() -> {T}`
Returns current page items.

### `pages:AdvanceToNextPageAsync()`
Loads next page.

### `pages.IsFinished: boolean`
True when there are no more pages.

## Key Notes

- The module uses Supabase REST (`/rest/v1`), not direct Postgres sockets.
- `postgresql://...` URIs are not used directly by this module.
- Keep `service_role` keys server-side only.
- `anon` key is not your database password.

## Troubleshooting

### `PGRST205 ... Could not find table ... in the schema cache`
Create the table and reload PostgREST schema cache (see schema section above).

### `Supabase HTTP error ... 401/403`
Wrong key, insufficient role, or RLS policy issues.

### `Supabase HTTP error ... 404`
Wrong table name or project URL.

### `Cannot increment a non-number value`
`IncrementAsync` can only operate on numeric values.
