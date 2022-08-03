local Plugin = Plugin
local Shine = Shine

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
        local Player = Client:GetControllingPlayer()
        local PlayerName = Player:GetName()

        -- If there is a game in progress, deny it.
        local Gamerules = GetGamerules()
        if Gamerules:GetGameStarted() then
            Shine:Notify(Client, ChatName, PlayerName, "A game has already started.")
            return
        end

        -- Check if the player is already a captain.
        if self:GetCaptainIndex(Client) then
            Shine:Notify(Client, ChatName, PlayerName, "You are already a captain.")
            return
        end

        if #self.Captains < 2 then
            table.insert(self.Captains, Client)
            self:Notify(PlayerName .. " is now a captain.", "green")
        else
            Shine:Notify(Client, ChatName, PlayerName, "There are already 2 captains.")
            return
        end

        -- If this is the second captain, we start the pick process.
        if #self.Captains > 1 then
            self:StartCaptains()

            -- Cancel the adverts
            Shine.Timer.Destroy("NeedOneMoreCaptain")

            return
        end

        -- If we have only one captain, notify everyone that we need one more.
        if #self.Captains == 1 then
            self:Notify("To appoint yourself as captain, type !captain")
            Shine.Timer.Create(
                "NeedOneMoreCaptain",
                20,
                -1,
                function(Timer)
                    local CaptainName = self.Captains[1]:GetControllingPlayer():GetName()
                    self:Notify("Need one more captain to start picking players.", "yellow")
                    self:Notify("To appoint yourself as captain, type !captain")
                    self:Notify(string.format("Current captain: %s", CaptainName))
                end
            )
        end
    end

    local CaptainCommand = self:BindCommand("sh_cm_captain", "captain", Captain, true)
    CaptainCommand:Help("Make yourself a captain.")

    local function Cancel(Client)
        local Player = Client:GetControllingPlayer()
        local PlayerName = Player and Player:GetName() or "Console"
        self:EndCaptains()
        self:Notify(string.format("Captains mode was cancelled by %s.", PlayerName), "red")
    end
    local CaptainCommand = self:BindCommand("sh_cm_cancel", "cancelcaptains", Cancel)
    CaptainCommand:Help("Cancel captains mode.")
end

function Plugin:Initialise()
    self:ResetState()
    self:CreateCommands()

    return true
end

function Plugin:ResetState()
    self.Captains = {}
    self.TeamNames = {"Marines", "Aliens"}
    self.Ready = {false, false}

    self.CaptainFirstTurn = nil
    self.CaptainTurn = nil
    self.InProgress = false
    self.Players = {}

    if math.random(0, 1) == 1 then
        self.Team1IsMarines = true
    else
        self.Team1IsMarines = false
    end

    Shine.Timer.Destroy("NeedOneMoreCaptain")
end

function Plugin:GetCaptainIndex(Client)
    local CaptainIndex = nil
    for Index, CaptainClient in pairs(self.Captains) do
        if CaptainClient == Client then
            CaptainIndex = Index
        end
    end
    return CaptainIndex
end

function Plugin:StartCaptains()
    local GameIDs = Shine.GameIDs

    if Plugin.Config.AutoRemoveBots then
        Shared.ConsoleCommand(string.format("sv_maxbots %d", 0))
    end
    if Plugin.Config.AutoDisableVoteRandom then
        Shared.ConsoleCommand("sh_disableplugin voteRandom")
    end
    if Plugin.Config.AutoReadyRoom then
        Shared.ConsoleCommand("sh_rr *")
    end

    self.InProgress = true
    self:Notify("Captains mode has started!", "yellow")

    local Captain1Name = self.Captains[1]:GetControllingPlayer():GetName()
    local Captain2Name = self.Captains[2]:GetControllingPlayer():GetName()
    self:Notify(string.format("Please wait while %s and %s pick teams.", Captain1Name, Captain2Name))

    for Client, ID in GameIDs:Iterate() do
        local SteamID = Client:GetUserId()
        local Player = Client:GetControllingPlayer()
        local PlayerName = Player:GetName()

        -- TeamNumber is used for the captain's picking process. See shared.lua
        -- Make spectators not available for picking.
        local TeamNumber
        if Player:GetTeamNumber() ~= 3 then
            TeamNumber = 3
        else
            TeamNumber = 0
        end

        local CaptainIndex = self:GetCaptainIndex(Client)
        if CaptainIndex then
            TeamNumber = CaptainIndex
        end

        local Skill = Player:GetPlayerSkill()
        local Data = {steamid = SteamID, name = PlayerName, skill = Skill, team = TeamNumber}
        self:Notify(Data)
        self.Players[SteamID] = Data
        self:SendNetworkMessage(self.Captains, "PlayerStatus", Data, true)
    end

    self:SendNetworkMessage(self.Captains, "StartCaptains", {team1marines = self.Team1IsMarines}, true)

    local Cap1Skill = self.Captains[1]:GetControllingPlayer():GetPlayerSkill()
    local Cap2Skill = self.Captains[2]:GetControllingPlayer():GetPlayerSkill()

    -- Decide who picks first based on hiveskill
    if Cap1Skill > Cap2Skill then
        self.CaptainTurn = self.Captains[2]
        self.CaptainFirstTurn = 2
        self:SendNetworkMessage(self.Captains[1], "CaptainTurn", {turn = false}, true)
        self:SendNetworkMessage(self.Captains[2], "CaptainTurn", {turn = true}, true)
    else
        self.CaptainTurn = self.Captains[1]
        self.CaptainFirstTurn = 1
        self:SendNetworkMessage(self.Captains[1], "CaptainTurn", {turn = true}, true)
        self:SendNetworkMessage(self.Captains[2], "CaptainTurn", {turn = false}, true)
    end
    local CaptainName = self.CaptainTurn:GetControllingPlayer():GetName()
    self:Notify(CaptainName .. " picks first.", "green")
end

function Plugin:ReceiveSetTeamName(Client, Data)
    local CaptainIndex = self:GetCaptainIndex(Client)
    if CaptainIndex then
        local TeamName = Data.teamname
        self.TeamNames[CaptainIndex] = TeamName
        self:SendNetworkMessage(self.Captains, "TeamName", {team = CaptainIndex, teamname = TeamName}, true)
        Shared.ConsoleCommand(string.format("sh_setteamname %s %s", CaptainIndex, TeamName))
    end
end

function Plugin:ReceiveSetReady(Client, Data)
    local Team = self:GetCaptainIndex(Client)
    local Ready = Data.ready
    local PlayerName = Client:GetControllingPlayer():GetName()

    if Team then
        self.Ready[Team] = Data.ready
        if Ready then
            self:Notify(PlayerName .. "'s team is ready.", "green")
        else
            self:Notify(PlayerName .. "'s team is not ready.", "red")
        end
    end

    if self.Ready[1] and self.Ready[2] then
        local Gamerules = GetGamerules()

        local Teams
        if self.Team1IsMarines then
            Teams = {1, 2}
        else
            Teams = {2, 1}
        end

        -- Start the game
        for SteamID, Player in pairs(self.Players) do
            if Player.team == 1 or Player.team == 2 then
                local PlayerObj = Shine.GetClientByNS2ID(SteamID):GetControllingPlayer()
                Gamerules:JoinTeam(PlayerObj, Teams[Player.team], true, true)
            end
        end

        -- Just close the GUI for now but don't reset state
        self:SendNetworkMessage(self.Captains, "EndCaptains", {}, true)

        self:StartGame()
    end
end

function Plugin:StartGame()
    local Gamerules = GetGamerules()
    local Seconds = Plugin.Config.CountdownSeconds

    Shine.Timer.Create(
        "GameStartCountdown",
        1,
        Seconds,
        function(Timer)
            Seconds = Seconds - 1
            self:SendNetworkMessage(
                nil,
                "CountdownNotification",
                {text = string.format("Game will start in %s seconds", Seconds)},
                true
            )
            if Seconds == 0 then
                Gamerules:ResetGame()
                Gamerules:SetGameState(kGameState.Countdown)
                Gamerules.countdownTime = kCountDownLength
                Gamerules.lastCountdownPlayed = nil

                local MarinesTeamName
                local AliensTeamName
                if self.Team1IsMarines then
                    MarinesTeamName = self.TeamNames[1]
                    AliensTeamName = self.TeamNames[2]
                else
                    MarinesTeamName = self.TeamNames[2]
                    AliensTeamName = self.TeamNames[1]
                end

                self:SendNetworkMessage(
                    nil,
                    "TeamNamesNotification",
                    {marines = MarinesTeamName, aliens = AliensTeamName},
                    true
                )
            end
        end
    )

    local Players, Count = Shine.GetAllPlayers()
    for i = 1, Count do
        local Player = Players[i]
        if Player.ResetScores then
            Player:ResetScores()
        end
    end
end

function Plugin:EndCaptains()
    self:SendNetworkMessage(self.Captains, "EndCaptains", {}, true)
    self:ResetState()
 
    if Plugin.Config.AutoRemoveBots then
        Shared.ConsoleCommand(string.format("sv_maxbots %d", 12))
    end
    if Plugin.Config.AutoDisableVoteRandom then
        Shared.ConsoleCommand("sh_enableplugin voteRandom")
    end
    if Plugin.Config.AutoDisableSelf then
        Shared.ConsoleCommand("sh_disableplugin captainsmode")
    end
end

function Plugin:ReceiveRequestEndCaptains(Client, Data)
    if self:GetCaptainIndex(Client) then
        local PlayerName = Client:GetControllingPlayer():GetName()
        self:Notify("Captains mode was cancelled by " .. PlayerName .. ".", "yellow")
        self:EndCaptains()
    end
end

function Plugin:ReceivePickPlayer(Client, Data)
    -- Check the client is a captain and it's his turn
    local CaptainIndex = self:GetCaptainIndex(Client)
    if not CaptainIndex or Client ~= self.CaptainTurn then
        return
    end

    -- Update local players table
    local Pick = self.Players[tonumber(Data.steamid)]
    Pick.team = CaptainIndex

    -- Send pick to captains
    self:SendNetworkMessage(self.Captains, "PlayerStatus", Pick, true)

    local CaptainName = Client:GetControllingPlayer():GetName()
    local PickMsg
    if Plugin.Config.AnnouncePlayerNames then
        PickMsg = CaptainName .. " picks " .. Pick.name .. "."
    else
        PickMsg = CaptainName .. " has picked a player."
    end

    self:Notify(PickMsg)
    self:SendNetworkMessage(nil, "PickNotification", {text = PickMsg}, true)

    -- Turn logic
    local TeamCount = {0, 0}

    for SteamID, Player in pairs(self.Players) do
        if Player.team == 1 then
            TeamCount[1] = TeamCount[1] + 1
        end
        if Player.team == 2 then
            TeamCount[2] = TeamCount[2] + 1
        end
    end

    local CaptainTurnIndex
    if self.CaptainFirstTurn == 1 then
        if TeamCount[1] > TeamCount[2] and CaptainIndex == 1 then
            CaptainTurnIndex = 2
        end
        if TeamCount[2] >= TeamCount[1] and CaptainIndex == 2 then
            CaptainTurnIndex = 1
        end
    else
        if TeamCount[1] >= TeamCount[2] and CaptainIndex == 1 then
            CaptainTurnIndex = 2
        end
        if TeamCount[2] > TeamCount[1] and CaptainIndex == 2 then
            CaptainTurnIndex = 1
        end
    end
    self.CaptainTurn = self.Captains[CaptainTurnIndex]

    if CaptainTurnIndex == 1 then
        self:SendNetworkMessage(self.Captains[2], "CaptainTurn", {turn = false}, true)
        self:SendNetworkMessage(self.Captains[1], "CaptainTurn", {turn = true}, true)
    else
        self:SendNetworkMessage(self.Captains[2], "CaptainTurn", {turn = true}, true)
        self:SendNetworkMessage(self.Captains[1], "CaptainTurn", {turn = false}, true)
    end
end

function Plugin:JoinTeam(_, Player, NewTeam, Force, ShineForce)
    if self.InProgress then
        local SteamID = Player:GetClient():GetUserId()

        -- Toggle availability when joining or leaving spectator team
        local TeamNumber
        if NewTeam == 3 then
            TeamNumber = 0
        elseif self.Players[SteamID].team == 0 then
            TeamNumber = 3
        else
            return
        end

        self.Players[SteamID].team = TeamNumber

        self:SendNetworkMessage(self.Captains, "PlayerStatus", self.Players[SteamID], true)
    end
end

function Plugin:SetGameState(Gamerules, State, OldState)
    if State == kGameState.Started then
        self:EndCaptains()
    end
end

-- Cancel captains mode if a captain quits the game
function Plugin:ClientDisconnect(Client)
    local SteamID = Client:GetUserId()
    if self.InProgress then
        if self:GetCaptainIndex(Client) then
            local PlayerName = Client:GetControllingPlayer():GetName()
            self:Notify("Captains mode was cancelled because " .. PlayerName .. " has left the game.", "red")
            self:EndCaptains()
        end

        local Player = self.Players[SteamID]
        Player.team = 0
        self:SendNetworkMessage(self.Captains, "PlayerStatus", Player, true)
    end
end

function Plugin:Cleanup()
    self.BaseClass.Cleanup(self)
    Print "Disabling server plugin..."
end
