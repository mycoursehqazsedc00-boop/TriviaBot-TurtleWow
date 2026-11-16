--[[
--
-- TriviaBotOptions.lua
-- In-game Settings Menu for TriviaBot-TurtleWoW (Vanilla 1.12 / Lua 5.0 safe)
--
--]]

local isRefreshingOptions = false;

local SET_BUTTON_DEFS = {
	{ key = "warcraft",  label = "Warcraft + Turtle", countFn = function() return table.getn(TURTLE_TRIVIA_QUESTIONS) + table.getn(WOW_TRIVIA_QUESTIONS); end },
	{ key = "turtle",    label = "Turtle WoW Only",   countFn = function() return table.getn(TURTLE_TRIVIA_QUESTIONS); end },
	{ key = "wow",       label = "WoW & WC1-3",       countFn = function() return table.getn(WOW_TRIVIA_QUESTIONS); end },
	{ key = "geography", label = "Geography",         countFn = function() return table.getn(GEOGRAPHY_TRIVIA_QUESTIONS); end },
	{ key = "normal",    label = "General Trivia",    countFn = function() return table.getn(NORMAL_TRIVIA_QUESTIONS); end },
	{ key = "all",       label = "All Combined",      countFn = function() return table.getn(TURTLE_TRIVIA_QUESTIONS) + table.getn(WOW_TRIVIA_QUESTIONS) + table.getn(GEOGRAPHY_TRIVIA_QUESTIONS) + table.getn(NORMAL_TRIVIA_QUESTIONS); end }
};

local CHANNEL_BUTTON_DEFS = { "SAY", "PARTY", "RAID", "GUILD" };

local setButtons = {};
local channelButtons = {};

local function Trivia_CreateSectionHeader(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
	fs:SetText("|cffffd100" .. text .. "|r");
	return fs;
end

local function Trivia_CreateSetButton(parent, def, x, y, width)
	local btn = CreateFrame("Button", "TriviaOptSetBtn_" .. def.key, parent, "UIPanelButtonTemplate");
	btn:SetWidth(width);
	btn:SetHeight(22);
	btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
	btn.setKey = def.key;
	btn.baseLabel = def.label;
	btn.countFn = def.countFn;

	btn:SetScript("OnClick", function()
		if (TRIVIA_ENABLED) then
			Trivia_ErrorMessage("Stop Trivia first before changing the question set.");
			return;
		end
		Trivia_LoadQuestionSet(this.setKey, false);
		Trivia_RefreshOptionsFrame();
	end);

	return btn;
end

local function Trivia_CreateChannelButton(parent, chName, x, y, width)
	local btn = CreateFrame("Button", "TriviaOptChanBtn_" .. chName, parent, "UIPanelButtonTemplate");
	btn:SetWidth(width);
	btn:SetHeight(22);
	btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
	btn.channelName = chName;
	btn:SetText(chName);

	btn:SetScript("OnClick", function()
		if (GetChannelName(TRIVIA_CHANNEL or "") > 0) then
			LeaveChannelByName(TRIVIA_CHANNEL);
		end
		TRIVIA_CHANNEL = this.channelName;
		Trivia_ConsoleMessage("Channel set to: " .. TRIVIA_CHANNEL);
		Trivia_UpdateToggleButton();
		Trivia_RefreshOptionsFrame();
	end);

	return btn;
end

local function Trivia_CreateTimerSlider(parent, name, title, minVal, maxVal, stepVal, x, y, onChangeFn, stepBtnDelta)
	local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate");
	slider:SetWidth(300);
	slider:SetHeight(16);
	slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
	slider:SetMinMaxValues(minVal, maxVal);
	slider:SetValueStep(stepVal);

	local textFS = getglobal(name .. "Text");
	local lowFS  = getglobal(name .. "Low");
	local highFS = getglobal(name .. "High");
	if (textFS) then textFS:SetText(title); end
	if (lowFS)  then lowFS:SetText(tostring(minVal)); end
	if (highFS) then highFS:SetText(tostring(maxVal)); end

	slider.titleLabel = title;
	slider.onChangeFn = onChangeFn;

	slider:SetScript("OnValueChanged", function()
		if (isRefreshingOptions) then return; end
		local val = math.floor(this:GetValue() + 0.5);
		if (this.onChangeFn) then
			this.onChangeFn(val);
		end
	end);

	if (stepBtnDelta and stepBtnDelta > 0) then
		local minusBtn = CreateFrame("Button", name .. "MinusBtn", parent, "UIPanelButtonTemplate");
		minusBtn:SetWidth(30);
		minusBtn:SetHeight(20);
		minusBtn:SetPoint("LEFT", slider, "RIGHT", 10, 0);
		minusBtn:SetText("-" .. stepBtnDelta);
		minusBtn.targetSlider = slider;
		minusBtn.delta = -stepBtnDelta;
		minusBtn:SetScript("OnClick", function()
			local s = this.targetSlider;
			local nextVal = math.floor(s:GetValue() + 0.5) + this.delta;
			s:SetValue(nextVal);
		end);

		local plusBtn = CreateFrame("Button", name .. "PlusBtn", parent, "UIPanelButtonTemplate");
		plusBtn:SetWidth(30);
		plusBtn:SetHeight(20);
		plusBtn:SetPoint("LEFT", minusBtn, "RIGHT", 4, 0);
		plusBtn:SetText("+" .. stepBtnDelta);
		plusBtn.targetSlider = slider;
		plusBtn.delta = stepBtnDelta;
		plusBtn:SetScript("OnClick", function()
			local s = this.targetSlider;
			local nextVal = math.floor(s:GetValue() + 0.5) + this.delta;
			s:SetValue(nextVal);
		end);
	end

	return slider;
end

local function Trivia_CreateCheckOption(parent, name, label, x, y, onClickFn)
	local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate");
	cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
	local textFS = getglobal(name .. "Text");
	if (textFS) then
		textFS:SetText(label);
		if (GameFontHighlightSmall and textFS.SetFontObject) then
			textFS:SetFontObject(GameFontHighlightSmall);
		end
	end
	cb.onClickFn = onClickFn;
	cb:SetScript("OnClick", function()
		local checked = (this:GetChecked() ~= nil);
		if (this.onClickFn) then
			this.onClickFn(checked);
		end
	end);
	return cb;
end

function Trivia_CreateOptionsFrame()
	if (TriviaBotOptionsFrame) then
		return TriviaBotOptionsFrame;
	end
	Trivia_EnsureConfig();

	local f = CreateFrame("Frame", "TriviaBotOptionsFrame", UIParent);
	f:SetWidth(450);
	f:SetHeight(560);
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 20);
	f:SetFrameStrata("DIALOG");
	f:SetToplevel(true);
	f:SetMovable(true);
	f:EnableMouse(true);
	f:SetClampedToScreen(true);
	f:RegisterForDrag("LeftButton");
	f:Hide();

	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 }
	});

	f:SetScript("OnDragStart", function()
		this:StartMoving();
	end);
	f:SetScript("OnDragStop", function()
		this:StopMovingOrSizing();
	end);
	f:SetScript("OnShow", function()
		Trivia_RefreshOptionsFrame();
	end);

	table.insert(UISpecialFrames, "TriviaBotOptionsFrame");

	-- Title
	local titleFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
	titleFS:SetPoint("TOP", f, "TOP", 0, -18);
	titleFS:SetText("TriviaBot-TurtleWoW v" .. TRIVIA_VERSION);

	local closeBtn = CreateFrame("Button", "TriviaBotOptionsCloseBtn", f, "UIPanelCloseButton");
	closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6);

	-- Live status bar
	local statusFS = f:CreateFontString("TriviaBotOptionsStatusText", "OVERLAY", "GameFontHighlightSmall");
	statusFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -4);
	f.statusText = statusFS;

	local timerLiveFS = f:CreateFontString("TriviaBotOptionsTimerLiveText", "OVERLAY", "GameFontNormalSmall");
	timerLiveFS:SetPoint("TOP", statusFS, "BOTTOM", 0, -2);
	f.timerLiveText = timerLiveFS;

	-- Section 1: Question Sets (3 rows x 2 columns)
	Trivia_CreateSectionHeader(f, "1. Question Set", 22, -62);
	local colWidths = 198;
	local i = 1;
	local numSets = table.getn(SET_BUTTON_DEFS);
	while (i <= numSets) do
		local def = SET_BUTTON_DEFS[i];
		local col = math.mod(i - 1, 2);
		local row = math.floor((i - 1) / 2);
		local bx = 22 + col * 206;
		local by = -80 - row * 26;
		setButtons[def.key] = Trivia_CreateSetButton(f, def, bx, by, colWidths);
		i = i + 1;
	end

	-- Section 2: Output / Answer Channel
	Trivia_CreateSectionHeader(f, "2. Chat Channel", 22, -166);
	local cIdx = 1;
	while (cIdx <= table.getn(CHANNEL_BUTTON_DEFS)) do
		local ch = CHANNEL_BUTTON_DEFS[cIdx];
		channelButtons[ch] = Trivia_CreateChannelButton(f, ch, 22 + (cIdx - 1) * 62, -184, 58);
		cIdx = cIdx + 1;
	end

	local customBox = CreateFrame("EditBox", "TriviaOptCustomChannelBox", f, "InputBoxTemplate");
	customBox:SetWidth(94);
	customBox:SetHeight(20);
	customBox:SetAutoFocus(false);
	customBox:SetMaxLetters(32);
	customBox:SetPoint("TOPLEFT", f, "TOPLEFT", 276, -185);
	customBox:SetScript("OnEnterPressed", function()
		this:ClearFocus();
		local ch = Trivia_Trim(this:GetText() or "");
		if (ch ~= "") then
			Trivia_Command("channel " .. string.lower(ch));
		end
	end);
	customBox:SetScript("OnEscapePressed", function()
		this:ClearFocus();
	end);
	f.customChannelBox = customBox;

	local joinBtn = CreateFrame("Button", "TriviaOptJoinChannelBtn", f, "UIPanelButtonTemplate");
	joinBtn:SetWidth(54);
	joinBtn:SetHeight(22);
	joinBtn:SetPoint("LEFT", customBox, "RIGHT", 4, 0);
	joinBtn:SetText("Set");
	joinBtn:SetScript("OnClick", function()
		TriviaOptCustomChannelBox:ClearFocus();
		local ch = Trivia_Trim(TriviaOptCustomChannelBox:GetText() or "");
		if (ch ~= "") then
			Trivia_Command("channel " .. string.lower(ch));
		end
	end);

	-- Section 3: Question Timers
	Trivia_CreateSectionHeader(f, "3. Timers & Pace", 22, -218);

	f.sliderTimeout = Trivia_CreateTimerSlider(
		f, "TriviaOptTimeoutSlider", "Time per Question", 10, 180, 5, 28, -248,
		function(val) Trivia_SetQuestionTimeout(val, true); end, 5
	);

	f.sliderWarn = Trivia_CreateTimerSlider(
		f, "TriviaOptWarnSlider", "Warn Before Timeout", 0, 60, 5, 28, -290,
		function(val) Trivia_SetWarnBeforeEnd(val, true); end, 5
	);

	f.sliderInterval = Trivia_CreateTimerSlider(
		f, "TriviaOptIntervalSlider", "Delay Between Questions", 3, 30, 1, 28, -332,
		function(val) Trivia_SetQuestionInterval(val, true); end, 1
	);

	f.sliderReport = Trivia_CreateTimerSlider(
		f, "TriviaOptReportSlider", "Report Leaderboard Every", 0, 20, 1, 28, -374,
		function(val) Trivia_SetScoreReportEvery(val, true); end, 1
	);

	-- Section 4: Display & Button Options
	Trivia_CreateSectionHeader(f, "4. Display & Button Options", 22, -404);

	f.cbChoices = Trivia_CreateCheckOption(
		f, "TriviaOptChoicesCB", "Show A / B / C / D choices", 20, -420,
		function(checked)
			TRIVIA_CONFIG.showChoices = checked;
			Trivia_UpdateToggleButton();
		end
	);

	f.cbButtonTimer = Trivia_CreateCheckOption(
		f, "TriviaOptBtnTimerCB", "Show timer on button", 225, -420,
		function(checked)
			TRIVIA_CONFIG.showButtonTimer = checked;
			Trivia_UpdateToggleButton();
		end
	);

	f.cbLock = Trivia_CreateCheckOption(
		f, "TriviaOptLockCB", "Lock moveable button", 20, -444,
		function(checked)
			TRIVIA_CONFIG.locked = checked;
			Trivia_UpdateToggleButton();
		end
	);

	f.cbHideBtn = Trivia_CreateCheckOption(
		f, "TriviaOptHideBtnCB", "Hide moveable button", 225, -444,
		function(checked)
			TRIVIA_CONFIG.buttonDisabled = checked;
			Trivia_UpdateToggleButton();
		end
	);

	f.cbNotify = Trivia_CreateCheckOption(
		f, "TriviaOptNotifyCB", "UnitXP SP3 taskbar flash", 20, -468,
		function(checked)
			TRIVIA_CONFIG.notifyTaskbar = checked;
			Trivia_RefreshOptionsFrame();
		end
	);

	local resetPosBtn = CreateFrame("Button", "TriviaOptResetPosBtn", f, "UIPanelButtonTemplate");
	resetPosBtn:SetWidth(155);
	resetPosBtn:SetHeight(22);
	resetPosBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 228, -472);
	resetPosBtn:SetText("Reset Button Position");
	resetPosBtn:SetScript("OnClick", function()
		Trivia_Command("button reset");
	end);

	-- Bottom Control Bar
	local startStopBtn = CreateFrame("Button", "TriviaOptStartStopBtn", f, "UIPanelButtonTemplate");
	startStopBtn:SetWidth(104);
	startStopBtn:SetHeight(26);
	startStopBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 18);
	startStopBtn:SetScript("OnClick", function()
		Trivia_Toggle();
	end);
	f.startStopBtn = startStopBtn;

	local skipBtn = CreateFrame("Button", "TriviaOptSkipBtn", f, "UIPanelButtonTemplate");
	skipBtn:SetWidth(66);
	skipBtn:SetHeight(26);
	skipBtn:SetPoint("LEFT", startStopBtn, "RIGHT", 6, 0);
	skipBtn:SetText("Skip");
	skipBtn:SetScript("OnClick", function()
		if (TRIVIA_ENABLED) then
			Trivia_SkipQuestion();
			Trivia_ConsoleMessage("Question skipped.");
		else
			Trivia_ErrorMessage("Trivia is not running.");
		end
	end);

	local shuffleBtn = CreateFrame("Button", "TriviaOptShuffleBtn", f, "UIPanelButtonTemplate");
	shuffleBtn:SetWidth(72);
	shuffleBtn:SetHeight(26);
	shuffleBtn:SetPoint("LEFT", skipBtn, "RIGHT", 6, 0);
	shuffleBtn:SetText("Shuffle");
	shuffleBtn:SetScript("OnClick", function()
		Trivia_Command("shuffle");
	end);

	local scoresBtn = CreateFrame("Button", "TriviaOptScoresBtn", f, "UIPanelButtonTemplate");
	scoresBtn:SetWidth(76);
	scoresBtn:SetHeight(26);
	scoresBtn:SetPoint("LEFT", shuffleBtn, "RIGHT", 6, 0);
	scoresBtn:SetText("Scores");
	scoresBtn:SetScript("OnClick", function()
		Trivia_ReportScores();
	end);

	local clearBtn = CreateFrame("Button", "TriviaOptClearBtn", f, "UIPanelButtonTemplate");
	clearBtn:SetWidth(68);
	clearBtn:SetHeight(26);
	clearBtn:SetPoint("LEFT", scoresBtn, "RIGHT", 6, 0);
	clearBtn:SetText("Clear");
	clearBtn:SetScript("OnClick", function()
		Trivia_Command("clear");
	end);

	return f;
end

function Trivia_RefreshOptionsTimer(rem)
	local f = TriviaBotOptionsFrame;
	if (not f or not f:IsShown()) then return; end
	if (TRIVIA_ENABLED and TRIVIA_ACCEPTING_ANSWERS) then
		local r = rem or Trivia_GetRemainingSeconds() or 0;
		f.timerLiveText:SetText("|cff44ff44Active Question: " .. r .. "s remaining|r");
	elseif (TRIVIA_ENABLED) then
		f.timerLiveText:SetText("|cffffff00Between questions...|r");
	else
		f.timerLiveText:SetText("|cffaaaaaaIdle - ready to start|r");
	end
end

function Trivia_RefreshOptionsFrame()
	local f = TriviaBotOptionsFrame;
	if (not f or not f:IsShown()) then
		return;
	end
	Trivia_EnsureConfig();
	isRefreshingOptions = true;

	-- Update status line
	local stateLabel = TRIVIA_ENABLED and "|cff44ff44RUNNING|r" or "|cffff4444STOPPED|r";
	local qCount = table.getn(TRIVIA_QUESTIONS);
	f.statusText:SetText("Status: " .. stateLabel .. "  -  Set: |cff00ffff" .. tostring(TRIVIA_QLIST) .. "|r (" .. qCount .. ")  -  Ch: |cffffff00" .. tostring(TRIVIA_CHANNEL) .. "|r");
	Trivia_RefreshOptionsTimer();

	-- Update question set buttons
	for key, btn in pairs(setButtons) do
		local cnt = btn.countFn and btn.countFn() or 0;
		local isSelected = (string.lower(TRIVIA_QLIST or "") == key);
		if (isSelected) then
			btn:SetText("|cff44ff44> " .. btn.baseLabel .. " (" .. cnt .. ")|r");
		else
			btn:SetText(btn.baseLabel .. " (" .. cnt .. ")");
		end
	end

	-- Update channel buttons
	local curChan = string.upper(TRIVIA_CHANNEL or "SAY");
	for chName, btn in pairs(channelButtons) do
		if (curChan == chName) then
			btn:SetText("|cff44ff44[" .. chName .. "]|r");
		else
			btn:SetText(chName);
		end
	end
	if (curChan ~= "SAY" and curChan ~= "PARTY" and curChan ~= "RAID" and curChan ~= "GUILD") then
		if (not f.customChannelBox:HasFocus()) then
			f.customChannelBox:SetText(tostring(TRIVIA_CHANNEL));
		end
	end

	-- Update sliders and labels
	f.sliderTimeout:SetValue(TRIVIA_CONFIG.questionTimeout);
	getglobal("TriviaOptTimeoutSliderText"):SetText("Time per Question: |cffffff00" .. TRIVIA_CONFIG.questionTimeout .. " sec|r");

	f.sliderWarn:SetValue(TRIVIA_CONFIG.warnBeforeEnd);
	local warnText = (TRIVIA_CONFIG.warnBeforeEnd == 0) and "|cffff4444Off|r" or ("|cffffff00" .. TRIVIA_CONFIG.warnBeforeEnd .. " sec before end|r");
	getglobal("TriviaOptWarnSliderText"):SetText("Time Warning: " .. warnText);

	f.sliderInterval:SetValue(TRIVIA_CONFIG.questionInterval);
	getglobal("TriviaOptIntervalSliderText"):SetText("Delay Between Questions: |cffffff00" .. TRIVIA_CONFIG.questionInterval .. " sec|r");

	f.sliderReport:SetValue(TRIVIA_CONFIG.scoreReportEvery);
	local repText = (TRIVIA_CONFIG.scoreReportEvery == 0) and "|cffff4444Off|r" or ("|cffffff00Every " .. TRIVIA_CONFIG.scoreReportEvery .. " questions|r");
	getglobal("TriviaOptReportSliderText"):SetText("Leaderboard Report: " .. repText);

	-- Update checkboxes
	f.cbChoices:SetChecked(TRIVIA_CONFIG.showChoices and 1 or nil);
	f.cbButtonTimer:SetChecked(TRIVIA_CONFIG.showButtonTimer and 1 or nil);
	f.cbLock:SetChecked(TRIVIA_CONFIG.locked and 1 or nil);
	f.cbHideBtn:SetChecked(TRIVIA_CONFIG.buttonDisabled and 1 or nil);
	f.cbNotify:SetChecked(TRIVIA_CONFIG.notifyTaskbar and 1 or nil);

	local notifyTextFS = getglobal("TriviaOptNotifyCBText");
	if (notifyTextFS) then
		if (HAS_XP3) then
			notifyTextFS:SetText("UnitXP SP3 taskbar flash");
		else
			notifyTextFS:SetText("UnitXP SP3 taskbar flash (DLL not loaded)");
		end
	end

	-- Update Start/Stop button
	if (TRIVIA_ENABLED) then
		f.startStopBtn:SetText("|cffff4444Stop Trivia|r");
	else
		f.startStopBtn:SetText("|cff44ff44Start Trivia|r");
	end

	isRefreshingOptions = false;
end

function Trivia_ToggleOptionsFrame()
	local f = Trivia_CreateOptionsFrame();
	if (f:IsShown()) then
		f:Hide();
	else
		f:Show();
	end
end
