--[[
--
-- TriviaBot-TurtleWoW Version 1.2
-- Maintained by LizardBerry
-- Based on work created by Roadblock of Nostalrius, Guri of Trollbane, and Psy on Frostwolf
-- Improved with 4,010 pre-TBC Warcraft/Turtle WoW/General questions, A/B/C/D multiple choice,
-- configurable question timers, settings menu, fuzzy ("likely") answer matching,
-- and a moveable on-screen toggle button.
--
--]]

-- Colour codes for console messages
local RED     = "|cffff4444";
local GREEN   = "|cff44ff44";
local YELLOW  = "|cffffff00";
local MAGENTA = "|cffff00ff";
local CYAN    = "|cff00ffff";
local WHITE   = "|cffffffff";
local GREY    = "|cffaaaaaa";

TRIVIA_ENABLED = false;
TRIVIA_ACCEPTING_ANSWERS = false;
TRIVIA_LOADED = false;

TRIVIA_QUESTION_TIMEOUT = 45;  -- Default seconds per question (overridden by TRIVIA_CONFIG.questionTimeout)
TRIVIA_QUESTION_TIMEWARN = 25; -- Legacy fallback
TRIVIA_WARN_REMAINING = 15;    -- Computed remaining seconds announced by QUESTION_WARN

TRIVIA_VERSION = "1.4";

NEW_TRIVIA_CHANNEL = nil;

TRIVIA_ACTIVE_QUESTION = 0;
TRIVIA_QUESTION_ORDER = {};
TRIVIA_TOTAL_QUESTIONS = 0;
TRIVIA_SET_READY = false;
TRIVIA_SCORE_REPORT = 5;
TRIVIA_QUESTION_STARTTIME = 0;
TRIVIA_TIME_RECORD = {["time"] = 46, ["holder"] = "noone"};

TRIVIA_PAUSED = false;
TRIVIA_PAUSED_BY_COMBAT = false;
TRIVIA_PAUSED_REMAINING = 0;
TRIVIA_PAUSED_WAS_ACCEPTING = false;

TRIVIA_STREAK_HOLDER = nil;
TRIVIA_STREAK_COUNT = 0;
TRIVIA_BEST_STREAK = {["count"] = 0, ["holder"] = "noone"};
TRIVIA_ROUND_ASKED = 0;
TRIVIA_AFK_STREAK = 0;

TRIVIA_SCORES = {};
TRIVIA_SCHEDULE = {};
TRIVIA_TELLS = {};

-- Packed question registry (zero sub-tables, zero duplicate copies)
TRIVIA_PACKS = {};
local ACTIVE_PACKS = {};

local TRIVIA_PACK_META = {
	warcraft = { count = 1299 },
};

local TRIVIA_SET_PACKS = {
	warcraft = { "warcraft" },
};

-- Current unpacked question fields (cached once per question for zero hot-path unpacking)
local curQ = nil;
local curA1 = nil;
local curAlt = nil;
local curCh = nil;

-- Current multiple-choice state for the active question
TRIVIA_CURRENT_CORRECT_LETTER = nil;
TRIVIA_CURRENT_OPTIONS = {};
TRIVIA_WRONG_LETTER_COOLDOWN = {};

INVALID_COMMAND = RED .. "Invalid Command Entered. " .. WHITE .. "Try '/trivia help'";

TRIVIA_UPDATEINTERVAL = 0.5;
local lastTimerSecond = -1;
local channelRetryCount = 0;

local function Trivia_IsStandardChannel(ch)
	return (ch == "SAY" or ch == "PARTY" or ch == "RAID" or ch == "GUILD");
end

-- Client mod feature detection (checked at PLAYER_LOGIN)
HAS_XP3 = false;

-- Reusable buffers & hoisted constants (zero hot-path allocations)
local levRow0 = {};
local levRow1 = {};
local splitBuf = {};
local dueEvents = {};
local choiceOpts = {};
local shuffleOrder = {1, 2, 3, 4};
local sortScores = {};
local CHOICE_LETTERS = {"a", "b", "c", "d"};
local CHAT_EVENTS = {
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_SAY",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_GUILD",
};
local CORE_PATTERNS = {
	"^(.+) at age %d+",
	"^(.+) in %d%d%d%d",
	"^(.+) as the %d+",
	"^(.+) in nepal",
	"^(.+) with %d+",
};
local PROTECTED_CHANNELS = {
	"general", "trade", "lookingforgroup", "guildrecruitment",
	"localdefence", "localdefense", "worlddefence", "worlddefense", "world",
};

-- Number word normalization lookup
local NUMBER_WORDS = {
	["zero"] = "0", ["one"] = "1", ["two"] = "2", ["three"] = "3", ["four"] = "4",
	["five"] = "5", ["six"] = "6", ["seven"] = "7", ["eight"] = "8", ["nine"] = "9",
	["ten"] = "10", ["eleven"] = "11", ["twelve"] = "12", ["thirteen"] = "13",
	["fourteen"] = "14", ["fifteen"] = "15", ["sixteen"] = "16", ["seventeen"] = "17",
	["eighteen"] = "18", ["nineteen"] = "19", ["twenty"] = "20", ["thirty"] = "30",
	["thirtyfive"] = "35", ["thirty five"] = "35", ["forty"] = "40", ["fifty"] = "50",
	["fiftyseven"] = "57", ["fifty seven"] = "57", ["sixty"] = "60", ["seventy"] = "70",
	["seventyfive"] = "75", ["seventy five"] = "75", ["eighty"] = "80", ["ninety"] = "90",
	["one hundred"] = "100"
};

-- Stopwords ignored when matching single-keyword core tokens
local STOPWORDS = {
	["the"] = true, ["and"] = true, ["for"] = true, ["with"] = true, ["from"] = true,
	["that"] = true, ["this"] = true, ["into"] = true, ["over"] = true, ["under"] = true,
	["king"] = true, ["lord"] = true, ["lady"] = true, ["high"] = true, ["grand"] = true,
	["dark"] = true, ["black"] = true, ["red"] = true, ["blue"] = true, ["green"] = true,
	["white"] = true, ["city"] = true, ["keep"] = true, ["port"] = true, ["isle"] = true,
	["island"] = true, ["mount"] = true, ["clan"] = true, ["quality"] = true
};

local QLIST_CYCLE = {"warcraft"};

-------------------------------------------------------------------------------
-- Initialization & Event Handling
-------------------------------------------------------------------------------

local function Trivia_UpdateFrameActive()
	if (not Trivia) then return; end
	local activeRun = (TRIVIA_ENABLED and not TRIVIA_PAUSED);
	if (activeRun or (TRIVIA_SCHEDULE and table.getn(TRIVIA_SCHEDULE) > 0)) then
		if (not Trivia:IsShown()) then
			Trivia.TimeSinceLastUpdate = 0;
			Trivia:Show();
		end
	else
		if (Trivia:IsShown()) then
			Trivia:Hide();
		end
	end
end

local function Trivia_UnregisterChatEvents()
	if (not Trivia) then return; end
	local i = 1;
	local n = table.getn(CHAT_EVENTS);
	while (i <= n) do
		Trivia:UnregisterEvent(CHAT_EVENTS[i]);
		i = i + 1;
	end
	Trivia:UnregisterEvent("PLAYER_REGEN_DISABLED");
	Trivia:UnregisterEvent("PLAYER_REGEN_ENABLED");
end

local function Trivia_RegisterChatEvents()
	if (not Trivia) then return; end
	Trivia_UnregisterChatEvents();
	if (TRIVIA_CHANNEL == "SAY") then
		Trivia:RegisterEvent("CHAT_MSG_SAY");
	elseif (TRIVIA_CHANNEL == "GUILD") then
		Trivia:RegisterEvent("CHAT_MSG_GUILD");
	elseif (TRIVIA_CHANNEL == "PARTY") then
		Trivia:RegisterEvent("CHAT_MSG_PARTY");
	elseif (TRIVIA_CHANNEL == "RAID") then
		Trivia:RegisterEvent("CHAT_MSG_RAID");
		Trivia:RegisterEvent("CHAT_MSG_RAID_LEADER");
	else
		Trivia:RegisterEvent("CHAT_MSG_CHANNEL");
	end
	Trivia:RegisterEvent("PLAYER_REGEN_DISABLED");
	Trivia:RegisterEvent("PLAYER_REGEN_ENABLED");
end

function Trivia_OnLoad()
	-- Only register lightweight lifecycle events at login; chat events register on Start
	this:RegisterEvent("ADDON_LOADED");
	this:RegisterEvent("PLAYER_LOGIN");

	SLASH_TRIVIA1 = "/trivia";
	SLASH_TRIVIA2 = "/triviabot";
	SlashCmdList["TRIVIA"] = Trivia_Command;
end

function Trivia_EnsureConfig()
	if (type(TRIVIA_CONFIG) ~= "table") then
		TRIVIA_CONFIG = {};
	end
	if (TRIVIA_CONFIG.locked == nil) then
		TRIVIA_CONFIG.locked = false;
	end
	if (TRIVIA_CONFIG.buttonDisabled == nil) then
		TRIVIA_CONFIG.buttonDisabled = false;
	end
	if (TRIVIA_CONFIG.showChoices == nil) then
		TRIVIA_CONFIG.showChoices = true;
	end
	if (TRIVIA_CONFIG.showButtonTimer == nil) then
		TRIVIA_CONFIG.showButtonTimer = true;
	end
	if (TRIVIA_CONFIG.notifyTaskbar == nil) then
		TRIVIA_CONFIG.notifyTaskbar = false;
	end
	if (TRIVIA_CONFIG.autoPauseCombat == nil) then
		TRIVIA_CONFIG.autoPauseCombat = true;
	end
	if (type(TRIVIA_CONFIG.afkLimit) ~= "number" or TRIVIA_CONFIG.afkLimit < 0 or TRIVIA_CONFIG.afkLimit > 10) then
		TRIVIA_CONFIG.afkLimit = 5;
	end
	if (type(TRIVIA_CONFIG.roundLimit) ~= "number" or TRIVIA_CONFIG.roundLimit < 0 or TRIVIA_CONFIG.roundLimit > 50) then
		TRIVIA_CONFIG.roundLimit = 0;
	end
	if (type(TRIVIA_CONFIG.targetScore) ~= "number" or TRIVIA_CONFIG.targetScore < 0 or TRIVIA_CONFIG.targetScore > 30) then
		TRIVIA_CONFIG.targetScore = 0;
	end
	if (type(TRIVIA_CONFIG.questionTimeout) ~= "number" or TRIVIA_CONFIG.questionTimeout < 10 or TRIVIA_CONFIG.questionTimeout > 180) then
		TRIVIA_CONFIG.questionTimeout = 45;
	end
	if (type(TRIVIA_CONFIG.warnBeforeEnd) ~= "number" or TRIVIA_CONFIG.warnBeforeEnd < 0 or TRIVIA_CONFIG.warnBeforeEnd > 60) then
		TRIVIA_CONFIG.warnBeforeEnd = 15;
	end
	if (type(TRIVIA_CONFIG.questionInterval) ~= "number" or TRIVIA_CONFIG.questionInterval < 3 or TRIVIA_CONFIG.questionInterval > 30) then
		TRIVIA_CONFIG.questionInterval = 7;
	end
	if (type(TRIVIA_CONFIG.scoreReportEvery) ~= "number" or TRIVIA_CONFIG.scoreReportEvery < 0 or TRIVIA_CONFIG.scoreReportEvery > 20) then
		TRIVIA_CONFIG.scoreReportEvery = 5;
	end
	if (not TRIVIA_CONFIG.point) then
		TRIVIA_CONFIG.point = "TOP";
		TRIVIA_CONFIG.relativePoint = "TOP";
		TRIVIA_CONFIG.xOfs = 0;
		TRIVIA_CONFIG.yOfs = -60;
	end
	TRIVIA_QUESTION_TIMEOUT = TRIVIA_CONFIG.questionTimeout;
end

function Trivia_OnUpdate(elapsed)
	this.TimeSinceLastUpdate = this.TimeSinceLastUpdate + elapsed;
	if (this.TimeSinceLastUpdate > TRIVIA_UPDATEINTERVAL) then
		this.TimeSinceLastUpdate = 0;
		if (TRIVIA_SCHEDULE and table.getn(TRIVIA_SCHEDULE) > 0) then
			Trivia_DoSchedule();
		end
		Trivia_UpdateCountdownUI();
	end
end

local function Trivia_StripTranslatePrefix(msg)
	if (not msg) then return ""; end
	local s = Trivia_Trim(msg);
	local low = string.lower(s);
	local p = string.find(low, "wowtranslate", 1, true);
	if (p and p <= 50) then
		local closeBracket = string.find(s, "]", p, true);
		if (closeBracket) then
			local rest = Trivia_Trim(string.sub(s, closeBracket + 1));
			if (rest ~= "") then
				return rest;
			end
		end
	end
	return s;
end

local function Trivia_IsBotMessage(msg)
	if (not msg) then return true; end
	local stripped = Trivia_StripTranslatePrefix(msg);
	local low = Trivia_Trim(string.lower(stripped));
	if (low == "") then return true; end
	if (string.find(low, "^%[turtletrivia%]")) then
		return true;
	end
	if (string.find(low, "^q:%s")) then
		return true;
	end
	if (string.find(low, "^%[a%] ") and string.find(low, "%[b%] ")) then
		return true;
	end
	if (string.find(low, "^%[c%] ") and string.find(low, "%[d%] ")) then
		return true;
	end
	return false;
end

local function Trivia_HandleIncomingChat(player, msg)
	if (not TRIVIA_ENABLED or not msg or not player) then return; end
	local cleanMsg = Trivia_StripTranslatePrefix(msg);
	if (Trivia_IsBotMessage(cleanMsg)) then return; end

	local lowerMsg = Trivia_Trim(string.lower(cleanMsg));
	if (lowerMsg == "score" or lowerMsg == "!score") then
		Trivia_WhisperScore(player);
	elseif (TRIVIA_ACCEPTING_ANSWERS) then
		Trivia_CheckAnswer(player, cleanMsg);
	end
end

function Trivia_OnEvent(event)
	if (event == "ADDON_LOADED") then
		if (not TRIVIA_LOADED and (arg1 == "TriviaBot-TurtleWow" or arg1 == "TriviaBot-TurtleWoW")) then
			Trivia_Initialize();
		end
	elseif (event == "PLAYER_LOGIN") then
		HAS_XP3 = pcall(UnitXP, "nop", "nop");
		if (not TRIVIA_LOADED) then
			Trivia_Initialize();
		end
		Trivia_UpdateToggleButton();
		if (Trivia_RefreshOptionsFrame) then
			Trivia_RefreshOptionsFrame();
		end
	elseif (event == "PLAYER_REGEN_DISABLED") then
		if (TRIVIA_ENABLED and TRIVIA_CONFIG and TRIVIA_CONFIG.autoPauseCombat and not TRIVIA_PAUSED) then
			Trivia_Pause(true);
		end
	elseif (event == "PLAYER_REGEN_ENABLED") then
		if (TRIVIA_ENABLED and TRIVIA_PAUSED and TRIVIA_PAUSED_BY_COMBAT) then
			Trivia_Resume(true);
		end
	elseif (event == "CHAT_MSG_CHANNEL") then
		local msg = arg1;
		local player = arg2;
		local channel = arg9;
		if (TRIVIA_ENABLED and TRIVIA_CHANNEL and msg and player and channel) then
			if (string.lower(channel) == string.lower(TRIVIA_CHANNEL)) then
				Trivia_HandleIncomingChat(player, msg);
			end
		end
	elseif (event == "CHAT_MSG_SAY" or event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_PARTY") then
		local msg = arg1;
		local player = arg2;
		if (TRIVIA_ENABLED and msg and player and Trivia_IsActiveChannelEvent(event)) then
			Trivia_HandleIncomingChat(player, msg);
		end
	elseif (event == "RETRY_CHANNEL_CHANGE") then
		Trivia_ChangeChannel();
	elseif (event == "NEXT_QUESTION") then
		if (TRIVIA_ENABLED) then
			Trivia_AskQuestion();
		end
	elseif (event == "QUESTION_TIMEOUT") then
		if (TRIVIA_ENABLED and TRIVIA_ACCEPTING_ANSWERS) then
			Trivia_QuestionTimeout();
		end
	elseif (event == "QUESTION_WARN") then
		if (TRIVIA_ENABLED and TRIVIA_ACCEPTING_ANSWERS) then
			local rem = TRIVIA_WARN_REMAINING or 15;
			if (TRIVIA_CONFIG and TRIVIA_CONFIG.showChoices) then
				Trivia_SendMessage(rem .. " seconds left! (Reply with A, B, C, D or the answer)");
			else
				Trivia_SendMessage(rem .. " seconds left!");
			end
		end
	elseif (event == "REPORT_SCORERS") then
		if (TRIVIA_ENABLED) then
			Trivia_ReportScores();
		end
	elseif (event == "SHOW_ANSWER") then
		if (TRIVIA_ENABLED) then
			local ans = curA1 or Trivia_GetAnswer1(TRIVIA_QUESTION_ORDER[TRIVIA_ACTIVE_QUESTION]) or "Unknown";
			if (TRIVIA_CONFIG.showChoices and TRIVIA_CURRENT_CORRECT_LETTER) then
				Trivia_SendMessage("The correct answer was: [" .. string.upper(TRIVIA_CURRENT_CORRECT_LETTER) .. "] " .. ans);
			else
				Trivia_SendMessage("The correct answer was: " .. ans);
			end
		end
	end
end

function Trivia_IsActiveChannelEvent(event)
	if (TRIVIA_CHANNEL == "SAY" and event == "CHAT_MSG_SAY") then
		return true;
	elseif (TRIVIA_CHANNEL == "GUILD" and event == "CHAT_MSG_GUILD") then
		return true;
	elseif (TRIVIA_CHANNEL == "PARTY" and event == "CHAT_MSG_PARTY") then
		return true;
	elseif (TRIVIA_CHANNEL == "RAID" and (event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER")) then
		return true;
	end
	return false;
end

function Trivia_Initialize()
	TRIVIA_ENABLED = false;
	TRIVIA_ACCEPTING_ANSWERS = false;

	Trivia_EnsureConfig();

	if (not TRIVIA_CHANNEL or TRIVIA_CHANNEL == "") then
		TRIVIA_CHANNEL = "SAY";
	end

	-- Migrate any legacy saved question set (normal/geography/turtle/wow/all) to unified warcraft pack
	TRIVIA_QLIST = "warcraft";

	TRIVIA_SCORE_REPORT = TRIVIA_CONFIG.scoreReportEvery;
	TRIVIA_TIME_RECORD = {["time"] = TRIVIA_CONFIG.questionTimeout + 1, ["holder"] = "noone"};

	-- Defer shuffle until Trivia_Start(); lazy-create toggle button only if enabled
	Trivia_LoadQuestionSet(TRIVIA_QLIST, true, true);
	if (not TRIVIA_CONFIG.buttonDisabled) then
		Trivia_CreateToggleButton();
	end
	Trivia_UpdateToggleButton();
	Trivia_UpdateFrameActive();

	TRIVIA_LOADED = true;
	Trivia_ConsoleMessage("Version " .. TRIVIA_VERSION .. " loaded (" .. Trivia_GetSetQuestionCount("warcraft") .. " questions). Type " .. CYAN .. "/trivia" .. WHITE .. " for Settings & Standings or " .. CYAN .. "/trivia help" .. WHITE .. ".");
end

-------------------------------------------------------------------------------
-- Question Set Management (Single-Array Flat Pack & Zero-Copy Indexing)
-------------------------------------------------------------------------------

function Trivia_RegisterFlatPack(key, data)
	if (not key or not data) then return; end
	TRIVIA_PACKS[key] = {
		data = data,
		count = table.getn(data),
	};
end

local function Trivia_UnpackRecord(rec)
	if (not rec) then return nil, nil, nil, nil; end
	local p1 = string.find(rec, "\n", 1, true);
	if (not p1) then return rec, "", "", ""; end
	local p2 = string.find(rec, "\n", p1 + 1, true);
	if (not p2) then
		return string.sub(rec, 1, p1 - 1), string.sub(rec, p1 + 1), "", "";
	end
	local p3 = string.find(rec, "\n", p2 + 1, true);
	if (not p3) then
		return string.sub(rec, 1, p1 - 1), string.sub(rec, p1 + 1, p2 - 1), string.sub(rec, p2 + 1), "";
	end
	return string.sub(rec, 1, p1 - 1),
		string.sub(rec, p1 + 1, p2 - 1),
		string.sub(rec, p2 + 1, p3 - 1),
		string.sub(rec, p3 + 1);
end

function Trivia_GetPackCount(packKey)
	local p = TRIVIA_PACKS[packKey];
	if (p) then
		return p.count;
	end
	local meta = TRIVIA_PACK_META[packKey];
	return (meta and meta.count) or 0;
end

function Trivia_GetSetQuestionCount(setKey)
	return Trivia_GetPackCount("warcraft");
end

local function Trivia_EnsurePackLoaded(packKey)
	if (TRIVIA_PACKS[packKey]) then
		return TRIVIA_PACKS[packKey];
	end
	Trivia_ErrorMessage("Question pack '" .. tostring(packKey) .. "' is not loaded. Verify WarcraftQuestions.lua is present.");
	return nil;
end

local function Trivia_ResolveQuestion(qIdx)
	if (not qIdx or qIdx < 1) then return nil, nil; end
	local i = 1;
	local n = table.getn(ACTIVE_PACKS);
	while (i <= n) do
		local entry = ACTIVE_PACKS[i];
		if (qIdx <= entry.offset + entry.count) then
			return entry.pack, qIdx - entry.offset;
		end
		i = i + 1;
	end
	return nil, nil;
end

function Trivia_GetQuestionText(qIdx)
	local pack, localIdx = Trivia_ResolveQuestion(qIdx);
	if (not pack or not pack.data) then return nil; end
	local q = Trivia_UnpackRecord(pack.data[localIdx]);
	return q;
end

function Trivia_GetAnswer1(qIdx)
	local pack, localIdx = Trivia_ResolveQuestion(qIdx);
	if (not pack or not pack.data) then return nil; end
	local _, a1 = Trivia_UnpackRecord(pack.data[localIdx]);
	return a1;
end

local function Trivia_SplitTabs(str)
	if (not str or str == "") then return 0; end
	local n = 0;
	local startPos = 1;
	while (true) do
		local tabPos = string.find(str, "\t", startPos, true);
		n = n + 1;
		if (tabPos) then
			splitBuf[n] = string.sub(str, startPos, tabPos - 1);
			startPos = tabPos + 1;
		else
			splitBuf[n] = string.sub(str, startPos);
			break;
		end
	end
	return n;
end

function Trivia_EnsureActiveSetLoaded()
	if (TRIVIA_SET_READY and TRIVIA_TOTAL_QUESTIONS > 0) then
		return true;
	end
	return Trivia_LoadQuestionSet(TRIVIA_QLIST or "warcraft", true, false);
end

function Trivia_LoadQuestionSet(qlist, silent, deferLoad)
	qlist = "warcraft";
	local packKeys = TRIVIA_SET_PACKS[qlist];
	if (not packKeys) then
		return false;
	end

	TRIVIA_QLIST = qlist;
	ACTIVE_PACKS = {};
	TRIVIA_QUESTION_ORDER = {};
	TRIVIA_ACTIVE_QUESTION = 0;
	TRIVIA_TOTAL_QUESTIONS = 0;
	TRIVIA_SET_READY = false;

	if (not deferLoad) then
		local offset = 0;
		local i = 1;
		local n = table.getn(packKeys);
		while (i <= n) do
			local p = Trivia_EnsurePackLoaded(packKeys[i]);
			if (p and p.count > 0) then
				table.insert(ACTIVE_PACKS, { pack = p, offset = offset, count = p.count });
				offset = offset + p.count;
			end
			i = i + 1;
		end
		TRIVIA_TOTAL_QUESTIONS = offset;
		if (TRIVIA_TOTAL_QUESTIONS > 0) then
			TRIVIA_SET_READY = true;
			Trivia_RandomiseOrder();
		end
	end

	Trivia_UpdateToggleButton();
	if (Trivia_RefreshOptionsFrame) then
		Trivia_RefreshOptionsFrame();
	end

	if (not silent) then
		local dispCount = TRIVIA_SET_READY and TRIVIA_TOTAL_QUESTIONS or Trivia_GetSetQuestionCount(TRIVIA_QLIST);
		Trivia_ConsoleMessage("Question set selected: " .. YELLOW .. TRIVIA_QLIST .. WHITE .. " (" .. dispCount .. " questions).");
	end
	return (deferLoad or TRIVIA_TOTAL_QUESTIONS > 0);
end

function Trivia_SetQuestionTimeout(sec, silent)
	Trivia_EnsureConfig();
	sec = tonumber(sec);
	if (not sec) then return false; end
	sec = math.floor(sec + 0.5);
	if (sec < 10) then sec = 10; end
	if (sec > 180) then sec = 180; end
	TRIVIA_CONFIG.questionTimeout = sec;
	TRIVIA_QUESTION_TIMEOUT = sec;
	if (TRIVIA_TIME_RECORD and TRIVIA_TIME_RECORD["holder"] == "noone") then
		TRIVIA_TIME_RECORD["time"] = sec + 1;
	end
	if (not silent) then
		Trivia_ConsoleMessage("Time per question set to " .. YELLOW .. sec .. " seconds" .. WHITE .. ".");
	end
	if (Trivia_RefreshOptionsFrame) then Trivia_RefreshOptionsFrame(); end
	return true;
end

function Trivia_SetWarnBeforeEnd(sec, silent)
	Trivia_EnsureConfig();
	sec = tonumber(sec);
	if (not sec) then return false; end
	sec = math.floor(sec + 0.5);
	if (sec < 0) then sec = 0; end
	if (sec > 60) then sec = 60; end
	TRIVIA_CONFIG.warnBeforeEnd = sec;
	if (not silent) then
		if (sec == 0) then
			Trivia_ConsoleMessage("Question time warning is now " .. RED .. "DISABLED" .. WHITE .. ".");
		else
			Trivia_ConsoleMessage("Time warning set to " .. YELLOW .. sec .. " seconds" .. WHITE .. " before timeout.");
		end
	end
	if (Trivia_RefreshOptionsFrame) then Trivia_RefreshOptionsFrame(); end
	return true;
end

function Trivia_SetQuestionInterval(sec, silent)
	Trivia_EnsureConfig();
	sec = tonumber(sec);
	if (not sec) then return false; end
	sec = math.floor(sec + 0.5);
	if (sec < 3) then sec = 3; end
	if (sec > 30) then sec = 30; end
	TRIVIA_CONFIG.questionInterval = sec;
	if (not silent) then
		Trivia_ConsoleMessage("Delay between questions set to " .. YELLOW .. sec .. " seconds" .. WHITE .. ".");
	end
	if (Trivia_RefreshOptionsFrame) then Trivia_RefreshOptionsFrame(); end
	return true;
end

function Trivia_SetScoreReportEvery(n, silent)
	Trivia_EnsureConfig();
	n = tonumber(n);
	if (not n) then return false; end
	n = math.floor(n + 0.5);
	if (n < 0) then n = 0; end
	if (n > 20) then n = 20; end
	TRIVIA_CONFIG.scoreReportEvery = n;
	TRIVIA_SCORE_REPORT = n;
	if (not silent) then
		if (n == 0) then
			Trivia_ConsoleMessage("Automatic leaderboard report is now " .. RED .. "DISABLED" .. WHITE .. ".");
		else
			Trivia_ConsoleMessage("Leaderboard will report every " .. YELLOW .. n .. WHITE .. " questions.");
		end
	end
	if (Trivia_RefreshOptionsFrame) then Trivia_RefreshOptionsFrame(); end
	return true;
end

function Trivia_SetAfkLimit(n, silent)
	Trivia_EnsureConfig();
	n = tonumber(n);
	if (not n) then return false; end
	n = math.floor(n + 0.5);
	if (n < 0) then n = 0; end
	if (n > 10) then n = 10; end
	TRIVIA_CONFIG.afkLimit = n;
	if (not silent) then
		if (n == 0) then
			Trivia_ConsoleMessage("AFK auto-stop is now " .. RED .. "DISABLED" .. WHITE .. ".");
		else
			Trivia_ConsoleMessage("AFK auto-stop set to " .. YELLOW .. n .. WHITE .. " unanswered questions in a row.");
		end
	end
	if (Trivia_RefreshOptionsFrame) then Trivia_RefreshOptionsFrame(); end
	return true;
end

function Trivia_SetRoundLimit(n, silent)
	Trivia_EnsureConfig();
	n = tonumber(n);
	if (not n) then return false; end
	n = math.floor(n + 0.5);
	if (n < 0) then n = 0; end
	if (n > 50) then n = 50; end
	TRIVIA_CONFIG.roundLimit = n;
	if (not silent) then
		if (n == 0) then
			Trivia_ConsoleMessage("Round question limit set to " .. YELLOW .. "Endless" .. WHITE .. ".");
		else
			Trivia_ConsoleMessage("Round limit set to " .. YELLOW .. n .. " questions" .. WHITE .. ".");
		end
	end
	if (Trivia_RefreshOptionsFrame) then Trivia_RefreshOptionsFrame(); end
	return true;
end

function Trivia_SetTargetScore(n, silent)
	Trivia_EnsureConfig();
	n = tonumber(n);
	if (not n) then return false; end
	n = math.floor(n + 0.5);
	if (n < 0) then n = 0; end
	if (n > 30) then n = 30; end
	TRIVIA_CONFIG.targetScore = n;
	if (not silent) then
		if (n == 0) then
			Trivia_ConsoleMessage("Target score win condition is now " .. RED .. "DISABLED" .. WHITE .. ".");
		else
			Trivia_ConsoleMessage("Target score set to " .. YELLOW .. "first to " .. n .. " points" .. WHITE .. ".");
		end
	end
	if (Trivia_RefreshOptionsFrame) then Trivia_RefreshOptionsFrame(); end
	return true;
end

-------------------------------------------------------------------------------
-- Slash Command Handler
-------------------------------------------------------------------------------

function Trivia_Command(cmd)
	cmd = Trivia_Trim(string.lower(cmd or ""));

	local msgArgs = {};
	local numArgs = 0;

	for value in string.gfind(cmd, "[^ ]+") do
		numArgs = numArgs + 1;
		msgArgs[numArgs] = value;
	end

	if (numArgs == 0) then
		if (Trivia_ToggleOptionsFrame) then
			Trivia_ToggleOptionsFrame();
		else
			Trivia_Help();
		end
		return;
	end

	local sub = msgArgs[1];
	local arg = msgArgs[2];

	if (sub == "menu" or sub == "config" or sub == "options" or sub == "settings" or sub == "ui") then
		if (Trivia_ToggleOptionsFrame) then
			Trivia_ToggleOptionsFrame();
		end
	elseif (sub == "start") then
		Trivia_Start();
	elseif (sub == "stop") then
		Trivia_Stop();
	elseif (sub == "pause") then
		Trivia_Pause(false);
	elseif (sub == "resume") then
		Trivia_Resume(false);
	elseif (sub == "toggle") then
		Trivia_Toggle();
	elseif (sub == "skip") then
		if (TRIVIA_ENABLED) then
			Trivia_SkipQuestion();
			Trivia_ConsoleMessage("Question skipped.");
		else
			Trivia_ErrorMessage("Trivia is not currently running.");
		end
	elseif (sub == "shuffle") then
		Trivia_UnSchedule("all");
		TRIVIA_ACCEPTING_ANSWERS = false;
		lastTimerSecond = -1;
		if (TRIVIA_SET_READY) then
			Trivia_RandomiseOrder();
		end
		Trivia_UpdateToggleButton();
		Trivia_ConsoleMessage("Questions shuffled.");
		if (TRIVIA_ENABLED) then
			Trivia_SendMessage("Questions shuffled. Restarting with a new question in 5 seconds.");
			Trivia_Schedule("NEXT_QUESTION", 5);
		end
	elseif (sub == "clear") then
		TRIVIA_SCORES = {};
		TRIVIA_TIME_RECORD = {["time"] = TRIVIA_CONFIG.questionTimeout + 1, ["holder"] = "noone"};
		TRIVIA_STREAK_HOLDER = nil;
		TRIVIA_STREAK_COUNT = 0;
		TRIVIA_BEST_STREAK = {["count"] = 0, ["holder"] = "noone"};
		Trivia_ConsoleMessage("Scores cleared.");
		if (TRIVIA_ENABLED) then
			Trivia_SendMessage("Scores cleared.");
		end
		if (Trivia_RefreshOptionsFrame) then Trivia_RefreshOptionsFrame(); end
	elseif (sub == "score" or sub == "scores") then
		Trivia_ReportScores();
	elseif (sub == "round") then
		if (not arg) then
			local rStr = (TRIVIA_CONFIG.roundLimit == 0) and "Endless" or (TRIVIA_CONFIG.roundLimit .. " questions");
			Trivia_ConsoleMessage("Current round limit: " .. YELLOW .. rStr .. WHITE .. " (Usage: /trivia round <0-50>, 0 = endless)");
		elseif (not Trivia_SetRoundLimit(arg, false)) then
			Trivia_ErrorMessage("Usage: /trivia round <0-50>");
		end
	elseif (sub == "target" or sub == "firstto") then
		if (not arg) then
			local tStr = (TRIVIA_CONFIG.targetScore == 0) and "Off" or ("First to " .. TRIVIA_CONFIG.targetScore .. " points");
			Trivia_ConsoleMessage("Current target score: " .. YELLOW .. tStr .. WHITE .. " (Usage: /trivia target <0-30>, 0 = off)");
		elseif (not Trivia_SetTargetScore(arg, false)) then
			Trivia_ErrorMessage("Usage: /trivia target <0-30>");
		end
	elseif (sub == "afk") then
		if (not arg) then
			local aStr = (TRIVIA_CONFIG.afkLimit == 0) and "Off" or (TRIVIA_CONFIG.afkLimit .. " unanswered in a row");
			Trivia_ConsoleMessage("Current AFK auto-stop: " .. YELLOW .. aStr .. WHITE .. " (Usage: /trivia afk <0-10>, 0 = off)");
		elseif (not Trivia_SetAfkLimit(arg, false)) then
			Trivia_ErrorMessage("Usage: /trivia afk <0-10>");
		end
	elseif (sub == "combat") then
		Trivia_EnsureConfig();
		if (arg == "on") then
			TRIVIA_CONFIG.autoPauseCombat = true;
		elseif (arg == "off") then
			TRIVIA_CONFIG.autoPauseCombat = false;
		else
			TRIVIA_CONFIG.autoPauseCombat = not TRIVIA_CONFIG.autoPauseCombat;
		end
		local cStr = TRIVIA_CONFIG.autoPauseCombat and (GREEN .. "ENABLED" .. WHITE) or (RED .. "DISABLED" .. WHITE);
		Trivia_ConsoleMessage("Auto-pause in combat is now " .. cStr .. ".");
		if (Trivia_RefreshOptionsFrame) then Trivia_RefreshOptionsFrame(); end
	elseif (sub == "timer" or sub == "timeout" or sub == "time") then
		if (not arg) then
			Trivia_ConsoleMessage("Current time per question: " .. YELLOW .. TRIVIA_CONFIG.questionTimeout .. "s" .. WHITE .. " (Usage: /trivia timer <10-180>)");
		elseif (not Trivia_SetQuestionTimeout(arg, false)) then
			Trivia_ErrorMessage("Usage: /trivia timer <10-180>");
		end
	elseif (sub == "warn") then
		if (not arg) then
			Trivia_ConsoleMessage("Current time warning: " .. YELLOW .. TRIVIA_CONFIG.warnBeforeEnd .. "s before timeout" .. WHITE .. " (Usage: /trivia warn <0-60>, 0 = off)");
		elseif (not Trivia_SetWarnBeforeEnd(arg, false)) then
			Trivia_ErrorMessage("Usage: /trivia warn <0-60>");
		end
	elseif (sub == "delay" or sub == "interval") then
		if (not arg) then
			Trivia_ConsoleMessage("Current delay between questions: " .. YELLOW .. TRIVIA_CONFIG.questionInterval .. "s" .. WHITE .. " (Usage: /trivia delay <3-30>)");
		elseif (not Trivia_SetQuestionInterval(arg, false)) then
			Trivia_ErrorMessage("Usage: /trivia delay <3-30>");
		end
	elseif (sub == "report") then
		if (not arg) then
			Trivia_ConsoleMessage("Current leaderboard report interval: " .. YELLOW .. TRIVIA_CONFIG.scoreReportEvery .. WHITE .. " (Usage: /trivia report <0-20>, 0 = off)");
		elseif (not Trivia_SetScoreReportEvery(arg, false)) then
			Trivia_ErrorMessage("Usage: /trivia report <0-20>");
		end
	elseif (sub == "choices" or sub == "abcd") then
		Trivia_EnsureConfig();
		if (arg == "on") then
			TRIVIA_CONFIG.showChoices = true;
		elseif (arg == "off") then
			TRIVIA_CONFIG.showChoices = false;
		else
			TRIVIA_CONFIG.showChoices = not TRIVIA_CONFIG.showChoices;
		end
		local stateStr = TRIVIA_CONFIG.showChoices and (GREEN .. "ENABLED" .. WHITE) or (RED .. "DISABLED" .. WHITE);
		Trivia_ConsoleMessage("Multiple-choice (A/B/C/D) display is now " .. stateStr .. ".");
		if (Trivia_RefreshOptionsFrame) then Trivia_RefreshOptionsFrame(); end
	elseif (sub == "lock") then
		Trivia_EnsureConfig();
		if (arg == "on" or arg == "true") then
			TRIVIA_CONFIG.locked = true;
		elseif (arg == "off" or arg == "false") then
			TRIVIA_CONFIG.locked = false;
		else
			TRIVIA_CONFIG.locked = not TRIVIA_CONFIG.locked;
		end
		Trivia_UpdateToggleButton();
		local lockStr = TRIVIA_CONFIG.locked and (YELLOW .. "LOCKED" .. WHITE) or (GREEN .. "UNLOCKED" .. WHITE);
		Trivia_ConsoleMessage("Moveable Trivia button is now " .. lockStr .. ".");
	elseif (sub == "unlock") then
		Trivia_EnsureConfig();
		TRIVIA_CONFIG.locked = false;
		Trivia_UpdateToggleButton();
		Trivia_ConsoleMessage("Moveable Trivia button is now " .. GREEN .. "UNLOCKED" .. WHITE .. ".");
	elseif (sub == "disable" or sub == "disablebutton" or sub == "hide") then
		Trivia_EnsureConfig();
		TRIVIA_CONFIG.buttonDisabled = true;
		Trivia_UpdateToggleButton();
		Trivia_ConsoleMessage("Moveable Trivia button is now " .. RED .. "DISABLED (hidden)" .. WHITE .. ". Type '/trivia enable' to show it again.");
	elseif (sub == "enable" or sub == "enablebutton" or sub == "show") then
		Trivia_EnsureConfig();
		TRIVIA_CONFIG.buttonDisabled = false;
		Trivia_UpdateToggleButton();
		Trivia_ConsoleMessage("Moveable Trivia button is now " .. GREEN .. "ENABLED (visible)" .. WHITE .. ".");
	elseif (sub == "button" or sub == "resetbutton") then
		Trivia_EnsureConfig();
		if (sub == "resetbutton" or arg == "reset") then
			TRIVIA_CONFIG.point = "TOP";
			TRIVIA_CONFIG.relativePoint = "TOP";
			TRIVIA_CONFIG.xOfs = 0;
			TRIVIA_CONFIG.yOfs = -60;
			TRIVIA_CONFIG.buttonDisabled = false;
			if (TriviaBotToggleButton) then
				TriviaBotToggleButton:ClearAllPoints();
				TriviaBotToggleButton:SetPoint("TOP", UIParent, "TOP", 0, -60);
			end
			Trivia_UpdateToggleButton();
			Trivia_ConsoleMessage("Moveable Trivia button position reset to top-center.");
		elseif (arg == "off" or arg == "disable" or arg == "hide") then
			TRIVIA_CONFIG.buttonDisabled = true;
			Trivia_UpdateToggleButton();
			Trivia_ConsoleMessage("Moveable Trivia button is now " .. RED .. "DISABLED (hidden)" .. WHITE .. ".");
		elseif (arg == "on" or arg == "enable" or arg == "show") then
			TRIVIA_CONFIG.buttonDisabled = false;
			Trivia_UpdateToggleButton();
			Trivia_ConsoleMessage("Moveable Trivia button is now " .. GREEN .. "ENABLED (visible)" .. WHITE .. ".");
		else
			TRIVIA_CONFIG.buttonDisabled = not TRIVIA_CONFIG.buttonDisabled;
			Trivia_UpdateToggleButton();
			local btnStr = TRIVIA_CONFIG.buttonDisabled and (RED .. "DISABLED (hidden)" .. WHITE) or (GREEN .. "ENABLED (visible)" .. WHITE);
			Trivia_ConsoleMessage("Moveable Trivia button is now " .. btnStr .. ".");
		end
	elseif (sub == "notify") then
		Trivia_EnsureConfig();
		TRIVIA_CONFIG.notifyTaskbar = not TRIVIA_CONFIG.notifyTaskbar;
		local notifyStr = TRIVIA_CONFIG.notifyTaskbar and (GREEN .. "ENABLED" .. WHITE) or (RED .. "DISABLED" .. WHITE);
		Trivia_ConsoleMessage("UnitXP SP3 taskbar notification on answer: " .. notifyStr .. ".");
		if (Trivia_RefreshOptionsFrame) then Trivia_RefreshOptionsFrame(); end
	elseif (sub == "qlist") then
		Trivia_ConsoleMessage("Unified question pack: " .. YELLOW .. "warcraft" .. WHITE .. " (" .. Trivia_GetSetQuestionCount("warcraft") .. " Turtle WoW & pre-TBC Warcraft questions).");
	elseif (sub == "channel") then
		if (not arg or arg == "") then
			Trivia_ConsoleMessage("Current channel: " .. YELLOW .. tostring(TRIVIA_CHANNEL));
			Trivia_ConsoleMessage("Usage: /trivia channel [SAY|PARTY|RAID|GUILD|<custom channel>]");
		else
			if (arg == "guild" or arg == "say" or arg == "party" or arg == "raid") then
				NEW_TRIVIA_CHANNEL = nil;
				channelRetryCount = 0;
				if (TRIVIA_CHANNEL and not Trivia_IsStandardChannel(TRIVIA_CHANNEL) and GetChannelName(TRIVIA_CHANNEL) > 0) then
					LeaveChannelByName(TRIVIA_CHANNEL);
				end
				TRIVIA_CHANNEL = string.upper(arg);
				if (TRIVIA_ENABLED) then
					Trivia_RegisterChatEvents();
				end
				Trivia_ConsoleMessage("Channel set to: " .. TRIVIA_CHANNEL);
			else
				NEW_TRIVIA_CHANNEL = arg;
				Trivia_ChangeChannel(true);
			end
			Trivia_UpdateToggleButton();
			if (Trivia_RefreshOptionsFrame) then
				Trivia_RefreshOptionsFrame();
			end
		end
	elseif (sub == "mem" or sub == "memory" or sub == "status") then
		Trivia_PrintMemoryStatus();
	elseif (sub == "help") then
		Trivia_Help();
	else
		Trivia_ErrorMessage("Invalid Command - Try '/trivia help'");
	end
end

function Trivia_PrintMemoryStatus()
	local qCount = Trivia_GetSetQuestionCount("warcraft");
	local onUpdateState = (Trivia and Trivia:IsShown()) and (GREEN .. "ACTIVE" .. WHITE) or (GREY .. "IDLE (0 CPU)" .. WHITE);
	Trivia_ConsoleMessage("Pack: " .. YELLOW .. "Warcraft & Turtle WoW (" .. qCount .. " Qs)" .. WHITE .. " | OnUpdate: " .. onUpdateState);
	if (type(UpdateAddOnMemoryUsage) == "function" and type(GetAddOnMemoryUsage) == "function") then
		UpdateAddOnMemoryUsage();
		local mem = GetAddOnMemoryUsage("TriviaBot-TurtleWow") or 0;
		Trivia_ConsoleMessage("Addon Memory: " .. GREEN .. math.floor(mem + 0.5) .. " KB" .. WHITE .. " (1 flat array, 0 sub-tables, 0 hash tables)");
	end
end

function Trivia_Help()
	Trivia_ConsoleMessage(YELLOW .. "--- TriviaBot-TurtleWoW v" .. TRIVIA_VERSION .. " Commands ---");
	Trivia_ConsoleMessage(CYAN .. "/trivia" .. WHITE .. " (or " .. CYAN .. "/trivia menu" .. WHITE .. ") - Open the Settings Menu.");
	Trivia_ConsoleMessage(CYAN .. "/trivia start | stop | pause | resume | toggle" .. WHITE .. " - Control TriviaBot.");
	Trivia_ConsoleMessage(CYAN .. "/trivia round <0-50> | target <0-30>" .. WHITE .. " - Round question limit or first-to-N score win.");
	Trivia_ConsoleMessage(CYAN .. "/trivia afk <0-10> | combat [on|off]" .. WHITE .. " - AFK auto-stop & auto-pause in combat.");
	Trivia_ConsoleMessage(CYAN .. "/trivia timer <10-180>" .. WHITE .. " - Set seconds allowed per question.");
	Trivia_ConsoleMessage(CYAN .. "/trivia warn <0-60>" .. WHITE .. " - Set warning seconds before timeout (0 = off).");
	Trivia_ConsoleMessage(CYAN .. "/trivia delay <3-30>" .. WHITE .. " - Set delay seconds between questions.");
	Trivia_ConsoleMessage(CYAN .. "/trivia lock | unlock" .. WHITE .. " - Lock/unlock the moveable Trivia button.");
	Trivia_ConsoleMessage(CYAN .. "/trivia disable | enable" .. WHITE .. " - Hide or show the Trivia button.");
	Trivia_ConsoleMessage(CYAN .. "/trivia button reset" .. WHITE .. " - Reset the moveable button to top-center.");
	Trivia_ConsoleMessage(CYAN .. "/trivia channel [SAY|PARTY|RAID|GUILD|<channel>]" .. WHITE .. " - Set trivia chat channel.");
	Trivia_ConsoleMessage(CYAN .. "/trivia choices" .. WHITE .. " - Toggle A/B/C/D multiple-choice options on/off.");
	Trivia_ConsoleMessage(CYAN .. "/trivia skip | shuffle | clear | score | mem" .. WHITE .. " - Skip, shuffle, clear, scores, or memory status.");
end

-------------------------------------------------------------------------------
-- Start / Stop / Toggle & Moveable On-Screen Button
-------------------------------------------------------------------------------

function Trivia_Start()
	if (TRIVIA_ENABLED) then
		if (TRIVIA_PAUSED) then
			Trivia_Resume(false);
		else
			Trivia_ConsoleMessage("Trivia is already running! Use '/trivia stop' to stop or '/trivia pause' to pause.");
		end
		return;
	end
	Trivia_EnsureConfig();
	if (not Trivia_EnsureActiveSetLoaded()) then
		Trivia_ErrorMessage("Unable to start Trivia: no questions loaded for set '" .. tostring(TRIVIA_QLIST) .. "'.");
		return;
	end
	local timeout = TRIVIA_CONFIG.questionTimeout;
	local roundLimit = TRIVIA_CONFIG.roundLimit or 0;
	local targetScore = TRIVIA_CONFIG.targetScore or 0;

	TRIVIA_ROUND_ASKED = 0;
	TRIVIA_AFK_STREAK = 0;
	TRIVIA_PAUSED = false;
	TRIVIA_PAUSED_BY_COMBAT = false;
	TRIVIA_PAUSED_REMAINING = 0;
	TRIVIA_PAUSED_WAS_ACCEPTING = false;

	if (roundLimit > 0 or targetScore > 0) then
		TRIVIA_SCORES = {};
		TRIVIA_STREAK_HOLDER = nil;
		TRIVIA_STREAK_COUNT = 0;
		TRIVIA_BEST_STREAK = {["count"] = 0, ["holder"] = "noone"};
		TRIVIA_TIME_RECORD = {["time"] = timeout + 1, ["holder"] = "noone"};
	end

	TRIVIA_ENABLED = true;
	TRIVIA_ACCEPTING_ANSWERS = false;
	lastTimerSecond = -1;
	Trivia_UnSchedule("all");
	Trivia_RegisterChatEvents();
	Trivia_UpdateFrameActive();
	Trivia_UpdateToggleButton();

	local modeTag = "";
	if (roundLimit > 0 and targetScore > 0) then
		modeTag = " [" .. roundLimit .. " Qs / First to " .. targetScore .. "]";
	elseif (roundLimit > 0) then
		modeTag = " [Round: " .. roundLimit .. " Qs]";
	elseif (targetScore > 0) then
		modeTag = " [First to " .. targetScore .. " pts]";
	end

	Trivia_ConsoleMessage("Trivia started in channel " .. YELLOW .. TRIVIA_CHANNEL .. WHITE .. " (" .. TRIVIA_QLIST .. " set, " .. timeout .. "s/question" .. modeTag .. "). First question in 2 seconds!");
	if (TRIVIA_CONFIG.showChoices) then
		Trivia_SendMessage("Trivia started (" .. TRIVIA_QLIST .. " set, " .. timeout .. "s/Q" .. modeTag .. ")! Answer with A, B, C, D or type the answer.");
	else
		Trivia_SendMessage("Trivia started (" .. TRIVIA_QLIST .. " set, " .. timeout .. "s/Q" .. modeTag .. ")! Type the answer in chat.");
	end
	Trivia_Schedule("NEXT_QUESTION", 2);
end

function Trivia_Stop(silentChat)
	Trivia_UnSchedule("all");
	local wasEnabled = TRIVIA_ENABLED;
	TRIVIA_ENABLED = false;
	TRIVIA_ACCEPTING_ANSWERS = false;
	TRIVIA_PAUSED = false;
	TRIVIA_PAUSED_BY_COMBAT = false;
	TRIVIA_PAUSED_REMAINING = 0;
	TRIVIA_PAUSED_WAS_ACCEPTING = false;
	curQ = nil; curA1 = nil; curAlt = nil; curCh = nil;
	TRIVIA_WRONG_LETTER_COOLDOWN = {};
	TRIVIA_TELLS = {};
	lastTimerSecond = -1;
	Trivia_UnregisterChatEvents();
	Trivia_UpdateFrameActive();
	Trivia_UpdateToggleButton();
	if (wasEnabled and not silentChat) then
		Trivia_SendMessage("Trivia bot stopped.");
	end
	Trivia_ConsoleMessage("Trivia bot stopped.");
end

function Trivia_Pause(byCombat)
	if (not TRIVIA_ENABLED or TRIVIA_PAUSED) then
		if (not byCombat) then
			Trivia_ErrorMessage("Trivia is not running or is already paused.");
		end
		return;
	end
	TRIVIA_PAUSED_WAS_ACCEPTING = TRIVIA_ACCEPTING_ANSWERS;
	if (TRIVIA_ACCEPTING_ANSWERS) then
		local rem = Trivia_GetRemainingSeconds() or 10;
		if (rem < 5) then rem = 5; end
		TRIVIA_PAUSED_REMAINING = rem;
	else
		TRIVIA_PAUSED_REMAINING = 0;
	end
	TRIVIA_PAUSED = true;
	TRIVIA_PAUSED_BY_COMBAT = (byCombat == true);
	TRIVIA_ACCEPTING_ANSWERS = false;
	lastTimerSecond = -1;
	Trivia_UnSchedule("all");
	Trivia_UpdateFrameActive();
	Trivia_UpdateToggleButton();
	if (byCombat) then
		Trivia_ConsoleMessage(YELLOW .. "Entered combat - Trivia auto-paused." .. WHITE);
	else
		Trivia_ConsoleMessage(YELLOW .. "Trivia paused." .. WHITE .. " Type '/trivia resume' to continue.");
	end
end

function Trivia_Resume(byCombat)
	if (not TRIVIA_ENABLED or not TRIVIA_PAUSED) then
		if (not byCombat) then
			Trivia_ErrorMessage("Trivia is not currently paused.");
		end
		return;
	end
	if (byCombat and not TRIVIA_PAUSED_BY_COMBAT) then
		return;
	end
	TRIVIA_PAUSED = false;
	TRIVIA_PAUSED_BY_COMBAT = false;
	lastTimerSecond = -1;

	if (TRIVIA_PAUSED_WAS_ACCEPTING and TRIVIA_PAUSED_REMAINING > 0) then
		local timeout = (TRIVIA_CONFIG and TRIVIA_CONFIG.questionTimeout) or 45;
		local warnBefore = (TRIVIA_CONFIG and TRIVIA_CONFIG.warnBeforeEnd) or 0;
		local rem = TRIVIA_PAUSED_REMAINING;
		TRIVIA_QUESTION_STARTTIME = GetTime() - (timeout - rem);
		TRIVIA_ACCEPTING_ANSWERS = true;
		Trivia_Schedule("QUESTION_TIMEOUT", rem);
		if (warnBefore > 0 and warnBefore < rem) then
			TRIVIA_WARN_REMAINING = warnBefore;
			Trivia_Schedule("QUESTION_WARN", rem - warnBefore);
		end
		Trivia_ConsoleMessage(GREEN .. "Trivia resumed" .. WHITE .. " (" .. rem .. "s remaining).");
	else
		Trivia_Schedule("NEXT_QUESTION", 3);
		Trivia_ConsoleMessage(GREEN .. "Trivia resumed." .. WHITE .. " Next question in 3 seconds.");
	end
	TRIVIA_PAUSED_WAS_ACCEPTING = false;
	TRIVIA_PAUSED_REMAINING = 0;
	Trivia_UpdateFrameActive();
	Trivia_UpdateToggleButton();
end

function Trivia_FinishRound(reasonText)
	Trivia_UnSchedule("all");
	TRIVIA_ENABLED = false;
	TRIVIA_ACCEPTING_ANSWERS = false;
	TRIVIA_PAUSED = false;
	TRIVIA_PAUSED_BY_COMBAT = false;
	curQ = nil; curA1 = nil; curAlt = nil; curCh = nil;
	TRIVIA_WRONG_LETTER_COOLDOWN = {};
	TRIVIA_TELLS = {};
	lastTimerSecond = -1;
	Trivia_UnregisterChatEvents();
	Trivia_UpdateFrameActive();
	Trivia_UpdateToggleButton();

	Trivia_SendMessage(reasonText);
	Trivia_ReportScores();
	Trivia_ConsoleMessage(YELLOW .. reasonText .. WHITE);
end

function Trivia_Toggle()
	if (TRIVIA_ENABLED) then
		Trivia_Stop();
	else
		Trivia_Start();
	end
end

function Trivia_CycleQuestionSet()
	if (TRIVIA_ENABLED) then
		Trivia_ErrorMessage("Stop the trivia bot first before changing question sets.");
		return;
	end
	local current = TRIVIA_QLIST or "warcraft";
	local nextSet = "warcraft";
	local count = table.getn(QLIST_CYCLE);
	local i = 1;
	while (i <= count) do
		if (QLIST_CYCLE[i] == current) then
			local nextIdx = i + 1;
			if (nextIdx > count) then nextIdx = 1; end
			nextSet = QLIST_CYCLE[nextIdx];
			break;
		end
		i = i + 1;
	end
	Trivia_LoadQuestionSet(nextSet, false, true);
end

function Trivia_CreateToggleButton()
	if (TriviaBotToggleButton) then
		return;
	end
	Trivia_EnsureConfig();

	local btn = CreateFrame("Button", "TriviaBotToggleButton", UIParent);
	btn:SetWidth(134);
	btn:SetHeight(28);
	btn:SetFrameStrata("MEDIUM");
	btn:SetToplevel(true);
	btn:SetMovable(true);
	btn:EnableMouse(true);
	btn:SetClampedToScreen(true);
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	btn:RegisterForDrag("LeftButton");

	btn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 }
	});
	btn:SetBackdropColor(0.08, 0.08, 0.12, 0.90);
	btn:SetBackdropBorderColor(0.6, 0.6, 0.6, 1.0);

	local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
	text:SetPoint("CENTER", btn, "CENTER", 0, 0);
	btn.text = text;

	btn:ClearAllPoints();
	btn:SetPoint(
		TRIVIA_CONFIG.point or "TOP",
		UIParent,
		TRIVIA_CONFIG.relativePoint or "TOP",
		TRIVIA_CONFIG.xOfs or 0,
		TRIVIA_CONFIG.yOfs or -60
	);

	btn:SetScript("OnDragStart", function()
		if (not TRIVIA_CONFIG.locked) then
			this:StartMoving();
			this.isMoving = true;
		else
			Trivia_ConsoleMessage("Button is locked. Type " .. CYAN .. "/trivia lock" .. WHITE .. " to unlock dragging.");
		end
	end);

	btn:SetScript("OnDragStop", function()
		if (this.isMoving) then
			this:StopMovingOrSizing();
			this.isMoving = false;
			local point, _, relativePoint, xOfs, yOfs = this:GetPoint();
			if (point) then
				TRIVIA_CONFIG.point = point;
				TRIVIA_CONFIG.relativePoint = relativePoint;
				TRIVIA_CONFIG.xOfs = math.floor(xOfs + 0.5);
				TRIVIA_CONFIG.yOfs = math.floor(yOfs + 0.5);
			end
		end
	end);

	btn:SetScript("OnClick", function()
		if (arg1 == "RightButton") then
			if (IsShiftKeyDown()) then
				if (TRIVIA_ENABLED) then
					Trivia_SkipQuestion();
					Trivia_ConsoleMessage("Question skipped.");
				else
					Trivia_CycleQuestionSet();
				end
			else
				if (Trivia_ToggleOptionsFrame) then
					Trivia_ToggleOptionsFrame();
				elseif (TRIVIA_ENABLED) then
					Trivia_SkipQuestion();
				else
					Trivia_CycleQuestionSet();
				end
			end
		else
			Trivia_Toggle();
		end
		if (GameTooltip:IsOwned(this)) then
			Trivia_ShowButtonTooltip(this);
		end
	end);

	btn:SetScript("OnEnter", function()
		Trivia_ShowButtonTooltip(this);
	end);

	btn:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);
end

function Trivia_ShowButtonTooltip(frame)
	GameTooltip:SetOwner(frame, "ANCHOR_BOTTOMRIGHT");
	GameTooltip:ClearLines();
	GameTooltip:AddLine("TriviaBot-TurtleWoW v" .. TRIVIA_VERSION, 1, 0.82, 0);
	if (TRIVIA_ENABLED) then
		GameTooltip:AddDoubleLine("Status:", "ON (Running)", 0.8, 0.8, 0.8, 0.2, 1.0, 0.2);
	else
		GameTooltip:AddDoubleLine("Status:", "OFF (Stopped)", 0.8, 0.8, 0.8, 1.0, 0.3, 0.3);
	end
	GameTooltip:AddDoubleLine("Channel:", tostring(TRIVIA_CHANNEL), 0.8, 0.8, 0.8, 1, 1, 1);
	GameTooltip:AddDoubleLine("Question Set:", tostring(TRIVIA_QLIST) .. " (" .. Trivia_GetSetQuestionCount(TRIVIA_QLIST) .. ")", 0.8, 0.8, 0.8, 0.4, 0.9, 1);
	GameTooltip:AddDoubleLine("Timer:", tostring(TRIVIA_CONFIG.questionTimeout) .. "s / question", 0.8, 0.8, 0.8, 1, 0.82, 0);
	GameTooltip:AddDoubleLine("A/B/C/D Choices:", TRIVIA_CONFIG.showChoices and "Enabled" or "Disabled", 0.8, 0.8, 0.8, 1, 1, 1);
	GameTooltip:AddDoubleLine("Button Position:", TRIVIA_CONFIG.locked and "Locked" or "Unlocked", 0.8, 0.8, 0.8, TRIVIA_CONFIG.locked and 1 or 0.3, TRIVIA_CONFIG.locked and 0.6 or 1, 0.3);
	GameTooltip:AddLine(" ");
	GameTooltip:AddLine("Left-Click: " .. WHITE .. (TRIVIA_ENABLED and "Stop Trivia" or "Start Trivia"), 0, 1, 0);
	GameTooltip:AddLine("Right-Click: " .. WHITE .. "Open Settings Menu", 1, 0.82, 0);
	if (TRIVIA_ENABLED) then
		GameTooltip:AddLine("Shift + Right-Click: " .. WHITE .. "Skip Current Question", 0, 0.8, 1);
	end
	if (not TRIVIA_CONFIG.locked) then
		GameTooltip:AddLine("Left-Drag: " .. WHITE .. "Move Button", 0.7, 0.7, 0.7);
	end
	GameTooltip:AddLine("Commands: " .. GREY .. "/trivia | /trivia lock | /trivia disable", 0.6, 0.6, 0.6);
	GameTooltip:Show();
end

function Trivia_GetRemainingSeconds()
	if (not TRIVIA_ENABLED or not TRIVIA_ACCEPTING_ANSWERS) then
		return nil;
	end
	local timeout = (TRIVIA_CONFIG and TRIVIA_CONFIG.questionTimeout) or 45;
	local rem = math.ceil(timeout - (GetTime() - TRIVIA_QUESTION_STARTTIME));
	if (rem < 0) then rem = 0; end
	return rem;
end

function Trivia_UpdateCountdownUI()
	if (TRIVIA_ENABLED and TRIVIA_ACCEPTING_ANSWERS) then
		local rem = Trivia_GetRemainingSeconds();
		if (rem and rem ~= lastTimerSecond) then
			lastTimerSecond = rem;
			if (TriviaBotToggleButton and TriviaBotToggleButton:IsShown() and TRIVIA_CONFIG and TRIVIA_CONFIG.showButtonTimer) then
				local lockTag = TRIVIA_CONFIG.locked and (GREY .. " [L]" .. WHITE) or "";
				TriviaBotToggleButton.text:SetText(WHITE .. "Trivia: " .. GREEN .. "ON " .. YELLOW .. "(" .. rem .. "s)" .. lockTag);
			end
			if (Trivia_RefreshOptionsTimer) then
				Trivia_RefreshOptionsTimer(rem);
			end
		end
	elseif (lastTimerSecond ~= -1) then
		lastTimerSecond = -1;
		Trivia_UpdateToggleButton();
	end
end

function Trivia_UpdateToggleButton()
	Trivia_EnsureConfig();
	if (Trivia_RefreshOptionsFrame) then
		Trivia_RefreshOptionsFrame();
	end
	if (TRIVIA_CONFIG.buttonDisabled) then
		if (TriviaBotToggleButton) then
			TriviaBotToggleButton:Hide();
		end
		return;
	end
	if (not TriviaBotToggleButton) then
		Trivia_CreateToggleButton();
	end
	if (not TriviaBotToggleButton) then
		return;
	end

	TriviaBotToggleButton:Show();
	local lockTag = TRIVIA_CONFIG.locked and (GREY .. " [L]" .. WHITE) or "";
	if (TRIVIA_ENABLED) then
		if (TRIVIA_PAUSED) then
			lastTimerSecond = -1;
			local pauseTag = TRIVIA_PAUSED_BY_COMBAT and "COMBAT" or "PAUSED";
			TriviaBotToggleButton.text:SetText(WHITE .. "Trivia: " .. YELLOW .. pauseTag .. lockTag);
			TriviaBotToggleButton:SetBackdropBorderColor(0.95, 0.8, 0.15, 1.0);
		else
			local timerTag = "";
			if (TRIVIA_ACCEPTING_ANSWERS and TRIVIA_CONFIG.showButtonTimer) then
				local rem = Trivia_GetRemainingSeconds();
				if (rem) then
					lastTimerSecond = rem;
					timerTag = " " .. YELLOW .. "(" .. rem .. "s)";
				end
			end
			TriviaBotToggleButton.text:SetText(WHITE .. "Trivia: " .. GREEN .. "ON" .. timerTag .. lockTag);
			TriviaBotToggleButton:SetBackdropBorderColor(0.2, 0.9, 0.2, 1.0);
		end
	else
		lastTimerSecond = -1;
		TriviaBotToggleButton.text:SetText(WHITE .. "Trivia: " .. RED .. "OFF" .. lockTag);
		TriviaBotToggleButton:SetBackdropBorderColor(0.6, 0.6, 0.6, 1.0);
	end
end

-------------------------------------------------------------------------------
-- Question Ordering & Multiple Choice (A, B, C, D) Generation
-------------------------------------------------------------------------------

function Trivia_RandomiseOrder()
	TRIVIA_QUESTION_ORDER = {};
	TRIVIA_ACTIVE_QUESTION = 0;

	local noOfQuestions = TRIVIA_TOTAL_QUESTIONS;
	local n = 1;
	while (n <= noOfQuestions) do
		TRIVIA_QUESTION_ORDER[n] = n;
		n = n + 1;
	end

	-- Fisher-Yates single-pass shuffle (O(N), uniform distribution)
	local i = noOfQuestions;
	while (i >= 2) do
		local randIdx = math.random(i);
		local tmp = TRIVIA_QUESTION_ORDER[i];
		TRIVIA_QUESTION_ORDER[i] = TRIVIA_QUESTION_ORDER[randIdx];
		TRIVIA_QUESTION_ORDER[randIdx] = tmp;
		i = i - 1;
	end
end

function Trivia_BuildChoicesForQuestion()
	local correctAns = curA1 or "";
	local packedChoices = (curCh and curCh ~= "") and curCh or nil;

	choiceOpts[1] = nil; choiceOpts[2] = nil; choiceOpts[3] = nil; choiceOpts[4] = nil;
	local optCount = 0;

	if (packedChoices) then
		local n = Trivia_SplitTabs(packedChoices);
		if (n == 3) then
			choiceOpts[1] = correctAns;
			choiceOpts[2] = splitBuf[1];
			choiceOpts[3] = splitBuf[2];
			choiceOpts[4] = splitBuf[3];
			optCount = 4;
		elseif (n >= 4) then
			choiceOpts[1] = splitBuf[1];
			choiceOpts[2] = splitBuf[2];
			choiceOpts[3] = splitBuf[3];
			choiceOpts[4] = splitBuf[4];
			optCount = 4;
		end
	end

	if (optCount < 4) then
		choiceOpts[1] = correctAns;
		optCount = 1;
		local totalQ = TRIVIA_TOTAL_QUESTIONS;
		local normCorrect = Trivia_NormalizeText(correctAns);
		local attempts = 0;
		while (optCount < 4 and attempts < 60 and totalQ > 4) do
			attempts = attempts + 1;
			local pickIdx = math.random(totalQ);
			local candidate = Trivia_GetAnswer1(pickIdx);
			if (candidate and Trivia_NormalizeText(candidate) ~= normCorrect) then
				local dup = false;
				local candNorm = Trivia_NormalizeText(candidate);
				local k = 1;
				while (k <= optCount) do
					if (Trivia_NormalizeText(choiceOpts[k]) == candNorm) then
						dup = true;
						break;
					end
					k = k + 1;
				end
				if (not dup) then
					optCount = optCount + 1;
					choiceOpts[optCount] = candidate;
				end
			end
		end
		while (optCount < 4) do
			optCount = optCount + 1;
			choiceOpts[optCount] = "None of these (" .. optCount .. ")";
		end
	end

	-- Shuffle index order so index 1 (canonical answer) is always tracked reliably
	shuffleOrder[1] = 1; shuffleOrder[2] = 2; shuffleOrder[3] = 3; shuffleOrder[4] = 4;
	local i = 4;
	while (i >= 2) do
		local r = math.random(i);
		local tmp = shuffleOrder[i];
		shuffleOrder[i] = shuffleOrder[r];
		shuffleOrder[r] = tmp;
		i = i - 1;
	end

	TRIVIA_CURRENT_CORRECT_LETTER = "a";
	local idx = 1;
	while (idx <= 4) do
		local ltr = CHOICE_LETTERS[idx];
		local srcIndex = shuffleOrder[idx];
		TRIVIA_CURRENT_OPTIONS[ltr] = choiceOpts[srcIndex];
		if (srcIndex == 1) then
			TRIVIA_CURRENT_CORRECT_LETTER = ltr;
		end
		idx = idx + 1;
	end
end

function Trivia_AskQuestion()
	Trivia_EnsureConfig();
	local totalQ = TRIVIA_TOTAL_QUESTIONS;
	if (totalQ == 0) then
		Trivia_ErrorMessage("No questions loaded in current set!");
		Trivia_Stop();
		return;
	end

	TRIVIA_ACTIVE_QUESTION = TRIVIA_ACTIVE_QUESTION + 1;
	if (TRIVIA_ACTIVE_QUESTION > totalQ) then
		Trivia_RandomiseOrder();
		TRIVIA_ACTIVE_QUESTION = 1;
		Trivia_ConsoleMessage("Out of questions... Reshuffled and restarted.");
	end

	local qIdx = TRIVIA_QUESTION_ORDER[TRIVIA_ACTIVE_QUESTION];
	local pack, localIdx = Trivia_ResolveQuestion(qIdx);
	curQ, curA1, curAlt, curCh = Trivia_UnpackRecord(pack and pack.data and pack.data[localIdx]);

	TRIVIA_ROUND_ASKED = TRIVIA_ROUND_ASKED + 1;
	TRIVIA_WRONG_LETTER_COOLDOWN = {};
	Trivia_BuildChoicesForQuestion();

	local timeout = TRIVIA_CONFIG.questionTimeout or 45;
	local warnBefore = TRIVIA_CONFIG.warnBeforeEnd;
	if (warnBefore == nil) then warnBefore = 15; end

	TRIVIA_QUESTION_STARTTIME = GetTime();
	TRIVIA_ACCEPTING_ANSWERS = true;
	lastTimerSecond = -1;
	Trivia_UnSchedule("all");
	Trivia_Schedule("QUESTION_TIMEOUT", timeout);
	if (warnBefore > 0 and warnBefore < timeout) then
		TRIVIA_WARN_REMAINING = warnBefore;
		Trivia_Schedule("QUESTION_WARN", timeout - warnBefore);
	elseif (warnBefore >= timeout and timeout >= 20) then
		TRIVIA_WARN_REMAINING = math.floor(timeout / 2);
		Trivia_Schedule("QUESTION_WARN", timeout - TRIVIA_WARN_REMAINING);
	end
	Trivia_UpdateToggleButton();

	local roundLimit = TRIVIA_CONFIG.roundLimit or 0;
	local qPrefix = (roundLimit > 0) and ("Q (" .. TRIVIA_ROUND_ASKED .. "/" .. roundLimit .. "): ") or "Q: ";
	Trivia_SendMessage(qPrefix .. (curQ or ""));

	if (TRIVIA_CONFIG.showChoices and TRIVIA_CURRENT_OPTIONS["a"]) then
		local lineAB = "[A] " .. TRIVIA_CURRENT_OPTIONS["a"] .. "   [B] " .. TRIVIA_CURRENT_OPTIONS["b"];
		local lineCD = "[C] " .. TRIVIA_CURRENT_OPTIONS["c"] .. "   [D] " .. TRIVIA_CURRENT_OPTIONS["d"];
		local singleLine = lineAB .. "   " .. lineCD;
		if (string.len(singleLine) <= 225) then
			Trivia_SendMessage(singleLine);
		else
			Trivia_SendMessage(lineAB);
			Trivia_SendMessage(lineCD);
		end
	end
end

function Trivia_QuestionTimeout()
	TRIVIA_ACCEPTING_ANSWERS = false;
	lastTimerSecond = -1;
	Trivia_UpdateToggleButton();
	Trivia_SendMessage("Time is up! No correct answer was given.");

	local ans = curA1 or "Unknown";
	local ansLabel = (TRIVIA_CONFIG.showChoices and TRIVIA_CURRENT_CORRECT_LETTER)
		and ("[" .. string.upper(TRIVIA_CURRENT_CORRECT_LETTER) .. "] " .. ans)
		or ans;

	-- AFK Auto-Stop check
	TRIVIA_AFK_STREAK = TRIVIA_AFK_STREAK + 1;
	local afkLimit = (TRIVIA_CONFIG and TRIVIA_CONFIG.afkLimit) or 0;
	if (afkLimit > 0 and TRIVIA_AFK_STREAK >= afkLimit) then
		Trivia_SendMessage("The correct answer was: " .. ansLabel);
		Trivia_SendMessage("No answers for " .. TRIVIA_AFK_STREAK .. " questions in a row. Trivia auto-stopped.");
		Trivia_Stop(true);
		return;
	end

	-- Round limit check
	local roundLimit = (TRIVIA_CONFIG and TRIVIA_CONFIG.roundLimit) or 0;
	if (roundLimit > 0 and TRIVIA_ROUND_ASKED >= roundLimit) then
		Trivia_SendMessage("The correct answer was: " .. ansLabel);
		Trivia_FinishRound("ROUND OVER! All " .. roundLimit .. " questions completed!");
		return;
	end

	local interval = (TRIVIA_CONFIG and TRIVIA_CONFIG.questionInterval) or 7;
	local reportEvery = (TRIVIA_CONFIG and TRIVIA_CONFIG.scoreReportEvery) or 5;

	if (reportEvery > 0 and TRIVIA_SCORE_REPORT <= 1) then
		Trivia_Schedule("SHOW_ANSWER", 2);
		Trivia_Schedule("REPORT_SCORERS", 4);
		Trivia_Schedule("NEXT_QUESTION", interval + 5);
		TRIVIA_SCORE_REPORT = reportEvery;
	else
		if (reportEvery > 0) then
			TRIVIA_SCORE_REPORT = TRIVIA_SCORE_REPORT - 1;
		end
		Trivia_Schedule("SHOW_ANSWER", 2);
		Trivia_Schedule("NEXT_QUESTION", interval);
	end
end

function Trivia_SkipQuestion()
	if (TRIVIA_ENABLED) then
		local wasAccepting = TRIVIA_ACCEPTING_ANSWERS;
		TRIVIA_ACCEPTING_ANSWERS = false;
		lastTimerSecond = -1;
		Trivia_UpdateToggleButton();
		Trivia_UnSchedule("all");
		if (wasAccepting) then
			Trivia_SendMessage("Question was skipped.");
			Trivia_Schedule("SHOW_ANSWER", 1);
			Trivia_Schedule("NEXT_QUESTION", 4);
		else
			Trivia_Schedule("NEXT_QUESTION", 1);
		end
	end
end

-------------------------------------------------------------------------------
-- Text Normalization & Fuzzy ("Likely") Answer Matching
-------------------------------------------------------------------------------

function Trivia_Trim(s)
	if (not s) then return ""; end
	local _, _, trimmed = string.find(s, "^%s*(.-)%s*$");
	return trimmed or "";
end

function Trivia_NormalizeText(s)
	if (not s) then return ""; end
	s = string.lower(s);
	-- Replace punctuation with spaces or empty string
	s = string.gsub(s, "['\"`]", "");
	s = string.gsub(s, "[%.,!%?:;%-_/%(%)%[%]%{%}]", " ");
	s = string.gsub(s, "%s+", " ");
	s = Trivia_Trim(s);

	-- Strip common conversational prefixes and articles
	local _, _, rest = string.find(s, "^i think it is (.+)$");
	if (rest) then s = rest; end
	_, _, rest = string.find(s, "^it is (.+)$");
	if (rest) then s = rest; end
	_, _, rest = string.find(s, "^its (.+)$");
	if (rest) then s = rest; end
	_, _, rest = string.find(s, "^the (.+)$");
	if (rest) then s = rest; end
	_, _, rest = string.find(s, "^a (.+)$");
	if (rest) then s = rest; end
	_, _, rest = string.find(s, "^an (.+)$");
	if (rest) then s = rest; end

	s = Trivia_Trim(s);
	if (NUMBER_WORDS[s]) then
		s = NUMBER_WORDS[s];
	end
	return s;
end

function Trivia_ExtractCoreAnswer(normAns)
	-- Strips verbose explanations found in NormalQuestions (e.g. "tatum oneal at age 10" -> "tatum oneal")
	local i = 1;
	local n = table.getn(CORE_PATTERNS);
	while (i <= n) do
		local _, _, core = string.find(normAns, CORE_PATTERNS[i]);
		if (core and string.len(core) >= 3) then
			return Trivia_Trim(core);
		end
		i = i + 1;
	end
	return normAns;
end

function Trivia_Levenshtein(s1, s2)
	local len1 = string.len(s1);
	local len2 = string.len(s2);
	if (len1 == 0) then return len2; end
	if (len2 == 0) then return len1; end
	if ( math.abs(len1 - len2) > 4 ) then return 99; end

	local j = 0;
	while (j <= len2) do
		levRow0[j] = j;
		j = j + 1;
	end

	local i = 1;
	while (i <= len1) do
		levRow1[0] = i;
		local c1 = string.byte(s1, i);
		j = 1;
		while (j <= len2) do
			local cost = (c1 == string.byte(s2, j)) and 0 or 1;
			local del = levRow0[j] + 1;
			local ins = levRow1[j - 1] + 1;
			local sub = levRow0[j - 1] + cost;
			local minVal = del;
			if (ins < minVal) then minVal = ins; end
			if (sub < minVal) then minVal = sub; end
			levRow1[j] = minVal;
			j = j + 1;
		end
		j = 0;
		while (j <= len2) do
			levRow0[j] = levRow1[j];
			j = j + 1;
		end
		i = i + 1;
	end
	return levRow0[len2];
end

function Trivia_ParseLetterChoice(msg)
	local raw = Trivia_Trim(string.lower(msg or ""));
	if (raw == "a" or raw == "b" or raw == "c" or raw == "d") then
		return raw;
	end
	local _, _, ltr = string.find(raw, "^%(?%[?([abcd])%]?%)?[%.%:%)%-]?$");
	if (ltr) then
		return ltr;
	end
	_, _, ltr = string.find(raw, "^option ([abcd])$");
	if (ltr) then
		return ltr;
	end
	_, _, ltr = string.find(raw, "^answer ([abcd])$");
	if (ltr) then
		return ltr;
	end
	_, _, ltr = string.find(raw, "^choice ([abcd])$");
	if (ltr) then
		return ltr;
	end
	return nil;
end

function Trivia_IsLikelyMatch(playerMsg, targetAns)
	if (not playerMsg or not targetAns) then return false; end

	local normPlayer = Trivia_NormalizeText(playerMsg);
	local normTarget = Trivia_NormalizeText(targetAns);
	if (normPlayer == "" or normTarget == "") then return false; end

	-- 1. Exact normalized match
	if (normPlayer == normTarget) then
		return true;
	end

	-- 2. Core answer match (for verbose answers like "Tatum O'Neal at age 10")
	local coreTarget = Trivia_ExtractCoreAnswer(normTarget);
	if (normPlayer == coreTarget) then
		return true;
	end

	-- Do not fuzzy-match pure numbers or boolean answers
	local targetHasDigits = (string.find(coreTarget, "%d") ~= nil);
	local playerHasDigits = (string.find(normPlayer, "%d") ~= nil);
	if (coreTarget == "true" or coreTarget == "false" or coreTarget == "yes" or coreTarget == "no") then
		return false;
	end

	-- 3. Multi-word token / substring match (e.g. "Lashlayer" for "Broodlord Lashlayer", or "Sorrowguard" for "Sorrowguard Keep")
	local playerLen = string.len(normPlayer);
	local targetLen = string.len(coreTarget);

	if (not targetHasDigits and not playerHasDigits) then
		-- If player typed a single distinctive word (>= 5 chars) that matches a non-stopword token of the target
		if (playerLen >= 5 and not string.find(normPlayer, " ")) then
			for token in string.gfind(coreTarget, "[^ ]+") do
				if (string.len(token) >= 5 and not STOPWORDS[token]) then
					if (normPlayer == token) then
						return true;
					end
					if (string.len(token) >= 6 and Trivia_Levenshtein(normPlayer, token) <= 1) then
						return true;
					end
				end
			end
		end

		-- If player's sentence contains the full target answer (e.g. "b) broodlord lashlayer")
		if (targetLen >= 4 and playerLen > targetLen) then
			if (string.find(" " .. normPlayer .. " ", " " .. coreTarget .. " ", 1, true)) then
				return true;
			end
		end

		-- 4. Typo tolerance via Levenshtein edit distance
		if (targetLen >= 4 and playerLen >= 3) then
			local dist = Trivia_Levenshtein(normPlayer, coreTarget);
			if (targetLen <= 6 and dist <= 1) then
				return true;
			elseif (targetLen <= 11 and dist <= 2) then
				return true;
			elseif (targetLen >= 12 and dist <= 3) then
				return true;
			end
		end
	end

	return false;
end

function Trivia_CheckAnswer(player, msg)
	if (not TRIVIA_ACCEPTING_ANSWERS) then return; end
	if (Trivia_IsBotMessage(msg)) then return; end
	local qIdx = TRIVIA_QUESTION_ORDER[TRIVIA_ACTIVE_QUESTION];
	if (not qIdx) then return; end

	-- Prevent copying multiple A/B/C/D options into one message to exploit fuzzy substring matching
	if (TRIVIA_CONFIG.showChoices and TRIVIA_CURRENT_OPTIONS["a"] and TRIVIA_CURRENT_CORRECT_LETTER) then
		local normMsg = " " .. Trivia_NormalizeText(msg) .. " ";
		local normCorrectOpt = Trivia_NormalizeText(TRIVIA_CURRENT_OPTIONS[TRIVIA_CURRENT_CORRECT_LETTER]);
		local distractorHits = 0;
		local idx = 1;
		while (idx <= 4) do
			local ltr = CHOICE_LETTERS[idx];
			if (ltr ~= TRIVIA_CURRENT_CORRECT_LETTER) then
				local optNorm = Trivia_NormalizeText(TRIVIA_CURRENT_OPTIONS[ltr]);
				if (string.len(optNorm) >= 4 and not string.find(normCorrectOpt, optNorm, 1, true)) then
					if (string.find(normMsg, " " .. optNorm .. " ", 1, true)) then
						distractorHits = distractorHits + 1;
					end
				end
			end
			idx = idx + 1;
		end
		if (distractorHits >= 1 and string.len(normMsg) > string.len(normCorrectOpt) + 6) then
			return;
		end
	end

	local isCorrect = false;

	-- 1. Check A / B / C / D choice answer
	if (TRIVIA_CONFIG.showChoices and TRIVIA_CURRENT_CORRECT_LETTER) then
		local guessedLetter = Trivia_ParseLetterChoice(msg);
		if (guessedLetter) then
			local cooldownUntil = TRIVIA_WRONG_LETTER_COOLDOWN[player];
			if (cooldownUntil and GetTime() < cooldownUntil) then
				return;
			end
			if (guessedLetter == TRIVIA_CURRENT_CORRECT_LETTER) then
				isCorrect = true;
			else
				-- Prevent rapid A/B/C/D spam guessing for 3 seconds
				TRIVIA_WRONG_LETTER_COOLDOWN[player] = GetTime() + 3.0;
				return;
			end
		end
	end

	-- 2. Check full / likely text answer across cached canonical answer, packed alternates, and displayed option
	if (not isCorrect) then
		if (curA1 and curA1 ~= "" and Trivia_IsLikelyMatch(msg, curA1)) then
			isCorrect = true;
		end
		if (not isCorrect and curAlt and curAlt ~= "") then
			local nAlt = Trivia_SplitTabs(curAlt);
			local i = 1;
			while (i <= nAlt) do
				if (Trivia_IsLikelyMatch(msg, splitBuf[i])) then
					isCorrect = true;
					break;
				end
				i = i + 1;
			end
		end
		if (not isCorrect and TRIVIA_CURRENT_CORRECT_LETTER and TRIVIA_CURRENT_OPTIONS[TRIVIA_CURRENT_CORRECT_LETTER]) then
			if (Trivia_IsLikelyMatch(msg, TRIVIA_CURRENT_OPTIONS[TRIVIA_CURRENT_CORRECT_LETTER])) then
				isCorrect = true;
			end
		end
	end

	if (isCorrect) then
		TRIVIA_ACCEPTING_ANSWERS = false;
		TRIVIA_AFK_STREAK = 0;
		lastTimerSecond = -1;
		Trivia_UnSchedule("all");

		local canonicalAns = curA1 or "";
		local answerLabel = canonicalAns;
		if (TRIVIA_CONFIG.showChoices and TRIVIA_CURRENT_CORRECT_LETTER) then
			answerLabel = "[" .. string.upper(TRIVIA_CURRENT_CORRECT_LETTER) .. "] " .. canonicalAns;
		end

		Trivia_SendMessage("That is the correct answer, " .. player .. "! (" .. answerLabel .. ")");

		if (HAS_XP3 and TRIVIA_CONFIG.notifyTaskbar) then
			pcall(UnitXP, "notify", "taskbarIcon");
		end

		local timeTaken = GetTime() - TRIVIA_QUESTION_STARTTIME;
		timeTaken = math.floor(timeTaken * 100 + 0.5) / 100;

		if (timeTaken < TRIVIA_TIME_RECORD["time"]) then
			Trivia_SendMessage("NEW RECORD! Answered in: " .. timeTaken .. " sec");
			TRIVIA_TIME_RECORD["holder"] = player;
			TRIVIA_TIME_RECORD["time"] = timeTaken;
		end

		-- Win Streak tracking
		if (TRIVIA_STREAK_HOLDER == player) then
			TRIVIA_STREAK_COUNT = TRIVIA_STREAK_COUNT + 1;
			if (TRIVIA_STREAK_COUNT == 3) then
				Trivia_SendMessage(player .. " is on fire! (3-question streak!)");
			elseif (TRIVIA_STREAK_COUNT == 5) then
				Trivia_SendMessage(player .. " is UNSTOPPABLE! (5-question streak!)");
			elseif (TRIVIA_STREAK_COUNT >= 10 and math.mod(TRIVIA_STREAK_COUNT, 5) == 0) then
				Trivia_SendMessage(player .. " is GODLIKE! (" .. TRIVIA_STREAK_COUNT .. "-question streak!)");
			end
		else
			if (TRIVIA_STREAK_HOLDER and TRIVIA_STREAK_COUNT >= 3) then
				Trivia_SendMessage(player .. " ended " .. TRIVIA_STREAK_HOLDER .. "'s " .. TRIVIA_STREAK_COUNT .. "-question streak!");
			end
			TRIVIA_STREAK_HOLDER = player;
			TRIVIA_STREAK_COUNT = 1;
		end
		if (TRIVIA_STREAK_COUNT > TRIVIA_BEST_STREAK["count"]) then
			TRIVIA_BEST_STREAK["count"] = TRIVIA_STREAK_COUNT;
			TRIVIA_BEST_STREAK["holder"] = player;
		end

		local score = TRIVIA_SCORES[player];
		if (score) then
			score = score + 1;
		else
			score = 1;
		end
		TRIVIA_SCORES[player] = score;

		Trivia_UpdateToggleButton();

		-- Round Mode win condition checks
		local targetScore = (TRIVIA_CONFIG and TRIVIA_CONFIG.targetScore) or 0;
		local roundLimit = (TRIVIA_CONFIG and TRIVIA_CONFIG.roundLimit) or 0;
		if (targetScore > 0 and score >= targetScore) then
			Trivia_FinishRound("ROUND OVER! " .. player .. " reached " .. score .. " points and wins the round!");
			return;
		elseif (roundLimit > 0 and TRIVIA_ROUND_ASKED >= roundLimit) then
			Trivia_FinishRound("ROUND OVER! All " .. roundLimit .. " questions completed!");
			return;
		end

		local interval = (TRIVIA_CONFIG and TRIVIA_CONFIG.questionInterval) or 7;
		local reportEvery = (TRIVIA_CONFIG and TRIVIA_CONFIG.scoreReportEvery) or 5;

		if (reportEvery > 0 and TRIVIA_SCORE_REPORT <= 1) then
			Trivia_Schedule("REPORT_SCORERS", 3);
			Trivia_Schedule("NEXT_QUESTION", interval + 4);
			TRIVIA_SCORE_REPORT = reportEvery;
		else
			if (reportEvery > 0) then
				TRIVIA_SCORE_REPORT = TRIVIA_SCORE_REPORT - 1;
			end
			Trivia_Schedule("NEXT_QUESTION", interval);
		end
	end
end

-------------------------------------------------------------------------------
-- Scoring & Whisper Score
-------------------------------------------------------------------------------

local function Trivia_CompareScoreEntries(v1, v2)
	if (v1.score == v2.score) then
		return v1.player < v2.player;
	end
	return v1.score > v2.score;
end

function Trivia_GetSortedStandings()
	local count = 0;
	for player, score in pairs(TRIVIA_SCORES) do
		count = count + 1;
		local rec = sortScores[count];
		if (not rec) then
			rec = {};
			sortScores[count] = rec;
		end
		rec.player = player;
		rec.score = score;
	end
	local extra = count + 1;
	while (sortScores[extra]) do
		sortScores[extra] = nil;
		extra = extra + 1;
	end
	if (count > 1) then
		table.sort(sortScores, Trivia_CompareScoreEntries);
	end
	return sortScores, count;
end

function Trivia_ReportScores()
	local list, count = Trivia_GetSortedStandings();

	if (count == 0) then
		Trivia_SendMessage("No scores recorded yet.");
		return;
	end

	Trivia_SendMessage("Standing so far:");
	local id = 1;
	while (id <= count and id <= 3) do
		local record = list[id];
		local ess = (record.score == 1) and "" or "s";
		Trivia_SendMessage(id .. "]: " .. record.player .. " (" .. record.score .. " point" .. ess .. ")");
		id = id + 1;
	end

	if (TRIVIA_TIME_RECORD["holder"] ~= "noone") then
		Trivia_SendMessage("Speed Record: " .. TRIVIA_TIME_RECORD["holder"] .. " in " .. TRIVIA_TIME_RECORD["time"] .. " sec");
	end
	if (TRIVIA_BEST_STREAK["count"] >= 2) then
		Trivia_SendMessage("Best Streak: " .. TRIVIA_BEST_STREAK["holder"] .. " (" .. TRIVIA_BEST_STREAK["count"] .. " in a row)");
	end
end

local function Trivia_SendRawChat(line, chatType, language, channel)
	if (type(WoWTranslate_SendRaw) == "function") then
		WoWTranslate_SendRaw(line, chatType, language, channel);
	else
		SendChatMessage(line, chatType, language, channel);
	end
end

function Trivia_WhisperScore(player)
	if (not player) then return; end
	local now = GetTime();
	if (TRIVIA_TELLS[player] and now < TRIVIA_TELLS[player]) then
		return;
	end
	TRIVIA_TELLS[player] = now + 10;

	local score = TRIVIA_SCORES[player] or 0;
	local ess = (score == 1) and "" or "s";
	Trivia_SendRawChat("[TurtleTrivia]: You currently have " .. score .. " point" .. ess .. ".", "WHISPER", nil, player);
end

function Trivia_ClearTells(player)
	TRIVIA_TELLS[player] = nil;
end

-------------------------------------------------------------------------------
-- Safe Event Scheduler (Mutation-Safe)
-------------------------------------------------------------------------------

local triviaScheduleEpoch = 0;

local function Trivia_CompareScheduleEvents(a, b)
	return a["time"] < b["time"];
end

function Trivia_DoSchedule()
	if (not TRIVIA_SCHEDULE) then return; end
	local now = GetTime();
	local n = 0;
	local i = table.getn(TRIVIA_SCHEDULE);

	while (i >= 1) do
		local ev = TRIVIA_SCHEDULE[i];
		if (ev and ev["time"] <= now) then
			n = n + 1;
			dueEvents[n] = ev;
			table.remove(TRIVIA_SCHEDULE, i);
		end
		i = i - 1;
	end

	local extra = n + 1;
	while (dueEvents[extra]) do
		dueEvents[extra] = nil;
		extra = extra + 1;
	end

	if (n == 0) then return; end
	if (n > 1) then
		table.sort(dueEvents, Trivia_CompareScheduleEvents);
	end

	local runEpoch = triviaScheduleEpoch;
	for idx = 1, n do
		if (triviaScheduleEpoch ~= runEpoch) then
			break;
		end
		Trivia_OnEvent(dueEvents[idx]["name"]);
	end
	for idx = 1, n do
		dueEvents[idx] = nil;
	end
	Trivia_UpdateFrameActive();
end

function Trivia_Schedule(name, timeOffset)
	local thisEvent = {["name"] = name, ["time"] = GetTime() + timeOffset};
	table.insert(TRIVIA_SCHEDULE, thisEvent);
	Trivia_UpdateFrameActive();
end

function Trivia_UnSchedule(id)
	if (id == "all") then
		TRIVIA_SCHEDULE = {};
		triviaScheduleEpoch = triviaScheduleEpoch + 1;
	else
		table.remove(TRIVIA_SCHEDULE, id);
	end
	Trivia_UpdateFrameActive();
end

-------------------------------------------------------------------------------
-- Channel & Output Helpers
-------------------------------------------------------------------------------

function Trivia_ChangeChannel(isNewAttempt)
	if (isNewAttempt) then
		channelRetryCount = 0;
	end
	if (not NEW_TRIVIA_CHANNEL or NEW_TRIVIA_CHANNEL == "") then
		channelRetryCount = 0;
		return;
	end

	local protected = false;
	local lowerNew = string.lower(NEW_TRIVIA_CHANNEL);
	for _, channel in ipairs(PROTECTED_CHANNELS) do
		if (string.find(lowerNew, "^" .. channel .. "[.]*") ~= nil) then
			protected = channel;
			break;
		end
	end
	if (protected ~= false) then
		channelRetryCount = 0;
		NEW_TRIVIA_CHANNEL = nil;
		Trivia_ErrorMessage("Channel '" .. lowerNew .. "' contains a protected keyword: " .. protected .. ", unable to change channel.");
		Trivia_ErrorMessage("Spamming a global server channel can get you muted or even banned.");
		return;
	end

	if (TRIVIA_CHANNEL and not Trivia_IsStandardChannel(TRIVIA_CHANNEL)) then
		if (string.lower(TRIVIA_CHANNEL) == lowerNew and GetChannelName(TRIVIA_CHANNEL) > 0) then
			channelRetryCount = 0;
			NEW_TRIVIA_CHANNEL = nil;
			Trivia_ConsoleMessage("Already using channel: " .. TRIVIA_CHANNEL);
			return;
		end
		if (GetChannelName(TRIVIA_CHANNEL) > 0) then
			LeaveChannelByName(TRIVIA_CHANNEL);
			channelRetryCount = channelRetryCount + 1;
			if (channelRetryCount <= 5) then
				Trivia_Schedule("RETRY_CHANNEL_CHANGE", 1);
			else
				channelRetryCount = 0;
				NEW_TRIVIA_CHANNEL = nil;
				Trivia_ErrorMessage("Timed out leaving channel '" .. tostring(TRIVIA_CHANNEL) .. "'.");
			end
			return;
		end
	end

	JoinChannelByName(NEW_TRIVIA_CHANNEL);
	ChatFrame_AddChannel(DEFAULT_CHAT_FRAME, NEW_TRIVIA_CHANNEL);

	if (GetChannelName(NEW_TRIVIA_CHANNEL) > 0) then
		TRIVIA_CHANNEL = NEW_TRIVIA_CHANNEL;
		NEW_TRIVIA_CHANNEL = nil;
		channelRetryCount = 0;
		if (TRIVIA_ENABLED) then
			Trivia_RegisterChatEvents();
		end
		Trivia_ConsoleMessage("Channel set to: " .. TRIVIA_CHANNEL);
		Trivia_UpdateToggleButton();
		if (Trivia_RefreshOptionsFrame) then
			Trivia_RefreshOptionsFrame();
		end
	else
		channelRetryCount = channelRetryCount + 1;
		if (channelRetryCount <= 5) then
			Trivia_Schedule("RETRY_CHANNEL_CHANGE", 1);
		else
			channelRetryCount = 0;
			local failedCh = tostring(NEW_TRIVIA_CHANNEL);
			NEW_TRIVIA_CHANNEL = nil;
			Trivia_ErrorMessage("Could not join channel '" .. failedCh .. "'. Check channel name or 10-channel limit.");
		end
	end
end

function Trivia_SanitizeChatText(text)
	if (not text) then return ""; end
	text = tostring(text);
	-- Pipe characters act as escape codes in WoW chat messages and throw errors if invalid
	text = string.gsub(text, "|", "/");
	text = string.gsub(text, "[\r\n]+", " ");
	return text;
end

local function Trivia_DispatchSingleLine(line)
	if (TRIVIA_CHANNEL == "GUILD") then
		Trivia_SendRawChat(line, "GUILD");
	elseif (TRIVIA_CHANNEL == "SAY") then
		Trivia_SendRawChat(line, "SAY");
	elseif (TRIVIA_CHANNEL == "PARTY") then
		Trivia_SendRawChat(line, "PARTY");
	elseif (TRIVIA_CHANNEL == "RAID") then
		Trivia_SendRawChat(line, "RAID");
	elseif (TRIVIA_CHANNEL ~= nil) then
		local id = GetChannelName(TRIVIA_CHANNEL);
		if (id > 0) then
			Trivia_SendRawChat(line, "CHANNEL", nil, id);
		else
			Trivia_ErrorMessage("Unable to send to channel '" .. tostring(TRIVIA_CHANNEL) .. "'.");
			Trivia_ErrorMessage("Reset channel with '/trivia channel [SAY|PARTY|RAID|GUILD|<channel>]'");
			Trivia_ErrorMessage("Current Trivia game stopped.");
			Trivia_UnSchedule("all");
			TRIVIA_ENABLED = false;
			TRIVIA_ACCEPTING_ANSWERS = false;
			Trivia_UnregisterChatEvents();
			Trivia_UpdateFrameActive();
			Trivia_UpdateToggleButton();
			return false;
		end
	end
	return true;
end

function Trivia_SendMessage(msg)
	local prefix = "[TurtleTrivia]: ";
	local body = Trivia_SanitizeChatText(msg);
	local maxBodyLen = 230; -- 16 prefix + 230 body <= 246 bytes (safely under WoW's 255-byte chat cap)

	if (string.len(body) <= maxBodyLen) then
		Trivia_DispatchSingleLine(prefix .. body);
		return;
	end

	local remaining = body;
	while (string.len(remaining) > 0) do
		if (string.len(remaining) <= maxBodyLen) then
			Trivia_DispatchSingleLine(prefix .. remaining);
			break;
		end

		local chunk = string.sub(remaining, 1, maxBodyLen);
		local splitPos = nil;
		local searchPos = 1;
		while (true) do
			local sp = string.find(chunk, " ", searchPos, true);
			if (not sp) then break; end
			splitPos = sp;
			searchPos = sp + 1;
		end

		if (splitPos and splitPos > 40) then
			chunk = string.sub(remaining, 1, splitPos - 1);
			remaining = Trivia_Trim(string.sub(remaining, splitPos + 1));
		else
			remaining = Trivia_Trim(string.sub(remaining, maxBodyLen + 1));
		end

		if (not Trivia_DispatchSingleLine(prefix .. chunk)) then
			break;
		end
	end
end

function Trivia_ConsoleMessage(msg)
	if (DEFAULT_CHAT_FRAME) then
		DEFAULT_CHAT_FRAME:AddMessage(MAGENTA .. "Trivia: " .. WHITE .. msg);
	end
end

function Trivia_ErrorMessage(msg)
	if (DEFAULT_CHAT_FRAME) then
		DEFAULT_CHAT_FRAME:AddMessage(MAGENTA .. "Trivia: " .. RED .. "ERROR! - " .. WHITE .. msg);
	end
end
