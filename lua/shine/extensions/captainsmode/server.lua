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

function Plugin:NS2StartVote( VoteName, Client, Data )
	self.Logger:Debug( "Captains Mode NS2StartVote=========================== %s", VoteName)
	if not (self.InProgress or self.GameStarted) then return end
	--if not self:IsEndVote() and not self.CyclingMap then return end

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

function Plugin:CreateCommands()

	local function Captain(Client)
		local PlayerName = Shine.GetClientName( Client )	
		local Player       = Client:GetControllingPlayer()
		local TeamNumber   = Player:GetTeamNumber()
		if TeamNumber == 3 then
			Shine:Notify(Client, ChatName, PlayerName, "Spectators not allowed to Captain.")
			-- requires register.
			--self:SendTranslatedNotify( Client, "SPECTATOR_TO_CAPTAIN" )
			--something is missing
			--self:NotifyTranslated( nil, "SPECTATOR_TO_CAPTAIN")
			return
		end

		-- If there is a game in progress, deny it.
		local Gamerules = GetGamerules()
		if Gamerules:GetGameStarted() then
			Shine:Notify(Client, ChatName, PlayerName, "A game has already started.")
			return
		end
		-- Check if the player is already a captain.
        if self:GetCaptainIndex(Client) then
            Shine:Notify(Client, ChatName, PlayerName, "You are already a captain.")
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
			Shine:Notify(Client, ChatName, PlayerName, "There are already 2 captains.")
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
			self:Notify("Diamond Gamers Captains mode:")
			self:Notify("To appoint yourself as captain, type !captain")
			-- name, delay, reps, func
			self:CreateTimer(
				"NeedOneMoreCaptain",
				20,
				-1,
				function(Timer)
					local CaptainName = Shine.GetClientName( self.Captains[1] )
					self:Notify("Need one more captain to start picking players.", "yellow")
					self:Notify("To appoint yourself as captain, type !captain")
					self:Notify(string.format("Current captain: %s", CaptainName))
				end
			)
		end
	end

	local CaptainCommand = self:BindCommand("sh_cm_captain", "captain", Captain, true)
	CaptainCommand:Help("Diamond Gamers Captains mode: Make yourself a captain.")


	--[[
		The sh_cm_mutiny allows Players to drop out as captain.
	]]
	local function CaptainMutiny(Client)
		local PlayerName = Shine.GetClientName( Client )
		if self:GetCaptainIndex(Client) 
		or Shine:HasAccess( Client, "sh_cm_cancel" )
		then 
			self:EndCaptains()
			self:Notify(string.format("Captains mode was cancelled by %s.", PlayerName), "red")
		else
			Shine:Notify(Client, ChatName, PlayerName, "You are not allowed to Mutiny.")
		end
	end
	self:BindCommand("sh_cm_mutiny", "cancelcaptains", CaptainMutiny
	, true):Help("Cancel captains mode.")


	--[[
		The sh_cm_cancel allows admins to cancel captains for the users.
	]]
	local function CancelCaptains(Client)
		local PlayerName = Shine.GetClientName( Client )
		self:EndCaptains()
		self:Notify(string.format("Captains mode was cancelled by %s.", PlayerName), "red")
	end
	self:BindCommand("sh_cm_cancel", nil, CancelCaptains
		):Help("Cancel captains mode.")

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
		if not self.InProgress then return end
		if not Plugin.Config.AllowPlayersToViewTeams then return end 
		self:SendNetworkMessage(Client, "ShowTeamMenu", {}, true)
	end 
	, true ):Help( "Show current Captain Teams." )


	self:BindCommand( "sh_cm_hidemouse", "hidemouse", function (Client)
		self:SendNetworkMessage(Client, "HideMouse", {}, true)
	end 
	, true ):Help( "Hide the mouse if for some reason it is still showing." )		
		
	if Plugin.Config.AllowTesting then
		self:CreateTestingCommands()
	end
			
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


function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )
	self.Logger:Debug( "Server Initialise" )
	-- Setup for Think()
	self.Delay = 0.5
	self.LastRun = Shared.GetTime()
	self.NextRun = self.LastRun+ self.Delay
	self.ProcessEndCaptains = false

	self:ResetState()
	self:CreateCommands()
	
	self:TestingCaptainsInitialise()

	return true
end

function Plugin:ResetState()
	
	self.Logger:Debug( "Server ResetState" )
	self:DestroyAllTimers()
	self.InProgress = false
	self.Pending = false

	self.Players = {}
	self.Captains = {}
	
	self.TeamNames = {"Marines", "Aliens"}
	self.Ready = {false, false}
	self.LastCount = {0,0}

	self.CaptainFirstTurn = nil
	self.CaptainTurn = nil
	self.MovingPlayers = false
	self.GameStarted = false
	
	if math.random(0, 1) == 1 then
		self.Team1IsMarines = true
		self.dt.Team1Name= self.TeamNames[1]
		self.dt.Team2Name= self.TeamNames[2]
	else
		self.Team1IsMarines = false
		self.dt.Team1Name= self.TeamNames[2]
		self.dt.Team2Name= self.TeamNames[1]
	end
	self.dt.CaptainTurn = 0
	
end

function Plugin:GetCaptainIndex(Client)
	self.Logger:Trace( "Server GetCaptainIndex" )
	local CaptainIndex = nil
	if Client == nil then return CaptainIndex end
	
	for Index, CaptainClient in pairs(self.Captains) do
		if CaptainClient == Client then
			CaptainIndex = Index
			-- Return when we found it.
			return CaptainIndex
		end
	end
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
	
	if not self.InProgress then return end
	
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
			isPickable  = not (TeamNumber == 3 or TeamNumber > 4),
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
	
	if not self.InProgress then return end

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

	if Plugin.Config.AutoRemoveBots then
		Shared.ConsoleCommand(string.format("sv_maxbots %d", 0))
	end
	if Plugin.Config.AutoDisableVoteRandom then
		local Enabled, VoteRandom = Shine:IsExtensionEnabled( "voterandom" )
		if Enabled and not VoteRandom.Suspended then
			VoteRandom:Suspend()
			self.Logger:Info( "Plugin voterandom has been suspended." )
		end 
		--Shared.ConsoleCommand("sh_unloadplugin voterandom")
		--Shared.ConsoleCommand("sh_suspendplugin voterandom")
	end
	if Plugin.Config.AutoReadyRoom then
		--this forces everyone to the ready room
		local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
		if Enabled then
			MapVote:ForcePlayersIntoReadyRoom()
		else
			-- fallback to just moving *everyone* to the readyroom.
			Shared.ConsoleCommand("sh_rr *")
		end
	end
end
--[[
	StartCaptains: Start by sending all the players to the clients and setting who picks first.
]]
function Plugin:StartCaptains()
	local GameIDs = Shine.GameIDs
	self.Logger:Debug( "Server Start Captains" )

	self:Notify("Captains mode has started!", "yellow")

	local Captain1Name = Shine.GetClientName( self.Captains[1] )
	local Captain2Name = Shine.GetClientName( self.Captains[2] ) 
	self:Notify(string.format("Please wait while %s and %s pick teams.", Captain1Name, Captain2Name))

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
	self:Notify(CaptainName .. " picks first.", "green")
end


function Plugin:ReceiveSetTeamName(Client, Data)
	local CaptainIndex = self:GetCaptainIndex(Client)
	self.Logger:Debug( "Server ReceiveSetTeamName " )
	
	if CaptainIndex then
		local TeamName = Data.teamname
		self.Logger:Debug( "Captain %s changed their team name %s", CaptainIndex, TeamName )		
		self.TeamNames[CaptainIndex] = TeamName
		if CaptainIndex == 1 then
			self.dt.Team1Name = TeamName
		elseif CaptainIndex == 2 then
			self.dt.Team2Name = TeamName
		else
			return
		end
	end
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
	if self.TestingCaptainBots and self.TestingCaptainBots[CaptainIndex] ~= nil  then
		return true
	end
	return false
end



function Plugin:ReceiveSetReady(Client, Data)
	local Team = self:GetCaptainIndex(Client)
	local Ready = Data.ready
	local CaptainName = Shine.GetClientName( Client )
	
	self.Logger:Debug( "Server ReceiveSetReady " )

	if Team then
		self.Ready[Team] = Data.ready
		if Ready then
			self:Notify(CaptainName .. "'s team is ready.", "green")
		else
			self:Notify(CaptainName .. "'s team is not ready.", "red")
		end
	end

	
	if self.Ready[1] and self.Ready[2] then
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
				self:Notify(string.format("Picked player %s removed from team %s[%s].", Player.name,  Shine.GetClientName( self.Captains[Player.pick] ),Player.pick), "red")
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
		
		-- Make sure teams are not more than one appart.
		if TeamCount[1] > (TeamCount[2]+1) 
		or TeamCount[2] > (TeamCount[1]+1) then
			if  self.LastCount[1] ~= TeamCount[1]
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


function Plugin:StartTeams()		

	local Gamerules = GetGamerules()
	
	local Teams
	if self.Team1IsMarines then
		Teams = {1, 2}
	else
		Teams = {2, 1}
	end
	
	self.MovingPlayers = true

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
					Shine:NotifyError(nil,string.format("Player %s not found", Player.name))
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
 
	if Plugin.Config.AutoRemoveBots then
		Shared.ConsoleCommand(string.format("sv_maxbots %d", 12))
	end
	if Plugin.Config.AutoDisableVoteRandom then
		local Enabled, VoteRandom = Shine:IsExtensionEnabled( "voterandom" )
		if VoteRandom and not Enabled and VoteRandom.Suspended then
			VoteRandom:Resume()
			self.Logger:Info( "Plugin voterandom has been resumed." )
		end 
		--Shared.ConsoleCommand("sh_loadplugin voterandom")
		--Shared.ConsoleCommand("sh_resumeplugin voterandom")
	end
	if Plugin.Config.AutoDisableSelf then
		--Shared.ConsoleCommand("sh_disableplugin captainsmodeharq")
		--Shared.ConsoleCommand("sh_unloadplugin captainsmodeharq")
		--self:Notify("Captains mode completed please ask a Diamond admin to reset the plugin.")
	end
end

function Plugin:ReceiveRequestEndCaptains(Client, Data)
	self.Logger:Debug( "Server ReceiveRequestEndCaptains" )
	-- allow Captain or Admin to cancel.
	if self:GetCaptainIndex(Client) 
	or Shine:HasAccess( Client, "sh_cm_cancel" ) 
	then
		local PlayerName = Shine.GetClientName( Client )
		self:EndCaptains()
		self:Notify("Captains mode was cancelled by " .. PlayerName .. ".", "yellow")
	else
		local PlayerName = Shine.GetClientName(Client)
		Shine:Notify(Client, ChatName, PlayerName, "You are not allowed to end Captains.")
	end

end

function Plugin:ReceivePickPlayer(Client, Data)
	local CaptainName = Shine.GetClientName( Client )
	self.Logger:Debug( "Server ReceivePickPlayer Client %s", CaptainName )
	-- If we are not on a Captain Turn then don't process anything.	
	if self.dt.CaptainTurn == 0 then return end
	-- Check the client is a captain and it's his turn
	local CaptainIndex = self:GetCaptainIndex(Client)
	if not CaptainIndex then
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
			-- send invalid pick??
	 		Shine:Notify(Client, ChatName, CaptainName, "Player you picked is already on the other team.")
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

function Plugin:ReceiveTradePlayer(Client, Data)
	local CaptainName = Shine.GetClientName( Client )
	self.Logger:Debug( "Server ReceiveTradePlayer Client %s", CaptainName )
	local CaptainIndex = self:GetCaptainIndex(Client)
	if not CaptainIndex then
		self.Logger:Debug( "Received Player trade from an invalid player. %s is not a captain", CaptainName )
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

	--local CaptainTurnIndex
	local CaptainTurnIndex = (self.dt.CaptainTurn % 2 ) + 1
	-- Adjust turn for Team Count?
	if self.CaptainFirstTurn == 1 and CaptainTurnIndex == 1 and TeamCount[1] > TeamCount[2] then
		--allow 2 to pick again
		CaptainTurnIndex = 2
	elseif self.CaptainFirstTurn == 2 and CaptainTurnIndex == 2 and TeamCount[2] > TeamCount[1] then
		--allow 1 to pick again
		CaptainTurnIndex = 1
	end
	
	self.CaptainTurn = self.Captains[CaptainTurnIndex]
	self.dt.CaptainTurn = CaptainTurnIndex  

end
--[[
	Block players from joining Marines or Aliens while we are Picking Teams
]]
function Plugin:JoinTeam(_, Player, NewTeam, Force, ShineForce)
	if ShineForce then self.Logger:Trace( "Server JoinTeam Force"); return end
	if not self.InProgress and NewTeam ~= 3 then self.Logger:Trace( "Server JoinTeam Not InProgress"); return end
	if not Player then return end
	local PlayerName = Player:GetName()
	
	-- this is "before" the team on Player:GetTeamNumber is updated.
	if NewTeam == 3 then
		-- Don't allow captains into spec
		local Client = Shine.GetClientForPlayer( Player )
		local CaptainIndex = self:GetCaptainIndex(Client)
		if CaptainIndex > 0 then
			Shine:NotifyError(Player
				,string.format("Captain not allowed to join %s [%s]. You must !cancelcaptains first."
					, Plugin:GetTeamName( NewTeam )
					, NewTeam)) 
			return false 
		end
		--Moved To Spectate
 		--Shine:NotifyError(Player,string.format("Attempting to join Team %s [%s].", Plugin:GetTeamName( NewTeam ), NewTeam))
		return
	elseif NewTeam == 0 then
		return		
	else
		-- If we are testing, Allow Allow Bots to join teams.
		if self.TestingCaptains then 
			local Client = Shine.GetClientForPlayer( Player )
			if Client and Client:GetIsVirtual() then return end
		end
		-- Not Spectate, Not ReadyRoom
		self.Logger:Debug( "Player Blocked from joining team %s : %s", NewTeam, PlayerName )
		Shine:NotifyError(Player,string.format("Not allowed to join %s while captains picking is active.", Plugin:GetTeamName( NewTeam ) ))
		return false
	end

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
		--Shared.ConsoleCommand(string.format("sv_maxbots %d", 12))
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
		return	
	end
	
	-- self.InProgress and 
	
	if State == kGameState.Started then
		self.Logger:Trace( "Captains Mode Game Starting" )
		self:DestroyTimer("EndCaptainsGame")
		-- The Captains game is starting. Send the Team Notification. 
		self.GameStarted = true
		self:DestroyTimer("GameStartCountdown")
		self.InProgress = false
		
		local MarinesTeamName
		local AliensTeamName
		if self.Team1IsMarines then
			MarinesTeamName = self.dt.Team1Name
			AliensTeamName = self.dt.Team2Name
		else
			MarinesTeamName = self.dt.Team2Name
			AliensTeamName = self.dt.Team1Name
		end

		self:SendNetworkMessage(
			nil,
			"TeamNamesNotification",
			{marines = MarinesTeamName, aliens = AliensTeamName},
			true
		)		

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
	self.Logger:Trace( "Server PlayerNameChange from [%s] to [%s]", Name, OldName )
	self:PlayerUpdate( Client )
end

--[[
	Processing when a new player connects and picking is in progress.
]]
function Plugin:ClientConfirmConnect( Client )

	if not self.InProgress then return end

	self:PlayerUpdate( Client )
	
	local IsBot = Client:GetIsVirtual()
	if IsBot then return end 

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


-- Cancel captains mode if a captain quits the game
function Plugin:ClientDisconnect(Client)
	local PlayerName = Shine.GetClientName( Client )
	self.Logger:Debug( "ClientDisconnect %s.", PlayerName )
	
	--local IsBot = Client:GetIsVirtual()
	--if IsBot then return end 
 
	if self.InProgress then
		local pickid = self:GetPickId(Client)
		
		if self:GetCaptainIndex(Client) then
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

	self.TestingCaptains = false
	self.TestingCaptainBots = nil
	
	--self:CreateCommands()

	return true
end

function Plugin:CreateTestingCommands()
	--[[
		TestCaptain allow for testing the Captains mod 
	]]
	local function TestCaptain(Client)
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
		
		self.TestingCaptains = true
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

	self.InProgress = true
	
	if Plugin.Config.AutoRemoveBots then
		Shared.ConsoleCommand(string.format("sv_maxbots %d", 0))
	end
	if Plugin.Config.AutoDisableVoteRandom then
		local Enabled, VoteRandom = Shine:IsExtensionEnabled( "voterandom" )
		if VoteRandom and Enabled and not VoteRandom.Suspended then
			VoteRandom:Suspend()
			self.Logger:Info( "Plugin voterandom has been suspended." )
		end
		--Shared.ConsoleCommand("sh_unloadplugin voterandom")
		--Shared.ConsoleCommand("sh_suspendplugin voterandom")
	end
	if Plugin.Config.AutoReadyRoom then
		--this forces everyone to the ready room
		--Shared.ConsoleCommand("sh_rr *")
		-- Shine.mapvote:ForcePlayersIntoReadyRoom()
		local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )
		if Enabled then
			self.Logger:Info( "Server ForcePlayersIntoReadyRoom" )
			MapVote:ForcePlayersIntoReadyRoom()
		end
	end
	self:DestroyTimer("NeedOneMoreCaptain")
	
	-- Add 12 more bots for testing. We need the bots to add now so they get Ids generated in PlayerUpdate.
	--Shared.ConsoleCommand(string.format("addbot %d", 12))
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
	if not self.TestingCaptains then return end
	
	for team = 1, 2 do
		local team = self:GetCaptainIndex(self.TestingCaptainBots[team])
		if team ~= nil then
			local team2 = (team % 2) + 1
		
			local timerName = string.format("AutoPickTeam_%d", team)
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
						self:Notify( string.format( "Bot Captain team : %s Ready", team) , "green")
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
				self:Notify( string.format( "Bot Captain team : %s Ready", team) , "green")
				self.Ready[team] = true
				self:DestroyTimer(timerName)
				return
			end)
			
		end		
	end
				
end

function Plugin:Think( DeltaTime )
	local Time = Shared.GetTime()
	if self.NextRun and self.NextRun > Time then
		return
	end
	self.LastRun = Time
	self.NextRun = self.LastRun+ self.Delay

	-- Something wants to End captains.
	if (self.ProcessEndCaptains) then
		self.ProcessEndCaptains = false
		if self.Pending then
			self:EndCaptains()
		end
	end

end



Shine.LoadPluginModule( "logger.lua", Plugin )
