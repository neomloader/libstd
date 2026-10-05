local ffi = require 'ffi'
local imgui = require 'mimgui'
local vmajor, vminor, vpatch = string.match(imgui._VERSION, '(%d+)%.(%d+)%.(%d+)')
local ImVec2 = imgui.ImVec2
local ImVec4 = imgui.ImVec4
local ImColor = imgui.ImColor

local function ImRectAdd(rect, rhs)
	local Min, Max = rect.Min, rect.Max
	if Min.x > rhs.x then Min.x = rhs.x end
	if Min.y > rhs.y then Min.y = rhs.y end
	if Max.x < rhs.x then Max.x = rhs.x end
	if Max.y < rhs.y then Max.y = rhs.y end
end

local function NewPieMenu(context)
	local obj = {
		m_iCurrentIndex = 0,
		m_fMaxItemSqrDiameter = 0,
		m_fLastMaxItemSqrDiameter = 0,
		m_iHoveredItem = 0,
		m_iLastHoveredItem = 0,
		m_iClickedItem = 0,
		m_oItemIsSubMenu = {},
		m_oItemNames = {},
		m_oItemSizes = {},
	}
	return obj
end

local function NewPieMenuContext(MaxPieMenuStack, MaxPieItemCount, RadiusEmpty, RadiusMin, MinItemCount, MinItemCountPerLevel)
	local obj = {
		c_iMaxPieMenuStack = MaxPieMenuStack or 8,
		c_iMaxPieItemCount = MaxPieItemCount or 12,
		c_iRadiusEmpty = RadiusEmpty or (30 * (MONET_DPI_SCALE or 1)),
		c_iRadiusMin = RadiusMin or (30 * (MONET_DPI_SCALE or 1)),
		c_iMinItemCount = MinItemCount or 3,
		c_iMinItemCountPerLevel = MinItemCountPerLevel or 3,

		m_oPieMenuStack = {},
		m_iCurrentIndex = -1,
		m_iLastFrame = 0,
		m_iMaxIndex = 0,
		m_oCenter = ImVec2(0, 0),
		m_iMouseButton = 1,
		m_bClose = false,
	}
	for i = 0, obj.c_iMaxPieMenuStack - 1 do
		obj.m_oPieMenuStack[i] = NewPieMenu(obj)
	end
	return obj
end

local function BeginPieMenuEx(menuCtx)
	if menuCtx.m_iCurrentIndex >= menuCtx.c_iMaxPieMenuStack - 1 then
		menuCtx.m_iCurrentIndex = menuCtx.c_iMaxPieMenuStack - 2
	end
	menuCtx.m_iCurrentIndex = menuCtx.m_iCurrentIndex + 1
	menuCtx.m_iMaxIndex = math.max(menuCtx.m_iMaxIndex, menuCtx.m_iCurrentIndex)
	local oPieMenu = menuCtx.m_oPieMenuStack[menuCtx.m_iCurrentIndex]
	if oPieMenu then
		oPieMenu.m_iCurrentIndex = 0
		oPieMenu.m_fMaxItemSqrDiameter = 0
		if imgui.IsMouseClicked(0) then
			oPieMenu.m_iHoveredItem = -1
		end
		if menuCtx.m_iCurrentIndex > 0 then
			local prev = menuCtx.m_oPieMenuStack[menuCtx.m_iCurrentIndex - 1]
			if prev then
				oPieMenu.m_fMaxItemSqrDiameter = prev.m_fMaxItemSqrDiameter
			end
		end
	end
end

local function EndPieMenuEx(menuCtx)
	if menuCtx.m_iCurrentIndex >= 0 then
		menuCtx.m_iCurrentIndex = menuCtx.m_iCurrentIndex - 1
	end
end

local function BeginPiePopup(menuCtx, pName, iMouseButton)
	iMouseButton = iMouseButton or 0
	if imgui.IsPopupOpen(pName) then
		imgui.PushStyleColor(imgui.Col.WindowBg, ImVec4(0, 0, 0, 0))
		imgui.PushStyleColor(imgui.Col.Border, ImVec4(0, 0, 0, 0))
		imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 0.0)
		imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, 1.0)
		menuCtx.m_iMouseButton = iMouseButton
		menuCtx.m_bClose = false

		local defaultCenter = nil
		local itemMin = imgui.GetItemRectMin()
		local itemMax = imgui.GetItemRectMax()
		if itemMin and itemMax and itemMax.x > itemMin.x and itemMax.y > itemMin.y and itemMin.x > 0 and itemMin.y > 0 then
			defaultCenter = ImVec2((itemMin.x + itemMax.x) * 0.5, (itemMin.y + itemMax.y) * 0.5)
		else
			local wpos = imgui.GetWindowPos()
			local wsz = imgui.GetWindowSize()
			if wpos and wsz and wsz.x > 0 and wsz.y > 0 and wpos.x > 0 and wpos.y > 0 then
				defaultCenter = ImVec2(wpos.x + wsz.x * 0.5, wpos.y + wsz.y * 0.5)
			end
		end

		imgui.SetNextWindowPos( ImVec2( -100, -100 ), imgui.Cond.Appearing )
		imgui.SetNextWindowSize(ImVec2(0, 0), imgui.Cond.Always)
		local bOpened = imgui.BeginPopup(pName)
		if bOpened then
			local iCurrentFrame = imgui.GetFrameCount()
			if menuCtx.m_iLastFrame < (iCurrentFrame - 1) then
				menuCtx.m_iOpenFrame = iCurrentFrame
				menuCtx.m_bClose = false
				for i = 0, menuCtx.c_iMaxPieMenuStack - 1 do
					local pm = menuCtx.m_oPieMenuStack[i]
					if pm then
						pm.m_iHoveredItem = -1
						pm.m_iLastHoveredItem = -1
					end
				end
				local io = imgui.GetIO()
				local clickPos = io.MouseClickedPos and io.MouseClickedPos[0]
				local mp = io.MousePos
				local disp = io.DisplaySize
				if defaultCenter and defaultCenter.x > 0 and defaultCenter.y > 0 then
					menuCtx.m_oCenter = defaultCenter
				elseif clickPos and clickPos.x > 0 and clickPos.y > 0 and clickPos.x < 10000 and clickPos.y < 10000 then
					menuCtx.m_oCenter = ImVec2(clickPos.x, clickPos.y)
				elseif mp and mp.x > 0 and mp.y > 0 and mp.x < 10000 and mp.y < 10000 then
					menuCtx.m_oCenter = ImVec2(mp.x, mp.y)
				elseif disp and disp.x > 0 and disp.y > 0 then
					menuCtx.m_oCenter = ImVec2(disp.x * 0.5, disp.y * 0.5)
				else
					menuCtx.m_oCenter = ImVec2(500, 500)
				end
			end
			menuCtx.m_iLastFrame = iCurrentFrame
			menuCtx.m_iMaxIndex = -1
			menuCtx.m_iCurrentIndex = -1
			BeginPieMenuEx(menuCtx)
			return true
		else
			imgui.PopStyleColor(2)
			imgui.PopStyleVar(2)
		end
	end
	return false
end

local function EndPiePopup(menuCtx)
	EndPieMenuEx(menuCtx)
	local pDrawList = imgui.GetWindowDrawList()
	local oStyle = imgui.GetStyle()
	local ok, err = pcall(function()
		pDrawList:PushClipRectFullScreen()
		local oMousePos = imgui.GetIO().MousePos
		local oDragDelta = ImVec2(oMousePos.x - menuCtx.m_oCenter.x, oMousePos.y - menuCtx.m_oCenter.y)
		local fDragDistSqr = oDragDelta.x*oDragDelta.x + oDragDelta.y*oDragDelta.y
		local fCurrentRadius = menuCtx.c_iRadiusEmpty

		local oArea = {Min = ImVec2(menuCtx.m_oCenter), Max = ImVec2(menuCtx.m_oCenter)}
		local bItemHovered = false
		local c_fDefaultRotate = -math.pi / 2
		local fLastRotate = c_fDefaultRotate
		for iIndex = 0, menuCtx.m_iMaxIndex do
			local oPieMenu = menuCtx.m_oPieMenuStack[iIndex]
			if not oPieMenu then break end
			local fMenuHeight = math.sqrt(oPieMenu.m_fMaxItemSqrDiameter)
			local fMinRadius = fCurrentRadius
			local fMaxRadius = fMinRadius + (fMenuHeight * oPieMenu.m_iCurrentIndex) / 2
			local item_arc_span = 2 * math.pi / math.max(menuCtx.c_iMinItemCount + menuCtx.c_iMinItemCountPerLevel * iIndex, oPieMenu.m_iCurrentIndex)
			local drag_angle = math.atan2(oDragDelta.y, oDragDelta.x)
			local fRotate = fLastRotate - item_arc_span * ( oPieMenu.m_iCurrentIndex - 1 ) / 2
			local item_hovered = -1
			for item_n = 0, oPieMenu.m_iCurrentIndex - 1 do
				local item_label = oPieMenu.m_oItemNames[ item_n ]
				local inner_spacing = oStyle.ItemInnerSpacing.x / fMinRadius / 2
				local fMinInnerSpacing = oStyle.ItemInnerSpacing.x / ( fMinRadius * 2 )
				local fMaxInnerSpacing = oStyle.ItemInnerSpacing.x / ( fMaxRadius * 2 )
				local item_inner_ang_min = item_arc_span * ( item_n - 0.5 + fMinInnerSpacing ) + fRotate
				local item_inner_ang_max = item_arc_span * ( item_n + 0.5 - fMinInnerSpacing ) + fRotate
				local item_outer_ang_min = item_arc_span * ( item_n - 0.5 + fMaxInnerSpacing ) + fRotate
				local item_outer_ang_max = item_arc_span * ( item_n + 0.5 - fMaxInnerSpacing ) + fRotate
				local hovered = false
				if fDragDistSqr >= fMinRadius * fMinRadius and fDragDistSqr < fMaxRadius * fMaxRadius  then
					while (drag_angle - item_inner_ang_min) < 0 do
						drag_angle = drag_angle + (2 * math.pi)
					end
					while (drag_angle - item_inner_ang_min) > 2 * math.pi do
						drag_angle = drag_angle - (2 * math.pi)
					end
					if drag_angle >= item_inner_ang_min and drag_angle < item_inner_ang_max  then
						hovered = true
						bItemHovered = true
					end
				end

				local arc_segments = math.floor(( 32 * item_arc_span / ( 2 * math.pi ) ) + 1)
				local iColor = imgui.GetColorU32( hovered and imgui.Col.ButtonHovered or imgui.Col.Button )
				local fAngleStepInner = (item_inner_ang_max - item_inner_ang_min) / arc_segments
				local fAngleStepOuter = ( item_outer_ang_max - item_outer_ang_min ) / arc_segments
				pDrawList:PrimReserve(arc_segments * 6, (arc_segments + 1) * 2)
				for iSeg = 0, arc_segments do
					local fCosInner = math.cos(item_inner_ang_min + fAngleStepInner * iSeg)
					local fSinInner = math.sin(item_inner_ang_min + fAngleStepInner * iSeg)
					local fCosOuter = math.cos(item_outer_ang_min + fAngleStepOuter * iSeg)
					local fSinOuter = math.sin(item_outer_ang_min + fAngleStepOuter * iSeg)

					if iSeg < arc_segments then
						local VtxCurrentIdx = pDrawList._VtxCurrentIdx
						pDrawList:PrimWriteIdx(VtxCurrentIdx + 0)
						pDrawList:PrimWriteIdx(VtxCurrentIdx + 2)
						pDrawList:PrimWriteIdx(VtxCurrentIdx + 1)
						pDrawList:PrimWriteIdx(VtxCurrentIdx + 3)
						pDrawList:PrimWriteIdx(VtxCurrentIdx + 2)
						pDrawList:PrimWriteIdx(VtxCurrentIdx + 1)
					end
					local pos = ImVec2(menuCtx.m_oCenter.x + fCosInner * (fMinRadius + oStyle.ItemInnerSpacing.x), menuCtx.m_oCenter.y + fSinInner * (fMinRadius + oStyle.ItemInnerSpacing.x))
					local pos2 = ImVec2(menuCtx.m_oCenter.x + fCosOuter * (fMaxRadius - oStyle.ItemInnerSpacing.x), menuCtx.m_oCenter.y + fSinOuter * (fMaxRadius - oStyle.ItemInnerSpacing.x))
					local white_uv = (pDrawList._Data ~= nil and pDrawList._Data ~= ffi.null) and pDrawList._Data.TexUvWhitePixel or imgui.GetFontTexUvWhitePixel()
					pDrawList:PrimWriteVtx(pos, white_uv, iColor)
					pDrawList:PrimWriteVtx(pos2, white_uv, iColor)
				end

				local fRadCenter = ( item_arc_span * item_n ) + fRotate
				local oOuterCenter = ImVec2( menuCtx.m_oCenter.x + math.cos( fRadCenter ) * fMaxRadius, menuCtx.m_oCenter.y + math.sin( fRadCenter ) * fMaxRadius )
				ImRectAdd(oArea, oOuterCenter)
				if oPieMenu.m_oItemIsSubMenu[item_n] then
					local oTrianglePos = {ImVec2(), ImVec2(), ImVec2()}
					local fRadLeft = fRadCenter - 5 / fMaxRadius
					local fRadRight = fRadCenter + 5 / fMaxRadius
					oTrianglePos[ 0+1 ].x = menuCtx.m_oCenter.x + math.cos( fRadCenter ) * ( fMaxRadius - 5 )
					oTrianglePos[ 0+1 ].y = menuCtx.m_oCenter.y + math.sin( fRadCenter ) * ( fMaxRadius - 5 )
					oTrianglePos[ 1+1 ].x = menuCtx.m_oCenter.x + math.cos( fRadLeft ) * ( fMaxRadius - 10 )
					oTrianglePos[ 1+1 ].y = menuCtx.m_oCenter.y + math.sin( fRadLeft ) * ( fMaxRadius - 10 )
					oTrianglePos[ 2+1 ].x = menuCtx.m_oCenter.x + math.cos( fRadRight ) * ( fMaxRadius - 10 )
					oTrianglePos[ 2+1 ].y = menuCtx.m_oCenter.y + math.sin( fRadRight ) * ( fMaxRadius - 10 )
					pDrawList:AddTriangleFilled(oTrianglePos[1], oTrianglePos[2], oTrianglePos[3], 0xFFFFFFFF)
				end
				local text_size = ImVec2(oPieMenu.m_oItemSizes[item_n])
				local text_pos = ImVec2(
					menuCtx.m_oCenter.x + math.cos((item_inner_ang_min + item_inner_ang_max) * 0.5) * (fMinRadius + fMaxRadius) * 0.5 - text_size.x * 0.5,
					menuCtx.m_oCenter.y + math.sin((item_inner_ang_min + item_inner_ang_max) * 0.5) * (fMinRadius + fMaxRadius) * 0.5 - text_size.y * 0.5)
				pDrawList:AddText(text_pos, imgui.GetColorU32(imgui.Col.Text), item_label)
				if hovered then
					item_hovered = item_n
				end
			end
			fCurrentRadius = fMaxRadius
			oPieMenu.m_fLastMaxItemSqrDiameter = oPieMenu.m_fMaxItemSqrDiameter
			if fDragDistSqr >= fMaxRadius * fMaxRadius then
				item_hovered = oPieMenu.m_iLastHoveredItem
			elseif fDragDistSqr >= fMinRadius * fMinRadius then
				bItemHovered = true
			end
			oPieMenu.m_iHoveredItem = item_hovered
			oPieMenu.m_iLastHoveredItem = item_hovered
			fLastRotate = item_arc_span * oPieMenu.m_iLastHoveredItem + fRotate
			if item_hovered == -1 or not oPieMenu.m_oItemIsSubMenu[item_hovered] then
				break
			end
		end
		if fDragDistSqr < fCurrentRadius * fCurrentRadius then
			bItemHovered = true
		end
		pDrawList:PopClipRect()
		if oArea.Min.x < 0  then
			menuCtx.m_oCenter.x = ( menuCtx.m_oCenter.x - oArea.Min.x )
		end
		if oArea.Min.y < 0  then
			menuCtx.m_oCenter.y = ( menuCtx.m_oCenter.y - oArea.Min.y )
		end
		local oDisplaySize = imgui.GetIO().DisplaySize
		if oDisplaySize and oDisplaySize.x > 0 and oDisplaySize.y > 0 then
			if oArea.Max.x > oDisplaySize.x  then
				menuCtx.m_oCenter.x = ( menuCtx.m_oCenter.x - oArea.Max.x ) + oDisplaySize.x
			end
			if oArea.Max.y > oDisplaySize.y  then
				menuCtx.m_oCenter.y = ( menuCtx.m_oCenter.y - oArea.Max.y ) + oDisplaySize.y
			end
		end
		local isReleased = imgui.IsMouseReleased(0) or (menuCtx.m_iMouseButton and imgui.IsMouseReleased(menuCtx.m_iMouseButton))
		local isClicked = imgui.IsMouseClicked(0) or (menuCtx.m_iMouseButton and imgui.IsMouseClicked(menuCtx.m_iMouseButton))
		local curFrame = imgui.GetFrameCount()
		if menuCtx.m_bClose or (menuCtx.m_iOpenFrame and curFrame > menuCtx.m_iOpenFrame + 5 and not bItemHovered and (isClicked or isReleased)) then
			imgui.CloseCurrentPopup()
		end
	end)
	if not ok then
		pcall(function() pDrawList:PopClipRect() end)
		print("[imgui_piemenu] Error in EndPiePopup drawing: " .. tostring(err))
	end
	imgui.EndPopup()
	imgui.PopStyleColor(2)
	imgui.PopStyleVar(2)
end

local function BeginPieMenu(menuCtx, pName, bEnabled)
	if menuCtx.m_iCurrentIndex < 0 or menuCtx.m_iCurrentIndex >= menuCtx.c_iMaxPieItemCount then
		return false
	end
	bEnabled = bEnabled or true
	local oPieMenu = menuCtx.m_oPieMenuStack[menuCtx.m_iCurrentIndex]
	if not oPieMenu then return false end
	local oTextSize = imgui.CalcTextSize(pName)
	oPieMenu.m_oItemSizes[oPieMenu.m_iCurrentIndex] = oTextSize
	local dpi = MONET_DPI_SCALE or 1
 	local fSqrDiameter = oTextSize.x * 15 * dpi + oTextSize.y * 30 * dpi
	if fSqrDiameter > oPieMenu.m_fMaxItemSqrDiameter then
		oPieMenu.m_fMaxItemSqrDiameter = fSqrDiameter
	end
	oPieMenu.m_oItemIsSubMenu[oPieMenu.m_iCurrentIndex] = true
	oPieMenu.m_oItemNames[oPieMenu.m_iCurrentIndex] = pName
	local itemIdx = oPieMenu.m_iCurrentIndex
	if oPieMenu.m_iLastHoveredItem == itemIdx or oPieMenu.m_iHoveredItem == itemIdx then
		oPieMenu.m_iCurrentIndex = itemIdx + 1
		BeginPieMenuEx(menuCtx)
		return true
	end
	oPieMenu.m_iCurrentIndex = itemIdx + 1
	return false
end

local function EndPieMenu(menuCtx)
	if menuCtx.m_iCurrentIndex >= 0 then
		menuCtx.m_iCurrentIndex = menuCtx.m_iCurrentIndex - 1
	end
end

local function PieMenuItem(menuCtx, pName, bEnabled)
	if menuCtx.m_iCurrentIndex < 0 or menuCtx.m_iCurrentIndex >= menuCtx.c_iMaxPieItemCount then
		return false
	end
	bEnabled = bEnabled or true
	local oPieMenu = menuCtx.m_oPieMenuStack[menuCtx.m_iCurrentIndex]
	if not oPieMenu then return false end
	local oTextSize = imgui.CalcTextSize(pName)
	oPieMenu.m_oItemSizes[oPieMenu.m_iCurrentIndex] = oTextSize
	local dpi = MONET_DPI_SCALE or 1
	local fSqrDiameter = oTextSize.x * 15 * dpi + oTextSize.y * 30 * dpi
	if fSqrDiameter > oPieMenu.m_fMaxItemSqrDiameter then
		oPieMenu.m_fMaxItemSqrDiameter = fSqrDiameter
	end
	oPieMenu.m_oItemIsSubMenu[oPieMenu.m_iCurrentIndex] = false
	oPieMenu.m_oItemNames[oPieMenu.m_iCurrentIndex] = pName
	local isReleased = imgui.IsMouseReleased(0) or (menuCtx.m_iMouseButton and imgui.IsMouseReleased(menuCtx.m_iMouseButton))
	local isClicked = imgui.IsMouseClicked(0)
	local curFrame = imgui.GetFrameCount()
	local itemIdx = oPieMenu.m_iCurrentIndex
	local isHovered = (itemIdx == oPieMenu.m_iHoveredItem) or (itemIdx == oPieMenu.m_iLastHoveredItem)
	local bActive = isHovered and (isReleased or isClicked) and (curFrame > (menuCtx.m_iOpenFrame or 0) + 2)
	oPieMenu.m_iCurrentIndex = itemIdx + 1
	if bActive then
		menuCtx.m_bClose = true
	end
	return bActive
end

local function New(...)
	local menuContext = NewPieMenuContext(...)
	return {
		BeginPiePopup = function(name, mouseButton)
			local r = BeginPiePopup(menuContext, name, mouseButton)
			return r
		end,
		EndPiePopup = function()
			local r = EndPiePopup(menuContext)
			return r
		end,
		PieMenuItem = function(name, enabled)
			local r = PieMenuItem(menuContext, name, enabled)
			return r
		end,
		BeginPieMenu = function(name, enabled)
			local r = BeginPieMenu(menuContext, name, enabled)
			return r
		end,
		EndPieMenu = function()
			local r = EndPieMenu(menuContext)
			return r
		end
	}
end

local defaultPieMenu = New()
defaultPieMenu.New = New
return defaultPieMenu
