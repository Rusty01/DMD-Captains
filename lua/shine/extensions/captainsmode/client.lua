--[[
	Captains Mode client.
]]

local Plugin = ...

local Shine = Shine
local SGUI = Shine.GUI
local StringFormat = string.format
local TableConcat = table.concat
local TableCopy = table.Copy
local Max = math.max;


function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )

	if Plugin.Config.ShowMarineAlienToCaptains then
		self.DefaultTeamNames = {"Marines", "Aliens"}
	else
		self.DefaultTeamNames = {"Team1", "Team2"}
	end
	
	self.CaptainOptions = nil
	self.Enabled = true
	self:ResetState()

	self.Window = nil
	self.Created = false
	self:CaptainMenuReset()

	self:SetTeamNames()

	return true
end


function Plugin:ResetState()
	self.Logger:Trace( "Reset State")

	self.Players = {}
	self.IsReady = false
	self.QueuePlayerUpdate = false
	self.QueuePickCompleteCheck = false

	self.myPickid = ""
	self.otherTeam = 0
	self.myTeam = 0
	self.myTeamName = ""
	self.myTeamReady = false
	self.mySwapRequest = false

	self.Team1IsMarines = true
	self.TeamSwap = {false, false}
	self.TeamStrings = TableCopy( self.DefaultTeamNames )
	self.TeamIndex = {1, 2}
	self.TeamNames = TableCopy( self.DefaultTeamNames )
	self.CaptainNames = {"One","Two"}
	self:ResetTeamNames( )

	--self.TeamNames[1] = self.dt.Team1Name
	--self.TeamNames[2] = self.dt.Team2Name
	--self:SetTeamNames(Data.marines,Data.aliens)

	self.MatchStart = false
	self.ClientInProgress = false

end


function Plugin:CaptainMenuReset()
	self.Logger:Debug( "Reset Menu")

	self.myGUIObjs = nil

	self.PickListSort = {SortedColumn = 2, Descending = false}
	self.PickList = nil
	self.PickRows = {}
	self.PickRowsCount = 0

	self.TeamList = {}
	self.TeamListSort = {{SortedColumn = 2, Descending = false},{SortedColumn = 2, Descending = false}}
	self.TeamListRows= {{},{}}
	self.TeamSkill = {0,0}
	self.TeamCount = {0,0}
	self.TeamNotice = {"",""}

	self.PickChange = false

end


function Plugin:CaptainMenuInitialise()
	if SGUI.IsValid( self.Window ) then
		self.Logger:Debug( "CaptainMenu Initialise: Window already exists." )
		return
	end
	self.Logger:Debug( "CaptainMenu Initialise" )

	self:CaptainMenuReset()


	local ScreenWidth = Client.GetScreenWidth()
	local ScreenHeight = Client.GetScreenHeight()
	self.PanelSize = Vector(ScreenWidth * 0.6 - 128, ScreenHeight * 0.8, 0)

	self.Window = SGUI:Create("TabPanel")
	self.Window:SetDebugName( "CaptainsMenuWindow" )
	self.Window:SetIsVisible(false)
	self.Window:SetAnchor("TopLeft")
	self.Window:SetSize(Vector(ScreenWidth * 0.6, ScreenHeight * 0.8, 0))
	self.Window:SetPos(Vector(ScreenWidth * 0.3, ScreenHeight * 0.1, 0))

	-- If, for some reason, there's an error in a panel hook, then this is removed.
	-- We don't want to leave the mouse showing if that happens.
	self.Window:CallOnRemove( function()
		if self.IgnoreRemove then return end
		self.Logger:Debug("CaptainMenu Window Removed" )

		if self.Visible then
			SGUI:EnableMouse( false , self.Window )
			self.Visible = false
		end

		self.Created = false
		self.Window = nil
		self:CaptainMenuReset()

		if self.myTeam ~= 0 then
			-- send end, but only if we were a captain.
			self:SendNetworkMessage("RequestEndCaptains", {}, true)
		end

		self.Logger:Error( "CaptainsMode Failed.")
	end )

	self.Window.OnPreTabChange = function( Window )

		if Window:GetIsVisible() == true then
			self.Logger:Debug( "OnPreTabChange Window Visible")
		else
			self.Logger:Debug("OnPreTabChange Window NOT Visible" )
		end

		if not Window.ActiveTab then return end
		local Tab = Window:GetActiveTab()
		if not Tab or not Tab.Name then return end

		self.Logger:Debug("Window OnPreTabChange Tab %s", Tab.Name )

		if Tab.Name == "Pick" then
			self.PickListSort.SortedColumn = self.PickList and self.PickList.SortedColumn or 3
			self.PickListSort.Descending = self.PickList and self.PickList.Descending or false
		end

		if Tab.Name == "Teams" then
			-- Capture when the Teams tab goes away, and save the team name.
			self.TeamListSort[1].SortedColumn = self.TeamList[1].SortedColumn or 3
			self.TeamListSort[1].Descending = self.TeamList[1].Descending or false
			self.TeamListSort[2].SortedColumn = self.TeamList[2].SortedColumn or 3
			self.TeamListSort[2].Descending = self.TeamList[2].Descending or false
			self:UpdateTeamName()
		end

	end


	self.Window:AddTab ("Pick",
		function(Panel)
			self.Logger:Debug("Populate Pick Window" )

			local ListTitlePanel = Panel:Add("Panel")
			ListTitlePanel:SetAnchor("TopLeft")
			ListTitlePanel:SetSize(Vector(self.PanelSize.x * 0.96, self.PanelSize.y * 0.05, 0))
			ListTitlePanel:SetPos(Vector(self.PanelSize.x * 0.02, self.PanelSize.y * 0.02, 0))

			local ListTitleText = ListTitlePanel:Add("Label")
			ListTitleText:SetAnchor("CentreMiddle")
			ListTitleText:SetFont(Fonts.kAgencyFB_Small)
			ListTitleText:SetText("DMD-Captains: Players available for picking")
			ListTitleText:SetTextAlignmentX(GUIItem.Align_Center)
			ListTitleText:SetTextAlignmentY(GUIItem.Align_Center)

			if self.myTeam ~= 0 then
				local ListTitleTeamText = ListTitlePanel:Add("Label")
				--ListTitleTeamText:SetAnchor("CentreLeft")
				ListTitleTeamText:SetAnchor(GUIItem.Left, GUIItem.Center)
				ListTitleTeamText:SetFont(Fonts.kAgencyFB_Small)
				ListTitleTeamText:SetText(  self:GetTeamString(self.myTeam)  )
				ListTitleTeamText:SetTextAlignmentX(GUIItem.Align_Center)
				ListTitleTeamText:SetTextAlignmentY(GUIItem.Align_Center)
				ListTitleTeamText:SetPos(Vector(self.PanelSize.x * 0.02, self.PanelSize.y * 0.02, 0))
				self:GUI_AddObj( nil, "ListTitleTeamText", ListTitleTeamText )
			end

			local PickList = Panel:Add("List")
			PickList:SetAnchor("TopLeft")
			PickList:SetSize(Vector(self.PanelSize.x * 0.96, self.PanelSize.y * 0.74, 0))
			PickList:SetPos(Vector(self.PanelSize.x * 0.02, self.PanelSize.y * 0.09, 0))
			PickList:SetColumns("NS2ID", "Name", "Skill", "Marine", "Alien", "Room")
			--PickList:SetSpacing(0.3, 0.55, 0.15)
			PickList:SetSpacing(0.15, 0.40, 0.10, 0.10, 0.10, 0.15)
			PickList:SetNumericColumn(1)
			PickList:SetNumericColumn(3)
			PickList:SetNumericColumn(4)
			PickList:SetNumericColumn(5)
			PickList.TitlePanel = ListTitlePanel
			PickList.TitleText = ListTitleText

			self.PickList = PickList

			self.PickList.SortedColumn = self.PickListSort.SortedColumn
			self.PickList.Descending = self.PickListSort.Descending


			self.PickRows = {}
			self.PickRowsCount = 0

			local CommandPanel = Panel:Add("Panel")
			CommandPanel:SetSize(Vector(self.PanelSize.x, self.PanelSize.y * 0.13, 0))
			CommandPanel:SetPos(Vector(0, self.PanelSize.y * 0.85, 0))

			local CommandPanelSize = CommandPanel:GetSize()

			local Turn = CommandPanel:Add("Label")
			Turn:SetFont(Fonts.kAgencyFB_Large)
			Turn:SetPos(Vector(CommandPanelSize.x * 0.02, CommandPanelSize.y * 0.30, 0))
			Turn:SetBright(true)

			local Pick = CommandPanel:Add("Button")
			Pick:SetFont(Fonts.kAgencyFB_Large)
			Pick:SetSize(Vector(CommandPanelSize.x * 0.2, CommandPanelSize.y, 0))
			Pick:SetPos(Vector(CommandPanelSize.x * 0.78, 0, 0))
			Pick:SetText("Pick")
			Pick:SetEnabled(false)
			Pick:SetIsVisible(false)

			local SwapTeam = CommandPanel:Add("Button")
			SwapTeam:SetFont(Fonts.kAgencyFB_Large)
			SwapTeam:SetSize(Vector(CommandPanelSize.x * 0.2, CommandPanelSize.y, 0))
			SwapTeam:SetPos(Vector(CommandPanelSize.x * 0.50, 0, 0))
			SwapTeam:SetIsVisible( (self.myTeam ~= 0) )
			local swapEnabled, swapText = self:FormatSwapText()
			SwapTeam:SetEnabled( swapEnabled )
			SwapTeam:SetText( swapText )			

			function SwapTeam.DoClick()
				self:Notify( "You clicked SwapTeam.")
				self.TeamSwap[self.myTeam] = true
				local swapEnabled, swapText = self:FormatSwapText()
				SwapTeam:SetEnabled( swapEnabled )
				SwapTeam:SetText( swapText )							
				self:OnRequestSwapTeams(self.myTeam, false)
			end


			self:GUI_AddObj( nil, "TurnText", Turn )
			self:GUI_AddObj( nil, "PickButton", Pick )
			self:GUI_AddObj( nil, "SwapTeamButton", SwapTeam )

			self:UpdateTurnLabels(Turn, Pick)

			function PickList:OnRowSelected(Index, Row)
				Pick:SetEnabled(true)
			end

			function PickList:OnRowDeselected(Index, Row)
				Pick:SetEnabled(false)
			end

			function Pick.DoClick()
			-- Row.Selected. caused an issue.
				local Row = PickList:GetSelectedRow()
				if not SGUI.IsValid(Row) then
					Pick:SetEnabled(false)
					StartSoundEffect("sound/NS2.fev/common/invalid", 5)
					return
				end
				local pickid = Row:GetData( "pickid" )
				self:OnPickPlayer(pickid)
			end

			self:PicklistUpdate()

		end
	)

	self.Window:AddTab( "Teams" ,
		function(Panel)
			self.Logger:Debug("Populate Teams Window" )

			for i = 1, 2 do
				local col = i-1
				local ListTitlePanel = Panel:Add("Panel")
				ListTitlePanel:SetSize(Vector(self.PanelSize.x * 0.47, self.PanelSize.y * 0.05, 0))
				ListTitlePanel:SetAnchor("TopLeft")
				ListTitlePanel.Pos = Vector(self.PanelSize.x * (0.02 + 0.47 * col) + self.PanelSize.x * 0.02 * col, self.PanelSize.y * 0.02, 0)
				ListTitlePanel:SetPos(ListTitlePanel.Pos)

				local ListTitleText = ListTitlePanel:Add("Label")
				ListTitleText:SetAnchor("CentreMiddle")
				ListTitleText:SetFont(Fonts.kAgencyFB_Small)
				ListTitleText:SetTextAlignmentX(GUIItem.Align_Center)
				ListTitleText:SetTextAlignmentY(GUIItem.Align_Center)
				ListTitleText:SetText( self:FormatTeamHeading( i ) )
				self:GUI_AddObj( i, "teamLabel", ListTitleText )

				-- Add Input for Setting My Team Name
				if self.myTeam == i then
					ListTitleText:SetAnchor("CenterRight")
					ListTitleText:SetTextAlignmentX(GUIItem.Align_Max)

					local myTeamInput = SGUI:Create("TextEntry", ListTitlePanel)
					--self.myGUIObjs["teamInput"] = myTeamInput
					self:GUI_AddObj( nil, "teamInput", myTeamInput )

					myTeamInput:SetDebugName( "CaptainsMyTeamName" )
					myTeamInput:SetAnchor("CenterLeft")
					--myTeamInput:SetTextAlignmentY(GUIItem.Align_Center)
					myTeamInput:SetFont(Fonts.kAgencyFB_Small)
					--myTeamInput:SetPos(Vector(-160, -5, 0))
					--myTeamInput:SetSize(Vector(320, 32, 0))
					myTeamInput:SetSize( ListTitlePanel:GetSize() * 0.5 )
					--myTeamInput:SetBorderSize(  )
					myTeamInput:SetText(StringFormat("%s", self.TeamNames[i]))
					myTeamInput.MaxLength = 255

					myTeamInput.teamHasFocus = false

					function myTeamInput.OnGainFocus(Input)
						if SGUI.FocusedControl then
							self.Logger:Trace( "myTeamInput.OnGainFocus Name %s", SGUI.FocusedControl:GetDebugName())
						end
						-- SGUI doesn't track lost focus very well.
						-- So, we will activate our focus and then process it once in Lose Focus.
						myTeamInput.teamHasFocus = true
					end

					function myTeamInput.OnLoseFocus(Input)
						if myTeamInput.teamHasFocus == true then
							myTeamInput.teamHasFocus = false
							self.Logger:Trace( "myTeamInput.OnLoseFocus %s", Input:GetText())
							self:UpdateTeamName(myTeamInput)
						end
					end

					function myTeamInput.OnEnter(Input)
						self.Logger:Trace( "myTeamInput.OnEnter %s", Input:GetText())
						self:UpdateTeamName(myTeamInput)
					end

					function myTeamInput.OnEscape(Input)
						self.Logger:Trace( "myTeamInput.OnEscape %s", Input:GetText())
						self:UpdateTeamName(myTeamInput)
					end

				end


				local List = Panel:Add("List")
				List:SetAnchor("TopLeft")
				List.Pos = Vector(self.PanelSize.x * (0.02 + 0.47 * col) + self.PanelSize.x * 0.02 * col, self.PanelSize.y * 0.09, 0)
				List:SetPos(List.Pos)
				List:SetColumns("Name", "Skill", "Room")
				--List:SetSpacing(0.7, 0.3)
				List:SetSpacing(0.6, 0.2, 0.2)
				List:SetSize(Vector(self.PanelSize.x * 0.47, self.PanelSize.y * 0.69, 0))
				--List:SetNumericColumn(1)
				List:SetNumericColumn(2)
				List.ScrollPos = Vector(0, 32, 0)
				List.TitlePanel = ListTitlePanel

				self.TeamList[i] = List
				self.TeamListRows[i] = {}

				self.TeamList[i].SortedColumn = self.TeamListSort[i].SortedColumn or 1
				self.TeamList[i].Descending = self.TeamListSort[i].Descending or false



				local Padding = Vector2( 5, 0 )
				local ZeroVector = Vector2( 0, 0 )
				local LastColumn = Vector2( 0, 0 )

				local BottomRow = Panel:Add("Panel")
				BottomRow:SetSize(Vector(self.PanelSize.x * 0.47, self.PanelSize.y * 0.05, 0))
				BottomRow:SetAnchor("TopLeft")
				BottomRow.Pos = Vector(List.Pos.x, self.PanelSize.y * 0.79, 0)
				BottomRow:SetPos(BottomRow.Pos)
				--BottomRow.Background:SetColor( Colour( 255, 0, 0 ) )
				--BottomRow.Background:SetColor( Panel.Background:GetColor()  )
				BottomRow.Background:SetColor( Colour( 0.3, 0.3, 0.3, 1 ) )

				local TextObjs = {}
				BottomRow.TextObjs = TextObjs
				BottomRow.ColumnText = {}
				BottomRow.ColumnText[1] = ""
				BottomRow.ColumnText[2] = "0"
				BottomRow.ColumnText[3] = "0"

				-- Copy spacing from List header.
				local X = BottomRow:GetSize().x
				local Spacing = {}
				for j = 1, #List.HeaderSizes do
					Spacing[j] = Vector2(List.HeaderSizes[j] * X , 0 )
				end
				for j = 1, #Spacing do
					local TextObj = BottomRow:Add("Label")
					TextObj:SetAnchorFraction( 0, 0.5 )
					TextObj:SetFont(Fonts.kAgencyFB_Small)
					TextObj:SetTextAlignmentY(GUIItem.Align_Center)
					TextObj:SetText( BottomRow.ColumnText[j] )

					TextObj:SetPos( Padding + (Spacing[j-1] or ZeroVector) + LastColumn )
					LastColumn = TextObj:GetPos()
					TextObjs[j] = TextObj
				end
				--self.TeamSkillText[i] = TextObjs

				self:GUI_AddObj( i, "bottomMessage", TextObjs[1] )
				self:GUI_AddObj( i, "bottomSkill", TextObjs[2] )
				self:GUI_AddObj( i, "bottomCount", TextObjs[3] )

				-- BottomRow.TextObjs[ i ]:SetAutoSize( UnitVector( Percentage( Size * 100 ), Percentage.ONE_HUNDRED ) )

			end

			if self.myTeam == 0 then
				-- Not-A-Captain. Add Close button.
				local Ready = Panel:Add("Button")
				Ready:SetFont(Fonts.kAgencyFB_Large)
				Ready:SetSize(Vector(self.PanelSize.x * 0.3, self.PanelSize.y * 0.1, 0))
				Ready:SetPos(Vector(self.PanelSize.x * 0.35, self.PanelSize.y * 0.88, 0))
				Ready:SetText( "Close" )

				function Ready.DoClick()
					self:SetIsVisible(false)
					self:Notify( "Captains window hidden. Use !showteams to see it again.")
				end


			else
				-- Set a Captain Ready button
				local Ready = Panel:Add("Button")
				Ready:SetFont(Fonts.kAgencyFB_Large)
				Ready:SetSize(Vector(self.PanelSize.x * 0.3, self.PanelSize.y * 0.1, 0))
				Ready:SetPos(Vector(self.PanelSize.x * 0.35, self.PanelSize.y * 0.88, 0))

				Ready:SetText( self.myTeamReady and "Not Ready" or "Ready")

				function Ready.DoClick()
					self.myTeamReady = not self.myTeamReady
					Ready:SetText( self.myTeamReady and "Not Ready" or "Ready")
					self:SendNetworkMessage("SetReady", {ready = self.myTeamReady, team=self.myTeam, settings=false}, true)
				end
				self:GUI_AddObj( nil, "ReadyButton", Ready )

				-- Add Trade Player button
				local Trade = Panel:Add("Button")
				Trade:SetFont(Fonts.kAgencyFB_Large)
				--Trade:SetSize(Vector(self.PanelSize.x * 0.3, self.PanelSize.y * 0.1, 0))
				Trade:SetSize(Vector(self.PanelSize.x * 0.20,self.PanelSize.y * 0.1, 0))
				--Trade:SetPos(Vector(self.PanelSize.x * 0.35,self.PanelSize.y * 0.88, 0))
				Trade:SetText( "Give Player" )
				Trade:SetEnabled(false)

				Trade:SetIsVisible(self:PickingDone())

				if self.myTeam == 1 then
					Trade:SetPos(Vector(
						self.PanelSize.x * (0.02 )
					, 	self.PanelSize.y * 0.88, 0
						))
				else
					Trade:SetPos(Vector(
						(self.PanelSize.x * (0.02 + 0.47) + self.PanelSize.x * 0.02)
						+ (self.PanelSize.x * 0.47)
						- (self.PanelSize.x * 0.20)
						, 	self.PanelSize.y * 0.88, 0
						))
				end

				self.TeamList[self.myTeam].OnRowSelected = function(List, Index, Row)
					if not Trade:GetIsVisible() and self:PickingDone() then
						Trade:SetIsVisible(true)
					end
					local pickid = Row:GetData( "pickid" )
					-- Activate Trade if they didn't click on themselves.
					if self.myPickid ~= pickid then
						Trade:SetEnabled(true)
					end
				end

				self.TeamList[self.myTeam].OnRowDeselected = function(List, Index, Row)
					Trade:SetEnabled(false)
				end

				function Trade.DoClick()
				-- Row.Selected. caused an issue.
					local Row = self.TeamList[self.myTeam]:GetSelectedRow()
					if not SGUI.IsValid(Row) then
						Trade:SetEnabled(false)
						StartSoundEffect("sound/NS2.fev/common/invalid", 5)
						return
					end
					local pickid = Row:GetData( "pickid" )
					if self.myPickid == pickid then
						Trade:SetEnabled(false)
						StartSoundEffect("sound/NS2.fev/common/invalid", 5)
						return
					end
					self:OnTradePlayer(pickid)
				end

			end

			self:TeamListUpdate()

		end
	)

	-- add Cancel tab
	self.Window:AddTab(
		"Cancel",
		function(Panel)
			self.Logger:Debug("Populate Cancel Window" )

			local Cancel = Panel:Add("Button")
			Cancel:SetFont(Fonts.kAgencyFB_Large)
			Cancel:SetSize(Vector(self.PanelSize.x * 0.3, self.PanelSize.y * 0.1, 0))
			Cancel:SetPos(Vector(self.PanelSize.x * 0.35, self.PanelSize.y * 0.45, 0))
			Cancel:SetText("Cancel Captains")

			function Cancel.DoClick()
				self.Logger:Trace("Cancel Button DoClick")
				-- Disable their button so we don't worry about multi-clicks.
				Cancel:SetEnabled(false)
				self:SendNetworkMessage("RequestEndCaptains", {}, true)
				if self.myTeam == 0 then
					self:SetIsVisible( false )
				end
			end

		end
	)

	-- if self.dt.TestingCaptains then
	-- if Shine:HasAccess( Client, "sh_cm_captainsnight" ) then

		local function GetTeamID( teamIndex, name )
			return StringFormat("ID%sTeam%s", teamIndex, name)
		end

		local Units = SGUI.Layout.Units
		local HighResScaled = Units.HighResScaled
		local Percentage = Units.Percentage
		local Spacing = Units.Spacing
		local UnitVector = Units.UnitVector
		local Auto = Units.Auto		
		local SMALL_PADDING = HighResScaled( 8 )


		local Font = {
			Family = "kAgencyFB",
			Size = HighResScaled( 27 )
		}
		local AgencyFBSmall = {
			Family = "kAgencyFB",
			Size = HighResScaled( 20 )
		}		
		local AgencyFBNormal = {
			Family = "kAgencyFB",
			Size = HighResScaled( 27 )
		}
		local AgencyFBMedium = {
			Family = "kAgencyFB",
			Size = Units.HighResScaled( 33 )
		}		

		if not self.CaptainOptions then 
			self:RequestCaptainOptions()
		end

		self.Window:AddTab(
			"Settings",
			function(Panel)
				self.Logger:Debug("Populate Settings Window" )
				local Rows = {}

		if self.CaptainOptions and self.CaptainOptions.ShowSettings then 
				local teamIndex = 1
				local inputName = StringFormat("SettingsTeam%sName", teamIndex)
				local inputID = StringFormat("ID%sTeam", teamIndex)
			
				-- Rows[ #Rows + 1] = {
				-- 	ID = this,
				-- 	Class = "Label",
				-- 	Props = {
				-- 		Plugin = Plugin,
				-- 		Margin = Spacing( 0, 0, 0, SMALL_PADDING ),
				-- 		AutoSize = UnitVector( Percentage.ONE_HUNDRED, Units.Auto.INSTANCE ),
				-- 		Text = "Label Text"
				-- 	}
				-- }

			for i = 1, 2 do
				local teamIndex = i

				Rows[ #Rows + 1] = {
					Class = "Horizontal",
					Type = "Layout",
					Props = {
						AutoSize = UnitVector( Percentage( 96 ), HighResScaled( 32 ) ),
						Margin = Spacing( 0, 0, 0, HighResScaled( 5 ) ),
						Fill = false
					},
					Children = {
						{
							Class = "Label",
							Props = {
								AutoFont = Font,
								DebugName =  inputName.."Label",
								-- AutoSize = UnitVector( Percentage( 25 ), HighResScaled( 32 ) ),
								AutoSize = UnitVector( Percentage( 25 ), Percentage.ONE_HUNDRED ),
								-- Text = 	self:GetPhrase( "REASON" ),
								Text = 	StringFormat("Team %s Name", teamIndex),
								Margin = Spacing( HighResScaled( 5 )  ),								
							}
						},
						{
							ID = GetTeamID(teamIndex, "Name"),
							Class = "TextEntry",
							Props = {
								DebugName = GetTeamID(teamIndex, "Name_Settings"),
								Fill = true,
								AutoFont = Font,
								Margin = Spacing( HighResScaled( 5 ) ),
								Text = "Team name text",
								Data = { 
									teamIndex = teamIndex
								},
							},
							OnBuilt = function( config, TextEntry, Elements)
								TextEntry.teamHasFocus = false
								TextEntry.teamIndex = config.Props.Data.teamIndex
								self:GUI_AddObj( nil, config.ID, TextEntry )
								-- TextEntry:SetText(self:FormatTeamHeading( TextEntry.teamIndex ) )
								TextEntry:SetText( self.TeamNames[TextEntry.teamIndex]  )
							end
						},
						{
							ID = GetTeamID( teamIndex, "Icon" ),
							Class = "Button",
							Props = {
								DebugName = GetTeamID(teamIndex, "IconButton"),
								AutoFont = {
									Family = "Ionicons",
									Size = HighResScaled( 29 )
								},
								AutoSize = UnitVector( HighResScaled( 32 ), HighResScaled( 32 ) ),
								--Margin = Spacing( HighResScaled( 5 ) ),
								Text = SGUI.Icons.Ionicons.Upload,
								--Tooltip = self:GetPhrase( "SELECT_PLAYER" ),
								Tooltip = "Send Name Change",
								StyleName = "InputGroupEnd",
								DoClick = function( Button )
									teamInput = self:GUI_GetObj( nil, GetTeamID(Button.teamIndex, "Name") )
									self:UpdateTeamNameForTeam( Button.teamIndex, teamInput )
								end,
								Data = {
									teamIndex = teamIndex
								}
							},
							OnBuilt = function( config, Button, Elements )
								Button.teamIndex = config.Props.Data.teamIndex
							end
						}
					}
				}

				Rows[ #Rows + 1] = {
					Class = "Horizontal",
					Type = "Layout",
					Props = {
						AutoSize = UnitVector( Percentage( 96 ), HighResScaled( 32 ) ),
						--	Spacing( left, up, right, down )
						Margin = Spacing( 0, 0, 0, HighResScaled( 5 ) ),
						Fill = false
					},
					Children = {
						{
							ID = GetTeamID(teamIndex, "Swap"),
							Class = "Button",
							Props = {
								AutoFont = Font,
								AutoSize = UnitVector( Percentage( 20 ), HighResScaled( 32 ) ),
								Margin = Spacing( HighResScaled( 32 ), HighResScaled( 5 ), HighResScaled( 5 ), HighResScaled( 5 ) ),
								Text = StringFormat("Swap Team %s", teamIndex),
								-- Tooltip = self:GetPhrase( "SELECT_PLAYER" ),
								-- Tooltip = "Send Name Change",
								-- StyleName = "InputGroupEnd",
								DoClick = function( Button )
									DebugTraceLog("DoClick")
									self:Notify( "You clicked SwapTeam.")
									self.TeamSwap[Button.teamIndex] = true
									local swapEnabled, swapText = self:FormatSwapText(Button.teamIndex)
									Button:SetText( swapText )
									self:OnRequestSwapTeams(Button.teamIndex, true)
								end,
								Data = { 
									teamIndex = teamIndex
								},
							},
							OnBuilt = function( config, Button )
								-- DebugTraceLog("OnBuilt")
								-- PrintTable( config )
								Button.teamIndex = config.Props.Data.teamIndex
								local swapEnabled, swapText = self:FormatSwapText(Button.teamIndex)
								Button:SetText( swapText )
								self:GUI_AddObj( nil, config.ID, Button )
							end
						}
					}
				}


				Rows[ #Rows + 1] = {
					Class = "Horizontal",
					Type = "Layout",
					Props = {
						AutoSize = UnitVector( Percentage( 96 ), HighResScaled( 32 ) ),
						--	Spacing( left, up, right, down )
						Margin = Spacing( 0, 0, 0, HighResScaled( 5 ) ),
						Fill = false
					},
					Children = {
						{
							ID = GetTeamID(teamIndex, "ReadyButton"),
							Class = "Button",
							Props = {
								AutoFont = Font,
								AutoSize = UnitVector( Percentage( 20 ), HighResScaled( 32 ) ),
								Margin = Spacing( HighResScaled( 32 ), HighResScaled( 5 ), HighResScaled( 5 ), HighResScaled( 5 ) ),
								Text = StringFormat("Force Team %s Ready", teamIndex),
								-- Tooltip = self:GetPhrase( "SELECT_PLAYER" ),
								-- Tooltip = "Send Name Change",
								-- StyleName = "InputGroupEnd",
								DoClick = function( Button )
									self:SendNetworkMessage("SetReady", {ready = true, team=Button.teamIndex, settings=true}, true)
								end,
								Data = { 
									teamIndex = teamIndex
								},
							},
							OnBuilt = function( config, Button )
								Button.teamIndex = config.Props.Data.teamIndex
							end
						},
						{
							ID = GetTeamID(teamIndex, "NotReadyButton"),
							Class = "Button",
							Props = {
								AutoFont = Font,
								AutoSize = UnitVector( Percentage( 20 ), HighResScaled( 32 ) ),
								Margin = Spacing( HighResScaled( 32 ), HighResScaled( 5 ), HighResScaled( 5 ), HighResScaled( 5 ) ),
								Text = StringFormat("Force Team %s NOT Ready", teamIndex),
								-- Tooltip = self:GetPhrase( "SELECT_PLAYER" ),
								-- Tooltip = "Send Name Change",
								-- StyleName = "InputGroupEnd",
								DoClick = function( Button )
									self:SendNetworkMessage("SetReady", {ready = false, team=Button.teamIndex, settings=true}, true)
								end,
								Data = { 
									teamIndex = teamIndex
								},
							},
							OnBuilt = function( config, Button )
								Button.teamIndex = config.Props.Data.teamIndex
							end
						}						
					}
				}
			end

			Rows[ #Rows + 1] = {
				Class = "Horizontal",
				Type = "Layout",
				Props = {
					AutoSize = UnitVector( Percentage( 96 ), HighResScaled( 32 ) ),
					--	Spacing( left, up, right, down )
					Margin = Spacing( 0, 0, 0, HighResScaled( 5 ) ),
					Fill = false
				},
				Children = {
					{
						ID = "TeamRefresh",
						Class = "Button",
						Props = {
							AutoFont = Font,
							AutoSize = UnitVector( Percentage( 20 ), HighResScaled( 32 ) ),
							Margin = Spacing( HighResScaled( 32 ), HighResScaled( 5 ), HighResScaled( 5 ), HighResScaled( 5 ) ),
							Text = "Refresh Team List",
							DoClick = function( Button )
								self:SendNetworkMessage("CheckTeams", {settings=true}, true)
								Button:SetEnabled(false)
							end,
						},
						-- OnBuilt = function( config, Button )
						-- 	self:GUI_AddObj( nil, config.ID, Button )
						-- end
					}
				}
			}

		end

				local LastRow = Rows[ #Rows ]
				if LastRow then
					LastRow.Props.Margin = nil
				end	
				
				local Elements = SGUI:BuildTree( {
					Parent = Panel,
					{
						Class = "Vertical",
						Type = "Layout",
						Props = {
							AutoSize = UnitVector( Percentage( 96 ), Percentage( 80 ) ),
							Padding = Spacing( SMALL_PADDING, SMALL_PADDING, SMALL_PADDING, SMALL_PADDING ),
						},
						Children = {
							{
								Class = "Label",
								Props = {
									AutoFont = AgencyFBSmall,
									Anchor = "TopMiddle",
									TextAlignmentX = GUIItem.Align_Center,
									TextAlignmentY = GUIItem.Align_Center,
									-- Text = Locale:GetPhrase( "Core", "TESTING_OPTIONS" ),
									Text = "DMD-Captains: Options",
									--Margin = Spacing( 0, 0, 0, SMALL_PADDING ),
									-- Margin = Spacing( SMALL_PADDING ),
									Margin = Spacing( SMALL_PADDING, SMALL_PADDING, SMALL_PADDING, SMALL_PADDING ),
									-- AutoSize = UnitVector( Percentage( 96 ), HighResScaled( 32 ) ),
									AutoSize = UnitVector( Percentage.ONE_HUNDRED, Units.Auto.INSTANCE ),
									--AutoSize = UnitVector( Percentage( 96 ), Percentage( 5 ) ),
								}
							},
							{
								Class = "Column",
								Props = {
									Scrollable = true,
									Fill = true,
									--Colour = Colour( 0, 0, 0, 1 ),
									--Colour = Colour( 0, 0, 0, 0 ),
									--Colour = Colour( 1, 1, 1, 1 ),
									BackgroundColour = Colour( 0.3, 0.3, 0.3, 1 ),
									ScrollbarPos = Vector2( 0, 0 ),
									ScrollbarWidth = HighResScaled( 8 ):GetValue(),
									ScrollbarHeightOffset = 0
								},
								Children = Rows
							}
						},
						OnBuilt = function( Definition, Vertical, Elem )
							-- can we disable the tab?
							-- DebugTraceLog("OnBuilt")
							-- PrintTable( Elem )
							-- DebugTraceLog("OnBuilt")
							-- PrintTable( Vertical.Parent )
							-- DebugTraceLog("OnBuilt")
							-- PrintTable( Vertical.Parent.Parent )
						end
					}
				} )


			end
		)	
	-- end

	self.CaptainMenuCreated = true

	self.Logger:Debug( "CaptainMenu Initialise done" )

end

function Plugin:PicklistCheck()
	if self.myTeam == 0 then return end

	local Turn = self:GUI_GetObj( 0, "TurnText" )
	local Pick = self:GUI_GetObj( 0, "PickButton" )

	if not SGUI.IsValid( self.Window ) then
		self.Logger:Debug( "PicklistCheck Window invalid" )
 		return
	end

	if  self.PickRowsCount == 0
	and SGUI.IsValid( Turn )
	and SGUI.IsValid( Pick )
	and Turn:GetIsVisible() then
		self.Logger:Debug( "PicklistCheck Tab Check" )
		local tab = 2
		local haveTab = self.Window:SetSelectedTab( self.Window.Tabs[ tab ] )
		if haveTab then self.Logger:Debug( "PicklistCheck new Tab %s", self.Window.Tabs[ tab ].Name ) end
		self.Window:InvalidateLayout( true )
		StartSoundEffect("sound/NS2.fev/marine/voiceovers/commander/research_complete")
	end
end

function Plugin:PicklistUpdate()
	self.Logger:Debug("Picklist Update start" )

	if not SGUI.IsValid(self.PickList) then
		self.Logger:Debug("Picklist Update EMPTY" )
		return
	end
	local ExistingPlayers = {}

	for _, Ent in pairs( self.Players ) do
		self:PickListAdd( Ent )
		ExistingPlayers[ Ent.pickid ] = true
	end

	self.PickRowsCount = 0
	for pickid, Row in pairs( self.PickRows ) do
		if not ExistingPlayers[ pickid ] then
			self:PickListRemove( pickid, Row.Index, Row:GetColumnText(2) )
		else
			self.PickRowsCount = self.PickRowsCount + 1
		end
	end

	self.Logger:Debug("Picklist Update end" )

end

function Plugin:PickListAdd( Ent )

	local pickTeam = Ent.pick or 0
	local isPickable = Ent.isPickable or false

	local Row = self.PickRows[ Ent.pickid ]

	if SGUI.IsValid( Row ) then
		if pickTeam == 0 and isPickable then
			Row:SetColumnText( 1, tostring( Ent.steamid ) )
			Row:SetColumnText( 2, Ent.name )
			Row:SetColumnText( 3, tostring( Max( 0, Ent.skill) ) )
			Row:SetColumnText( 4, tostring( Ent.marine ) )
			Row:SetColumnText( 5, tostring( Ent.alien) )
			Row:SetColumnText( 6, Plugin:GetTeamName( Ent.team, true ) )
			Row:SetColumnText( 7, tostring( Ent.pickid ) )
			Row:SetData( "pickid" , Ent.pickid )
			Row:SetTooltip( Ent.skillText )
			self.Logger:Trace("Picklist Updated [%s]%s", Ent.pickid, Ent.name )

			if not (isPickable) then
				Row:SetTextOverride( 4, {
						Font = Fonts.kAgencyFB_Small,
						TextScale = GetScaledVector(),
						Colour = Colour( 255, 0, 0 )
					} )
			end


		else
			-- remove them if they were picked.
			self.PickList:RemoveRow( Row.Index )
			self.PickRows[ Ent.pickid ] = nil
			self.Logger:Trace("Picklist Removed [%s]%s", Ent.pickid, Ent.name )
		end
		return
	elseif pickTeam ~= 0 or not isPickable then
		return
	end

	self.PickRows[ Ent.pickid ] = self.PickList:AddRow(
				  Ent.steamid
				, Ent.name
				, Max( 0, Ent.skill)
				, Ent.marine
				, Ent.alien
				, Plugin:GetTeamName( Ent.team, true )
				)
	self.PickRows[ Ent.pickid ]:SetData("pickid",Ent.pickid )
	self.PickRows[ Ent.pickid ]:SetTooltip( Ent.skillText )

	if not (isPickable) then
		self.PickRows[ Ent.pickid ]:SetTextOverride( 4, {
				Font = Fonts.kAgencyFB_Small,
				TextScale = GetScaledVector(),
				Colour = Colour( 255, 0, 0 )
			} )
	end

	self.Logger:Trace("Picklist Added [%s]%s",  Ent.pickid, Ent.name )
end

function Plugin:PickListRemove( pickid, index, playerName)
	if team == 0 then return end
	if SGUI.IsValid(self.PickList ) then
		self.PickList:RemoveRow( index )
	end
	self.PickRows[ pickid ] = nil
	self.Logger:Trace("Picklist Removed [%s]%s", pickid, playerName )
end

function Plugin:PickingDone()
	local Exists = false
	local HavePickable = false
	for Index, Player in ipairs(self.Players) do
		Exists = true
		if Player.pick == 0 and Player.isPickable then
			HavePickable  = true
			break
		end
	end
	return Exists and not HavePickable
end


function Plugin:TeamListUpdate()

	self.Logger:Debug("TeamList Update start" )
	if not SGUI.IsValid(self.TeamList and self.TeamList[1])
	or not SGUI.IsValid(self.TeamList and self.TeamList[2])
	then
		self.Logger:Debug("TeamList Update EMPTY" )
		return
	end
	local ExistingPlayers = {}

	if self.PickChange then
		-- reset team list
		self.TeamList[1]:Clear()
		self.TeamList[2]:Clear()
		self.TeamListRows= {}
		self.TeamListRows[1] = {}
		self.TeamListRows[2] = {}
		self.PickChange = false
	end

	self.TeamSkill = {0,0}
	self.TeamCount = {0,0}

	for _, Ent in pairs( self.Players ) do
		self:TeamListAdd( Ent )
		ExistingPlayers[ Ent.pickid ] = true
	end

	for team, t_list in pairs( self.TeamListRows ) do
		for pickid, Row in pairs( t_list ) do
			if not ExistingPlayers[ pickid ] then
				self:TeamListRemove( team, pickid, Row.Index, Row:GetColumnText(1) )
			end
		end
	end

	if  self.TeamCount[1] > (self.TeamCount[2]+1) then
		self.TeamNotice[1] = "Select a player to give."
		self.TeamNotice[2] = "Wait for a player trade."
		local skillDiff = self.TeamSkill[1] - self.TeamSkill[2]
		if skillDiff > 0 then
			skillDiff = skillDiff / 2
			if skillDiff > 0 then
				self.TeamNotice[1] = self.TeamNotice[1] ..  StringFormat( " Around Skill: %i", skillDiff )
			end
		end

	elseif self.TeamCount[2] > (self.TeamCount[1]+1) then
		self.TeamNotice[2] = "Select a player to give."
		self.TeamNotice[1] = "Wait for a player trade."
		local skillDiff = self.TeamSkill[1] - self.TeamSkill[2]
		if skillDiff > 0 then
			skillDiff = skillDiff / 2
			if skillDiff > 0 then
				self.TeamNotice[2] = self.TeamNotice[2] ..  StringFormat( " Around Skill: %i", skillDiff )
			end
		end
	end

	for i = 1, 2 do
		self:GUI_SetText( i, "bottomSkill", "%s", self.TeamSkill[i] )
		self:GUI_SetText( i, "bottomCount", "%s", self.TeamCount[i] )
		self:GUI_SetText( i, "bottomMessage", "%s", self.TeamNotice[i] )
	end
	self.Logger:Debug("TeamList Update End" )
end


function Plugin:TeamListAdd( Ent )
	local pickTeam = Ent.pick or 0
	if pickTeam  == 0 then return end

	if self.TeamList == nil
	or not SGUI.IsValid(self.TeamList[1])
	or not SGUI.IsValid(self.TeamList[2])
	then
		return
	end
	if self.TeamListRows[pickTeam ] == nil then return end
	local ptSkill = ( self.TeamIndex[pickTeam] == 1 and Ent.marine or Ent.alien)

	local Row = self.TeamListRows[pickTeam ][ Ent.pickid ]
	if SGUI.IsValid( Row ) then
		Row:SetColumnText( 1, Ent.name )
		Row:SetColumnText( 2, tostring( ptSkill ) )
		Row:SetColumnText( 3, Plugin:GetTeamName( Ent.team, true ) )
		Row:SetData("pickid", Ent.pickid)
		Row:SetTooltip( Ent.skillText )
		self.Logger:Trace("Team %s Updated [%s]%s", pickTeam, Ent.pickid, Ent.name )
		self.TeamSkill[pickTeam] = self.TeamSkill[pickTeam] + ptSkill
		self.TeamCount[pickTeam] = self.TeamCount[pickTeam] + 1

		if not (Ent.isPickable) then
			local Font, Scale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )
			Row:SetTextOverride( 3, {
					Font = Font,
					TextScale = Scale,
					Colour = Colour( 255, 0, 0 )
				} )
		end

		return
	end
	Row = self.TeamList[pickTeam]:AddRow( Ent.name, ptSkill, Plugin:GetTeamName( Ent.team, true ))
	self.TeamListRows[pickTeam][ Ent.pickid ] = Row
	Row:SetData("pickid", Ent.pickid)
	Row:SetTooltip( Ent.skillText )
	self.Logger:Trace("Team %s Added [%s]%s", pickTeam, Ent.pickid, Ent.name )
	self.TeamSkill[pickTeam] = self.TeamSkill[pickTeam] + ptSkill
	self.TeamCount[pickTeam] = self.TeamCount[pickTeam] + 1
	if not (Ent.isPickable) then
		local Font, Scale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )
		Row:SetTextOverride( 3, {
				Font = Font,
				TextScale = Scale,
				Colour = Colour( 255, 0, 0 )
			} )
	end

end

function Plugin:TeamListRemove( team , ID, index, playerName )
	if team == 0 then return end
	if SGUI.IsValid(self.TeamList[team]) then
		self.TeamList[team]:RemoveRow( index )
	end
	self.TeamListRows[team][ ID ] = nil
	self.Logger:Trace("Team %s Removed [%s]%s", team, ID, playerName )
end


function Plugin:UpdatePlayers(force)

	-- this worked too well. when the window appears, the list is empty.
	if not force then
		if not (SGUI.IsValid( self.Window ) and self.Window:GetIsVisible() == true ) then
			self.Logger:Debug( "UpdatePlayers Not Window:Not Visible" )
			return
		end
	end

	self.Logger:Debug( "UpdatePlayers" )
	self:PicklistUpdate()
	self:TeamListUpdate()

end

function Plugin:UpdateTurn()
	if self.myTeam == 0 then return end

	local Turn = self:GUI_GetObj( 0, "TurnText" )
	local Pick = self:GUI_GetObj( 0, "PickButton" )

	if  SGUI.IsValid( Turn )
	and SGUI.IsValid( Pick )
	and Turn:GetIsVisible() then
		self.Logger:Debug( "UpdateTurn Screen Text" )
		if (self:UpdateTurnLabels(Turn, Pick) ) then
		-- If Pick is enabled && something was selected. See if that row still exists.
			local Row = self.PickList.GetSelectedRow and self.PickList:GetSelectedRow()
			if not SGUI.IsValid(Row) then
				Pick:SetEnabled(false)
			end
		end
		-- InvalidateLayout will cause the window to refresh in the next refresh frame.
		self.Window:InvalidateLayout( )
		self.QueuePickCompleteCheck = true
		return
	end

end

function Plugin:UpdateTurnLabels(Turn, Pick)
	if (Plugin.dt.CaptainTurn == 0 or self.myTeam == 0) then
		return false
	end
	if (Plugin.dt.CaptainTurn == self.myTeam) then
		Turn:SetColour(Colour(0, 1, 0, 1))
		Turn:SetText("Your turn.")
		Pick:SetIsVisible(true)
		return true
	else
		Turn:SetColour(Colour(1, 1, 1, 1))
		Turn:SetText("Waiting for another captain...")
		Pick:SetIsVisible(false)
		return false
	end
end



function Plugin:SetIsVisible( show , tab)
	-- re-init the window if it crashed.
	self:CaptainMenuInitialise()

	if not SGUI.IsValid( self.Window ) then
		self.Logger:Debug( "SetIsVisible Window invalid" )
 		return
	end

	if tab and tab > 0 and tab < 3 then
		local haveTab = self.Window:SetSelectedTab( self.Window.Tabs[ tab ] )
		if haveTab then self.Logger:Debug( "SetIsVisible Tab %s", self.Window.Tabs[ tab ].Name ) end
	end
	self.Window:SetIsVisible( show )
	self.Window:InvalidateLayout( true )
	SGUI:EnableMouse(show,self.Window)
	self.Logger:Debug( "SetIsVisible done %s", show and "show" or "hide" )
	self.Visible = show

end

function Plugin:ShowTeamMenu()
	if not self.ClientInProgress then return end

	self.Logger:Debug( "ShowTeamMenu" )
	self:SetIsVisible( true , 2 )
end

function Plugin:OnPlayerLost()
	self.Logger:Debug( "Plugin:OnPlayerLost")
	if self.myTeam == 0 then return end

	Client.WindowNeedsAttention()
	self.myTeamReady = false
	self:GUI_SetText( nil, "ReadyButton", self.myTeamReady and "Not Ready" or "Ready" )
	self.Window:InvalidateLayout( )
	StartSoundEffect("sound/NS2.fev/marine/voiceovers/soldier_lost")
	self.TeamNotice[self.myTeam] = "Player List Updated"
end

function Plugin:OnUnsetReady()
	self.Logger:Debug( "Plugin:OnUnsetReady")
	if self.myTeam == 0 then return end

	Client.WindowNeedsAttention()
	self.myTeamReady = false
	self:GUI_SetText( nil, "ReadyButton", self.myTeamReady and "Not Ready" or "Ready" )
	self.Window:InvalidateLayout( )
	StartSoundEffect("sound/NS2.fev/marine/voiceovers/soldier_lost")
	self.TeamNotice[self.myTeam] = "Player List Updated"
	self:ShowTeamMenu()
end

function Plugin:ReceiveUnsetReady(Data)
	self.Logger:Debug( "Plugin:ReceiveUnsetReady")
	self.ProcessUnsetReady = true
end


function Plugin:ReceiveShowTeamMenu(Data)
	self.Logger:Debug( "Plugin:ReceiveShowTeamMenu")
	self:ShowTeamMenu()
end

function Plugin:ReceiveHideMouse(Data)
	self.Logger:Debug( "Plugin:ReceiveHideMouse")
	SGUI:EnableMouse(false)

	-- I think the CHAT window is messing up the MOUSE.

	-- maybe print SGUI.MouseObjects to log? or just run that many times.
	if SGUI.EnabledMouse and SGUI.EnabledMouse == true then
		self.Logger:Debug( "Plugin:ReceiveHideMouse %s", SGUI.MouseObjects)
	 	for i = SGUI.MouseObjects, 1, -1 do
			SGUI:EnableMouse(false)
		end
	end

end

function Plugin:FormatSwapText( Team )
	Team = Team or self.myTeam 
	local OtherTeam = (Team % 2) + 1
	local Enabled = false
	local Text
	if Team ~= 0 then
		Enabled = not self.TeamSwap[Team]
		Text = StringFormat( "%s Swap %s", 
			self.TeamSwap[Team] and "Pending" 
				or self.TeamSwap[OtherTeam] and "Approve" 
				or "Request",
				self:GetTeamString(OtherTeam) )
	else
		Text = "Swap"
	end
	return Enabled, Text
end

function Plugin:FormatTeamHeading(team)
	local Text

	if self.myTeam == 0 then
		if Plugin.Config.ShowMarineAlienToPlayers then
			Text = StringFormat("%s (%s)", self.CaptainNames[team], self:GetTeamString(team))
		else
			-- show Captain names to everyone else for Team Names.
			Text = StringFormat("%s", self.CaptainNames[team])	
		end
	elseif Plugin.Config.ShowMarineAlienToCaptains then
		Text = StringFormat("%s (%s)", self.TeamNames[team], self:GetTeamString(team))
	else
		Text = StringFormat("%s", self.TeamNames[team])
	end
	self.Logger:Trace("FormatTeamHeading text [%s]", Text )
	return Text
end

-- Update TeamName from SGUI
function Plugin:UpdateTeamName(Input)
	self.Logger:Debug( "UpdateTeamName" )
	local teamInput = Input
	if teamInput == nil then
		teamInput = self:GUI_GetObj( nil, "teamInput" )
		if not SGUI.IsValid(teamInput)  then
			self.Logger:Debug( "UpdateTeamName not IsValid" )
		end
	end
	if not SGUI.IsValid(teamInput) then return end
	if self.myTeam == 0  then return end
	local Text = teamInput:GetText()
	self.Logger:Debug( "UpdateTeamName have team %s ", self.myTeam  )

	if Text and Text:len() > 0
	and Text ~= self.TeamNames[ self.myTeam]
	then
		self:SendNetworkMessage("SetTeamName", {team = self.myTeam, teamname = Text, settings=false}, true)
		self.Logger:Debug( "Send Team Name %s ", Text )
		self.TeamNames[self.myTeam] = Text
		self:GUI_SetText( self.myTeam, "teamLabel", self:FormatTeamHeading(self.myTeam) )
	end
end

function Plugin:UpdateTeamNameForTeam( Team, Input )
	self.Logger:Debug( "UpdateTeamNameForTeam %s %s", Team, Input )
	local teamInput = Input
	-- if teamInput == nil then
	-- 	teamInput = self:GUI_GetObj( nil, GetTeamID(Team, "Name") )
	-- 	if not SGUI.IsValid(teamInput)  then
	-- 		self.Logger:Debug( "UpdateTeamNameForTeam not IsValid" )
	-- 	end
	-- end
	if not SGUI.IsValid(teamInput) then
		return
	end
	if not (Team == 1 or Team == 2) then return end
	local Text = teamInput:GetText()
	self.Logger:Debug( "UpdateTeamName have team %s ", Team  )

	if Text and Text:len() > 0
	and Text ~= self.TeamNames[ Team ]
	then
		self:SendNetworkMessage("SetTeamName", {team = Team, teamname = Text, settings=true}, true)
		self.Logger:Debug( "Send Team Name %s ", Text )
		self.TeamNames[ Team ] = Text
		self:GUI_SetText( Team, "teamLabel", self:FormatTeamHeading(Team) )
	end	
end


function Plugin:GUI_AddObj( team, name, obj )
	self.myGUIObjs = self.myGUIObjs or {}
	if team and (team == 1 or team == 2) then
		self.myGUIObjs["team"] = self.myGUIObjs["team"] or  {}
		self.myGUIObjs["team"][team] = self.myGUIObjs["team"][team] or {}
		self.myGUIObjs["team"][team][name] = obj
		self.Logger:Trace("AddObj add team %s %s", team, name )
	else
		self.myGUIObjs[name] = obj
		self.Logger:Trace("AddObj add %s", name )
	end
end

function Plugin:GUI_GetObj( team, name )
	self.myGUIObjs = self.myGUIObjs or {}
	local myObj = nil
	if team and (team == 1 or team == 2) then
		self.Logger:Debug("Plugin:GUI:GetObj team %s", team)
		teamObj = self.myGUIObjs["team"]
		if not (teamObj and teamObj[team]) then
			self.Logger:Debug("Plugin:GUI:GetObj team not found")
			return myObj
		end
		myObj = teamObj[team][name]
		self.Logger:Debug("Plugin:GUI:GetObj team %s %s", team, name )
	else
		myObj = self.myGUIObjs[name]
		self.Logger:Debug("Plugin:GUI:GetObj %s", name )
	end
	-- We will do this when we use it anyway. so skip IsValid for now.
	if not SGUI.IsValid(myObj) then
		self.Logger:Debug("Plugin:GUI:GetObj object not IsValid.")
		return myObj
	end
	return myObj
end

function Plugin:GUI_SetText( team, name, text, ... )
	local myObj = self:GUI_GetObj( team, name )
	if not SGUI.IsValid(myObj) then
		self.Logger:Trace("Plugin:GUI:SetText object invalid.")
		return
	end
	if not myObj.SetText then return end
	if not ... then
		myObj:SetText(text)
		self.Logger:Trace("Plugin:GUI:SetText text \"%s\"", text)
	else
		local formatText = StringFormat(text, ...)
		myObj:SetText( formatText )
		self.Logger:Trace("Plugin:GUI:SetText StringFormat \"%s\"", formatText )
	end
end


function Plugin:NetworkUpdate( Key, Old, New )
	self.Logger:Trace( "NetworkUpdate %s %s %s", Key, Old, New )

	if Key == "Team1Name" then
		self.TeamNames[1] = self.dt.Team1Name
		self.DoTeamNameChange = true
	elseif Key == "Team2Name" then
		self.TeamNames[2] = self.dt.Team2Name
		self.DoTeamNameChange = true
	elseif Key == "CaptainTurn" then
		self:UpdateTurn()
	end
end

function Plugin:OnPickPlayer(PickID)
	self.Logger:Debug( "Plugin:OnPickPlayer %s",PickID  )
	self:SendNetworkMessage("PickPlayer", {pickid = PickID}, true)
end

function Plugin:OnTradePlayer(PickID)
	self.Logger:Debug( "Plugin:OnTradePlayer %s",PickID  )
	self:SendNetworkMessage("TradePlayer", {pickid = PickID}, true)
end

function Plugin:OnRequestSwapTeams( Team, FromSettings )
	self.Logger:Debug("Plugin:RequestSwapTeams")
	self:SendNetworkMessage("RequestSwapTeams" , {team = Team, settings = FromSettings}, true)
end

--[[
	ReceiveTeamSwapRequested
		receive the request from the other captain to swap teams.
]] 
function Plugin:ReceiveTeamSwapRequested(Data)
	local team = Data.team
	if not (team == 1 or team == 2) then return end
	self.Logger:Debug("Plugin:ReceiveTeamSwapRequested %s", team)
	self.TeamSwap[team] = true

	local SwapTeamButton = self:GUI_GetObj( 0, "SwapTeamButton" )
	if SGUI.IsValid( SwapTeamButton ) 
	and SwapTeamButton:GetIsVisible() then
		self.Logger:Trace( "Update text SwapTeamButton" )
		local swapEnabled, swapText = self:FormatSwapText()
		SwapTeamButton:SetEnabled( swapEnabled )
		SwapTeamButton:SetText( swapText )
	end
	SwapTeamButton = self:GUI_GetObj( 0, "ID1TeamSwap" )
	if SGUI.IsValid( SwapTeamButton ) 
	and SwapTeamButton:GetIsVisible() then
		self.Logger:Trace( "Update text ID1TeamSwap" )
		local swapEnabled, swapText = self:FormatSwapText(1)
		SwapTeamButton:SetText( swapText )
	end
	SwapTeamButton = self:GUI_GetObj( 0, "ID2TeamSwap" )
	if SGUI.IsValid( SwapTeamButton ) 
	and SwapTeamButton:GetIsVisible() then
		self.Logger:Trace( "Update text ID2TeamSwap" )
		local swapEnabled, swapText = self:FormatSwapText(2)
		SwapTeamButton:SetText( swapText )
	end		

	-- The other captain has requested to swap teams.
	-- set button text to "Approve Swap"
end

--[[
	ReceiveSwapTeams
		Both captains agree to swap teams.
]] 
function Plugin:ReceiveSwapTeams(Data) 
	self.Logger:Debug("Plugin:ReceiveSwapTeams")
	self.TeamSwap = {false, false}
	self.Team1IsMarines = Data.team1marines
	if self.Team1IsMarines then
		self.TeamIndex = {1, 2}
	else
		self.TeamIndex = {2, 1}
	end
	-- fix team names.
	self:GUI_SetText( 1, "teamLabel", self:FormatTeamHeading(1) )
	self:GUI_SetText( 2, "teamLabel", self:FormatTeamHeading(2) )
	if self.myTeam ~= 0 then
		self:GUI_SetText( nil, "teamInput", self.TeamNames[self.myTeam] )
		self:GUI_SetText( nil, "ListTitleTeamText", self:GetTeamString(self.myTeam) )
	end
	self:GUI_SetText( nil, "ID1TeamName", self.TeamNames[1] )
	self:GUI_SetText( nil, "ID2TeamName", self.TeamNames[2] )

	--self:GUI_SetText( nil, "SwapTeamButton", "Swap Teams" )	
	local SwapTeamButton = self:GUI_GetObj( 0, "SwapTeamButton" )
	if SGUI.IsValid( SwapTeamButton ) 
	and SwapTeamButton:GetIsVisible() then
		local swapEnabled, swapText = self:FormatSwapText()
		SwapTeamButton:SetEnabled( swapEnabled )
		SwapTeamButton:SetText( swapText )
	end
	SwapTeamButton = self:GUI_GetObj( 0, "ID1TeamSwap" )
	if SGUI.IsValid( SwapTeamButton ) 
	and SwapTeamButton:GetIsVisible() then
		local swapEnabled, swapText = self:FormatSwapText(1)
		SwapTeamButton:SetText( swapText )
	end
	SwapTeamButton = self:GUI_GetObj( 0, "ID2TeamSwap" )
	if SGUI.IsValid( SwapTeamButton ) 
	and SwapTeamButton:GetIsVisible() then
		local swapEnabled, swapText = self:FormatSwapText(2)
		SwapTeamButton:SetText( swapText )
	end	


end


function Plugin:Cleanup()
	self.Logger:Debug( "Plugin:Cleanup" )
	self:ResetTeamNames( )
	self:CaptainMenuCleanup()
	self.BaseClass.Cleanup(self)
end

function Plugin:CaptainMenuCleanup()
	self.Logger:Trace( "CaptainMenuCleanup" )
	if not SGUI.IsValid( self.Window ) then
	 	if self.Visible then
			SGUI:EnableMouse(false, self.Window)
		end
		return
	end
	self.Logger:Debug( "CaptainMenuCleanup Destroy Window" )
	-- Hide and destroy the window
	self.Window:SetIsVisible(false)
	SGUI:EnableMouse(false,self.Window)
	self.IgnoreRemove = true
	self.Window:Destroy()
	self.IgnoreRemove = nil
	self.Window = nil

	-- nil out all the SGUI items we are tracking
	self.myGUIObjs = nil
	self.PickListSort = nil
	self.PickList = nil
	self.PickListSort = nil
	self.PickList = nil
	self.PickRows = nil
	self.TeamList = nil
	self.TeamListSort = nil
	self.TeamListRows= nil

end


function Plugin:ReceiveStartCaptains(Data)
	self.Logger:Debug( "ReceiveStartCaptains" )

	self.ClientInProgress = true

	self.Team1IsMarines = Data.team1marines

	if self.Team1IsMarines then
		self.TeamIndex = {1, 2}
	else
		self.TeamIndex = {2, 1}
	end
	self.TeamNames[1] = self.dt.Team1Name
	self.TeamNames[2] = self.dt.Team2Name


	if SGUI.IsValid( self.Window ) then
		self.Logger:Debug( "ReceiveStartCaptains: Force New CaptainMenu" )
		self.IgnoreRemove = true
		self.Window:Destroy()
		self.IgnoreRemove = nil
	end

	self:SetIsVisible(true)
	--[[self:CaptainMenuInitialise()
	self.Window:SetIsVisible( true )
	self.Window:InvalidateLayout( true )
	SGUI:EnableMouse(true,self.Window)]]

	StartSoundEffect("sound/NS2.fev/marine/voiceovers/commander/online", 3)

end



function Plugin:ReceiveCaptainsMatchStart(Data)
	self.Logger:Debug( "ReceiveCaptainsMatchStart" )
	-- when the match starts.. remove stuff.

	self:SetIsVisible(false)
	-- Having issues with Hidden objects and OnLoseFocus
	-- Try Destroy.

	self.IgnoreRemove = true
	self.Window:Destroy()
	self.IgnoreRemove = nil
	self:CaptainMenuReset()

	self.MatchStart = true

end


function Plugin:ReceiveCaptainsMatchComplete(Data)
	self.Logger:Debug( "ReceiveCaptainsMatchComplete" )
	self:ResetState()

	if SGUI.IsValid( self.Window ) then
		Plugin:CaptainMenuCleanup()
	end

end

function Plugin:RequestCaptainOptions( )
	self:SendNetworkMessage( "RequestCaptainOptions", {}, true )
end

function Plugin:ReceiveCaptainOptions( Data )
	self.Logger:Trace( "ReceiveCaptainOptions")
	if self.Logger:IsTraceEnabled() then
		self.Logger:Trace( "ReceiveCaptainOptions Print")
		PrintTable( Data )
	end
	self.CaptainOptions = {
		ShowSettings = Data.ShowSettings 
	}
	if self.CaptainOptions.ShowSettings == true and self.CaptainMenuCreated then
		-- force new tab? or enable Settings.
	end
end

function Plugin:ReceiveEndCaptains(Data)
	self.Logger:Debug( "ReceiveEndCaptains" )
	self:ResetState()

	if SGUI.IsValid( self.Window ) then
		self:CaptainMenuCleanup()
		StartSoundEffect("sound/NS2.fev/marine/voiceovers/commander/commander_ejected")
	end

end


function Plugin:ReceivePlayerStatus(Data)
	-- Upsert player to local table
	local Exists = false

	local function GetTeamsAvgSkill(skill, skillOffset)
  		return Max(0, skill + skillOffset), Max(0, skill - skillOffset); -- Marine, Alien
	end
	local function BuildSkillText(skill, marineSkill, alienSkill)
		if skill == -1 then return nil end
		local description                = StringFormat("Skill: %i", skill)
		if marineSkill ~= alienSkill then
		    description = description .. StringFormat("\nMarine: %i", marineSkill)
			description = description .. StringFormat("\nAlien: %i", alienSkill)
		end
	    return description
	end


	self.Logger:Debug( "ReceivePlayerStatus  %s {%s %s %s %s %s %s} "
			, Data.name
			, Data.pickid
			, Data.steamid
			, Data.team
			, Data.pick
			, Data.isCaptain
			, Data.isPickable
			);

	-- Check if My StreamID is a captain.
	local SteamID = Client.GetSteamId()
	-- record which team captain the Client is.
	if SteamID == tonumber(Data.steamid)
	and Data.isCaptain == true
	then
		self.myTeam = tonumber(Data.pick)
		self.myPickid = Data.pickid
		self.otherTeam = (self.myTeam % 2) + 1
	end

	if Data.isCaptain and Data.pick > 0 then
		self.CaptainNames[Data.pick] = Data.name
	end

	Data.marine, Data.alien = GetTeamsAvgSkill( Data.skill, Data.skilloffset )
	-- Format Skill tooltip
	Data.skillText = BuildSkillText( Data.skill, Data.marine, Data.alien)

	for Index, Player in ipairs(self.Players) do
		if Player.pickid == Data.pickid then
			if Player.pick > 0 and Player.pick ~= Data.pick then
			-- pick change detected
				self.PickChange = true
				if Player.isPickable ~= Data.isPickable then
					self.SoldierLost = true
				end
			end

			self.Players[Index] = Data
			Exists = true
		end
	end
	if not Exists then
		table.insert(self.Players, Data)
	end
	-- Process Updates in Think so we can queue up a few before we run through them.
	self.QueuePlayerUpdate = true

end

function Plugin:OnFirstThink()
	self:CallModuleEvent("OnFirstThink")
	self.Delay = 0.5
	self.LastRun = Shared.GetTime()
	self.NextRun = self.LastRun+ self.Delay

	self.ProcessUnsetReady = false
	self.QueuePlayerUpdate = false
	self.QueuePickCompleteCheck = false
	self.SoldierLost = false
	self.DoTeamNameChange = false

	-- Hook into the scoreboard so we know when to hide
	Shine.Hook.SetupClassHook( "GUIScoreboard", "SendKeyEvent", "Captain_GUIScoreboardSendKeyEvent", "PassivePost")
	Shine.Hook.SetupClassHook( "GUIScoreboard", "UpdateTeam", "Captain_GUIScoreboardUpdateTeam", "PassivePost")

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


	if (self.QueuePlayerUpdate == true ) then
		self.QueuePlayerUpdate = false
		self:UpdatePlayers()
	end

	if (self.SoldierLost == true ) then
		self.SoldierLost = false
		StartSoundEffect("sound/NS2.fev/marine/voiceovers/soldier_lost", 5)
	end

	if (self.DoTeamNameChange == true ) then
		self.DoTeamNameChange = false
		self:SetTeamNames()
	end

	if (self.QueuePickCompleteCheck == true) then
		self.QueuePickCompleteCheck = false
		self:PicklistCheck()
	end


end

function Plugin:Captain_GUIScoreboardUpdateTeam(  scoreboard, updateTeam  )
	if self.dt.Suspended then return end

	--Plugin._GUIScoreboardUpdateTeam(scoreboard, updateTeam)
	local teamNameGUIItem = updateTeam["GUIs"]["TeamName"]
	local teamScores = updateTeam["GetScores"]()
	local teamNumber = updateTeam["TeamNumber"]

	if not (teamNumber == 1 or teamNumber == 2) then return end
	if not self.MatchStart then return end

	local nameIndex = self:GetTeamIndex(teamNumber)
	local originalHeaderText = teamNameGUIItem:GetText()
	local newTeamName = self.TeamNames[nameIndex]
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
--[[
	Allow the Captain window to Hide when Tab is pressed to view the scoreboard.
]]
function Plugin:Captain_GUIScoreboardSendKeyEvent(  Scoreboard, Key, Down )
	if self.dt.Suspended then return end
-- This will run on Every keypress.

	-- if GameStarted then return end
	if self.MatchStart then return end

	self.Scoreboard_IsVisible = self.Scoreboard_IsVisible or false
	self.Scoreboard_Captain = self.Scoreboard_Captain or false

	if not SGUI.IsValid( self.Window ) then
		return
	end

	if Scoreboard.visible and not self.Scoreboard_IsVisible then
		self.Scoreboard_IsVisible = true
		self.Scoreboard_Captain = self.Window:GetIsVisible()
		if not self.Scoreboard_Captain then
			return
		end
		-- Hide captains menu
		self.Window:SetIsVisible(false)
		SGUI:EnableMouse(false,self.Window)
		--self:FadeOut()
		self.Logger:Trace( "Hide Captains menu Showing Scoreboard")

	elseif not Scoreboard.visible and self.Scoreboard_IsVisible then
		self.Scoreboard_IsVisible = false
		if self.Scoreboard_Captain then
			-- Unhide Captains Menu
			self.Window:SetIsVisible( true )
			SGUI:EnableMouse( true, self.Window )
			--self:FadeIn()
			self.Logger:Trace( "Unhide Captains menu Post Scoreboard")
		end
		return
	end

end

function Plugin:FadeIn()

	if not SGUI.IsValid( self.Window ) then
		return
	end

	SGUI:EnableMouse( true, self.Window )

	self.Window:SetIsVisible( true )
	self.Window:ApplyTransition( {
		Type = "Alpha",
		StartValue = 0,
		EndValue = 1,
		Duration = 0.3
	} )

end

local function OnFadeOutComplete( self )
	-- self is Plugin.Window
	self:SetIsVisible( false )
	--SGUI:EnableMouse(true,self.Window)
end

function Plugin:FadeOut( )

	if not SGUI.IsValid( self.Window ) then
		return
	end

	self.Window:ApplyTransition( {
		Type = "Alpha",
		EndValue = 0,
		Duration = 0.3,
		Callback = OnFadeOutComplete
	} )
end


function Plugin:ReceivePickNotification(Data)
	Client.WindowNeedsAttention()

	StartSoundEffect("sound/NS2.fev/common/ping")

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

function Plugin:ResetTeamNames()

	Shared.ConsoleCommand( "teams \"reset\"" )

end

function Plugin:GetTeamIndex( team )
	if self.TeamIndex[1] == team then
		return 1
	elseif self.TeamIndex[2] == team then
		return 2
	end
end
function Plugin:GetMarineName( )
	return self.TeamNames[self:GetTeamIndex(1)]
end
function Plugin:GetAlienName( )
	return self.TeamNames[self:GetTeamIndex(2)]	
end
function Plugin:GetTeamString( team )
	-- TeamStrings are also translated. But in this case its the Captain Index we are converting.
	return self.TeamStrings[self:GetTeamIndex(team)]
end

function Plugin:SetTeamNames( MarineName, AlienName )

	if MarineName == nil
	or AlienName == nil then
		Shared.ConsoleCommand( StringFormat( "teams \"%s\" \"%s\"", self:GetMarineName(), self:GetAlienName() ) )
		self.Logger:Info( "Captains Mode: teams \"%s\" \"%s\"" , self:GetMarineName(), self:GetAlienName() )
		return
	end

	if MarineName == "" and AlienName == "" then return end

	Shared.ConsoleCommand( StringFormat( "teams \"%s\" \"%s\"", MarineName, AlienName ) )

	self.Logger:Info( "Captains Mode: teams \"%s\" \"%s\"" , MarineName, AlienName)

end

function Plugin:ReceiveTeamNamesNotification(Data)

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
