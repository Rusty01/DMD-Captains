--[[
	Rematch client
]]

local Plugin = ...

local Shine = Shine
local SGUI = Shine.GUI
local StringFormat = string.format



function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )

	self.Enabled = true
	self:ResetState()

	self:SetTeamNames()

	return true
end


function Plugin:ResetState()
	self.Logger:Trace( "Reset State")

	--self.Players = {}
	-- self.QueuePlayerUpdate = false

	self.Team1IsMarines = true
	self.TeamStrings = {"Marines", "Aliens"}
	self.TeamNames = {"Marines", "Aliens"}
	--self.CaptainNames = {"One","Two"}
	self:ResetTeamNames( )

	self.MatchStart = false
	self.ClientInProgress = false

end



function Plugin:NetworkUpdate( Key, Old, New )
	self.Logger:Trace( "NetworkUpdate %s %s %s", Key, Old, New )

	if Key == "Team1Name" then
		self.TeamNames[1] = self.dt.Team1Name
		self.DoTeamNameChange = true
	elseif Key == "Team2Name" then
		self.TeamNames[2] = self.dt.Team2Name
		self.DoTeamNameChange = true
	end
end


function Plugin:Cleanup()
	self.Logger:Debug( "Plugin:Cleanup" )
	self:ResetTeamNames( )
	self.BaseClass.Cleanup(self)
end


function Plugin:ReceiveRematchMatchStart(Data)
	self.Logger:Debug( "ReceiveRematchMatchStart" )
	-- when the match starts.. remove stuff.
	self.MatchStart = true
end

function Plugin:ReceiveRematchMatchComplete(Data)
	self.Logger:Debug( "ReceiveRematchMatchComplete" )
	self:ResetState()
end

function Plugin:ReceiveRematchEnd(Data)
	self.Logger:Debug( "ReceiveRematchEnd" )
	self:ResetState()
end



function Plugin:OnFirstThink()
	self:CallModuleEvent("OnFirstThink")
	self.Delay = 0.5
	self.LastRun = Shared.GetTime()
	self.NextRun = self.LastRun+ self.Delay

	self.DoTeamNameChange = false

	Shine.Hook.SetupClassHook( "GUIScoreboard", "UpdateTeam", "Rematch_GUIScoreboardUpdateTeam", "PassivePost")

end


function Plugin:OnSuspend()
	--self:Disable()
	print("client: Plugin:OnSuspend")
end
function Plugin:OnResume()
	print("client: Plugin:OnResume")
end


function Plugin:Think( DeltaTime )
	if self.dt.Suspended then return end

	local Time = Shared.GetTime()
	if self.NextRun > Time then
		return
	end
	self.LastRun = Time
	self.NextRun = self.LastRun+ self.Delay

	if (self.ProcessUnsetReady == true ) then
		self.ProcessUnsetReady = false
		self:OnUnsetReady()
	end


	-- if (self.QueuePlayerUpdate == true ) then
	-- 	self.QueuePlayerUpdate = false
	-- 	self:UpdatePlayers()
	-- end

	-- if (self.SoldierLost == true ) then
	-- 	self.SoldierLost = false
	-- 	StartSoundEffect("sound/NS2.fev/marine/voiceovers/soldier_lost", 5)
	-- end

	if (self.DoTeamNameChange == true ) then
		self.DoTeamNameChange = false
		self:SetTeamNames()
	end


end



function Plugin:Rematch_GUIScoreboardUpdateTeam(  scoreboard, updateTeam  )
	if self.dt.Suspended then return end

	--Plugin._GUIScoreboardUpdateTeam(scoreboard, updateTeam)
	local teamNameGUIItem = updateTeam["GUIs"]["TeamName"]
	local teamScores = updateTeam["GetScores"]()
	local teamNumber = updateTeam["TeamNumber"]

	if not (teamNumber == 1 or teamNumber == 2) then return end
	if not self.MatchStart then return end

	local originalHeaderText = teamNameGUIItem:GetText()
	local newTeamName = self.TeamNames[teamNumber]
	local teamHeaderText

	local teamNameText = Locale.ResolveString(string.format("NAME_TEAM_%s", updateTeam["TeamNumber"]))
	teamHeaderText = string.gsub(originalHeaderText, teamNameText, newTeamName )

--	-- How many items per player.
--	local numPlayers = table.icount(teamScores)
--	-- Update the team name text.
--	local playersOnTeamText = string.format("%d %s", numPlayers, numPlayers == 1 and Locale.ResolveString("SB_PLAYER") or Locale.ResolveString("SB_PLAYERS"))
--	local teamHeaderText
--	teamHeaderText = string.format("%s (%s)", teamNameText, playersOnTeamText)

	teamNameGUIItem:SetText(teamHeaderText)

end


function Plugin:ReceiveCountdownNotification(Data)
	Shine.ScreenText.Add(
		"Notification",
		{
			X = 0.5,
			Y = 0.4,
			Text = Data.text,
			Duration = 1,
			R = 255,
			G = 255,
			B = 255,
			Alignment = 1,
			Size = 3,
			FadeIn = 0.2
		}
	)
end

function Plugin:ResetTeamNames()

	Shared.ConsoleCommand( "teams \"reset\"" )

end

function Plugin:SetTeamNames( MarineName, AlienName )

	if MarineName == nil
	or AlienName == nil then
		Shared.ConsoleCommand( StringFormat( "teams \"%s\" \"%s\"", self.TeamNames[1], self.TeamNames[2] ) )
		self.Logger:Info( "Rematch: teams \"%s\" \"%s\"" , self.TeamNames[1], self.TeamNames[2] )
		return
	end

	if MarineName == "" and AlienName == "" then return end

	Shared.ConsoleCommand( StringFormat( "teams \"%s\" \"%s\"", MarineName, AlienName ) )

	self.Logger:Info( "Rematch: teams \"%s\" \"%s\"" , MarineName, AlienName)

end


function Plugin:ReceiveTeamNamesNotification(Data)

	self.Logger:Info( "ReceiveTeamNamesNotification: teams \"%s\" \"%s\"" , Data.marines,Data.aliens)

	self:SetTeamNames(Data.marines,Data.aliens)

	Shine.ScreenText.Add(
		"MarinesTeamName",
		{
			X = 0.5,
			Y = 0.45,
			Text = Data.marines,
			Duration = 5,
			R = 0,
			G = 148,
			B = 255,
			Alignment = 1,
			Size = 3,
			FadeIn = 1
		}
	)
	Shine.ScreenText.Add(
		"Versus",
		{
			X = 0.5,
			Y = 0.5,
			Text = "vs",
			Duration = 5,
			R = 255,
			G = 255,
			B = 255,
			Alignment = 1,
			Size = 3,
			FadeIn = 1
		}
	)
	Shine.ScreenText.Add(
		"AliensTeamName",
		{
			X = 0.5,
			Y = 0.55,
			Text = Data.aliens,
			Duration = 5,
			R = 255,
			G = 136,
			B = 0,
			Alignment = 1,
			Size = 3,
			FadeIn = 1
		}
	)
end


Shine.LoadPluginModule( "logger.lua", Plugin )
