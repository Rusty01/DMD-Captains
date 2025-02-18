--[[
	Captains Mode server.
]]

local Plugin = ...

local Shine = Shine
local ChatName = "Captains Mode"


local TableSort = table.sort
local TableCopy = table.Copy
local TableConcat = table.concat
local StringFormat = string.format
local tostring = tostring


-- Block these votes when Captains Mode is running.
Plugin.BlockedEndOfMapVotes = {
	--VoteResetGame = true,
	VoteRandomizeRR = true,
	VotingForceEvenTeams = true,
	VoteChangeMap = true,
	VoteAddCommanderBots = true
}
Plugin.BlockedVoteAlways = {
	VotingForceEvenTeams = true,
	VoteChangeMap = true
}

function Plugin:NS2StartVote( VoteName, Client, Data )
	self.Logger:Debug( "Captains Mode NS2StartVote=========================== %s", VoteName)
	if self.dt.Suspended or not (self.InProgress or self.GameStarted) then return end
	--if not self:IsEndVote() and not self.CyclingMap then return end

	if self.BlockedVoteAlways[ VoteName ] then
		self.Logger:Debug( "Captains Mode NS2StartVote=========================== **BLOCKED**")
		return false, kVoteCannotStartReason.Waiting
	end

	-- don't block if under a certain player count.
	if Shine.GetHumanPlayerCount() < self.Config.BlockedVotesMinPlayer then return end

	if self.BlockedEndOfMapVotes[ VoteName ] then
		self.Logger:Debug( "Captains Mode NS2StartVote=========================== **BLOCKED**")
		return false, kVoteCannotStartReason.Waiting
	end
end

function Plugin:Notify(Message, Color)
	local ChatName = "Captains Mode"
	local R, G, B = 255, 255, 255
	if Color == "red" then
		R, G, B = 255, 0, 0
	elseif Color == "yellow" then
		R, G, B = 255, 183, 2
	elseif Color == "green" then
		R, G, B = 79, 232, 9
	end

	Shine:NotifyDualColour(nil, 131, 0, 255, ChatName .. ": ", R, G, B, Message)
end

function Plugin:TranslatedNotify(Player, Message, Color)
	local R, G, B = 255, 255, 255
	if Color == "red" then
		R, G, B = 255, 0, 0
	elseif Color == "yellow" then
		R, G, B = 255, 183, 2
	elseif Color == "green" then
		R, G, B = 79, 232, 9
	end

	Shine:TranslatedNotifyDualColour(Player, 131, 0, 255, "NOTIFY_PREFIX", R, G, B, Message, self.__Name)
end

function Plugin:NotifyCaptainsMessage( Player )

	if #self.Captains == 1 then
		self:TranslatedNotify( Player, "CAPTAINS_NEED_ONE" , "yellow")
		self:TranslatedNotify( Player, "CAPTAINS_APPOINT" )				
		local CaptainName = Shine.GetClientName( self.Captains[1] )
		self:SendTranslatedNotify( Player, "CAPTAINS_ANNOUNCE_NAME", {
			CaptainName= CaptainName
		} )
	
	elseif #self.Captains == 2 then
		self:TranslatedNotify( Player, "CAPTAINS_STARTED", "yellow" )
		local Captain1Name = Shine.GetClientName( self.Captains[1] )
		local Captain2Name = Shine.GetClientName( self.Captains[2] )
		self:SendTranslatedNotify( Player, "CAPTAINS_WAIT_PICKING", {
			Captain1Name = Captain1Name, 
			Captain2Name = Captain2Name
		} )

	else
		self:TranslatedNotify( Player, "CAPTAINS_NEED_MORE" , "yellow")
		self:TranslatedNotify( Player, "CAPTAINS_APPOINT" )				
	end

end

function Plugin:NotifyCaptainsNightMessage( Player ) 

	if not self.CaptainsNight then
		self:TranslatedNotify( Player, "CAPTAINS_NIGHT_ENDED", "yellow" )
	else
		self:TranslatedNotify( Player, "CAPTAINS_NIGHT_TEAM_BLOCK", "yellow" )
	end
end

do

	local CAPTAINS_TYPES = {
		Captains = "CAPTAINS_NOTIFY_",
		AutoDisableSelf = "CAPTAINS_AUTODISABLE_",
		CaptainsNight = "CAPTAINS_NIGHT_"
	}
	local CAPTAINS_DT = {
		Captains = true,
		CaptainsNight = true
	}

	function Plugin:NotifyState( Player )
		local Enable = self.dt.Suspended ~= true

		Shine:TranslatedNotifyDualColour( Player, Enable and 0 or 255, Enable and 255 or 0, 0,
			"CAPTAINS_TAG", 255, 255, 255, CAPTAINS_TYPES[ "Captains" ]..( Enable and "ENABLED" or "DISABLED" ),
			self.__Name )
	end

	function Plugin:NotifyFeatureState( Type, Enable, Player )
		Shine.AssertAtLevel( CAPTAINS_TYPES[ Type ], "Invalid captains mod feature: %s", 3, Type )

		Shine:TranslatedNotifyDualColour( Player, Enable and 0 or 255, Enable and 255 or 0, 0,
			"CAPTAINS_TAG", 255, 255, 255, CAPTAINS_TYPES[ Type ]..( Enable and "ENABLED" or "DISABLED" ),
			self.__Name )
	end

	function Plugin:IsFeatureEnabled( Type )
		Shine.AssertAtLevel( CAPTAINS_TYPES[ Type ], "Invalid captains mod feature: %s", 3, Type )

		return self.Config[ Type ]
	end

	function Plugin:SetFeatureEnabled( Type, Enabled, DontSave )
		Shine.AssertAtLevel( CAPTAINS_TYPES[ Type ], "Invalid captains mod feature: %s", 3, Type )

		Enabled = Enabled and true or false
		self.Config[ Type ] = Enabled
		
		if CAPTAINS_DT[ Type ] then 
			self.dt[ Type ] = Enabled 
		end

		if not DontSave then
			self:SaveConfig( true )
		end

		self.Logger:Trace( "Feature %s toggle %s", Type, ( Enabled and "ENABLED" or "DISABLED" ) )
	
		Shine.Hook.Broadcast( "OnCaptainsStateChange", Type, Enabled )
	end

end



function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )
	self.Logger:Debug( "Server Initialise" )
	-- Setup for Think()
	self.Delay = 0.5
	self.LastRun = Shared.GetTime()
	self.NextRun = self.LastRun+ self.Delay
	self.ProcessEndCaptains = false
	self.ProcessResetLastTeams = false
	self.VoteRandom_ShuffleTeams = false

	self.dt.CaptainsNight = (Plugin.Config.CaptainsNight ~= false)
	self.dt.Captains = (Plugin.Config.Captains ~= false)
	self.dt.Suspended = (self.dt.Captains ~= true)
	self.ProcessStartCaptainsNight = (self.dt.CaptainsNight == true and self.dt.Captains ~= true)

	if Plugin.Config.ShowMarineAlienToCaptains then
		self.DefaultTeamNames = {"Marines", "Aliens"}
	else
		self.DefaultTeamNames = {"Team1", "Team2"}
	end

	self:ResetState()
	self:CreateCommands()

	self:TestingCaptainsInitialise()

	-- we won't reset these values between games.
	self.LastTeamNames = TableCopy( self.DefaultTeamNames )

	return true
end

function Plugin:ResetState()

	self.Logger:Debug( "Server ResetState" )
	self:DestroyAllTimers()
	self.InProgress = false
	self.Pending = false
	self.CaptainsNight = self.dt.CaptainsNight

	self.Players = {}
	self.Captains = {}

	self.Ready = {false, false}
	self.LastCount = {0,0}
	self.TeamSwap = {false, false}

	self.CaptainFirstTurn = nil
	self.CaptainTurn = nil
	self.MovingPlayers = false
	self.GameStarted = false
	self.JoinTeamBlock = false
	self.JoinTeamBlockTime = 0

	self.Team1IsMarines = true
	self.dt.Team1Name= self.DefaultTeamNames[1]
	self.dt.Team2Name= self.DefaultTeamNames[2]

	self.dt.CaptainTurn = 0

	if self.CaptainsNight and self.dt.Captains then
		self:CreateCaptainTimer()
	end

end

function Plugin:CreateCommands()

	local function Captain(Client)
		if self.dt.Suspended then 
			self:NotifyState( Client );
			return
		end

		local PlayerName = Shine.GetClientName( Client )
		local Player       = Client:GetControllingPlayer()
		local TeamNumber   = Player:GetTeamNumber()
		if TeamNumber == 3 then
			self:NotifyTranslated( Client , "SPECTATOR_TO_CAPTAIN" )
			return
		end

		-- If there is a game in progress, deny it.
		local Gamerules = GetGamerules()
		if Gamerules:GetGameStarted() then
			self:NotifyTranslated( Client , "WARN_STARTED" )
			return
		end
		-- Check if the player is already a captain.
		if self:IsCaptain(Client) then
			self:NotifyTranslated( Client , "WARN_ALREADY_CAPTAIN" )
			if self.InProgress then
			-- show the screen just in case.
				self:SendNetworkMessage(Client, "ShowTeamMenu", {}, true)
			end
			return
		end
		if #self.Captains < 2 then
			table.insert(self.Captains, Client)
			self:Notify(PlayerName .. " is now a captain.", "green")
			self.Pending = true
		else
			self:NotifyTranslated( Client , "WARN_TWO_CAPTAINS" )
			return
		end

		-- If this is the second captain, we start the pick process.
		if #self.Captains > 1 then
			self:StartCaptainsPresetup()
			self:StartCaptains()
			-- Cancel the adverts
			self:DestroyTimer("NeedOneMoreCaptain")
			return
		end

		-- If we have only one captain, notify everyone that we need one more.
		if #self.Captains == 1 then
			self:NotifyTranslated( nil , "CAPTAINS_ANNOUNCE" )
			self:NotifyTranslated( nil , "CAPTAINS_APPOINT" )
			-- name, delay, reps, func
			self:CreateCaptainTimer()
		end
	end

	local CaptainCommand = self:BindCommand("sh_cm_captain", "captain", Captain, true)
	CaptainCommand:Help("Diamond Gamers Captains mode: Make yourself a captain.")


	--[[
		The sh_cm_mutiny allows Players to drop out as captain.
	]]
	local function CaptainMutiny(Client)
		if self.dt.Suspended then 
			self:NotifyState( Client );
			return
		end		

		local PlayerName = Shine.GetClientName( Client )
		if self:IsCaptain(Client)
		or Shine:HasAccess( Client, "sh_cm_cancel" )
		then
			self:EndCaptains()
			self:Notify(StringFormat("Captains mode was cancelled by %s.", PlayerName), "red")
		else
			Shine:Notify(Client, ChatName, PlayerName, "You are not allowed to Mutiny.")
		end
	end
	self:BindCommand("sh_cm_mutiny", "cancelcaptains", CaptainMutiny
	, true):Help("Player Cancel captains mode.")


	--[[
		The sh_cm_cancel allows admins to cancel captains for the users.
	]]
	local function CancelCaptains(Client)
		if self.dt.Suspended then 
			self:NotifyState( Client );
			return
		end		

		local PlayerName = Shine.GetClientName( Client )
		self:EndCaptains()
		self:Notify(StringFormat("Captains mode was cancelled by %s.", PlayerName), "red")
	end
	self:BindCommand("sh_cm_cancel", nil, CancelCaptains
		):Help("Admin Cancel captains mode.")

	--[[
		Admins can list teams
	]]
	self:BindCommand( "sh_cm_list", nil, function (Client)
		self:ReportTeams( Client )
	end):Help( "Lists the current teams." )

	--[[
		Players can re-enter Window
	]]
	self:BindCommand( "sh_cm_teams", "showteams", function (Client)
		if self.dt.Suspended then 
			self:NotifyState( Client );
			return
		end
		if not self.InProgress then return end
		if not Plugin.Config.AllowPlayersToViewTeams then return end
		self:SendNetworkMessage(Client, "ShowTeamMenu", {}, true)
	end
	, true ):Help( "Show current Captain Teams." )


	self:BindCommand( "sh_cm_hidemouse", "hidemouse", function (Client)
		self:SendNetworkMessage(Client, "HideMouse", {}, true)
	end
	, true ):Help( "Hide the mouse if for some reason it is still showing." )

	--[[
		The sh_cm_captainsnight allows admins to Force Everyone to RR for Captains night. 
	]]
	local CaptainsNight = self:BindCommand("sh_cm_captainsnight", 'captainsnight', function (Client, Enable)
		self.Logger:Trace( "Captains Night toggle %s", Enable and "Enabled" or "Disable")
		self:OnCaptainsNightChange( Enable )
	end)
	CaptainsNight:Help("Toggle Captains Night to block team joining.")	
	CaptainsNight:AddParam{ Type = "boolean", Optional = true, Default = true, Help = "Enabled" }

	self:BindCommand("sh_cm_autodisable", nil, function (client) 
		local feature = "AutoDisableSelf"
		local NewState = not self:IsFeatureEnabled( feature)
		self:SetFeatureEnabled( feature, NewState )
		self:NotifyFeatureState( feature, NewState, client )
	end ):Help("Toggle Captains Mod Auto Self Disable")


	--[[
		List Captains Info
	]]
	self:BindCommand( "sh_cm_status", 'captainstatus', function (Client)
		self.Logger:Info( "Captains Night %s ", self.CaptainsNight )
		self.Logger:Info( "Captains Suspended %s ", self.dt.Suspended )
		self.Logger:Info( "Captains %s ", self.dt.Captains )
		self.Logger:Info( "Captains Join Team %s ", self.JoinTeamBlock and "Blocked" or "Not Blocked")

		self:NotifyFeatureState( "CaptainsNight", self.CaptainsNight, Client )
		self:NotifyFeatureState( "Captains", self.dt.Captains, Client )
		self:TranslatedNotify( Client, StringFormat("Captains Mode is %s.", self.dt.Suspended and "Suspended" or "Active"),  self.dt.Suspended and "red" or "green" )
		self:TranslatedNotify( Client, StringFormat("Active Game Join Team %s.", self.JoinTeamBlock and "Blocked" or "Not Blocked"),  self.JoinTeamBlock and "red" or "green" )

	end):Help( "Lists the current Captains status." )


	if Plugin.Config.AllowTesting then
		self:CreateTestingCommands()
	end

end

function Plugin:OnCaptainsNightChange( CaptainsNightChange )
	local lastCaptainsNight = self.CaptainsNight

	if CaptainsNightChange then
		self:SetFeatureEnabled( "CaptainsNight", CaptainsNightChange )
		if self.dt.Suspended then
			self:SetFeatureEnabled( "Captains", true )
			self:NotifyState( nil );
		end	
		self.CaptainsNight = self.dt.CaptainsNight
		local pcallSuccess, GameState = pcall(function() return GetGamerules():GetGameState() end)
		if pcallSuccess then
			self.Logger:Trace( "OnCaptainsNightChange - GameState %s - Last %s", GameState or "NoState", lastCaptainsNight and "True" or "False" )
		end
		
		if pcallSuccess and GameState ~= kGameState.Started then
			--this forces everyone to the ready room
			local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
			if Enabled then
				self.Logger:Trace( "Server ForcePlayersIntoReadyRoom" )
				MapVote:ForcePlayersIntoReadyRoom()
			else
				self.Logger:Trace( "Server ForcePlayersIntoReadyRoom fallback sh_rr @alien,@marine" )
				Shared.ConsoleCommand("sh_rr @alien,@marine")
			end
			if not self.InProgress then 
				self:CreateCaptainTimer()
			end
		elseif pcallSuccess and GameState == kGameState.Started and not self.JoinTeamBlock then
			self.Logger:Trace( "Server Captains Night Started - Game Already Started" )
			self:TranslatedNotify( nil, "CAPTAINS_NIGHT_GAMESTARTED", "yellow" )
			return
		end
	else
		self:SetFeatureEnabled( "CaptainsNight", CaptainsNightChange )		
		self.CaptainsNight = self.dt.CaptainsNight
		if not self.Pending then 
			self:DestroyTimer("NeedOneMoreCaptain")
		end
		self.JoinTeamBlock = false
	end
	self:NotifyCaptainsNightMessage()
end

function Plugin:ReportTeams( Client )

	local SortTable = {}
	local Count = 0

	for pickid, Player in pairs(self.Players) do
		Count = Count + 1
		SortTable[ Count ] = { pickid, Player }
	end

	TableSort( SortTable, function( A, B )
		if A[ 2 ].pick < B[ 2 ].pick then return true
		elseif A[ 2 ].pick > B[ 2 ].pick then return false
		end
		if A[ 1 ] < B[ 1 ] then return true end
		return false
	end )

	local Columns = {
		{
			Name = "Key",
			Getter = function( Entry )
				return StringFormat( "%s", Entry[1] )
			end
		},
		{
			Name = "ID",
			Getter = function( Entry )
				return StringFormat( "%s", Entry[2].pickid )
			end
		},
		{
			Name = "Name",
			Getter = function( Entry )
				return tostring( Entry[2].name )
			end
		},
		{
			Name = "Steam ID",
			Getter = function( Entry )
				return tostring( Entry[2].steamid )
			end
		},
		{
			Name = "Team",
			Getter = function( Entry )
				local teamNumber = Entry[2].team
				return Plugin:GetTeamName( teamNumber or 5, true )
			end
		},
		{
			Name = "Picked",
			Getter = function( Entry )
				return tostring( Entry[2].pick )
			end
		},
		{
			Name = "Skill",
			Getter = function( Entry )
				return tostring( Entry[2].skill )
			end
		}
	}
	Shine.PrintTableToConsole( Client, Columns, SortTable )

end

function Plugin:CreateCaptainTimer( )
	if self.dt.Suspended then return end
	self:CreateTimer(
		"NeedOneMoreCaptain",
		20,
		-1,
		function(Timer)
			self:NotifyCaptainsMessage()
		end
	)
end

function Plugin:IsCaptain( Client )
	self.Logger:Trace( "Server IsCaptain" )
	if #self.Captains == 0 then return false end
	local CaptainIndex = self:GetCaptainIndex( Client )
	return CaptainIndex and (CaptainIndex > 0)
end

function Plugin:GetCaptainIndex(Client)
	self.Logger:Trace( "Server GetCaptainIndex" )
	local CaptainIndex = 0
	if Client == nil then return CaptainIndex end

	for Index, CaptainClient in pairs(self.Captains) do
		if CaptainClient == Client then
			CaptainIndex = Index
			-- Return when we found it.
			self.Logger:Trace( "Server Found CaptainIndex [%s]", CaptainIndex )
			return CaptainIndex
		end
	end
	self.Logger:Trace( "Server No CaptainIndex [%s]", CaptainIndex )
	return CaptainIndex
end

function Plugin:GetPickId(Client)

	local SteamID = Client:GetUserId()
	local ClientID = Client:GetId()
	local ID
	if SteamID > 0 then
		ID = tostring(SteamID)
	else
		ID = StringFormat("BOT%s",ClientID)
	end
	return ID

end
--[[
	Processing a player change to the clients
]]
function Plugin:PlayerUpdate( Client )

	if self.dt.Suspended or not self.InProgress then return end

	local Player       = Client:GetControllingPlayer()
	local SteamID      = Client:GetUserId()
	--local ClientID     = Client:GetId()
	--local PlayerID     = Player:GetId()
	local PlayerName   = Player:GetName()
	local Skill        = Player:GetPlayerSkill()
	local SkillOffset  = Player:GetPlayerSkillOffset()
	local TeamNumber   = Player:GetTeamNumber()
	local CaptainIndex = self:GetCaptainIndex( Client ) or 0
	local pickid       = self:GetPickId(Client)

	local Data = {
			Client = Client,

			pickid = pickid,
			steamid = SteamID,
			name = PlayerName,
			skill = Skill,
			skilloffset = SkillOffset,
			team = TeamNumber,
			pick = CaptainIndex,
			isPickable = not (TeamNumber == 3 or TeamNumber > 4),
			isCaptain = not (CaptainIndex == 0 )
		}
	self.Logger:Debug( "Server Player Update (%s) %s [%s]", Data.steamid, Data.name , Data.pick )

	local oldData = self.Players[pickid]
	if (oldData ~= nil and oldData.steamid == Data.steamid) then
		-- keep the current pick, update everything else.
		Data.pick = oldData.pick
		self.Players[pickid] = Data
		self:PlayerStatus( Data )
		--oldData.Client = Data.Client
		--oldData.name = Data.name
		--oldData.team = Data.team
		--oldData.isPickable = Data.isPickable
		--self:PlayerStatus( oldData )
	else
		self.Players[pickid] = Data
		self:PlayerStatus( Data )
	end

end
--[[
	Send Player Status to clients
]]
function Plugin:PlayerStatus( PlayerStatus )
	-- PlayerStatus = self.Players[pickid]

	if self.dt.Suspended or not self.InProgress then return end

	if Plugin.Config.AllowPlayersToViewTeams then
		self:SendNetworkMessage(nil, "PlayerStatus", PlayerStatus, true)
	else
		self:SendNetworkMessage(self.Captains, "PlayerStatus", PlayerStatus, true)
	end
end

--[[
	StartCaptainsPresetup : these are things we want done to prepare the game for Captains.
]]
function Plugin:StartCaptainsPresetup()

	self.Logger:Debug( "Server Start Captains Presetup" )
	self.InProgress = true

	if Plugin.Config.AutoReadyRoom then
		--this forces everyone to the ready room
		local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
		if Enabled then
			self.Logger:Trace( "Server ForcePlayersIntoReadyRoom" )
			MapVote:ForcePlayersIntoReadyRoom()
		else
			-- fallback to to console command. 
			Shared.ConsoleCommand("sh_rr @alien,@marine")
		end
	end
	if Plugin.Config.AutoRemoveBots then
		local Enabled, DMDBotManager = Shine:IsExtensionEnabled( "dmdbotmanager" )
		if DMDBotManager and Enabled then
			-- This should bock DMD Plugin from manipulating bots
			-- force bots disabled.
			DMDBotManager:SetBotsEnabled(false)			
			-- force bot delay to 24 hours.
			DMDBotManager:ForceBotDelay(86400)
			self.Logger:Info( "DMD Bot Delay set to 86400." )
		else
			local Gamerules = GetGamerules()
			if Gamerules and Gamerules.botTeamController then 
				local BotController = Gamerules.botTeamController
				self.SavedBotControllerMaxBots = BotController.MaxBots
			end
			Shared.ConsoleCommand(StringFormat("sv_maxbots %d", 0))				
		end
		
		self.AutoRemoveBotsComplete = true
	end

end
--[[
	StartCaptains: Start by sending all the players to the clients and setting who picks first.
]]
function Plugin:StartCaptains()
	local GameIDs = Shine.GameIDs
	self.Logger:Debug( "Server Start Captains" )

	self:NotifyCaptainsMessage()

	-- Roll the dice to see who gets which team.
	if math.random(0, 1) == 1 then
		self.Team1IsMarines = true
		self.dt.Team1Name= self.DefaultTeamNames[1]
		self.dt.Team2Name= self.DefaultTeamNames[2]
	else
		self.Team1IsMarines = false
		self.dt.Team1Name= self.DefaultTeamNames[2]
		self.dt.Team2Name= self.DefaultTeamNames[1]
	end

	-- Send Player:client to  everyone
	self.Logger:Debug( "Server Start Captains : Send Players" )
	for Client, ID in GameIDs:Iterate() do
		self:PlayerUpdate( Client )
	end

	if Plugin.Config.AllowPlayersToViewTeams then
		self:SendNetworkMessage( nil , "StartCaptains", {team1marines = self.Team1IsMarines}, true)
	else
		self:SendNetworkMessage(self.Captains, "StartCaptains", {team1marines = self.Team1IsMarines}, true)
	end

	local Cap1Skill = self.Captains[1]:GetControllingPlayer():GetPlayerSkill()
	local Cap2Skill = self.Captains[2]:GetControllingPlayer():GetPlayerSkill()
	local Cap1_ID = self.Captains[1]:GetUserId()
	local Cap2_ID = self.Captains[2]:GetUserId()

	local CaptainTurnIndex
	-- Decide who picks first based on hiveskill
	if Cap1Skill > Cap2Skill then
		CaptainTurnIndex = 2
	else
		CaptainTurnIndex = 1
	end
	self.CaptainTurn = self.Captains[CaptainTurnIndex]
	self.CaptainFirstTurn = CaptainTurnIndex
	-- Everyone gets notified when the self.dt.CaptainTurn changes.
	self.dt.CaptainTurn = CaptainTurnIndex

	local CaptainName =  Shine.GetClientName( self.CaptainTurn )
	-- self:Notify(CaptainName .. " picks first.", "green")
	self:SendTranslatedNotifyColour( nil, "CAPTAINS_FIRST_PICK", {
		R = 79, G = 232, B = 9,
		CaptainName = CaptainName
	} )

end

function Plugin:ReceiveSetTeamName(Client, Data)
	if Plugin.dt.Suspended then return end
	local PlayerName = Shine.GetClientName( Client )
	local CaptainIndex = self:GetCaptainIndex(Client)
	if CaptainIndex == 0 and Data.settings == false then
		return
	elseif CaptainIndex == 0 then
		if not Shine:HasAccess( Client, "sh_cm_captainsnight" ) then
			self.Logger:Error("ReceiveSetTeamName: Unauthorized %s", PlayerName)
			return
		end
	end
	CaptainIndex = Data.team

	if CaptainIndex == 1 or CaptainIndex == 2 then
		local TeamName = Data.teamname
		self.Logger:Info( "%s changed team %s name to %s", PlayerName, CaptainIndex, TeamName )
		if CaptainIndex == 1 then
			self.dt.Team1Name = TeamName
		else
			self.dt.Team2Name = TeamName
		end
	end
end

function Plugin:SendPlayerLost()
	for Index, CaptainClient in pairs(self.Captains) do
		self:SendNetworkMessage(CaptainClient, "PlayerLost", {}, true)
	end
	self:SetCaptainTurn()
end

function Plugin:SendUnsetReady()

	for Index, CaptainClient in pairs(self.Captains) do
		if self.Ready[Index] then
			self.Ready[Index] = false
			self:SendNetworkMessage(CaptainClient, "UnsetReady", {}, true)
			if self:IsCaptainBot( Index ) then
				-- just mark bots back as ready.
				self.Ready[Index] = true
			end
		end
	end

end

function Plugin:IsCaptainBot(CaptainIndex)
	if self.TestingCaptainBots
	and CaptainIndex and (CaptainIndex == 1 or CaptainIndex == 2)
	and self.TestingCaptainBots[CaptainIndex] ~= nil  then
		return true
	end
	return false
end

function Plugin:ReceiveSetReady(Client, Data)
	if Plugin.dt.Suspended then return end
	local PlayerName = Shine.GetClientName( Client )
	local CaptainIndex = self:GetCaptainIndex(Client)
	if not CaptainIndex and Data.settings == false then 
		return
	elseif CaptainIndex == 0 then 
		if not Shine:HasAccess( Client, "sh_cm_captainsnight" ) then
			self.Logger:Error("ReceiveSetReady: Unauthorized %s", PlayerName)
			return
		end	
	end
	local Team = Data.team
	local Ready = Data.ready
	self.Logger:Debug( "Server ReceiveSetReady " )

	if Team > 0 then
		self.Ready[Team] = Data.ready
		if CaptainIndex > 0 then 
			if Ready then
				self:Notify( StringFormat("%s's team is ready.", PlayerName), "green")
			else
				self:Notify( StringFormat("%s's team is not ready.", PlayerName), "red")
			end
		else
			if Ready then
				self:Notify( StringFormat("%s set team %s as ready.", PlayerName, Team), "green")
			else
				self:Notify( StringFormat("%s set team %s as not ready.", PlayerName, Team), "red")
			end
		end
	end

	if self.Ready[1] and self.Ready[2] then
		local TeamCount, revokePick = self:ValidateTeamPlayers()
		-- Make sure teams are not more than one appart.
		if TeamCount[1] > (TeamCount[2]+1)
		or TeamCount[2] > (TeamCount[1]+1) then
			if self.LastCount[1] ~= TeamCount[1]
			or self.LastCount[2] ~= TeamCount[2] then
				self.LastCount[1] = TeamCount[1]
				self.LastCount[2] = TeamCount[2]
		  		-- Send back for Trades. PostTradeReady
			  	self:Notify("Team count imbalance detected. Try to trade players to balance teams.", "red")
				self:SendUnsetReady()
				return
			end
			-- We told them they were off, but the ready'ed up anyway.
		end
		-- We had to remove a player. Let the captains know to review picks.
		if revokePick then
			self:Notify("Unavailable players removed. Ready Up again.", "red")
			self:SendUnsetReady()
			return
		end
		self.LastCount[1] = TeamCount[1]
		self.LastCount[2] = TeamCount[2]

		self:ReportTeams( nil )

		self:StartTeams()
	end
end

function Plugin:ReceiveCheckTeams( Client, Data )
	if Plugin.dt.Suspended then return end
	local PlayerName = Shine.GetClientName( Client )
	local CaptainIndex = self:GetCaptainIndex(Client)
	if not CaptainIndex and Data.settings == false then 
		return
	elseif CaptainIndex == 0 then 
		if not Shine:HasAccess( Client, "sh_cm_captainsnight" ) then
			self.Logger:Error("ReceiveSetReady: Unauthorized %s", PlayerName)
			return
		end	
	end
	local Team = Data.team
	self.Logger:Debug( "Server ReceiveCheckTeams " )

	local TeamCount, revokePick = self:ValidateTeamPlayers()
	-- We had to remove a player. Let the captains know to review picks.
	if revokePick then
		self:Notify("Unavailable players removed.", "red")
		self:SendPlayerLost()
		return
	end

end

function Plugin:ValidateTeamPlayers()

	local revokePick = false
	local TeamCount = {0, 0}

	for pickid, Player in pairs(self.Players) do
		if Player.isPickable then
		-- Revoke Pickable if Client is no longer valid.
			Player.isPickable = Shine:IsValidClient( Player.Client )
			if not Player.isPickable then
				Player.team = 5
				Player.Client = nil
			end
		end

		if not Player.isPickable and Player.pick ~= 0 then
			-- revoke pick
			self:Notify(StringFormat("Picked player %s removed from team %s[%s].", Player.name,  Shine.GetClientName( self.Captains[Player.pick] ),Player.pick), "red")
			self.Logger:Debug( "Server ReceiveSetReady revoke pick %s", Player.name )
			Player.pick = 0
			self:PlayerStatus( Player )
			revokePick = true

		end
		if Player.isPickable and Player.pick ~= 0 then
			if Player.pick == 1 then
				TeamCount[1] = TeamCount[1] + 1
			end
			if Player.pick == 2 then
				TeamCount[2] = TeamCount[2] + 1
			end
		end
	end

	return TeamCount, revokePick

end

function Plugin:StartTeams()

	local Gamerules = GetGamerules()

	local Teams
	if self.Team1IsMarines then
		Teams = {1, 2}
	else
		Teams = {2, 1}
	end

	self.MovingPlayers = true
	if not self.VoteRandom_ShuffleTeams then
		self:OverrideShuffleTeams()
	end

	self.LastTeams = {}
	self.LastTeams[1] = {}
	self.LastTeams[2] = {}

	-- Start the game
	for pickid, Player in pairs(self.Players) do
		if Player.pick == 1 or Player.pick == 2 then
			--local client = Shine.GetClientByNS2ID(SteamID)
			local client = Player.Client
			if client == nil then
				-- added this because its required when using BOTS
				client = Shine.GetClientByName(Player.name)
			end

			if Shine:IsValidClient( client ) then
				local PlayerObj = client and client:GetControllingPlayer()
				if PlayerObj ~= nil then
					Gamerules:JoinTeam(PlayerObj, Teams[Player.pick], true, true)
				else
					Shine:NotifyError(nil,StringFormat("Player %s not found", Player.name))
				end
			end
		end
	end
	self.MovingPlayers = false

	-- Just close the GUI for now but don't reset state
	self:SendNetworkMessage(nil, "CaptainsMatchStart", {}, true)

	self:StartGame()

end

function Plugin:StartGame()
	self.Logger:Debug( "Server StartGame " )
	local Seconds = Plugin.Config.CountdownSeconds

	local function ForceRoundStart( )
		local Gamerules = GetGamerules()
		Gamerules:ResetGame()
		Gamerules:SetGameState( kGameState.Countdown )
		local Players = Shine.GetAllPlayers()
		for i = 1, #Players do
			local Player = Players[ i ]
			if Player and Player.ResetScores then
				Player:ResetScores()
			end
		end
		Gamerules.countdownTime = kCountDownLength
		Gamerules.lastCountdownPlayed = nil
	end

	self:CreateTimer(
		"GameStartCountdown",
		1,
		Seconds,
		function(Timer)
			Seconds = Seconds - 1

			if (Seconds < 6 or (Seconds % 5) == 0) then

			self:SendNetworkMessage(
				nil,
				"CountdownNotification",
				{text = StringFormat("Game will start in %s seconds", Seconds)},
				true
			)

			end
			if Seconds == 0 then
				self.Logger:Debug( "Server StartGame GameStartCountdown" )
				ForceRoundStart()
			end
		end
	)

end

--[[
	MatchComplete - for when you want to rest the state, but not end the mod.
]]
function Plugin:MatchComplete()
	self.Logger:Debug( "Server MatchComplete" )

	self:SendNetworkMessage(nil, "CaptainsMatchComplete", {}, true)
	self:ResetState()
	--self:SendNetworkMessage(self.Captains, "EndCaptains", {}, true)

end


function Plugin:EndCaptains()
	self.Logger:Debug( "Server EndCaptains" )
	self:SendNetworkMessage( nil, "EndCaptains", {}, true)
	self:ResetState()

	if Plugin.Config.AutoRemoveBots and self.AutoRemoveBotsComplete then
		self.AutoRemoveBotsComplete = nil
		local Enabled, DMDBotManager = Shine:IsExtensionEnabled( "dmdbotmanager" )
		if DMDBotManager and Enabled then
			-- Allow DMDBotManager to add the bots 
			DMDBotManager:SetBotsEnabled(true)
			DMDBotManager:ForceBotDelay(1)
		else
			local maxbots = self.SavedBotControllerMaxBots or 12
			Shared.ConsoleCommand(StringFormat("sv_maxbots %d", maxbots))
			self.SavedBotControllerMaxBots = nil
		end
	end
end

function Plugin:ReceiveRequestEndCaptains(Client, Data)
	self.Logger:Debug( "Server ReceiveRequestEndCaptains" )
	-- allow Captain or Admin to cancel.
	if self:IsCaptain(Client)
	or Shine:HasAccess( Client, "sh_cm_cancel" )
	then
		local PlayerName = Shine.GetClientName( Client )
		self:EndCaptains()
		self:Notify("Captains mode was cancelled by " .. PlayerName .. ".", "yellow")
	else
		local PlayerName = Shine.GetClientName(Client)
		self:NotifyTranslated( Client , "END_CAPTAINS_FAIL" )
	end

end

function Plugin:ReceivePickPlayer(Client, Data)
	local CaptainName = Shine.GetClientName( Client )
	self.Logger:Debug( "Server ReceivePickPlayer Client %s", CaptainName )
	-- If we are not on a Captain Turn then don't process anything.
	if self.dt.CaptainTurn == 0 then return end
	-- Check the client is a captain and it's his turn
	if not self:IsCaptain( Client ) then
		self.Logger:Debug( "Received Player pick from an invalid player. %s is not a captain", CaptainName )
		return
	elseif Client ~= self.CaptainTurn then
		self.Logger:Debug( "Received Player pick from wrong Captain. %s is not supposed to be picking.", CaptainName )
		return
	end

	-- we expect it to be this captains turn:
	currentPicker = self.Captains[self.dt.CaptainTurn]
	if currentPicker ~= Client then
		return
	end

	-- Update local players table
	local Pick = self.Players and self.Players[Data.pickid]
	if Pick and Pick.pick then
		if Pick.pick ~= 0  then
			-- Player was already picked.
			self.Logger:Debug( "Received Player pick [%s] for team %s, but they are already on team %s.", Pick.name, CaptainName, Pick.pick  )
	 		Shine:Notify(Client, ChatName, CaptainName, "Player you picked is already on the other team. Repick Please.")
			self:SetCaptainTurn()
			return
		end
		Pick.pick = self.dt.CaptainTurn
		self:PlayerStatus( Pick )
	else
		self.Logger:Debug( "Received Player pick for ID [%s] but it was not found in Player list.", Data.pickid)
		Shine:Notify(Client, ChatName, CaptainName, "Player you picked was not found in the Player list.")
		self:SetCaptainTurn()
		return
	end

	local PickMsg
	if Plugin.Config.AnnouncePlayerNames then
		PickMsg = CaptainName .. " picks " .. Pick.name .. "."
	else
		PickMsg = CaptainName .. " has picked a player."
	end
	self.Logger:Debug( "Captain %s picks %s.", CaptainName, Pick.name )
	self:Notify(PickMsg)
	self:SendNetworkMessage(nil, "PickNotification", {text = PickMsg}, true)

	self:SetCaptainTurn()

end

function Plugin:ReceiveRequestSwapTeams(Client, Data )
	if Plugin.dt.Suspended then return end
	self.Logger:Debug("Plugin:ReceiveRequestSwapTeams")
	local PlayerName = Shine.GetClientName( Client )
	local CaptainIndex = self:GetCaptainIndex(Client)
	if CaptainIndex == 0 and Data.settings == false then 
		return
	elseif CaptainIndex == 0 then
		if not self:ShowSettings( Client )  then
			self.Logger:Error("RequestSwapTeams: Unauthorized %s", PlayerName)
			return
		end
	end
	CaptainIndex = Data.team

	if CaptainIndex == 1 or CaptainIndex == 2 then
		local otherCaptain = (CaptainIndex % 2) + 1
		self.TeamSwap[CaptainIndex] = true

		if self.TeamSwap[1]== true and self.TeamSwap[2]==true then
			self:OnSwapTeams( Client )
		else
			self:SendNetworkMessage(self.Captains[otherCaptain], "TeamSwapRequested", {team=CaptainIndex}, true)
		end
	end
end

function Plugin:OnSwapTeams( Client )
	self.Logger:Debug("Plugin:OnSwapTeams")
	self.TeamSwap = {false, false}

	self.Team1IsMarines = not self.Team1IsMarines

	local defaultTeamNames = TableCopy( self.DefaultTeamNames )
	local teamNames = {}

	teamNames[1] = self.dt.Team1Name
	teamNames[2] = self.dt.Team2Name
	if self.Team1IsMarines then 
		if teamNames[1] == defaultTeamNames[2] then
			teamNames[1] = defaultTeamNames[1]	
		end
		if teamNames[2] == defaultTeamNames[1] then
			teamNames[2] = defaultTeamNames[2]	
		end
	else
		if teamNames[1] == defaultTeamNames[1] then
			teamNames[1] = defaultTeamNames[2]	
		end
		if teamNames[2] == defaultTeamNames[2] then
			teamNames[2] = defaultTeamNames[1]	
		end		
	end
	self.dt.Team1Name= teamNames[1]
	self.dt.Team2Name= teamNames[2]
	
	if Plugin.Config.AllowPlayersToViewTeams then
		self:SendNetworkMessage( nil , "SwapTeams", {team1marines = self.Team1IsMarines}, true)
	else
		self:SendNetworkMessage(self.Captains, "SwapTeams", {team1marines = self.Team1IsMarines}, true)
	end

end

function Plugin:ReceiveTradePlayer(Client, Data)
	local CaptainName = Shine.GetClientName( Client )
	self.Logger:Debug( "Server ReceiveTradePlayer Client %s", CaptainName )
	local CaptainIndex = self:GetCaptainIndex(Client)
	if not CaptainIndex or CaptainIndex == 0 then
		self.Logger:Info( "Received Player trade from an invalid player. %s is not a captain", CaptainName )
		return
	end

	local OtherCaptain = (CaptainIndex % 2) + 1
	-- Update local players table
	local Pick = self.Players and self.Players[Data.pickid]
	if Pick and Pick.isCaptain and Pick.Client and Pick.Client == Client then
		self.Logger:Debug( "Received Player trade: Player %s tried to trade themselves.", CaptainName)
		Shine:Notify(Client, ChatName, CaptainName, "You are not allowed to trade yourself.")
		return
	end

	if Pick and Pick.pick then
		if Pick.pick == CaptainIndex then
			Pick.pick = (CaptainIndex % 2) + 1
			self:SendUnsetReady()
		 	-- Send Trade
			self:PlayerStatus( Pick )
		elseif self.IsCaptainBot and self:IsCaptainBot(OtherCaptain) then
			Pick.pick =  (Pick.pick % 2) + 1
			self:SendUnsetReady()
		 	-- Send Trade
			self:PlayerStatus( Pick )

		else
			self.Logger:Debug( "Received Player trade for ID [%s] but it was not found on team %s.", Data.pickid,CaptainIndex)
			Shine:Notify(Client, ChatName, CaptainName, "Player you traded was not found on your team.")
			return
		end
	else
		self.Logger:Debug( "Received Player trade for ID [%s] but it was not found in Player list.", Data.pickid)
		Shine:Notify(Client, ChatName, CaptainName, "Player you traded was not found in the Player list.")
		return
	end
	-- Reset Last count on any trade
	self.LastCount = {0,0}

end



function Plugin:SetCaptainTurn()

	-- Turn logic
	local TeamCount = {0, 0}

	for pickid, Player in pairs(self.Players) do
		if Player.pick == 1 then
			TeamCount[1] = TeamCount[1] + 1
		end
		if Player.pick == 2 then
			TeamCount[2] = TeamCount[2] + 1
		end
	end

	local LastPicker = self.dt.CaptainTurn
	local NextPicker = (self.dt.CaptainTurn % 2 ) + 1
	-- Allow FirstPicker to pick next
	if NextPicker ~= self.CaptainFirstTurn and TeamCount[1] == TeamCount[2] then
		NextPicker = self.CaptainFirstTurn

	elseif LastPicker > 0 then
		-- Adjust turn for Team Count?
		if NextPicker == self.CaptainFirstTurn
		and TeamCount[NextPicker] > TeamCount[LastPicker] then
			-- Allow the team with less players to pick next.
			NextPicker = LastPicker
		end
	end

	self.CaptainTurn = self.Captains[NextPicker]
	self.dt.CaptainTurn = NextPicker

end
--[[
	Block players from joining Marines or Aliens while we are Picking Teams
]]
function Plugin:JoinTeam(Gamerules, Player, NewTeam, Force, ShineForce)
	if ShineForce then self.Logger:Trace( "Server JoinTeam Force"); return end
	if self.dt.Suspended then return end

	if not self.CaptainsNight and not self.InProgress 
	and NewTeam ~= 3 then 
		self.Logger:Trace( "Server JoinTeam Not InProgress [%s]", NewTeam); 
		return 
	end

	if not Player then return end
	if NewTeam == 0 then
		return
	end
	local Client = Shine.GetClientForPlayer( Player )
	-- Ignore all bot team changes.
	if Client and Client:GetIsVirtual() then return end	

	local PlayerName = Player:GetName()
	-- this is "before" the team on Player:GetTeamNumber is updated.
	if NewTeam == 3 then
		-- Don't allow captains into spec
		if self:IsCaptain(Client) then
			Shine:NotifyError(Player
				,StringFormat("Captain not allowed to join %s [%s]. You must !cancelcaptains first."
					, Plugin:GetTeamName( NewTeam )
					, NewTeam))
			return false
		end
		--Moved To Spectate
 		--Shine:NotifyError(Player,StringFormat("Attempting to join Team %s [%s].", Plugin:GetTeamName( NewTeam ), NewTeam))
		return
	end
	-- NewTeam :: Not Readyroom and Not Spectator

	local GameState = Gamerules:GetGameState()
	if GameState and GameState == kGameState.Started and not self.JoinTeamBlock then
		-- Allow people to Join if the Game has started.
		self.Logger:Trace( "Server JoinTeam Game Started [%s]", NewTeam); 
		return
	end
	-- Not Spectate, Not ReadyRoom
	self.Logger:Debug( "Player Blocked from joining team %s : %s", NewTeam, PlayerName )
	if not self.CaptainsNight or self.InProgress then 
		self:SendTranslatedError( Player, "JOIN_TEAMS_BLOCKED", {
			team= Plugin:GetTeamName( NewTeam )
		} )
	else
		self:SendTranslatedError( Player, "JOIN_TEAMS_CAPTAINS_NIGHT", {
			team= Plugin:GetTeamName( NewTeam )
		} )			
	end
	return false

end

--[[
	Process Player Room Changes
]]
function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	if ShineForce then
		self.Logger:Debug( "Server PostJoinTeam Force" )
	end

	if not self.InProgress then return end
	if not Player then return end
	local PlayerName = Player:GetName()

	local Client = Shine.GetClientForPlayer( Player )
	if Client == nil then
		return
	end

	if NewTeam == 3 then
		self.Logger:Debug( "Player in Spectator : %s", PlayerName )
		self:PlayerUpdate( Client )
		return
	elseif NewTeam == 0 then
		if OldTeam and OldTeam == 3 and NewTeam == 0 then
			self.Logger:Debug( "Player out of Spectator on team %s : %s", NewTeam, PlayerName )
			self:PlayerUpdate( Client )
			return
		end
	end

end




function Plugin:SetGameState(Gamerules, State, OldState)

	self.Logger:Debug( "Server state=========================== %s[%s] ==> %s[%s]", kGameState[OldState],OldState, kGameState[State],State)
	--self:Notify(StringFormat("Server state: %s  %s", OldState, State))
	--[[
		kGameState = enum( {
		1	'NotStarted',
		2	'WarmUp',
		3	'PreGame',
		4	'Countdown',
		5	'Started',
		6	'Team1Won',
		7	'Team2Won',
		8	'Draw'
		} )
	]]

	-- After the game has started, Verify state transition.
	if self.GameStarted
	and (State == kGameState.Team1Won or
        State == kGameState.Team2Won or
        State == kGameState.Draw)
	then
		self.Logger:Debug( "Server state: Captains match over." )
		-- Okay to turn it off.
		self.GameStarted = false
		-- remove test bots. [this worked to remove all bots]
		--Shared.ConsoleCommand(StringFormat("sv_maxbots %d", 12))
		-- Delay MatchComplete for a few seconds for the Scores screen to appear before we reset team names.
		Plugin:SimpleTimer( 5, function(Timer)
			self:MatchComplete()
		end)
		return
	end

	if State == kGameState.Started
	and not (self.InProgress or self.GameStarted) then
		self.Logger:Debug( "Server state: End captains if it started outside of the mod" )
		-- End captains if it started outside of the mod.
		-- Collect and Delay Ending for a Update cycle.
		self.ProcessEndCaptains = true
		self.ProcessResetLastTeams = true
		return
	end

	-- self.InProgress and

	if State == kGameState.Started then
		self.Logger:Trace( "Captains Mode Game Starting" )
		self:DestroyTimer("EndCaptainsGame")
		-- The Captains game is starting. Send the Team Notification.
		self.GameStarted = true
		self.JoinTeamBlock = true
		self.JoinTeamBlockTime = Shared.GetTime() + Plugin.Config.JoinTeamBlockDelay
		self:DestroyTimer("GameStartCountdown")
		self.InProgress = false

		self:NotifyTeamNames()

		return
	end


	-- we started the game, but not it has not transitioned into a "Won or Draw" state.
	-- Like when someone is trying to reset the game to change the starting location.
	-- So we will create a timer to end the mod if the game doesn't start again within 60 seconds.
	--if State == kGameState.Started then
	if self.GameStarted
	and not (State == kGameState.Started or
		State == kGameState.Team1Won or
        State == kGameState.Team2Won or
        State == kGameState.Draw)
	 then
		-- create a timer to end Captains if it doesn't restart within 60 seconds.

		if not (self:TimerExists( "EndCaptainsGame" )) then

			self:CreateTimer( "EndCaptainsGame" , 60, 1, function(Timer)
				self.Logger:Debug( "Ending Captains EndGame Timer Running Check..." )

				-- if Picking is in Progress Stop counting.
				if self.InProgress then return end
				if not self.GameStarted then return end

				self.Logger:Info( "Ending Captains mode, game did not re-start after captains started it once." )
				-- If the time still exists in 60 seconds, end Captains.
				self.ProcessEndCaptains = true
			end);

		end

	end

end

function Plugin:OnGameReset()
	self:Notify("Game Reset")
end


function Plugin:PlayerNameChange( Player, Name, OldName )
	local Client = Shine.GetClientForPlayer( Player )
	self.Logger:Trace( "Server PlayerNameChange from [%s] to [%s]", OldName, Name )
	self:PlayerUpdate( Client )
end

--[[
	Processing when a new player connects and picking is in progress.
]]
function Plugin:ClientConfirmConnect( Client )

	if self.dt.Suspended then return end
	self:SendCaptainOptions( Client )

	self:PlayerUpdate( Client )

	local IsBot = Client:GetIsVirtual()
	if IsBot then return end

	-- Send messages for Captains night and making yourself captain.
	if self.CaptainsNight then
		self:NotifyCaptainsNightMessage(Client);
	end
	if not self.InProgress then 
		self:NotifyCaptainsMessage(Client);
		return 
	end

	-- lets make sure the new player is updated.
	for pickid, Player in pairs(self.Players) do
		self:SendNetworkMessage(Client, "PlayerStatus", Player, true)
	end

	-- allow new player to see the team picks.
	if Plugin.Config.AllowPlayersToViewTeams then
		self:SendNetworkMessage(Client , "StartCaptains", {team1marines = self.Team1IsMarines}, true)
		--self:SendNetworkMessage(Client, "ShowTeamMenu", {}, true)
	end

end

function Plugin:ShowSettings( Client )
	return Shine:HasAccess( Client, "sh_cm_captainsnight" )
end

function Plugin:SendCaptainOptions( Client ) 
	local CaptainOptions = {
		ShowSettings = self:ShowSettings( Client )
		-- ShowSettings = false
	}
	self:SendNetworkMessage( Client , "CaptainOptions", CaptainOptions, true )
end

function Plugin:ReceiveRequestCaptainOptions( Client )
	self:SendCaptainOptions( Client )
end

-- Cancel captains mode if a captain quits the game
function Plugin:ClientDisconnect(Client)
	local PlayerName = Shine.GetClientName( Client )
	self.Logger:Debug( "ClientDisconnect %s.", PlayerName )

	--local IsBot = Client:GetIsVirtual()
	--if IsBot then return end

	if self.InProgress then
		local pickid = self:GetPickId(Client)

		if self:IsCaptain(Client) then
		-- something with kicking the captain is crashing the game.
		-- To fix that we will delay this processing with a timer.

			self.Logger:Debug( "Captains mode was cancelled because %s has left the game.", PlayerName )
			self.Logger:Debug( "ClientDisconnect Removing Captain %s", pickid )
			-- Throw this into a Timer, because otherwise it was causing the game to crash.
			self:SimpleTimer( 1, function()
				self.Logger:Debug( "Post ClientDisconnect Ending Captains")
				self:EndCaptains()
				self:Notify("Captains mode was cancelled because " .. PlayerName .. " has left the game.", "red")
			end )
			return
		end

		local Player = self.Players[pickid]
		if Player ~= nil then
			self.Logger:Debug( "ClientDisconnect Removing Player %s", Player.pickid )

			Player.team = 5
			Player.Client = nil
			Player.isPickable = false
			self:PlayerStatus( Player )
		end
	end
end

function Plugin:Cleanup()
	self.Logger:Info( "Disabling server plugin..." )
	self.BaseClass.Cleanup(self)
end






function Plugin:TestingCaptainsInitialise()

	self.dt.TestingCaptains = false
	self.TestingCaptainBots = nil

	--self:CreateCommands()

	return true
end

function Plugin:CreateTestingCommands()
	--[[
		TestCaptain allow for testing the Captains mod
	]]
	local function TestCaptain(Client)
		if Plugin.dt.Suspended then return end
		
		local PlayerName = Shine.GetClientName( Client )
		-- If there is a game in progress, deny it.
		local Gamerules = GetGamerules()
		if Gamerules:GetGameStarted() then
			Shine:Notify(Client, ChatName, PlayerName, "A game has already started.")
			return
		end
		if #self.Captains >= 2 then
			Shine:Notify(Client, ChatName, PlayerName, "There are already 2 captains.")
			return
		end

		self.dt.TestingCaptains = true
		self.TestingCaptainBots = {}
		self.Logger:Debug( "Captains mode TESTING by %s.", PlayerName )
		self:TestingCaptainsPresetup()
	end
	local CaptainCommand = self:BindCommand("sh_cm_captain_test", "testcaptain", TestCaptain)
	CaptainCommand:Help("Test captains mode.")
end

function Plugin:TestingCaptainsPresetup()
	local GameIDs = Shine.GameIDs
	self.Logger:Debug( "Server TestingCaptainsPresetup" )

	self:StartCaptainsPresetup();

	self:DestroyTimer("NeedOneMoreCaptain")

	-- Add 12 more bots for testing. We need the bots to add now so they get Ids generated in PlayerUpdate.
	--Shared.ConsoleCommand(StringFormat("addbot %d", 12))
	self.Logger:Debug( "TestingCaptains: Add Bots for picking")
	OnConsoleAddBots( nil, 12 )
	self.Logger:Debug( "TestingCaptains: 12 Bots Added")
	-- Testing with Commander bots, I need this to remove them after the game is over.
	Gamerules.removeCommanderBots = true
	-- We need to wait for the bots to be added before we continue.
	-- Run the next steps with a Simple timer

	-- OnConsoleAddBots( nil, 1, TeamNumber, "com" )

	local function AddTestCaptain(Client)
		local IsBot = Client:GetIsVirtual()
		if not IsBot then return end

		if #self.Captains < 2 then
			local PlayerName = Shine.GetClientName(Client)
			local team = #self.Captains + 1
			local team2 = (team % 2 ) + 1
			self.Logger:Debug( "Adding bot captain %s for team : %s", PlayerName, team )
			table.insert(self.Captains, Client)
			self.TestingCaptainBots[team] = Client
			-- Find the bot by name, and set their team
			for pickid, botCheck in pairs(self.Players) do
				if botCheck.name == PlayerName then
					botCheck.pick = team
					botCheck.isCaptain = true
					break
				end
			end
			self:PlayerUpdate( Client )
		end

	end

	-- Wait for all the bots to Load and Generate Names. Then make one of them Captain and start the picking.
	self:SimpleTimer( 2, function()
		self.Logger:Debug( "TestingCaptains: Adding Bot Captains")
		local GameIDs = Shine.GameIDs
		-- We need to set one or two of the Bots as Captains
		for Client, ID in GameIDs:Iterate() do
			local rc = AddTestCaptain( Client )
			if #self.Captains < 2 then
			else
				break
			end
		end

		self:StartCaptains()
		self:TestingCaptainsAddTimers()
	end )

end

function Plugin:TestingCaptainsAddTimers()
	if not self.dt.TestingCaptains then return end

	for team = 1, 2 do
		local team = self:GetCaptainIndex(self.TestingCaptainBots[team])
		if team > 0 then
			local team2 = (team % 2) + 1

			local timerName = StringFormat("AutoPickTeam_%d", team)
			self.Logger:Debug( "TestingCaptains: Adding Bot Captain timer %s", timerName)

			self:CreateTimer(
			timerName,
			 2,
			-1,
			function (Timer)
				if self.dt.CaptainTurn == 0 then return end

				if self.dt.CaptainTurn ~= team then
					if self.Ready[team2] == true then
					 	self.Logger:Debug( "Bot Captain team : %s Ready", team)
						self:Notify( StringFormat( "Bot Captain team : %s Ready", team) , "green")
						self.Ready[team] = true
						self:DestroyTimer(timerName)
					end
					return
				end

				for pickid, Player in pairs(self.Players) do
					if Player.pick == 0 then
						self.Logger:Debug( "Bot Captain team : %s picking %s", team, Player.name )
						self:ReceivePickPlayer( self.Captains[team], {pickid = Player.pickid})
						return
					end
				end
				self.Logger:Debug( "Bot Captain team : %s Ready", team)
				self:Notify( StringFormat( "Bot Captain team : %s Ready", team) , "green")
				self.Ready[team] = true
				self:DestroyTimer(timerName)
				return
			end)

		end
	end

end

function Plugin:Think( DeltaTime )
	if self.dt.Suspended then return end

	local Time = Shared.GetTime()
	if self.NextRun and self.NextRun > Time then
		return
	end
	self.LastRun = Time
	self.NextRun = self.LastRun+ self.Delay

	-- Something wants to End captains.
	if (self.ProcessEndCaptains == true) then
		self.ProcessEndCaptains = false
		self.JoinTeamBlock = false
		if self.Pending then
			self:EndCaptains()
		end
		if self.CaptainsNight then
			self:DestroyTimer("NeedOneMoreCaptain")
		end
	end
	if (self.ProcessResetLastTeams == true) then
		self.ProcessResetLastTeams = false
		self:ResetLastTeams()
	end

	if self.JoinTeamBlock and self.JoinTeamBlockTime and self.JoinTeamBlockTime < Time then
		self.JoinTeamBlock = false
		self.Logger:Info( "Server Captains Night - Team joining now allowed, time limit reached." )
		self:NotifyTranslated( nil , "CAPTAINS_NIGHT_TIMELIMIT" )
	end

end

function Plugin:MapPostLoad()
	
	self:OverrideShuffleTeams()

	if (Plugin.Config.AutoDisableSelf ~=false) then
		self.Logger:Info( "Captains mode is Auto Disabled on map change." )
		-- Disable self after a new map loads.
		self:SetFeatureEnabled( "Captains", false, true )

	elseif self.ProcessStartCaptainsNight then
		self.Logger:Trace( "Process Captains Night Delayed Start" )
		self:OnCaptainsNightChange( true )
	end
	
end

function Plugin:OverrideShuffleTeams()
	local captains= self;

	if self.VoteRandom_ShuffleTeams == true then return end

	-- Check if seeding round & override time limit
	local Enabled, VoteRandom = Shine:IsExtensionEnabled( "voterandom" )
	if Enabled then
		self.Logger:Trace( "Plugin voterandom is enabled. create override for ShuffleTeams" )

		local oldShuffleTeams = VoteRandom.ShuffleTeams;
		VoteRandom.ShuffleTeams = function(self, ResetScores, ForceMode)
			
			if captains.dt.Suspended then 
				oldShuffleTeams(self, ResetScores, ForceMode); 
				return 
			end
			if captains.dt.Captains and (captains.InProgress or captains.GameStarted)
			then
				self.Logger:Info( "Captains Mode has blocked VoteRandom.ShuffleTeams" )
				return 
			end
			self.Logger:Info( "Captains Mode has allowed VoteRandom.ShuffleTeams" )

			oldShuffleTeams(self, ResetScores, ForceMode);

		end
		self.VoteRandom_ShuffleTeams = true
	end

end


function Plugin:OnCaptainsStateChange( Type, Enabled )
	if Type ~= "Captains" then return end

	self.dt.Suspended = (self.dt.Captains ~= true)

	if Enabled ~= true then
		self:EndCaptains()
	else
		self:ResetState()
	end

end

function Plugin:OnSuspend()
	self.Logger:Trace( "server: Plugin:OnSuspend" )
	self.dt.Suspended = true
	self:SetFeatureEnabled( "Captains", false, true )
end

function Plugin:OnResume()
	self.Logger:Trace( "server: Plugin:OnResume")
	self.dt.Suspended = false	
	self:SetFeatureEnabled( "Captains", true, true )
end

function Plugin:NotifyTeamNames()

	self.LastTeamNames = TableCopy( self.DefaultTeamNames )
	if self.Team1IsMarines then
		self.LastTeamNames[1] = self.dt.Team1Name
		self.LastTeamNames[2] = self.dt.Team2Name
	else
		self.LastTeamNames[1] = self.dt.Team2Name
		self.LastTeamNames[2] = self.dt.Team1Name
	end

	self:SendNetworkMessage(
		nil,
		"TeamNamesNotification",
		{marines = self.LastTeamNames[1], aliens = self.LastTeamNames[2]},
		true
	)

end

function Plugin:GetTeam1Name()
	return self.LastTeamNames[1]
end

function Plugin:GetTeam2Name()
	return self.LastTeamNames[2]
end

function Plugin:GetLastTeams()
	return self.LastTeams
end

function Plugin:ResetLastTeams()
	self.LastTeams = {}
	self.LastTeams[1] = {}
	self.LastTeams[2] = {}
	self.LastTeamNames = TableCopy( self.DefaultTeamNames )
end

function Plugin:SetLastTeams()

	local movedPlayer = false
	self.MovingPlayers = true
	for team, Teamlist in pairs(self.LastTeams) do
		for pickid, Player in pairs( TeamList ) do
			local client = Player.Client
			if client == nil then
				-- added this because its required when using BOTS
				client = Shine.GetClientByName(Player.name)
			end

			if Shine:IsValidClient( client ) then
				local PlayerObj = client and client:GetControllingPlayer()
				if PlayerObj ~= nil then
					Gamerules:JoinTeam(PlayerObj, team, true, true)
					movedPlayer = true
				else
					Shine:NotifyError(nil,StringFormat("Player %s not found", Player.name))
				end
			end
		end
	end
	self.MovingPlayers = false
	if movedPlayer == true then 
		self:NotifyTranslated( nil , "CAPTAINS_LASTTEAMS" ) 
	end 

end


Shine.LoadPluginModule( "logger.lua", Plugin )
