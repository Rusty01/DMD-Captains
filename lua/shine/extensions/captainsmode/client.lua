local Plugin = Plugin
local Shine = Shine
local SGUI = Shine.GUI

local CaptainMenu = {}
local Players = {}
local TeamNames = {"Marines", "Aliens"}
local IsReady = false
local MyTurn = false
local Team1IsMarines = true

function Plugin:OnFirstThink()
	self:CallModuleEvent("OnFirstThink")
end

function CaptainMenu:Create()
	if self.Created then
		return
	end

	local ScreenWidth = Client.GetScreenWidth()
	local ScreenHeight = Client.GetScreenHeight()

	local Window = SGUI:Create("TabPanel")

	self.Window = Window

	Window:SetIsVisible(false)
	Window:SetAnchor("TopLeft")
	Window:SetSize(Vector(ScreenWidth * 0.6, ScreenHeight * 0.8, 0))
	Window:SetPos(Vector(ScreenWidth * 0.3, ScreenHeight * 0.1, 0))

	Window:CallOnRemove(
		function()
			if self.IgnoreRemove then
				return
			end

			if self.Visible then
				-- Make sure mouse is disabled in case of error.
				SGUI:EnableMouse(false)
				self.Visible = false
			end

			self.Created = false
			self.Window = nil
		end
	)

	self.Window = Window

	local PanelSize = Vector(ScreenWidth * 0.6 - 128, ScreenHeight * 0.8, 0)
	Window:AddTab(
		"Pick",
		function(Panel)
			local ListTitlePanel = Panel:Add("Panel")
			ListTitlePanel:SetAnchor("TopLeft")
			ListTitlePanel:SetSize(Vector(PanelSize.x * 0.96, PanelSize.y * 0.05, 0))
			ListTitlePanel:SetPos(Vector(PanelSize.x * 0.02, PanelSize.y * 0.02, 0))

			local ListTitleText = ListTitlePanel:Add("Label")
			ListTitleText:SetAnchor("CentreMiddle")
			ListTitleText:SetFont(Fonts.kAgencyFB_Small)
			ListTitleText:SetText("Players available for picking")
			ListTitleText:SetTextAlignmentX(GUIItem.Align_Center)
			ListTitleText:SetTextAlignmentY(GUIItem.Align_Center)

			PickList = Panel:Add("List")
			PickList:SetAnchor("TopLeft")
			PickList:SetSize(Vector(PanelSize.x * 0.96, PanelSize.y * 0.74, 0))
			PickList:SetPos(Vector(PanelSize.x * 0.02, PanelSize.y * 0.09, 0))
			PickList:SetColumns("NS2ID", "Name", "Skill")
			PickList:SetSpacing(0.3, 0.55, 0.15)
			PickList:SetNumericColumn(1)
			PickList:SetNumericColumn(2)
			PickList.TitlePanel = ListTitlePanel
			PickList.TitleText = ListTitleText

			local CommandPanel = Panel:Add("Panel")
			CommandPanel:SetSize(Vector(PanelSize.x, PanelSize.y * 0.13, 0))
			CommandPanel:SetPos(Vector(0, PanelSize.y * 0.85, 0))

			local CommandPanelSize = CommandPanel:GetSize()

			local Turn = CommandPanel:Add("Label")
			Turn:SetFont(Fonts.kAgencyFB_Large)
			ListTitleText:SetAnchor("CentreMiddle")
			Turn:SetPos(Vector(CommandPanelSize.x * 0.02, CommandPanelSize.y * 0.30, 0))
			Turn:SetBright(true)

			local Pick = CommandPanel:Add("Button")
			Pick:SetFont(Fonts.kAgencyFB_Large)
			Pick:SetSize(Vector(CommandPanelSize.x * 0.2, CommandPanelSize.y, 0))
			Pick:SetPos(Vector(CommandPanelSize.x * 0.78, 0, 0))
			Pick:SetText("Pick")
			Pick:SetEnabled(false)

			if MyTurn then
				Turn:SetColour(Colour(0, 1, 0, 1))
				Turn:SetText("Your turn.")
				Pick:SetIsVisible(true)
			else
				Turn:SetColour(Colour(1, 1, 1, 1))
				Turn:SetText("Waiting for another captain...")
				Pick:SetIsVisible(false)
			end

			function PickList:OnRowSelected(Index, Row)
				Pick:SetEnabled(true)
			end

			function PickList:OnRowDeselected(Index, Row)
				Pick:SetEnabled(false)
			end

			function Pick.DoClick()
				local Row = PickList:GetSelectedRow()
				local SteamID = Row:GetColumnText(1)
				Plugin:SendNetworkMessage("PickPlayer", {steamid = SteamID}, true)
			end

			for Index, Player in ipairs(Players) do
				if Player.team == 3 then
					PickList:AddRow(Player.steamid, Player.name, Player.skill)
				end
			end
		end
	)

	Window:AddTab(
		"Teams",
		function(Panel)
			local ListItems = {}

			local TeamStrings
			if Team1IsMarines then
				TeamStrings = {"Marines", "Aliens"}
			else
				TeamStrings = {"Aliens", "Marines"}
			end

			for i = 0, 1 do
				local ListTitlePanel = Panel:Add("Panel")
				ListTitlePanel:SetSize(Vector(PanelSize.x * 0.47, PanelSize.y * 0.05, 0))
				ListTitlePanel:SetAnchor("TopLeft")
				ListTitlePanel.Pos = Vector(PanelSize.x * (0.02 + 0.47 * i) + PanelSize.x * 0.02 * i, PanelSize.y * 0.02, 0)
				ListTitlePanel:SetPos(ListTitlePanel.Pos)

				local ListTitleText = ListTitlePanel:Add("Label")
				ListTitleText:SetAnchor("CentreMiddle")
				ListTitleText:SetFont(Fonts.kAgencyFB_Small)
				ListTitleText:SetTextAlignmentX(GUIItem.Align_Center)
				ListTitleText:SetTextAlignmentY(GUIItem.Align_Center)

				if Plugin.Config.ShowMarineAlienToCaptains then
					ListTitleText:SetText(string.format("%s (%s)", TeamNames[i + 1], TeamStrings[i + 1]))
				else
					ListTitleText:SetText(string.format("%s", TeamNames[i + 1]))
				end

				local List = Panel:Add("List")
				List:SetAnchor("TopLeft")
				List.Pos = Vector(PanelSize.x * (0.02 + 0.47 * i) + PanelSize.x * 0.02 * i, PanelSize.y * 0.09, 0)
				List:SetPos(List.Pos)
				List:SetColumns("Name", "Skill")
				List:SetSpacing(0.7, 0.3)
				List:SetSize(Vector(PanelSize.x * 0.47, PanelSize.y * 0.69, 0))
				List:SetNumericColumn(1)
				List:SetNumericColumn(2)
				List.ScrollPos = Vector(0, 32, 0)
				List.TitlePanel = ListTitlePanel
				List.TitleText = ListTitleText

				ListItems[i] = List
			end

			local TeamName = Panel:Add("Button")
			TeamName:SetFont(Fonts.kAgencyFB_Small)
			TeamName:SetSize(Vector(PanelSize.x * 0.3, PanelSize.y * 0.06, 0))
			TeamName:SetPos(Vector(PanelSize.x * 0.35, PanelSize.y * 0.80, 0))
			TeamName:SetText("Team Name")

			function TeamName.DoClick()
				self:AskforTeamName()
			end

			local Ready = Panel:Add("Button")
			Ready:SetFont(Fonts.kAgencyFB_Large)
			Ready:SetSize(Vector(PanelSize.x * 0.3, PanelSize.y * 0.1, 0))
			Ready:SetPos(Vector(PanelSize.x * 0.35, PanelSize.y * 0.88, 0))
			Ready:SetText("Ready")

			function Ready.DoClick()
				if IsReady then
					IsReady = false
					Ready:SetText("Ready")
				else
					IsReady = true
					Ready:SetText("Not Ready")
				end
				Plugin:SendNetworkMessage("SetReady", {ready = IsReady}, true)
			end

			for Index, Player in ipairs(Players) do
				if Player.team == 1 then
					ListItems[0]:AddRow(Player.name, Player.skill)
				elseif Player.team == 2 then
					ListItems[1]:AddRow(Player.name, Player.skill)
				end
			end
		end
	)

	Window:AddTab(
		"Misc",
		function(Panel)
			local Cancel = Panel:Add("Button")
			Cancel:SetFont(Fonts.kAgencyFB_Large)
			Cancel:SetSize(Vector(PanelSize.x * 0.3, PanelSize.y * 0.1, 0))
			Cancel:SetPos(Vector(PanelSize.x * 0.35, PanelSize.y * 0.45, 0))
			Cancel:SetText("Cancel Captains")

			function Cancel.DoClick()
				Plugin:SendNetworkMessage("RequestEndCaptains", {}, true)
			end
		end
	)

	self.Created = true
end

function CaptainMenu:AskforTeamName()
	if self.TeamNameCreated then
		return
	end

	local Window = SGUI:Create("Panel")
	local ScreenHeight = Client.GetScreenHeight()
	Window:SetAnchor("CentreMiddle")
	Window:SetSize(Vector(400, 200, 0))
	Window:SetPos(Vector(-200, -ScreenHeight / 2 + ScreenHeight * 0.02, 0))

	Window:AddTitleBar("Team name")

	function Window.CloseButton.DoClick()
		Shine.AdminMenu:DontDestroyOnClose(Window)
		Window:Destroy()
		self.TeamNameCreated = false
	end

	local Label = SGUI:Create("Label", Window)
	Label:SetAnchor("CentreMiddle")
	Label:SetFont(Fonts.kAgencyFB_Small)
	Label:SetBright(true)
	Label:SetText("Please type in your new teamname.")
	Label:SetPos(Vector(0, -40, -25))
	Label:SetTextAlignmentX(GUIItem.Align_Center)
	Label:SetTextAlignmentY(GUIItem.Align_Center)

	local Input = SGUI:Create("TextEntry", Window)
	Input:SetAnchor("CentreMiddle")
	Input:SetFont(Fonts.kAgencyFB_Small)
	Input:SetPos(Vector(-160, -5, 0))
	Input:SetSize(Vector(320, 32, 0))

	local OK = SGUI:Create("Button", Window)
	OK:SetAnchor("CentreMiddle")
	OK:SetSize(Vector(128, 32, 0))
	OK:SetPos(Vector(-64, 40, 0))
	OK:SetFont(Fonts.kAgencyFB_Small)
	OK:SetText("OK")

	self.TeamNameCreated = true

	function OK.DoClick()
		local Text = Input:GetText()
		if Text and Text:len() > 0 then
			Plugin:SendNetworkMessage("SetTeamName", {teamname = Text}, true)
		end
		Window:Destroy()
		self.TeamNameCreated = false
	end
end

function Plugin:Initialise()
	CaptainMenu:Create()

	self.Enabled = true

	return true
end

function Plugin:ReceivePlayerStatus(Data)
	-- Upsert player to local table
	local Exists = false
	for Index, Player in ipairs(Players) do
		if Player.steamid == Data.steamid then
			Players[Index] = Data
			Exists = true
		end
	end
	if not Exists then
		table.insert(Players, Data)
	end

	self:UpdateCaptainMenu()
end

function Plugin:UpdateCaptainMenu(Data)
	-- Rerun the init function to update the view with the new data.
	-- Probably hacky
	CaptainMenu.Window.ContentPanel:Clear()
	CaptainMenu.Window.Tabs[CaptainMenu.Window.ActiveTab].OnPopulate(CaptainMenu.Window.ContentPanel)
end

function Plugin:ResetState()
	Players = {}
	TeamNames = {"Marines", "Aliens"}
	IsReady = false
	MyTurn = false
end

function Plugin:ReceiveStartCaptains(Data)
	Team1IsMarines = Data.team1marines
	CaptainMenu.Window:SetIsVisible(true)
	SGUI:EnableMouse(true)
end

function Plugin:ReceiveEndCaptains(Data)
	Plugin:ResetState()
	CaptainMenu.Window:SetIsVisible(false)
	SGUI:EnableMouse(false)
end

function Plugin:ReceiveCaptainTurn(Data)
	MyTurn = Data.turn
	self:UpdateCaptainMenu()
end

function Plugin:ReceivePickNotification(Data)
	Client.WindowNeedsAttention()

	StartSoundEffect("sound/NS2.fev/common/ping")
	-- StartSoundEffect("sound/NS2.fev/common/tooltip_off")

	Shine.ScreenText.Add(
		"PickNotification",
		{
			X = 0.5,
			Y = 0.4,
			Text = Data.text,
			Duration = 2,
			R = 255,
			G = 255,
			B = 255,
			Alignment = 1,
			Size = 3,
			FadeIn = 1
		}
	)
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

function Plugin:ReceiveTeamNamesNotification(Data)
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

function Plugin:ReceiveTeamName(Data)
	TeamNames[Data.team] = Data.teamname
	self:UpdateCaptainMenu()
end

function Plugin:Cleanup()
	self.BaseClass.Cleanup(self)

	CaptainMenu.Window:Destroy()
end
