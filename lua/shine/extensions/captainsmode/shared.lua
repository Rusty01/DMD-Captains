local Plugin = {}
Plugin.Version = "0.9.1"
Plugin.HasConfig = true
Plugin.ConfigName = "CaptainsMode.json"

Plugin.DefaultConfig = {
    AutoRemoveBots = true,
    AutoDisableVoteRandom = true,
    AutoReadyRoom = true,
    AutoDisableSelf = true,
    AnnouncePlayerNames = true,
    ShowMarineAlienToCaptains = true,
    CountdownSeconds = 60
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.CheckConfigRecursively = false
Plugin.DefaultState = false
Plugin.NS2Only = true

function Plugin:SetupDataTable()
    -- team: 0 = unavailable for picking, 1 = team 1, 2 = team 2, 3 = available for picking
    local PlayerStatus = {
        steamid = "string (255)",
        name = "string (255)",
        skill = "integer",
        team = "integer"
    }
    self:AddNetworkMessage("PlayerStatus", PlayerStatus, "Client")

    self:AddNetworkMessage("PickPlayer", {steamid = "string (255)"}, "Server")
    self:AddNetworkMessage("CaptainTurn", {turn = "boolean"}, "Client")

    self:AddNetworkMessage("StartCaptains", {team1marines = "boolean"}, "Client")
    self:AddNetworkMessage("EndCaptains", {}, "Client")
    self:AddNetworkMessage("RequestEndCaptains", {}, "Server")

    self:AddNetworkMessage("SetTeamName", {teamname = "string (255)"}, "Server")
    self:AddNetworkMessage("TeamName", {team = "integer", teamname = "string (255)"}, "Client")
    self:AddNetworkMessage("SetReady", {ready = "boolean"}, "Server")

    self:AddNetworkMessage("PickNotification", {text = "string (255)"}, "Client")
    self:AddNetworkMessage("TeamNamesNotification", {marines = "string (255)", aliens = "string (255)"}, "Client")
    self:AddNetworkMessage("CountdownNotification", {text = "string (255)"}, "Client")
end

Shine:RegisterExtension("captainsmode", Plugin)
