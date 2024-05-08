--[[
	Captains Mode voting.
		Addes Shine menu entry to allow users to run sh_votecaptain to activate or deactivate the Captains Mode mod.
]]

local Plugin = ...

Plugin.DependsOnPlugins = {
	"captainsmode"
}
Plugin.CaptainsMod = "captainsmode"

Plugin.Version = "0.1.1"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteCaptains.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
--Plugin.ShowLastVote = true  this reports incorrect last vote.

Plugin.VoteCommand = {
	ConCommand = "sh_votecaptain",
	ChatCommand = "votecaptain",
	Help = "Votes to toggle captains mode off and on."
}

local CAPTAINS_FEATURE = "Captains"
function Plugin:Initialise()
	local Enabled, Captains = Shine:IsExtensionEnabled( Plugin.CaptainsMod )
	if not Captains then
		return false, "Plugin \""..Plugin.CaptainsMod.."\" is required."
	elseif not Enabled and not Captains.Suspended then
		return false, "Plugin \""..Plugin.CaptainsMod.."\" is required."
	end

	-- Extract the current all-talk state.
	if Captains.Suspended then
		self.dt.IsEnabled = false
	else
		self.dt.IsEnabled = Captains:IsFeatureEnabled( CAPTAINS_FEATURE )
	end

	return self.BaseClass.Initialise( self )
end

function Plugin:GetVoteNotificationParams()
	return {
		VoteType = self.dt.IsEnabled and "DISABLE" or "ENABLE"
	}
end

function Plugin:OnVotePassed()
	local Enabled, Captains = Shine:IsExtensionEnabled( Plugin.CaptainsMod )
	if not Captains or not Enabled and not Captains.Suspended then 
		self.Logger:Trace( "Plugin %s is not loaded.", Plugin.CaptainsMod )
		return
	end

	local NewState = true 
	if not Enabled and Captains.Suspended then
		-- resume if it was Suspended.
		Captains:Resume()
	else
		NewState = not Captains:IsFeatureEnabled( CAPTAINS_FEATURE )
	end

	Captains:SetFeatureEnabled( CAPTAINS_FEATURE, NewState)
	Captains:NotifyFeatureState( CAPTAINS_FEATURE, NewState )	
end

function Plugin:OnCaptainsStateChange( Type, Enabled )
	if Type ~= CAPTAINS_FEATURE then return end

	self.dt.IsEnabled = Enabled
	self.Vote:Reset()
	self.Logger:Trace( "OnCaptainsStateChange %s", Enabled)

end

Shine.LoadPluginModule( "logger.lua", Plugin )