--[[
	All talk voting.
]]

local Plugin = ...

local Shine = Shine
local ChatName = "Rematch"

Plugin.CaptainsMod = "captainsmode"

local GetAllPlayers = Shine.GetAllPlayers
local TableSort = table.sort
local StringFormat = string.format
local tostring = tostring


-- Block these votes when Rematch is running.
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
	self.Logger:Debug( "Rematch Mode NS2StartVote=========================== %s", VoteName)
	if self.Suspended or not (self.RematchTrigger or self.GameStarted) then return end

	if self.BlockedVoteAlways[ VoteName ] then
		self.Logger:Debug( "Rematch Mode NS2StartVote=========================== **BLOCKED**")
		return false, kVoteCannotStartReason.Waiting
	end

	-- don't block if under a certain player count.
	if Shine.GetHumanPlayerCount() < self.Config.BlockedVotesMinPlayer then return end

	--if not self:IsEndVote() and not self.CyclingMap then return end
	if self.BlockedEndOfMapVotes[ VoteName ] then
		self.Logger:Debug( "Rematch Mode NS2StartVote=========================== **BLOCKED**")
		return false, kVoteCannotStartReason.Waiting
	end
end

function Plugin:OnCycleMap()
	self.Logger:Trace( "OnCycleMap")
	if self.dt.Suspended then return end
	-- Rematch is enabled. Don't allow cycle.
	-- I hope this blocks mapvote, but I'm not sure. 
	self.Logger:Trace( "OnCycleMap Blocked")
	return false	
end

--[[
	Prevents the map from cycling if rematch is active. 
]]
function Plugin:ShouldCycleMap()
	self.Logger:Trace( "ShouldCycleMap")
	if self.dt.Suspended then return end
	-- Rematch is enabled. Don't allow cycle.
	-- I hope this blocks mapvote, but I'm not sure. 
	self.Logger:Trace( "ShouldCycleMap Blocked")
	return false
end

function Plugin:Notify(Message, Color)
	local ChatName = "Rematch"
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

function Plugin:NotifyState( Player )
	local Enable = self.dt.Suspended ~= true

	Shine:TranslatedNotifyDualColour( Player, Enable and 0 or 255, Enable and 255 or 0, 0,
		"REMATCH_TAG", 255, 255, 255, "REMATCH_"..( Enable and "ENABLED" or "DISABLED" ),
		self.__Name )
end

do

	local REMATCH_TYPES = {
		Rematch = "REMATCH_NOTIFY_",
		AutoDisableSelf = "REMATCH_AUTODISABLE_"
	}
	local REMATCH_DT = {
		Rematch = true
	}	


	function Plugin:NotifyRematchState( Type, Enable, Player )
		Shine.AssertAtLevel( REMATCH_TYPES[ Type ], "Invalid rematch type: %s", 3, Type )

		Shine:TranslatedNotifyDualColour( Player, Enable and 0 or 255, Enable and 255 or 0, 0,
			"REMATCH_TAG", 255, 255, 255, REMATCH_TYPES[ Type ]..( Enable and "ENABLED" or "DISABLED" ),
			self.__Name )
	end

	function Plugin:IsRematchEnabled( Type )
		Shine.AssertAtLevel( REMATCH_TYPES[ Type ], "Invalid rematch type: %s", 3, Type )

		return self.Config[ Type ]
	end
 
	function Plugin:SetRematchEnabled( Type, Enabled, DontSave )
		Shine.AssertAtLevel( REMATCH_TYPES[ Type ], "Invalid rematch type: %s", 3, Type )

		Enabled = Enabled and true or false
		self.Config[ Type ] = Enabled
		
		if REMATCH_DT[ Type ] then 
			self.dt[ Type ] = Enabled 
		end		

		if not DontSave then
			self:SaveConfig( true )
		end

		self.Logger:Trace( "Toggle %s %s", Type, ( Enabled and "ENABLED" or "DISABLED" ) )
	
		Shine.Hook.Broadcast( "OnRematchStateChange", Type, Enabled )
	end

end

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )
	self.Logger:Debug( "Server Initialise" )
	-- Setup for Think()
	self.Delay = 0.5
	self.LastRun = Shared.GetTime()
	self.NextRun = self.LastRun+ self.Delay

	self.VoteRandom_ShuffleTeams = false
	self.VoteMap_CheckMapLimitsAfterRoundEnd = false
	self.GameStarted = false
	self.ProcessEndRematch = false
	self.ProcessRematchReset = false
	self.ProcessRematchStart = false
	self.ProcessForceRematch = false
	self.PendingGameStatus = false

	self.dt.Rematch = (Plugin.Config.Rematch ~= false)
	self.dt.Suspended = (self.dt.Rematch ~= true)

	self:ResetState()
	self:CreateCommands()

	return true
end

function Plugin:ResetState()

	self.Logger:Debug( "Server ResetState" )
	self:DestroyAllTimers()

	self.Players = {}
	self.TeamNames = {"Marines", "Aliens"}

	self.MovingPlayers = false
	self.GameStarted = false

	self.dt.Team1Name = Plugin:GetTeamName( 1, true )
	self.dt.Team2Name = Plugin:GetTeamName( 2, true )

	self.RematchStarted = false
	self.RematchTrigger = false
	self.RematchStartComplete = false

	-- check current game status???
	self.PendingGameStatus = true
	-- --if GetGamerules():GetGameStarted() then
	-- local gm = GetGamerules()
	-- if gm then
	-- 	if gm:GetGameStarted() then
	-- 		self.GameStarted = true
	-- 	end
	-- end

	-- if GetGamerules():GetGameStarted() then		
	-- 	self.GameStarted = true
	-- end

	if not self.VoteMap_CheckMapLimitsAfterRoundEnd then
		self:OverrideMapVote()
	end
end


function Plugin:CreateCommands()


	-- if self.dt.Suspended then 
	-- 	self:NotifyState( Client );
	-- 	return
	-- end


	--[[
		The sh_rematch allows admins to activate rematch without a vote. 
	]]
	local RematchCommand =self:BindCommand("sh_rematch", nil, function (Client, Enable, Save)
		Enabled = Enabled and true or false
		Save = Save and true or false
		self:SetRematchEnabled( "Rematch", Enabled, not Save )
	end)
	RematchCommand:Help("Swap teams after games over and start another game.")
	RematchCommand:AddParam{ Type = "boolean", Optional = true, Default = false, Help = "Enabled" }
	RematchCommand:AddParam{ Type = "boolean", Optional = true, Default = false, Help = "save" }

	self:BindCommand("sh_rematch_autodisable", nil, function (client) 
		local feature = "AutoDisableSelf"
		local NewState = not self:IsRematchEnabled( feature)
		self:SetRematchEnabled( feature, NewState )
		self:NotifyRematchState( feature, NewState, client )
	end ):Help("Toggle Rematch Mod Auto Self Disable")

	self:BindCommand("sh_rematch_force", nil, function(client) 
		-- self:RematchManual() < has issue with teams arrays not being arrays.
		self.ProcessForceRematch = true
		if self.dt.Suspended then 
			self:SetRematchEnabled( "Rematch", true, true )
		end		
		self.ProcessRematchStart = true
	end ):Help("Attempt to Force Rematch using last game player list.")

	self:BindCommand("sh_rematchcheck", nil, function (Client)
		
		self:NotifyState( Client );

		if 	self:IsRematchEnabled( "Rematch" ) then
			self.Logger:Debug( "Rematch is active" )
			--self:Notify( "Rematch is active", "yellow")	

			self:SetRematchEnabled( "Rematch", false, true )
		else
			self.Logger:Debug( "Rematch is inactive" )
			--self:Notify( "Rematch is inactive", "yellow")	

			self:SetRematchEnabled( "Rematch", true, true )
		end

	end
	, true ):Help("Test rematch function.")		

	self:BindCommand("sh_rematchtest", "rematchtest", function (Client)		
		self:RematchPlayerBuild( Client );
	end
	, true ):Help("Test rematch function.")		

end



function Plugin:StartRematch()
	local GameIDs = Shine.GameIDs
	self.Logger:Debug( "Server Start Rematch" )

	-- Send Player:client to  everyone
	self.Logger:Debug( "Server Start Rematch : Send Players" )
	for Client, ID in GameIDs:Iterate() do
		--self:PlayerUpdate( Client )
	end	
end


function Plugin:StartTeams()

	local Gamerules = GetGamerules()

	self:Notify( "Rematch Starting: StartTeams", "green" )

	local Teams = {2, 1}
	
	self.MovingPlayers = true
	if not self.VoteRandom_ShuffleTeams then
		self:OverrideShuffleTeams()
	end
	if not self.VoteMap_CheckMapLimitsAfterRoundEnd then
		self:OverrideMapVote()
	end

	-- Start the game
	for pickid, Player in pairs(self.Players) do
		if Player.team == 1 or Player.team == 2 then
			--local client = Shine.GetClientByNS2ID(SteamID)
			local client = Player.Client
			if client == nil then
				-- added this because its required when using BOTS
				client = Shine.GetClientByName(Player.name)
			end

			if Shine:IsValidClient( client ) then
				local PlayerObj = client and client:GetControllingPlayer()
				if PlayerObj ~= nil then
					Gamerules:JoinTeam(PlayerObj, Teams[Player.team], true, true)
				else
					Shine:NotifyError(nil,string.format("Player %s not found", Player.name))
				end
			else
				-- Most Likely the Bots were already removed from the server
				-- So lets just add a new bot for each bot we had. 
				if Player.isBot == true then
					if Player.isCommander ~= true then
						OnConsoleAddBots( nil, 1, Teams[Player.team] )
					else
						OnConsoleAddBots( nil, 1, Teams[Player.team], "com" )
						--Set if we added commander bots.
						Gamerules.removeCommanderBots = true						
					end
				end
			end
		end
	end

	self.MovingPlayers = false

	-- Just close the GUI for now but don't reset state
	self:SendNetworkMessage(nil, "RematchMatchStart", {}, true)

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
				{text = string.format("Game will start in %s seconds", Seconds)},
				true
			)

			end
			if Seconds == 0 then
				self.Logger:Debug( "Server StartGame GameStartCountdown" )
				ForceRoundStart()
			end
		end
	)

	self.RematchStarted = true

end

--[[
	MatchComplete - for when you want to rest the state, but not end the mod.
]]
function Plugin:MatchComplete()
	self.Logger:Debug( "Server MatchComplete" )
	self:SendNetworkMessage(nil, "RematchMatchComplete", {}, true)
	self:ResetState()
end

function Plugin:EndRematch()
	self.Logger:Debug( "Server EndRematch" )
	self:SendNetworkMessage( nil, "RematchEnd", {}, true)
	self:ResetState()	
end

function Plugin:SetGameState(Gamerules, State, OldState)
	if self.dt.Suspended then return end
	-- if not self.dt.Rematch then return end

	self.Logger:Debug( "Server state=========================== %s[%s] ==> %s[%s]", kGameState[OldState],OldState, kGameState[State],State)
	--self:Notify(string.format("Server state: %s  %s", OldState, State))
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

	-- Allow Rematch to start after game ends.
	-- 24
	-- 32
	if self.RematchTrigger and not self.RematchStarted
	and (State == kGameState.WarmUp) 
	then
		-- Delay Next Match for a few seconds for the Scores screen to appear
		Plugin:SimpleTimer( 5, function(Timer)
			self.ProcessRematchStart = true
		end)
	end

	-- trigger end on next think.
	-- self.ProcessEndRematch =  true
	-- self.GameStarted

	-- After the game has started, Verify state transition.
	if self.GameStarted
	and not self.RematchTrigger
	and (State == kGameState.Team1Won or
        State == kGameState.Team2Won or
        State == kGameState.Draw)
	then
		self.Logger:Debug( "Server state: match over. Start Rematch.")
		self.RematchTrigger = true
		-- Okay to turn it off.
		self.GameStarted = false
		-- Delay Next Match for a few seconds for the Scores screen to appear
		-- Plugin:SimpleTimer( 5, function(Timer)
		-- 	self:StartTeams()
		-- end)
		return
	end
	if self.GameStarted
	and self.RematchStarted
	and (State == kGameState.Team1Won or
        State == kGameState.Team2Won or
        State == kGameState.Draw)
	then
		self.Logger:Debug( "Server state: match over. Rematch Over." )
		-- Okay to turn it off.
		self.GameStarted = false
		-- Delay Next Match for a few seconds for the Scores screen to appear
		Plugin:SimpleTimer( 5, function(Timer)
			self:MatchComplete()
		end)
		return		
	end	

	if State == kGameState.Started then
		self.Logger:Trace( "Rematch Game Starting" )
		-- The Rematch is starting. Send the Team Notification.
		self.GameStarted = true
		self:DestroyTimer("GameStartCountdown")
		--self.InProgress = false

		if self.RematchStarted then 
			self:SendNetworkMessage(
				nil,
				"TeamNamesNotification",
				{marines = self.dt.Team1Name, aliens = self.dt.Team2Name},
				true
			)
			self.RematchStartComplete = true
		end

		return
	end

end


function Plugin:OnGameReset()
	self:Notify("Game Reset")
end

function Plugin:EndGame( Gamerules, WinningTeam )
	self.Logger:Debug( "Plugin:EndGame" )

	-- if self.RematchStartComplete then
	-- 	self.BlockMapVote = false
	-- end

	self:RematchPlayerBuild( nil )
end

--function Plugin:RematchManual( )
-- 	if self.dt.Suspended then 
-- 		self:SetRematchEnabled( "Rematch", true, true )
-- 	end

-- 	local Enabled, Captains = Shine:IsExtensionEnabled( Plugin.CaptainsMod )
-- 	if not Enabled then
-- 		return
-- 	end
	
-- 	local Team1String = Plugin:GetTeamName( 1, true )
-- 	local Team2String = Plugin:GetTeamName( 2, true )
-- 	local Team1Name = Captains:GetTeam1Name()
-- 	local Team2Name = Captains:GetTeam2Name()

-- 	local LastTeams = Captains:GetLastTeams()
-- 	self.Players = {}
	
-- 	-- Swap Team Names
-- 	if Team1Name ~= Team1String then 
-- 		self.dt.Team2Name = Team1Name;
-- 	else
-- 		self.dt.Team2Name = Team2String
-- 	end
-- 	if Team2Name ~= Team2String then		
-- 		self.dt.Team1Name = Team2Name;
-- 	else
-- 		self.dt.Team1Name = Team1String
-- 	end

-- 	local playerSet = false
-- 	for team, Teamlist in pairs(LastTeams) do
-- 		for id, Player in pairs( TeamList ) do
-- 			-- process valid clients. ignores bots.
-- 			if Shine:IsValidClient( Player.Client ) then
-- 				self:PlayerUpdate( Player.Client )
-- 				local pickid = self:GetPickId(Player.Client) 
-- 				self.Players[pickid].TeamNumber = team
-- 				self.Players[pickid].pick = team
-- 				playerSet = true
-- 			end
-- 		end
-- 	end
-- 	if playerSet == true then 
-- 		self.ProcessRematchStart = true
-- 		self:TranslatedNotify(nil, "REMATCH_FORCE", "red")
-- 	end
-- end

function Plugin:RematchPlayerBuild( Caller )

	local GameIDs = Shine.GameIDs
	self.Players = {}

	local Team1String = Plugin:GetTeamName( 1, true )
	local Team2String = Plugin:GetTeamName( 2, true )
	local Team1Name = Team1String
	local Team2Name = Team2String

	local Enabled, Captains = Shine:IsExtensionEnabled( Plugin.CaptainsMod )
	if Enabled then
		Team1Name = Captains:GetTeam1Name()
		Team2Name = Captains:GetTeam2Name()
	end
	-- Swap Team Names
	if Team1Name ~= Team1String then 
		self.dt.Team2Name = Team1Name;
	else
		self.dt.Team2Name = Team2String
	end
	if Team2Name ~= Team2String then		
		self.dt.Team1Name = Team2Name;
	else
		self.dt.Team1Name = Team1String
	end

	for Client, ID in GameIDs:Iterate() do
		self:PlayerUpdate( Client )
	end

end

function Plugin:Cleanup()
	self.Logger:Info( "Disabling server plugin..." )
	self.BaseClass.Cleanup(self)
end


function Plugin:OnSuspend()
	self.Logger:Trace( "server: Plugin:OnSuspend" )
	self.dt.Suspended = true
	self:SetRematchEnabled( "Rematch", false, true )
end

function Plugin:OnResume()
	self.Logger:Trace( "server: Plugin:OnResume")
	self.dt.Suspended = false
	self:SetRematchEnabled( "Rematch", true, true )
end

function Plugin:Think( DeltaTime )
	if self.dt.Suspended then return end

	local Time = Shared.GetTime()
	if self.NextRun and self.NextRun > Time then
		return
	end
	self.LastRun = Time
	self.NextRun = self.LastRun+ self.Delay
	
	--Print( "%s", Time)
	
	-- Something wants to End Rematch.
	if (self.ProcessEndRematch == true) then
		self.ProcessEndRematch = false
		if self.Pending then
			self:EndRematch()
		end
	end
	if (self.ProcessRematchReset == true ) then
		self.ProcessRematchReset = false
		if (self.dt.Rematch == true ) then
			self:ResetState()
		end
	end
	if (self.ProcessRematchStart == true) then
		self.ProcessRematchStart = false
		self:StartTeams()
		self.ProcessForceRematch = false
	end

	if (self.PendingGameStatus == true ) then
		self.PendingGameStatus = false
		self.GameStarted = ( GetGamerules():GetGameStarted() )
		if self.GameStarted then
			self.FirstMatch = true
		end
	end

end

function Plugin:MapPostLoad()

	self:OverrideShuffleTeams(  )

	if Plugin.Config.AutoDisableSelf and self.dt.Suspended ~= true then
		-- Disable self after a new map loads.
		self:OnSuspend()
	end
	
end

function Plugin:OverrideShuffleTeams(  )
	local selfRematch = self

	if self.VoteRandom_ShuffleTeams == true then return end

	-- Check if seeding round & override time limit
	local Enabled, VoteRandom = Shine:IsExtensionEnabled( "voterandom" )
	if Enabled then
		self.Logger:Trace( "Plugin voterandom is enabled. create override for ShuffleTeams" )

		local oldShuffleTeams = VoteRandom.ShuffleTeams;
		VoteRandom.ShuffleTeams = function(self, ResetScores, ForceMode) 
					
			if selfRematch.dt.Suspended then 
				oldShuffleTeams(self, ResetScores, ForceMode); 
				return 
			end

			if selfRematch.dt.Rematch or selfRematch.GameStarted then
				self.Logger:Info( "Rematch Mode has blocked VoteRandom.ShuffleTeams" )
				return 
			end
			self.Logger:Info( "Rematch Mode has allowed VoteRandom.ShuffleTeams" )

			oldShuffleTeams(self, ResetScores, ForceMode);

		end
		self.VoteRandom_ShuffleTeams = true
	end

end

function Plugin:OverrideMapVote()
	local selfRematch = self;

	if self.VoteMap_CheckMapLimitsAfterRoundEnd == true then return end
	
	local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
	if Enabled then
		self.Logger:Trace( "Server CheckMapLimitsAfterRoundEnd" )

		local oldCheckMapLimitsAfterRoundEnd = MapVote.CheckMapLimitsAfterRoundEnd;
		MapVote.CheckMapLimitsAfterRoundEnd = function ( self )
			selfRematch.Logger:Trace( "MapVote.CheckMapLimitsAfterRoundEnd" )
			if selfRematch.dt.Suspended then
				selfRematch.Logger:Trace( "Rematch Suspended. Allowing MapVote.CheckMapLimitsAfterRoundEnd" )
				oldCheckMapLimitsAfterRoundEnd(self);
				return 
			end
			if (selfRematch.RematchTrigger or selfRematch.RematchStarted) and not selfRematch.RematchStartComplete
			then
				selfRematch.Logger:Trace( "Rematch Mode has blocked MapVote.CheckMapLimitsAfterRoundEnd" )
				return 
			end
			selfRematch.Logger:Trace( "Rematch Mode has allowed MapVote.CheckMapLimitsAfterRoundEnd" )

			oldCheckMapLimitsAfterRoundEnd(self);

		end
		--MapVote.CheckMapLimitsAfterRoundEnd = CheckMapLimitsAfterRoundEndOverride
		self.VoteMap_CheckMapLimitsAfterRoundEnd = true
	end
end


function Plugin:OnRematchStateChange( Type, Enabled )
	if Type ~= "Rematch" then return end

	self.dt.Suspended = (self.dt.Rematch ~= true)
	if self.ProcessForceRematch == true then return end

	if Enabled ~= true then
		self:EndRematch()
	else
		self:ResetState()
	end

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

	--if self.dt.Suspended or not self.InProgress then return end

	local Player       = Client:GetControllingPlayer()
	local SteamID      = Client:GetUserId()
	local PlayerName   = Player:GetName()
	local TeamNumber   = Player:GetTeamNumber()
	local pickid       = self:GetPickId(Client)
	local IsBot        = Client:GetIsVirtual()
	local IsCommander  = Player:isa("Commander") and true or false

	local Data = {
			Client = Client,

			pickid = pickid,
			steamid = SteamID,
			name = PlayerName,
			team = TeamNumber,
			pick = (TeamNumber == 1 or TeamNumber == 2) and TeamNumber or 0, 
			isBot = IsBot,
			isCommander = IsCommander

		}
	self.Logger:Trace( "Server Player Update (%s) %s [%s]", Data.steamid, Data.name , Data.pick )

	-- Save Player to our list.
	self.Players[pickid] = Data

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
			Name = "Commander",
			Getter = function( Entry )
				return tostring( Entry[2].isCommander )
			end
		}
	}
	Shine.PrintTableToConsole( Client, Columns, SortTable )
	
	--SortTable

end



Shine.LoadPluginModule( "logger.lua", Plugin )
