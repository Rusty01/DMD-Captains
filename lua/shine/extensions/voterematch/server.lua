--[[
	Rematch voting.
]]

local Plugin = ...

Plugin.DependsOnPlugins = {
	"rematch"
}

Plugin.Version = "0.1.1"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteRematch.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
--Plugin.ShowLastVote = true  this reports incorrect last vote.

Plugin.VoteCommand = {
	ConCommand = "sh_voterematch",
	ChatCommand = "voterematch",
	Help = "Votes to trigger a rematch."
}

local REMATCH_TYPE = "Rematch"
function Plugin:Initialise()
	local Enabled, Rematch = Shine:IsExtensionEnabled( "rematch" )
	if not ( Enabled and Rematch ) then return false, "Plugin \"rematch\" is required."  end

	-- Extract the current all-talk state.
	self.dt.IsEnabled = Rematch:IsRematchEnabled( REMATCH_TYPE )

	return self.BaseClass.Initialise( self )
end

function Plugin:GetVoteNotificationParams()
	return {
		VoteType = self.dt.IsEnabled and "DISABLE" or "ENABLE"
	}
end

function Plugin:OnVotePassed()
	local Enabled, Rematch = Shine:IsExtensionEnabled( "rematch" )
	if not Enabled then
		return
	end

	local NewState = not Rematch:IsRematchEnabled( REMATCH_TYPE )

	Rematch:SetRematchEnabled( REMATCH_TYPE, NewState)
	Rematch:NotifyRematchState( REMATCH_TYPE, NewState )
end

function Plugin:OnRematchStateChange( Type, Enabled )
	if Type ~= REMATCH_TYPE then return end

	self.dt.IsEnabled = Enabled
	self.Vote:Reset()
end
