--[[
	All talk voting.
]]

local Plugin = Shine.Plugin( ... )

Plugin.Version = "0.1.1"
Plugin.HasConfig = true
Plugin.ConfigName = "rematch.json"

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.CheckConfigRecursively = false
Plugin.DefaultState = false
Plugin.NS2Only = true

Plugin.DefaultConfig = {
	Rematch = false,
	LogLevel = "INFO",
	CountdownSeconds = 60,
	BlockedVotesMinPlayer = 12,
	AllowTesting = false,
	AutoDisableSelf = true,
		-- AutoRemoveBots = true,
		-- AutoReadyRoom = true,
	RestoreTeamHistoryAfterMapchange = true,
	TeamHistoryLifeTime = 300, -- max amount of time the history is preserved after a mapchange. Increase/decrease this value based on server loading time
}

Plugin.NotifyPrefixColour = {
	131, 0, 255
}

local TeamDisconnect = "Disconnected"

function Plugin:GetTeamName( Team, Capitals, Singular )
	if Team > 4 then
		return TeamDisconnect
	end
	return Shine:GetTeamName( Team, Capitals, Singular )
end

function Plugin:SetupDataTable()

	self:AddDTVar( "boolean", "Rematch", false )
	self:AddDTVar( "boolean", "Suspended", false )
	self:AddDTVar( "string (255)", "Team1Name", "Marines" )
	self:AddDTVar( "string (255)", "Team2Name", "Aliens" )

	self:AddNetworkMessage("RematchMatchStart", {}, "Client")
	self:AddNetworkMessage("RematchMatchComplete", {}, "Client")
	self:AddNetworkMessage("RematchEnd", {}, "Client")

	--from gui. self:AddNetworkMessage("SetTeamName", {teamname = "string (255)"}, "Server")
	--unused?? self:AddNetworkMessage("TeamName", {team = "integer", teamname = "string (255)"}, "Client")

	self:AddNetworkMessage("TeamNamesNotification", {marines = "string (255)", aliens = "string (255)"}, "Client")
	self:AddNetworkMessage("CountdownNotification", {text = "string (255)"}, "Client")
end

return Plugin
