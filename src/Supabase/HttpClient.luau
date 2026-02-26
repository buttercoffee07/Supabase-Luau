--!strict

local HttpService = game:GetService("HttpService")

local HttpClient = {}
HttpClient.__index = HttpClient

type raw_schema = {
	_projectUrl: string,
	_restUrl: string,
	_authToken: string,
}

type schema = typeof(setmetatable({} :: raw_schema, HttpClient))

local function trimTrailingSlashes(text: string): string
	return (text:gsub("/+$", ""))
end

local function normalizeRestUrl(projectUrl: string): string
	local trimmed = trimTrailingSlashes(projectUrl)
	if trimmed:match("/rest/v1$") then
		return trimmed
	end
	return trimmed .. "/rest/v1"
end

function HttpClient.new(projectUrl: string, authToken: string): schema
	local self: schema = setmetatable({
		_projectUrl = trimTrailingSlashes(projectUrl),
		_restUrl = normalizeRestUrl(projectUrl),
		_authToken = authToken,
	}, HttpClient)
	return self
end

function HttpClient:urlEncode(value: any): string
	return HttpService:UrlEncode(tostring(value))
end

function HttpClient:request(method: string, path: string, queryString: string?, body: any?, prefer: string?): any
	local url = tostring(self._restUrl) .. "/" .. path
	if queryString ~= nil and queryString ~= "" then
		url ..= "?" .. queryString
	end

	local headers: { [string]: string } = {
		apikey = self._authToken,
		Authorization = "Bearer " .. self._authToken,
	}
	if prefer ~= nil then
		headers.Prefer = prefer
	end
	if body ~= nil then
		headers["Content-Type"] = "application/json"
	end

	local requestPayload: { [string]: any } = {
		Url = url,
		Method = method,
		Headers = headers,
	}
	if body ~= nil then
		requestPayload.Body = HttpService:JSONEncode(body)
	end

	local response = HttpService:RequestAsync(requestPayload)
	local responseBody = response.Body or ""

	local parsedBody: any = responseBody
	if responseBody ~= "" then
		local decodeOk, decoded = pcall(function()
			return HttpService:JSONDecode(responseBody)
		end)
		if decodeOk then
			parsedBody = decoded
		end
	end

	if not response.Success then
		error(
			string.format(
				"Supabase HTTP error (%s %s): %d %s",
				method,
				url,
				response.StatusCode,
				tostring(responseBody)
			),
			3
		)
	end

	return parsedBody
end

return HttpClient
