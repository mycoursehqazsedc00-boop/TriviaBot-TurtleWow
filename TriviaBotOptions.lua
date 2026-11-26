--[[
--
-- TriviaBotOptions.lua
-- In-game Settings Menu for TriviaBot-TurtleWoW (Vanilla 1.12 / Lua 5.0 safe)
--
--]]

local isRefreshingOptions = false;

local CHANNEL_BUTTON_DEFS = { "SAY", "PARTY", "RAID", "GUILD" };

local channelButtons = {};

local function Trivia_CreateSectionHeader(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
	fs:SetText("|cffffd100" .. text .. "|r");
	return fs;
end

local function Trivia_CreateChannelButton(parent, chName, x, y, width)
	local btn = CreateFrame("Button", "TriviaOptChanBtn_" .. chName, parent, "UIPanelButtonTemplate");
	btn:SetWidth(width);
	btn:SetHeight(22);
	btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
	btn.channelName = chName;
	btn:SetText(chName);

	btn:SetScript("OnClick", function()
		Trivia_Command("channel " .. string.lower(this.channelName));
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

local function Trivia_CreateCompactStepper(parent, name, label, x, y, stepDelta, getFn, setFn)
	local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
	lbl:SetText(label);

	local minusBtn = CreateFrame("Button", name .. "Minus", parent, "UIPanelButtonTemplate");
	minusBtn:SetWidth(22);
	minusBtn:SetHeight(20);
	minusBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 14);
	minusBtn:SetText("-");
	minusBtn:SetScript("OnClick", function()
		setFn((getFn() or 0) - stepDelta);
	end);

	local valFS = parent:CreateFontString(name .. "Val", "OVERLAY", "GameFontNormalSmall");
	valFS:SetWidth(66);
	valFS:SetJustifyH("CENTER");
	valFS:SetPoint("LEFT", minusBtn, "RIGHT", 2, 0);

	local plusBtn = CreateFrame("Button", name .. "Plus", parent, "UIPanelButtonTemplate");
	plusBtn:SetWidth(22);
	plusBtn:SetHeight(20);
	plusBtn:SetPoint("LEFT", valFS, "RIGHT", 2, 0);
	plusBtn:SetText("+");
	plusBtn:SetScript("OnClick", function()
		setFn((getFn() or 0) + stepDelta);
	end);

	return valFS;
end

function Trivia_CreateOptionsFrame()
	if (TriviaBotOptionsFrame) then
		return TriviaBotOptionsFrame;
	end
	Trivia_EnsureConfig();

	local f = CreateFrame("Frame", "TriviaBotOptionsFrame", UIParent);
	f:SetWidth(655);
	f:SetHeight(500);
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

	-- Section 1: Output / Answer Channel
	Trivia_CreateSectionHeader(f, "1. Chat Channel", 22, -62);
	local cIdx = 1;
	while (cIdx <= table.getn(CHANNEL_BUTTON_DEFS)) do
		local ch = CHANNEL_BUTTON_DEFS[cIdx];
		channelButtons[ch] = Trivia_CreateChannelButton(f, ch, 22 + (cIdx - 1) * 62, -80, 58);
		cIdx = cIdx + 1;
	end

	local customBox = CreateFrame("EditBox", "TriviaOptCustomChannelBox", f, "InputBoxTemplate");
	customBox:SetWidth(94);
	customBox:SetHeight(20);
	customBox:SetAutoFocus(false);
	customBox:SetMaxLetters(32);
	customBox:SetPoint("TOPLEFT", f, "TOPLEFT", 276, -81);
	customBox:SetScript("OnEditFocusGained", function()
		this.isFocused = true;
	end);
	customBox:SetScript("OnEditFocusLost", function()
		this.isFocused = false;
	end);
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

	-- Section 2: Question Timers
	Trivia_CreateSectionHeader(f, "2. Timers & Pace", 22, -114);

	f.sliderTimeout = Trivia_CreateTimerSlider(
		f, "TriviaOptTimeoutSlider", "Time per Question", 10, 180, 5, 28, -144,
		function(val) Trivia_SetQuestionTimeout(val, true); end, 5
	);

	f.sliderWarn = Trivia_CreateTimerSlider(
		f, "TriviaOptWarnSlider", "Warn Before Timeout", 0, 60, 5, 28, -186,
		function(val) Trivia_SetWarnBeforeEnd(val, true); end, 5
	);

	f.sliderInterval = Trivia_CreateTimerSlider(
		f, "TriviaOptIntervalSlider", "Delay Between Questions", 3, 30, 1, 28, -228,
		function(val) Trivia_SetQuestionInterval(val, true); end, 1
	);

	f.sliderReport = Trivia_CreateTimerSlider(
		f, "TriviaOptReportSlider", "Report Leaderboard Every", 0, 20, 1, 28, -270,
		function(val) Trivia_SetScoreReportEvery(val, true); end, 1
	);

	-- Section 3: Round Mode & AFK Guard (compact steppers)
	Trivia_CreateSectionHeader(f, "3. Round Mode & AFK Auto-Stop", 22, -300);

	f.valRoundLimit = Trivia_CreateCompactStepper(
		f, "TriviaOptRoundStep", "Round Limit", 22, -318, 5,
		function() return TRIVIA_CONFIG.roundLimit; end,
		function(v) Trivia_SetRoundLimit(v, true); end
	);

	f.valTargetScore = Trivia_CreateCompactStepper(
		f, "TriviaOptTargetStep", "Target Score", 156, -318, 1,
		function() return TRIVIA_CONFIG.targetScore; end,
		function(v) Trivia_SetTargetScore(v, true); end
	);

	f.valAfkLimit = Trivia_CreateCompactStepper(
		f, "TriviaOptAfkStep", "AFK Auto-Stop", 290, -318, 1,
		function() return TRIVIA_CONFIG.afkLimit; end,
		function(v) Trivia_SetAfkLimit(v, true); end
	);

	-- Section 4: Display & Automation Options
	Trivia_CreateSectionHeader(f, "4. Display & Automation", 22, -358);

	f.cbChoices = Trivia_CreateCheckOption(
		f, "TriviaOptChoicesCB", "Show A / B / C / D choices", 20, -374,
		function(checked)
			TRIVIA_CONFIG.showChoices = checked;
			Trivia_UpdateToggleButton();
		end
	);

	f.cbButtonTimer = Trivia_CreateCheckOption(
		f, "TriviaOptBtnTimerCB", "Show timer on button", 225, -374,
		function(checked)
			TRIVIA_CONFIG.showButtonTimer = checked;
			Trivia_UpdateToggleButton();
		end
	);

	f.cbLock = Trivia_CreateCheckOption(
		f, "TriviaOptLockCB", "Lock moveable button", 20, -398,
		function(checked)
			TRIVIA_CONFIG.locked = checked;
			Trivia_UpdateToggleButton();
		end
	);

	f.cbHideBtn = Trivia_CreateCheckOption(
		f, "TriviaOptHideBtnCB", "Hide moveable button", 225, -398,
		function(checked)
			TRIVIA_CONFIG.buttonDisabled = checked;
			Trivia_UpdateToggleButton();
		end
	);

	f.cbCombat = Trivia_CreateCheckOption(
		f, "TriviaOptCombatCB", "Auto-pause in combat", 20, -422,
		function(checked)
			TRIVIA_CONFIG.autoPauseCombat = checked;
			Trivia_RefreshOptionsFrame();
		end
	);

	f.cbNotify = Trivia_CreateCheckOption(
		f, "TriviaOptNotifyCB", "UnitXP SP3 taskbar flash", 225, -422,
		function(checked)
			TRIVIA_CONFIG.notifyTaskbar = checked;
			Trivia_RefreshOptionsFrame();
		end
	);

	-- Right Panel: Live Standings / Host Leaderboard
	local board = CreateFrame("Frame", "TriviaBotStandingsPanel", f);
	board:SetWidth(196);
	board:SetHeight(400);
	board:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -62);
	board:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 14,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	});
	board:SetBackdropColor(0.05, 0.05, 0.08, 0.85);
	board:SetBackdropBorderColor(0.45, 0.45, 0.55, 1.0);
	f.standingsPanel = board;

	local boardTitle = board:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	boardTitle:SetPoint("TOP", board, "TOP", 0, -10);
	boardTitle:SetText("|cffffd100Live Standings|r");

	local roundInfoFS = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	roundInfoFS:SetPoint("TOP", boardTitle, "BOTTOM", 0, -4);
	roundInfoFS:SetWidth(180);
	roundInfoFS:SetJustifyH("CENTER");
	f.boardRoundText = roundInfoFS;

	f.boardRows = {};
	local rowIdx = 1;
	while (rowIdx <= 10) do
		local rFS = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
		rFS:SetPoint("TOPLEFT", board, "TOPLEFT", 10, -42 - (rowIdx - 1) * 18);
		rFS:SetWidth(176);
		rFS:SetJustifyH("LEFT");
		f.boardRows[rowIdx] = rFS;
		rowIdx = rowIdx + 1;
	end

	local statsTitle = board:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
	statsTitle:SetPoint("TOPLEFT", board, "TOPLEFT", 10, -230);
	statsTitle:SetText("|cffffd100Session Records|r");

	local speedFS = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	speedFS:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", 0, -6);
	speedFS:SetWidth(176);
	speedFS:SetJustifyH("LEFT");
	f.boardSpeedText = speedFS;

	local streakFS = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	streakFS:SetPoint("TOPLEFT", speedFS, "BOTTOMLEFT", 0, -4);
	streakFS:SetWidth(176);
	streakFS:SetJustifyH("LEFT");
	f.boardStreakText = streakFS;

	local curStreakFS = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	curStreakFS:SetPoint("TOPLEFT", streakFS, "BOTTOMLEFT", 0, -4);
	curStreakFS:SetWidth(176);
	curStreakFS:SetJustifyH("LEFT");
	f.boardCurStreakText = curStreakFS;

	local afkFS = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	afkFS:SetPoint("TOPLEFT", curStreakFS, "BOTTOMLEFT", 0, -4);
	afkFS:SetWidth(176);
	afkFS:SetJustifyH("LEFT");
	f.boardAfkText = afkFS;

	local resetPosBtn = CreateFrame("Button", "TriviaOptResetPosBtn", board, "UIPanelButtonTemplate");
	resetPosBtn:SetWidth(172);
	resetPosBtn:SetHeight(22);
	resetPosBtn:SetPoint("BOTTOM", board, "BOTTOM", 0, 42);
	resetPosBtn:SetText("Reset Button Position");
	resetPosBtn:SetScript("OnClick", function()
		Trivia_Command("button reset");
	end);

	local scoresBtn = CreateFrame("Button", "TriviaOptScoresBtn", board, "UIPanelButtonTemplate");
	scoresBtn:SetWidth(84);
	scoresBtn:SetHeight(24);
	scoresBtn:SetPoint("BOTTOMLEFT", board, "BOTTOMLEFT", 12, 12);
	scoresBtn:SetText("Announce");
	scoresBtn:SetScript("OnClick", function()
		Trivia_ReportScores();
	end);

	local clearBtn = CreateFrame("Button", "TriviaOptClearBtn", board, "UIPanelButtonTemplate");
	clearBtn:SetWidth(84);
	clearBtn:SetHeight(24);
	clearBtn:SetPoint("BOTTOMRIGHT", board, "BOTTOMRIGHT", -12, 12);
	clearBtn:SetText("Clear");
	clearBtn:SetScript("OnClick", function()
		Trivia_Command("clear");
	end);

	-- Bottom Control Bar
	local startStopBtn = CreateFrame("Button", "TriviaOptStartStopBtn", f, "UIPanelButtonTemplate");
	startStopBtn:SetWidth(110);
	startStopBtn:SetHeight(26);
	startStopBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 16);
	startStopBtn:SetScript("OnClick", function()
		Trivia_Toggle();
	end);
	f.startStopBtn = startStopBtn;

	local pauseBtn = CreateFrame("Button", "TriviaOptPauseBtn", f, "UIPanelButtonTemplate");
	pauseBtn:SetWidth(94);
	pauseBtn:SetHeight(26);
	pauseBtn:SetPoint("LEFT", startStopBtn, "RIGHT", 8, 0);
	pauseBtn:SetText("Pause");
	pauseBtn:SetScript("OnClick", function()
		if (not TRIVIA_ENABLED) then
			Trivia_ErrorMessage("Trivia is not running.");
		elseif (TRIVIA_PAUSED) then
			Trivia_Resume(false);
		else
			Trivia_Pause(false);
		end
	end);
	f.pauseBtn = pauseBtn;

	local skipBtn = CreateFrame("Button", "TriviaOptSkipBtn", f, "UIPanelButtonTemplate");
	skipBtn:SetWidth(86);
	skipBtn:SetHeight(26);
	skipBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 8, 0);
	skipBtn:SetText("Skip Q");
	skipBtn:SetScript("OnClick", function()
		if (TRIVIA_ENABLED) then
			Trivia_SkipQuestion();
			Trivia_ConsoleMessage("Question skipped.");
		else
			Trivia_ErrorMessage("Trivia is not running.");
		end
	end);

	local shuffleBtn = CreateFrame("Button", "TriviaOptShuffleBtn", f, "UIPanelButtonTemplate");
	shuffleBtn:SetWidth(94);
	shuffleBtn:SetHeight(26);
	shuffleBtn:SetPoint("LEFT", skipBtn, "RIGHT", 8, 0);
	shuffleBtn:SetText("Shuffle");
	shuffleBtn:SetScript("OnClick", function()
		Trivia_Command("shuffle");
	end);

	return f;
end

function Trivia_RefreshOptionsTimer(rem)
	local f = TriviaBotOptionsFrame;
	if (not f or not f:IsShown()) then return; end
	if (TRIVIA_ENABLED and TRIVIA_PAUSED) then
		if (TRIVIA_PAUSED_BY_COMBAT) then
			f.timerLiveText:SetText("|cffffff00Paused (In Combat)|r");
		else
			f.timerLiveText:SetText("|cffffff00Paused by Host|r");
		end
	elseif (TRIVIA_ENABLED and TRIVIA_ACCEPTING_ANSWERS) then
		local r = rem or Trivia_GetRemainingSeconds() or 0;
		f.timerLiveText:SetText("|cff44ff44Active Question: " .. r .. "s remaining|r");
	elseif (TRIVIA_ENABLED) then
		f.timerLiveText:SetText("|cffffff00Between questions...|r");
	else
		f.timerLiveText:SetText("|cffaaaaaaIdle - ready to start|r");
	end
end

local function Trivia_RefreshStandingsPanel(f)
	if (not f or not f.boardRows) then return; end

	-- Round & mode header
	local rLim = TRIVIA_CONFIG.roundLimit or 0;
	local tScore = TRIVIA_CONFIG.targetScore or 0;
	local infoStr = "";
	if (rLim > 0) then
		infoStr = "Q: |cff00ffff" .. (TRIVIA_ROUND_ASKED or 0) .. "/" .. rLim .. "|r";
	else
		infoStr = "Mode: |cffaaaaaaEndless|r";
	end
	if (tScore > 0) then
		infoStr = infoStr .. "  Goal: |cffffff00" .. tScore .. "p|r";
	end
	f.boardRoundText:SetText(infoStr);

	local list, count = Trivia_GetSortedStandings();
	local i = 1;
	while (i <= 10) do
		local row = f.boardRows[i];
		if (i <= count) then
			local rec = list[i];
			local rankColor = "|cffffffff";
			if (i == 1) then rankColor = "|cffffd100";
			elseif (i == 2) then rankColor = "|cffdddddd";
			elseif (i == 3) then rankColor = "|cffcd7f32"; end
			local streakTag = "";
			if (TRIVIA_STREAK_HOLDER == rec.player and TRIVIA_STREAK_COUNT >= 2) then
				streakTag = " |cffff8800[" .. TRIVIA_STREAK_COUNT .. "x]|r";
			end
			row:SetText(rankColor .. i .. ". " .. rec.player .. "|r - |cff44ff44" .. rec.score .. "|r" .. streakTag);
		elseif (i == 1 and count == 0) then
			row:SetText("|cff888888No scores yet.|r");
		else
			row:SetText("");
		end
		i = i + 1;
	end

	-- Records & AFK counter
	if (TRIVIA_TIME_RECORD and TRIVIA_TIME_RECORD["holder"] ~= "noone") then
		f.boardSpeedText:SetText("Fastest: |cff00ffff" .. TRIVIA_TIME_RECORD["holder"] .. "|r (" .. TRIVIA_TIME_RECORD["time"] .. "s)");
	else
		f.boardSpeedText:SetText("Fastest: |cff888888---|r");
	end

	if (TRIVIA_BEST_STREAK and TRIVIA_BEST_STREAK["count"] >= 2) then
		f.boardStreakText:SetText("Best Streak: |cffff8800" .. TRIVIA_BEST_STREAK["holder"] .. "|r (" .. TRIVIA_BEST_STREAK["count"] .. "x)");
	else
		f.boardStreakText:SetText("Best Streak: |cff888888---|r");
	end

	if (TRIVIA_STREAK_HOLDER and TRIVIA_STREAK_COUNT >= 2) then
		f.boardCurStreakText:SetText("Hot Streak: |cff44ff44" .. TRIVIA_STREAK_HOLDER .. "|r (" .. TRIVIA_STREAK_COUNT .. "x)");
	else
		f.boardCurStreakText:SetText("Hot Streak: |cff888888---|r");
	end

	local afkLim = TRIVIA_CONFIG.afkLimit or 0;
	if (afkLim > 0) then
		f.boardAfkText:SetText("Unanswered: |cffffff00" .. (TRIVIA_AFK_STREAK or 0) .. "/" .. afkLim .. "|r");
	else
		f.boardAfkText:SetText("AFK Auto-Stop: |cff888888Off|r");
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
	local qCount = Trivia_GetSetQuestionCount("warcraft");
	f.statusText:SetText("Status: " .. stateLabel .. "  -  Pack: |cff00ffffWarcraft & Turtle WoW|r (" .. qCount .. " Qs)  -  Ch: |cffffff00" .. tostring(TRIVIA_CHANNEL) .. "|r");
	Trivia_RefreshOptionsTimer();

	-- Update channel buttons
	local curChan = string.upper(TRIVIA_CHANNEL or "SAY");
	for chName, btn in pairs(channelButtons) do
		if (curChan == chName) then
			btn:SetText("|cff44ff44[" .. chName .. "]|r");
		else
			btn:SetText(chName);
		end
	end
	if (not f.customChannelBox.isFocused) then
		if (curChan ~= "SAY" and curChan ~= "PARTY" and curChan ~= "RAID" and curChan ~= "GUILD") then
			f.customChannelBox:SetText(tostring(TRIVIA_CHANNEL));
		else
			f.customChannelBox:SetText("");
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

	-- Update Round / Target / AFK steppers
	local rLim = TRIVIA_CONFIG.roundLimit or 0;
	f.valRoundLimit:SetText((rLim == 0) and "|cffaaaaaaEndless|r" or ("|cffffff00" .. rLim .. " Qs|r"));

	local tScore = TRIVIA_CONFIG.targetScore or 0;
	f.valTargetScore:SetText((tScore == 0) and "|cffaaaaaaOff|r" or ("|cffffff00" .. tScore .. " pts|r"));

	local afkLim = TRIVIA_CONFIG.afkLimit or 0;
	f.valAfkLimit:SetText((afkLim == 0) and "|cffaaaaaaOff|r" or ("|cffffff00" .. afkLim .. " Qs|r"));

	-- Update checkboxes
	f.cbChoices:SetChecked(TRIVIA_CONFIG.showChoices and 1 or nil);
	f.cbButtonTimer:SetChecked(TRIVIA_CONFIG.showButtonTimer and 1 or nil);
	f.cbLock:SetChecked(TRIVIA_CONFIG.locked and 1 or nil);
	f.cbHideBtn:SetChecked(TRIVIA_CONFIG.buttonDisabled and 1 or nil);
	f.cbCombat:SetChecked(TRIVIA_CONFIG.autoPauseCombat and 1 or nil);
	f.cbNotify:SetChecked(TRIVIA_CONFIG.notifyTaskbar and 1 or nil);

	local notifyTextFS = getglobal("TriviaOptNotifyCBText");
	if (notifyTextFS) then
		if (HAS_XP3) then
			notifyTextFS:SetText("UnitXP SP3 taskbar flash");
		else
			notifyTextFS:SetText("UnitXP SP3 flash (no DLL)");
		end
	end

	-- Update Start/Stop & Pause/Resume buttons
	if (TRIVIA_ENABLED) then
		f.startStopBtn:SetText("|cffff4444Stop Trivia|r");
		if (TRIVIA_PAUSED) then
			f.pauseBtn:SetText("|cff44ff44Resume|r");
		else
			f.pauseBtn:SetText("|cffffff00Pause|r");
		end
	else
		f.startStopBtn:SetText("|cff44ff44Start Trivia|r");
		f.pauseBtn:SetText("|cff888888Pause|r");
	end

	Trivia_RefreshStandingsPanel(f);

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
