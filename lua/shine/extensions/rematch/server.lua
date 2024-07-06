--[[
	All talk voting.
]]

local Plugin = ...

local Shine = Shine
local Notify = Shared.Message
local TableConcat = table.concat

local ChatName = "Rematch"
Plugin.CaptainsMod = "captainsmode"

local GetAllPlayers = Shine.GetAllPlayers
local TableSort = table.sort
local StringFormat = string.format
local tostring = tostring

local TeamHistoryUtil = {}

Plugin.TeamHistoryFile = "config://shine/temp/rematch_team_history.json"

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

function Plugin:NotifyClient(Client, Message, Color)
	local ChatName = "Rematch"
	local R, G, B = 255, 255, 255
	if Color == "red" then
		R, G, B = 255, 0, 0
	elseif Color == "yellow" then
		R, G, B = 255, 183, 2
	elseif Color == "green" then
		R, G, B = 79, 232, 9
	end

	Shine:NotifyDualColour(Client, 131, 0, 255, ChatName .. ": ", R, G, B, Message)
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

	self:LoadTeamHistory()

	self:ResetState()
	self:CreateCommands()

	return true
end

function Plugin:ResetState()

	self.Logger:Debug( "Server ResetState" )
	self:DestroyAllTimers()

	self.MovingPlayers = false
	self.GameStarted = false

	self.dt.Team1Name = Plugin:GetTeamName( 1, true )
	self.dt.Team2Name = Plugin:GetTeamName( 2, true )

	self.RematchStarted = false
	self.RematchTrigger = false
	self.RematchStartComplete = false

	self.PendingGameStatus = true

	if not self.VoteMap_CheckMapLimitsAfterRoundEnd then
		self:OverrideMapVote()
	end
end


function Plugin:CreateCommands()

	--[[
		sh_rematchinfo reports info to the client about rematch.
	]]
	self:BindCommand("sh_rematchinfo", "rematchhelp", function (Client, Enable, Save)
		self:NotifyClient( Client, "Rematch mod is loaded.")
		if self:IsRematchEnabled( "Rematch" ) then
			self:NotifyClient( Client, "Rematch is enabled for the next round. Admins use \"!rematch false\" or \"sh_rematch false\" to deactivate Rematch.")
		else
			self:NotifyClient( Client, "Admins use !rematch or sh_rematch to activate Rematch for the next round.")
		end
		self:NotifyClient( Client, "Admins use !rematchforce [current, last, prior] to Force a Rematch right now with the specified team set. (console sh_rematch_force [current, last, prior])")
		self:NotifyClient( Client, "Admins use !rematchstatus [current, last, prior] to review the team set. (console sh_rematch_status [current, last, prior])")
		self:NotifyClient( Client, "Admins use !rematchupdate to rebuild the current team set with the current teams. (console sh_rematch_update)")
		self:NotifyClient( Client, "Admins use sh_rematch_autodisable to change the setting for Rematch to disable itself on the next map.")
	end)
	:Help("Report info on Rematch mod.")

	--[[
		The sh_rematch allows admins to activate rematch without a vote. 
	]]
	self:BindCommand("sh_rematch", "rematch", function (Client, Enable, Save)
		Enable = Enable and true or false
		Save = Save and true or false
		self:SetRematchEnabled( "Rematch", Enable, not Save )
	end)
	:Help("Swap teams after games over and start another game.")
	:AddParam{ Type = "boolean", Optional = true, Default = false, Help = "Enabled" }
	:AddParam{ Type = "boolean", Optional = true, Default = false, Help = "save" }

	--[[
		sh_rematch_autodisable - make Rematch turn off after a map load.
	]]		
	self:BindCommand("sh_rematch_autodisable", nil, function (client, Enable) 
		Enable = Enable and true or false
		local feature = "AutoDisableSelf"
		local CurrentState = self:IsRematchEnabled( feature)
		if Enable == CurrentState then
			self:NotifyRematchState( feature, CurrentState, client )
			return
		end
		self:SetRematchEnabled( feature, Enable )
		self:NotifyRematchState( feature, Enable, client )
	end )
	:Help("Update Auto Self Disable setting for Rematch")
	:AddParam{ Type = "boolean", Optional = true, Default = true, Help = "Enable" }

	--[[
		rematchforce - activate rematch without waiting. 
	]]		
	self:BindCommand("sh_rematch_force", "rematchforce", function(client, teamSet) 
		if teamSet =="current" then
			if not TeamHistoryUtil.IsSet( self.TeamHistory["current"] ) then
				self:RebuildTeamHistory( client, true )
			end
			if not TeamHistoryUtil.IsSet( self.TeamHistory["current"] ) then
				self:NotifyClient( client, "Team Set current is not loaded. Is anyone on the teams?")
				return
			end			
		elseif teamSet == "last" then
			if not (TeamHistoryUtil.IsSet( self.TeamHistory["current"] )
			or TeamHistoryUtil.IsSet( self.TeamHistory["last"] )) then
				self:NotifyClient( client, "Team Set last is not loaded.")
				return
			end	

		elseif teamSet == "prior" then
			if not TeamHistoryUtil.IsSet( self.TeamHistory["prior"] ) then
				self:NotifyClient( client, "Team Set prior is not loaded.")
				return
			end				
			TeamHistoryUtil.Copy( self.TeamHistory["prior"], self.TeamHistory["current"] ) 			
		else 
			self:NotifyClient( client, "Invalid team set. Allowed: current, last, prior", "red")
			return
		end

		self.ProcessForceRematch = true
		if self.dt.Suspended then 
			self:SetRematchEnabled( "Rematch", true, true )
		end		
		self.ProcessRematchStart = true
	end)
	:Help("Attempt to Force Rematch using last game player list.")
	:AddParam{ Type = "string", Optional = true, Default = "last", Help = "current, last, prior" }


	self:BindCommand("sh_rematch_status", "rematchstatus", function(client, teamSet) 
		local Message = {}
		if teamSet =="current" then
			self:PrintTeamHistorySet( Message , self.TeamHistory["current"] )
		elseif teamSet == "last" then
			if TeamHistoryUtil.IsSet( self.TeamHistory["current"] ) then
				self:PrintTeamHistorySet( Message , self.TeamHistory["current"] )
			elseif TeamHistoryUtil.IsSet( self.TeamHistory["last"] ) then
				self:PrintTeamHistorySet( Message , self.TeamHistory["last"] )
			end			
		elseif teamSet == "prior" then
			self:PrintTeamHistorySet( Message , self.TeamHistory["prior"] )
		else 
			self:NotifyClient( client, "Invalid team set. Allowed: current, last, prior", "red")
			return
		end
		self:NotifyClient( client, TableConcat( Message, "\n" ) )
		for i = 1, #Message do
			ServerAdminPrint( client, Message[ i ] )
		end
	end, true)
	:Help("Report Rematch team status.")
	:AddParam{ Type = "string", Optional = true, Default = "last", Help = "current, last, prior" }

end

function Plugin:StartTeams()

	local TeamHistory = self.TeamHistory["current"]
	if not TeamHistoryUtil.IsSet( TeamHistory ) then
		TeamHistory = self.TeamHistory["last"]
	end
	if not TeamHistoryUtil.IsSet( TeamHistory ) then
		TeamHistoryUtil.Copy(self.TeamHistory["prior"], self.TeamHistory["current"] )
		TeamHistory = self.TeamHistory["current"]
	end
	if not TeamHistoryUtil.IsSet( TeamHistory ) then
		self:Notify( "Rematch Failed. No teams found", "red" )
		self.Logger:Info( "Rematch Failed. No teams found" )
		return
	end


	local Gamerules = GetGamerules()

	self:Notify( "Rematch Starting: StartTeams", "green" )

	-- Force game back to WarmUp
	if Gamerules:GetGameState() >= kGameState.Started then
		Gamerules:SetGameState( kGameState.WarmUp )
	end

	--this forces everyone to the ready room
	local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
	if Enabled then
		self.Logger:Trace( "Server ForcePlayersIntoReadyRoom" )
		MapVote:ForcePlayersIntoReadyRoom()
	else
		-- fallback to to console command. 
		self.Logger:Trace( "mapvote not found. fallback: sh_rr @alien,@marine" )
		Shared.ConsoleCommand("sh_rr @alien,@marine")
	end	

	local Team1String = Plugin:GetTeamName( 1, true )
	local Team2String = Plugin:GetTeamName( 2, true )
	local Team1Name = TeamHistory.Team1Name
	local Team2Name = TeamHistory.Team2Name
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

	self.MovingPlayers = true
	if not self.VoteRandom_ShuffleTeams then
		self:OverrideShuffleTeams()
	end
	if not self.VoteMap_CheckMapLimitsAfterRoundEnd then
		self:OverrideMapVote()
	end

	local newTeam = 2
	for SteamId in TeamHistory.Team1:Iterate() do
		local client = Shine.GetClientByNS2ID( SteamId )
		if Shine:IsValidClient( client ) then
			local PlayerObj = client and client:GetControllingPlayer()
			if PlayerObj ~= nil then
				Gamerules:JoinTeam(PlayerObj, newTeam, true, true)
			else
				Shine:NotifyError(nil,string.format("Player %s not found", SteamId))
			end
		end
	end
	newTeam = 1
	for SteamId in TeamHistory.Team2:Iterate() do
		local client = Shine.GetClientByNS2ID( SteamId )
		if Shine:IsValidClient( client ) then
			local PlayerObj = client and client:GetControllingPlayer()
			if PlayerObj ~= nil then
				Gamerules:JoinTeam(PlayerObj, newTeam, true, true)
			else
				Shine:NotifyError(nil,string.format("Player %s not found", SteamId))
			end
		end
	end

	self.MovingPlayers = false

	-- Just close the GUI for now but don't reset state
	self:SendNetworkMessage(nil, "RematchMatchStart", {}, true)

	self:ReportTeams( TeamHistory );
	self:StartGame()

	-- Rotate and Save teams after we use it to start.
	if TeamHistoryUtil.IsSet( self.TeamHistory["current"] ) then
		TeamHistoryUtil.Rotate(self.TeamHistory["last"], self.TeamHistory["prior"] )
		TeamHistoryUtil.Rotate(self.TeamHistory["current"], self.TeamHistory["last"] )
	end
	TeamHistoryUtil.Reset( self.TeamHistory["current"] )
	self:SaveTeamHistory()
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
		self:CreateTimer( 
			"RematchStartTimer",
			5,
			1,
			function( Timer)
				self.ProcessRematchStart = true
			end
		)
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

			self:CreateTimer( "PostGameStartRematch" , 5, 1, function(Timer)
				self.Logger:Info( "Rematch Game Started" )
				self:SetRematchEnabled( "Rematch", false, true )
			end		
			)
		end

		return
	end

end


function Plugin:OnGameReset()
	self:Notify("Game Reset")
end

function Plugin:EndGame( Gamerules, WinningTeam )
	self.Logger:Debug( "Plugin:EndGame" )
	self:RebuildTeamHistory( )
end

function Plugin:MapChange()
	self.Logger:Trace( "MapChange" )
	if not self.Config.RestoreTeamHistoryAfterMapchange then return end

	if TeamHistoryUtil.IsSet( self.TeamHistory["current"] ) then
		TeamHistoryUtil.Rotate(self.TeamHistory["last"], self.TeamHistory["prior"] )
		TeamHistoryUtil.Rotate(self.TeamHistory["current"], self.TeamHistory["last"] )
	end
	self:SaveTeamHistory()
end

function Plugin:RebuildTeamHistory( NoRotate )
	NoRotate = NoRotate and true or false

	if not NoRotate then 
		TeamHistoryUtil.Rotate(self.TeamHistory["last"], self.TeamHistory["prior"] )
		TeamHistoryUtil.Rotate(self.TeamHistory["current"], self.TeamHistory["last"] )
	end
	TeamHistoryUtil.Reset( self.TeamHistory["current"] )
	local TeamHistory = self.TeamHistory["current"]

	local Enabled, Captains = Shine:IsExtensionEnabled( Plugin.CaptainsMod )
	if Enabled then
		TeamHistory.Team1Name = Captains:GetTeam1Name()
		TeamHistory.Team2Name = Captains:GetTeam2Name()
	end	

	local GameIDs = Shine.GameIDs
	for Client, ID in GameIDs:Iterate() do
		if not Client:GetIsVirtual() then
			local Player       = Client:GetControllingPlayer()
			local SteamID      = Client:GetUserId()
			local PlayerName   = Player:GetName()
			local TeamNumber   = Player:GetTeamNumber()
			self.Logger:Trace( "Server Player Update (%s) %s [%s]", SteamID, PlayerName, TeamNumber )
			if TeamNumber == kTeam1Index then
				TeamHistory.Team1:Add( SteamID )
			elseif TeamNumber == kTeam2Index then
				TeamHistory.Team2:Add( SteamID )
			end
		end
	end
end

function Plugin:SaveTeamHistory()
	self.Logger:Trace( "SaveTeamHistory" )
    local LastTeams = {
		TimeStamp = Shared.GetSystemTime(),
		teamset = { }
    }
	LastTeams.teamset["last"] = {
		Team1Name = self.TeamHistory["last"].Team1Name,
		Team1 = self.TeamHistory["last"].Team1:AsList(),
		Team2Name = self.TeamHistory["last"].Team2Name,
		Team2 = self.TeamHistory["last"].Team2:AsList()
	}
	LastTeams.teamset["prior"] = {
		Team1Name = self.TeamHistory["prior"].Team1Name,
		Team1 = self.TeamHistory["prior"].Team1:AsList(),
		Team2Name = self.TeamHistory["prior"].Team2Name,
		Team2 = self.TeamHistory["prior"].Team2:AsList()
	}
    Shine.SaveJSONFile( LastTeams, self.TeamHistoryFile )
end

function TeamHistoryUtil.New( )
	local TeamHistory = {} 
	TeamHistory.Team1 = Shine.Set()
	TeamHistory.Team2 = Shine.Set()
	TeamHistory.Team1Name = Shine:GetTeamName( 1, true )
	TeamHistory.Team2Name = Shine:GetTeamName( 2, true )
	return TeamHistory
end

function TeamHistoryUtil.Reset( TeamHistory )
	TeamHistory.Team1:Clear()
	TeamHistory.Team2:Clear()
	TeamHistory.Team1Name = Shine:GetTeamName( 1, true )
	TeamHistory.Team2Name = Shine:GetTeamName( 2, true )
end

function TeamHistoryUtil.Copy( FromTeamSet, ToTeamSet)
	TeamHistoryUtil.Reset( ToTeamSet )
	ToTeamSet.Team1Name = FromTeamSet.Team1Name
	ToTeamSet.Team2Name = FromTeamSet.Team2Name
	ToTeamSet.Team1:AddAll( FromTeamSet.Team1:AsList() )
	ToTeamSet.Team2:AddAll( FromTeamSet.Team2:AsList() )
end

function TeamHistoryUtil.Rotate( FromTeamSet, ToTeamSet )
	if FromTeamSet.Team1:GetCount() > 0 or FromTeamSet.Team2:GetCount() > 0 then
		TeamHistoryUtil.Copy( FromTeamSet, ToTeamSet)
	end
end

function TeamHistoryUtil.IsSet( TeamSet )
	return TeamSet.Team1:GetCount() > 0 or TeamSet.Team2:GetCount() > 0;
end

function Plugin:LoadTeamHistoryTeam( TeamSet, TeamHistory )
	if TeamHistory.Team1Name then
		TeamSet.Team1Name = TeamHistory.Team1Name
	end
	if TeamHistory.Team2Name then
		TeamSet.Team2Name = TeamHistory.Team2Name
	end	
	if TeamHistory.Team1 then
		TeamSet.Team1:AddAll(TeamHistory.Team1 ) 

	end
	if TeamHistory.Team2 then
		TeamSet.Team2:AddAll(TeamHistory.Team2 ) 
	end
end

function Plugin:LoadTeamHistory( )
	self.Logger:Trace( "LoadTeamHistory")

	self.TeamHistory = {}
	self.TeamHistory["last"] = TeamHistoryUtil.New()
	self.TeamHistory["prior"] = TeamHistoryUtil.New()
	self.TeamHistory["current"] = TeamHistoryUtil.New()

	if not self.Config.RestoreTeamHistoryAfterMapchange then return end

	local TeamHistory = Shine.LoadJSONFile( self.TeamHistoryFile ) or {}
	local now = Shared.GetSystemTime()

	local TimeStamp = TeamHistory.TimeStamp
	TimeStamp = now
	if not TimeStamp or tonumber( TimeStamp ) + self.Config.TeamHistoryLifeTime < now then
		self.Logger:Trace( "LoadTeamHistory History Expired" )		
		return
	end	
	self.Logger:Trace( "LoadTeamHistory File Read" )

	if TeamHistory.teamset["prior"] then 
		self:LoadTeamHistoryTeam( self.TeamHistory["prior"], TeamHistory.teamset["prior"] )
	end
	if TeamHistory.teamset["last"] then 
		self:LoadTeamHistoryTeam( self.TeamHistory["last"], TeamHistory.teamset["last"] )
	end	
end

function Plugin:PrintTeamHistory( Client )
	local Message = {}
	-- PrintTable( self.TeamHistory )
	
	Message[#Message + 1] = string.format("========Team History========")
	Message[#Message + 1] = string.format("Current ====================")
	self:PrintTeamHistorySet( Message, self.TeamHistory["current"]  )
	Message[#Message + 1] = string.format("Last    ====================")
	self:PrintTeamHistorySet( Message, self.TeamHistory["last"]  )
	Message[#Message + 1] = string.format("Prior   ====================")
	self:PrintTeamHistorySet( Message, self.TeamHistory["prior"]  )

		-- Shine.PrintToConsole
	if not Client then
		self.Logger:Trace( "PrintTeamHistory Notify")
		Notify( TableConcat( Message, "\n" ) )
	else
		self.Logger:Trace( "PrintTeamHistory ServerAdminPrint")
		for i = 1, #Message do
			ServerAdminPrint( Client, Message[ i ] )
		end
	end	
end

function Plugin:PrintTeamHistorySet( Message, TeamHistory )
	if TeamHistory.Team1:GetCount() == 0 then
		Message[#Message + 1] = string.format("Team 1 \"%s\"", TeamHistory.Team1Name)
		Message[#Message + 1] = "Team 1 is currently empty."
	else
		Message[#Message + 1] = string.format("Team 1 \"%s\":", TeamHistory.Team1Name)

		for SteamId in TeamHistory.Team1:Iterate() do
			local ClientName = "Unknown"
			local ListClient = Shine.GetClientByNS2ID( SteamId )
			if ListClient then
				ClientName = Shine.GetClientName( ListClient )
			end
			Message[#Message + 1] = string.format("\t%s[%d]", ClientName, SteamId)
		end
	end

	if TeamHistory.Team2:GetCount() == 0 then
		Message[#Message + 1] = string.format("Team 2 \"%s\"", TeamHistory.Team2Name)
		Message[#Message + 1] = "Team 2 is currently empty."
	else
		Message[#Message + 1] = string.format("Team 2 \"%s\":", TeamHistory.Team2Name)

		for SteamId in TeamHistory.Team2:Iterate() do
			local ClientName = "Unknown"
			local ListClient = Shine.GetClientByNS2ID( SteamId )
			if ListClient then
				ClientName = Shine.GetClientName( ListClient )
			end
			Message[#Message + 1] = string.format("\t%s[%d]", ClientName, SteamId)
		end
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

function Plugin:ReportTeams( TeamHistory, Client )

	TeamHistory = TeamHistory or self.TeamHistory["current"]

	local SortTable = {}
	local Count = 0

	local function AddTeamSet( TeamNumber, Team ) 
		for SteamId in Team:Iterate() do
			local ClientName = "Unknown"
			local client = Shine.GetClientByNS2ID( SteamId )
			if client then
				ClientName = Shine.GetClientName( client )
			end
			local Player = {
				steamid = SteamId,
				name = ClientName,
				team = TeamNumber
			}			
			Count = Count + 1
			SortTable[ Count ] = { Player }
		end
	end

	AddTeamSet( 1 , TeamHistory.Team1 )
	AddTeamSet( 2 , TeamHistory.Team2 )

	TableSort( SortTable, function( A, B )
		if A[ 1 ].team < B[ 1 ].team then return true
		elseif A[ 1 ].team > B[ 1 ].team then return false
		end		
		if A[ 1 ].name < B[ 1 ].name then return true
		elseif A[ 1 ].name > B[ 1 ].name then return false
		end
		if A[ 1 ].steamid < B[ 1 ].steamid then return true end
		return false
	end )

	local Columns = {
		{
			Name = "Name",
			Getter = function( Entry )
				return tostring( Entry[1].name )
			end
		},
		{
			Name = "Steam ID",
			Getter = function( Entry )
				return tostring( Entry[1].steamid )
			end
		},
		{
			Name = "Team",
			Getter = function( Entry )
				local teamNumber = Entry[1].team
				return Plugin:GetTeamName( teamNumber or 5, true )
			end
		}
	}
	Shine.PrintTableToConsole( Client, Columns, SortTable )

end

Shine.LoadPluginModule( "logger.lua", Plugin )
