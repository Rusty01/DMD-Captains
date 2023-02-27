--[[
	Captains Mode client.
]]

local Plugin = ...

local Shine = Shine
local SGUI = Shine.GUI
local StringFormat = string.format
local TableConcat = table.concat
local Max = math.max;

local CaptainMenu = {}

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )
	
	self.Enabled = true
	self:ResetState()
	
	self.Window = nil
	self.Created = false
	self:CaptainMenuReset()	
	
	return true
end

function Plugin:ResetState()
	self.Logger:Trace( "Reset State") 
	
	self.Players = {}
	self.IsReady = false
	self.QueuePlayerUpdate = false
	
	self.myPickid = ""
	self.myTeam = 0
	self.myTeamName = ""
	self.myTeamReady = false
	self.Team1IsMarines = true
	self.TeamStrings = {"Marines", "Aliens"}
	self.TeamIndex = {1, 2}
	self.TeamNames = {"Marines", "Aliens"}
	self.CaptainNames = {"One","Two"}
	self:SetTeamNames( )
	
	self.MatchStart = false
	self.InProgress = false
	
end


function Plugin:CaptainMenuReset()
	self.Logger:Debug( "Reset Menu")
	
	self.myGUIObjs = nil
	
	self.PickListSort = {SortedColumn = 2, Descending = false}
	self.PickList = nil
	self.PickRows = {}
	
	self.TeamList = {}
	self.TeamListSort = {{SortedColumn = 2, Descending = false},{SortedColumn = 2, Descending = false}}
	self.TeamListRows= {{},{}}
	self.TeamSkill = {0,0}
	self.TeamCount = {0,0}
	self.TeamNotice = {"",""}
	
	self.myTeamInput = nil
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

			local PickList = Panel:Add("List")
			PickList:SetAnchor("TopLeft")
			PickList:SetSize(Vector(self.PanelSize.x * 0.96, self.PanelSize.y * 0.74, 0))
			PickList:SetPos(Vector(self.PanelSize.x * 0.02, self.PanelSize.y * 0.09, 0))
			PickList:SetColumns("NS2ID", "Name", "Marine", "Alien", "Room")
			--PickList:SetSpacing(0.3, 0.55, 0.15)
			PickList:SetSpacing(0.15, 0.50, 0.10, 0.10, 0.15)
			PickList:SetNumericColumn(1)
			PickList:SetNumericColumn(3)
			PickList:SetNumericColumn(4)
			PickList.TitlePanel = ListTitlePanel
			PickList.TitleText = ListTitleText
			
			self.PickList = PickList
			
			self.PickList.SortedColumn = self.PickListSort.SortedColumn
			self.PickList.Descending = self.PickListSort.Descending

			
			self.PickRows = {}

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
			
			self:GUI_AddObj( nil, "TurnText", Turn )
			self:GUI_AddObj( nil, "PickButton", Pick )

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
				--self.TeamTitles[i] = ListTitleText
				
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
		
					function myTeamInput.OnLoseFocus()
						-- this never gets called when the tab changes.
						if not SGUI.IsValid(myTeamInput) then return end
						if not myTeamInput:HasFocus() then return end
						self:UpdateTeamName(myTeamInput)
					end
		
					function myTeamInput.OnEnter()
						self:UpdateTeamName(myTeamInput)
					end
					
					function myTeamInput.OnEscape()
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
					self:SendNetworkMessage("SetReady", {ready = self.myTeamReady}, true)
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
				self:SendNetworkMessage("RequestEndCaptains", {}, true)
				if self.myTeam == 0 then
					self:SetIsVisible( false )
				end
			end

		end
	)
		
	self.CaptainMenuCreated = true
	
	self.Logger:Debug( "CaptainMenu Initialise done" )

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


	for pickid, Row in pairs( self.PickRows ) do
		if not ExistingPlayers[ pickid ] then
			self:PickListRemove( pickid, Row.Index, Row:GetColumnText(2) )
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
			Row:SetColumnText( 3, tostring( Ent.marine ) )
			Row:SetColumnText( 4, tostring( Ent.alien) )
			Row:SetColumnText( 5, Plugin:GetTeamName( Ent.team, true ) )
			Row:SetColumnText( 6, tostring( Ent.pickid ) )
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
		self.TeamNotice[1] = "Select a player to give the other team."
		self.TeamNotice[2] = "Wait for a player from the other team."
		local skillDiff = self.TeamSkill[1] - self.TeamSkill[2]
		if skillDiff > 0 then
			skillDiff = skillDiff / 2
			if skillDiff > 0 then 
				self.TeamNotice[1] = self.TeamNotice[1] ..  StringFormat( " Around Skill: %i", skillDiff )
			end
		end   
		
	elseif self.TeamCount[2] > (self.TeamCount[1]+1) then
		self.TeamNotice[2] = "Select a player to give the other team."
		self.TeamNotice[1] = "Wait for a player from the other team."
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
	if not self.InProgress then return end
	
	self.Logger:Debug( "ShowTeamMenu" )
	self:SetIsVisible( true , 2 )
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
end


function Plugin:FormatTeamHeading(team)
	local Text
	
	if self.myTeam == 0 then
	-- show Captain names to everyone else for Team Names.
		Text = StringFormat("Team- %s", self.CaptainNames[team])
		
	elseif Plugin.Config.ShowMarineAlienToCaptains then
		Text = StringFormat("%s (%s)", self.TeamNames[team], self.TeamStrings[team])
	else
		Text = StringFormat("%s", self.TeamNames[team])
	end
	self.Logger:Trace("FormatTeamHeading text [%s]", Text )
	return Text
end

-- Update TeamName from SGUI
function Plugin:UpdateTeamName(Input)
	self.Logger:Debug( "UpdateTeamName" )
	teamInput = Input
	if teamInput == nil then
		teamInput = self:GUI_GetObj( nil, "teamInput" )
		if not SGUI.IsValid(teamInput)  then 
			self.Logger:Debug( "UpdateTeamName not IsValid" )
		end
	end
	if not SGUI.IsValid(teamInput) then return end
	local Text = teamInput:GetText()
	if self.myTeam == 0  then return end
	self.Logger:Debug( "UpdateTeamName have team %s ", self.myTeam  ) 

	if Text and Text:len() > 0
	and Text ~= self.TeamNames[ self.myTeam]
	then
		self:SendNetworkMessage("SetTeamName", {teamname = Text}, true)
		self.Logger:Debug( "Send Team Name %s ", Text ) 
		self.TeamNames[self.myTeam] = Text
		self:GUI_SetText( self.myTeam, "teamLabel", self:FormatTeamHeading(self.myTeam) )
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
		self.Logger:Trace("Plugin:GUI:SetText text %s", text)
	else	
		myObj:SetText(StringFormat(text, ...))
		self.Logger:Trace("Plugin:GUI:SetText StringFormat %s", text)
	end
end


function Plugin:NetworkUpdate( Key, Old, New )
	self.Logger:Trace( "NetworkUpdate %s %s %s", Key, Old, New )

	if Key == "Team1Name" then
		self.TeamNames[1] = self.dt.Team1Name
	elseif Key == "Team2Name" then
		self.TeamNames[2] = self.dt.Team2Name
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


function Plugin:Cleanup()
	self.Logger:Debug( "Plugin:Cleanup" ) 
	self:SetTeamNames( )
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
	self.TeamTitles = nil
	self.myTeamInput = nil
	
end


function Plugin:ReceiveStartCaptains(Data)
	self.Logger:Debug( "ReceiveStartCaptains" )
	
	self.InProgress = true

	self.Team1IsMarines = Data.team1marines

	if self.Team1IsMarines then
		self.TeamStrings = {"Marines", "Aliens"}
		self.TeamIndex = {1, 2}
	else
		self.TeamStrings = {"Aliens", "Marines"}
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
	self.SoldierLost = false
	
	-- Hook into the scoreboard so we know when to hide	
	Shine.Hook.SetupClassHook( "GUIScoreboard", "SendKeyEvent", "Captain_GUIScoreboardSendKeyEvent", "PassivePost")
	
end

function Plugin:Think( DeltaTime )
	local Time = Shared.GetTime()
	if self.NextRun > Time then
		return
	end
	self.LastRun = Time
	self.NextRun = self.LastRun+ self.Delay
	
	if (self.ProcessUnsetReady ) then
		self.ProcessUnsetReady = false
		self:OnUnsetReady()
	end
	

	if (self.QueuePlayerUpdate == true ) then
		self.QueuePlayerUpdate = false
		self:UpdatePlayers()
	end
	
	if (self.SoldierLost) then
		self.SoldierLost = false
		StartSoundEffect("sound/NS2.fev/marine/voiceovers/soldier_lost", 5)
	end 
	
end

function Plugin:Captain_GUIScoreboardSendKeyEvent(  Scoreboard, Key, Down )
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


function Plugin:SetTeamNames( MarineName, AlienName )
	if MarineName == nil 
	or AlienName == nil then
		Shared.ConsoleCommand( "teams \"reset\"" )
		return
	end 
	
	if MarineName == "" and AlienName == "" then return end

	Shared.ConsoleCommand( StringFormat( "teams \"%s\" \"%s\"", MarineName, AlienName ) )
	
	self.Logger:Debug( "Captains Mode Team1 [%s] Team2 [%s]" , MarineName, AlienName)
	
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
