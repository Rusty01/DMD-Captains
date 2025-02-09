--[[
	Captains Mode
]]

local Plugin = Shine.Plugin( ... )

Plugin.Version = "0.10.2"
Plugin.HasConfig = true
Plugin.ConfigName = "CaptainsMode.json"

Plugin.DefaultConfig = {
	Captains = false,
	CaptainsNight = false,
	AllowTesting = false,
	AutoRemoveBots = true,
	AutoDisableVoteRandom = true,
	AutoReadyRoom = true,
	AutoDisableSelf = false,
	AnnouncePlayerNames = true,
	AllowPlayersToViewTeams = true,
	ShowMarineAlienToCaptains = true,
	ShowMarineAlienToPlayers = true,
	CountdownSeconds = 60,
	LogLevel = "INFO",
	BlockedVotesMinPlayer = 12,
	JoinTeamBlockDelay = 5
}

Plugin.NotifyPrefixColour = {
	131, 0, 255
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.CheckConfigRecursively = false
Plugin.DefaultState = false
Plugin.NS2Only = true

local TeamDisconnect = "Disconnected"

function Plugin:GetTeamName( Team, Capitals, Singular )
	if Team > 4 then
		return TeamDisconnect
	end
	return Shine:GetTeamName( Team, Capitals, Singular )
end

function Plugin:SetupDataTable()
	-- team: 0 = unavailable for picking, 1 = team 1, 2 = team 2, 3 = available for picking
	local PlayerStatus = {
		pickid = "string (32)",
		steamid = "integer",
		name = "string (255)",
		skill = "integer",
		skilloffset = "integer",
		team = "integer",
		pick = "integer",
		isPickable = "boolean",
		isCaptain= "boolean"
	}

	self:AddDTVar( "boolean", "Captains", false )
	self:AddDTVar( "boolean", "Suspended", false )
	self:AddDTVar( "boolean", "CaptainsNight", false )
	self:AddDTVar( "boolean", "TestingCaptains", false )
	self:AddDTVar( "string (255)", "Team1Name", "Marines" )
	self:AddDTVar( "string (255)", "Team2Name", "Aliens" )
	self:AddDTVar( "integer (0 to 2)", "CaptainTurn", "0" )

	self:AddNetworkMessage("PlayerStatus", PlayerStatus, "Client")

	self:AddNetworkMessage("PickPlayer", {pickid = "string (32)"}, "Server")
	self:AddNetworkMessage("TradePlayer", {pickid = "string (32)"}, "Server")

	self:AddNetworkMessage("RequestSwapTeams", {team = 'integer (0 to 2)', settings="boolean"}, "Server")
	self:AddNetworkMessage("TeamSwapRequested", {team = 'integer (0 to 2)'}, "Client")
	self:AddNetworkMessage("SwapTeams", {team1marines = "boolean"}, "Client")

	self:AddNetworkMessage("StartCaptains", {team1marines = "boolean"}, "Client")
	self:AddNetworkMessage("EndCaptains", {}, "Client")
	self:AddNetworkMessage("CaptainsMatchStart", {}, "Client")
	self:AddNetworkMessage("CaptainsMatchComplete", {}, "Client")

	self:AddNetworkMessage("RequestEndCaptains", {}, "Server")

	self:AddNetworkMessage("SetTeamName", {team = 'integer (0 to 2)', teamname = "string (255)", settings="boolean"}, "Server")
	self:AddNetworkMessage("SetReady", {ready = "boolean", team = 'integer (0 to 2)', settings="boolean"}, "Server")
	self:AddNetworkMessage("UnsetReady", {}, "Client")
	self:AddNetworkMessage("PlayerLost", {}, "Client")
	self:AddNetworkMessage("CheckTeams", {settings="boolean"}, "Server")

	self:AddNetworkMessage("PickNotification", {text = "string (255)"}, "Client")
	self:AddNetworkMessage("TeamNamesNotification", {marines = "string (255)", aliens = "string (255)"}, "Client")
	self:AddNetworkMessage("CountdownNotification", {text = "string (255)"}, "Client")

	self:AddNetworkMessage("ShowTeamMenu", {}, "Client")
	self:AddNetworkMessage("HideMouse", {}, "Client")

	self:AddTranslatedNotify( "CAPTAINS_ANNOUNCE_NAME", {
        CaptainName = self:GetNameNetworkField()
    } )
	self:AddTranslatedNotify( "CAPTAINS_WAIT_PICKING", {
        Captain1Name = self:GetNameNetworkField(),
		Captain2Name = self:GetNameNetworkField()
    } )	
	self:AddTranslatedNotifyColour( "CAPTAINS_FIRST_PICK", {
        CaptainName = self:GetNameNetworkField()
    } )	
	self:AddTranslatedError( "JOIN_TEAMS_BLOCKED", { 
		team = self:GetNameNetworkField()
	} )
	self:AddTranslatedError( "JOIN_TEAMS_CAPTAINS_NIGHT", { 
		team = self:GetNameNetworkField()
	} )	

	local CaptainOptions = {
		ShowSettings = "boolean"
	}
	self:AddNetworkMessage( "CaptainOptions" , CaptainOptions, "Client" )
	self:AddNetworkMessage( "RequestCaptainOptions" , {}, "Server" )

end


return Plugin
