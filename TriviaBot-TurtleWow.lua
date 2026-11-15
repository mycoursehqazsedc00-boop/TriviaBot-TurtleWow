--[[
--
-- TriviaBot-TurtleWoW Version 1.1
-- Maintained by LizardBerry
-- Based on work created by Roadblock of Nostalrius, Guri of Trollbane, and Psy on Frostwolf
-- Improved with Turtle WoW & Warcraft I/II/III/Lore questions, A/B/C/D multiple choice,
-- fuzzy ("likely") answer matching, and a moveable on-screen toggle button.
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

TRIVIA_QUESTION_TIMEOUT = 45;  -- 45 seconds to answer correctly
TRIVIA_QUESTION_TIMEWARN = 25; -- 20 seconds left warning (at 25s elapsed)

TRIVIA_VERSION = "1.1";

NEW_TRIVIA_CHANNEL = nil;

TRIVIA_ACTIVE_QUESTION = 0;
TRIVIA_QUESTION_ORDER = {};
TRIVIA_SCORE_REPORT = 5;
TRIVIA_QUESTION_STARTTIME = 0;
TRIVIA_TIME_RECORD = {["time"] = 46, ["holder"] = "noone"};

TRIVIA_SCORES = {};
TRIVIA_SCHEDULE = {};
TRIVIA_TELLS = {};

-- Active question tables
TRIVIA_QUESTIONS = {};
TRIVIA_ANSWERS1 = {};
TRIVIA_ANSWERS2 = {};
TRIVIA_ANSWERS3 = {};
TRIVIA_ANSWERS4 = {};
TRIVIA_ANSWERS5 = {};
TRIVIA_ANSWERS6 = {};
TRIVIA_ANSWERS7 = {};
TRIVIA_ANSWERS8 = {};
TRIVIA_CHOICES = {};

-- Current multiple-choice state for the active question
TRIVIA_CURRENT_CORRECT_LETTER = nil;
TRIVIA_CURRENT_OPTIONS = {};
TRIVIA_WRONG_LETTER_COOLDOWN = {};

INVALID_COMMAND = RED .. "Invalid Command Entered. " .. WHITE .. "Try '/trivia help'";

TRIVIA_UPDATEINTERVAL = 0.5;

-- Client mod feature detection (checked at PLAYER_LOGIN)
local HAS_XP3 = false;

-- Reusable row buffers for Levenshtein distance (avoids table allocation in hot path)
local levRow0 = {};
local levRow1 = {};

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

local QLIST_CYCLE = {"warcraft", "turtle", "wow", "geography", "normal", "all"};

-------------------------------------------------------------------------------
-- Initialization & Event Handling
-------------------------------------------------------------------------------

function Trivia_OnLoad()
	this:RegisterEvent("CHAT_MSG_CHANNEL");
	this:RegisterEvent("CHAT_MSG_RAID");
	this:RegisterEvent("CHAT_MSG_RAID_LEADER");
	this:RegisterEvent("CHAT_MSG_SAY");
	this:RegisterEvent("CHAT_MSG_PARTY");
	this:RegisterEvent("CHAT_MSG_GUILD");
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
	if (TRIVIA_CONFIG.notifyTaskbar == nil) then
		TRIVIA_CONFIG.notifyTaskbar = false;
	end
	if (not TRIVIA_CONFIG.point) then
		TRIVIA_CONFIG.point = "TOP";
		TRIVIA_CONFIG.relativePoint = "TOP";
		TRIVIA_CONFIG.xOfs = 0;
		TRIVIA_CONFIG.yOfs = -60;
	end
end

function Trivia_OnUpdate(elapsed)
	this.TimeSinceLastUpdate = this.TimeSinceLastUpdate + elapsed;
	if (this.TimeSinceLastUpdate > TRIVIA_UPDATEINTERVAL) then
		this.TimeSinceLastUpdate = 0;
		if (TRIVIA_SCHEDULE and table.getn(TRIVIA_SCHEDULE) > 0) then
			Trivia_DoSchedule();
		end
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
	elseif (event == "CHAT_MSG_CHANNEL") then
		local msg = arg1;
		local player = arg2;
		local channel = arg9;
		if (msg and player and channel) then
			if (string.lower(channel) == string.lower(TRIVIA_CHANNEL)) then
				local lowerMsg = Trivia_Trim(string.lower(msg));
				if (lowerMsg == "score" or lowerMsg == "!score") then
					Trivia_WhisperScore(player);
				elseif (TRIVIA_ACCEPTING_ANSWERS) then
					Trivia_CheckAnswer(player, msg);
				end
			end
		end
	elseif (event == "CHAT_MSG_SAY" or event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_PARTY") then
		local msg = arg1;
		local player = arg2;
		if (msg and player and Trivia_IsActiveChannelEvent(event)) then
			local lowerMsg = Trivia_Trim(string.lower(msg));
			if (lowerMsg == "score" or lowerMsg == "!score") then
				Trivia_WhisperScore(player);
			elseif (TRIVIA_ACCEPTING_ANSWERS) then
				Trivia_CheckAnswer(player, msg);
			end
		end
	elseif (event == "RETRY_CHANNEL_CHANGE") then
		Trivia_ChangeChannel();
	elseif (event == "NEXT_QUESTION") then
		if (TRIVIA_ENABLED) then
			Trivia_AskQuestion();
		end
	elseif (event == "QUESTION_TIMEOUT") then
		Trivia_QuestionTimeout();
	elseif (event == "QUESTION_WARN") then
		Trivia_SendMessage("20 seconds left! (Reply with A, B, C, D or the answer)");
	elseif (event == "REPORT_SCORERS") then
		Trivia_ReportScores();
	elseif (event == "SHOW_ANSWER") then
		local qIdx = TRIVIA_QUESTION_ORDER[TRIVIA_ACTIVE_QUESTION];
		local ans = (qIdx and TRIVIA_ANSWERS1[qIdx]) or "Unknown";
		if (TRIVIA_CONFIG.showChoices and TRIVIA_CURRENT_CORRECT_LETTER) then
			Trivia_SendMessage("The correct answer was: [" .. string.upper(TRIVIA_CURRENT_CORRECT_LETTER) .. "] " .. ans);
		else
			Trivia_SendMessage("The correct answer was: " .. ans);
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

	if (not TRIVIA_QLIST or TRIVIA_QLIST == "") then
		TRIVIA_QLIST = "warcraft";
	end

	TRIVIA_TIME_RECORD = {["time"] = TRIVIA_QUESTION_TIMEOUT + 1, ["holder"] = "noone"};

	Trivia_LoadQuestionSet(TRIVIA_QLIST, true);
	Trivia_CreateToggleButton();
	Trivia_UpdateToggleButton();

	TRIVIA_LOADED = true;
	Trivia_ConsoleMessage("Version " .. TRIVIA_VERSION .. " loaded. Set: " .. YELLOW .. TRIVIA_QLIST .. WHITE .. " (" .. table.getn(TRIVIA_QUESTIONS) .. " questions). Type " .. CYAN .. "/trivia help" .. WHITE .. " for commands.");
end

-------------------------------------------------------------------------------
-- Question Set Management
-------------------------------------------------------------------------------

local function Trivia_AppendSet(srcQ, srcA1, srcA2, srcA3, srcA4, srcA5, srcA6, srcA7, srcA8, srcChoices)
	if (not srcQ) then return; end
	local count = table.getn(srcQ);
	local destIdx = table.getn(TRIVIA_QUESTIONS);
	local i = 1;
	while (i <= count) do
		if (srcQ[i] and srcA1[i]) then
			destIdx = destIdx + 1;
			TRIVIA_QUESTIONS[destIdx] = srcQ[i];
			TRIVIA_ANSWERS1[destIdx] = srcA1[i];
			TRIVIA_ANSWERS2[destIdx] = srcA2 and srcA2[i] or nil;
			TRIVIA_ANSWERS3[destIdx] = srcA3 and srcA3[i] or nil;
			TRIVIA_ANSWERS4[destIdx] = srcA4 and srcA4[i] or nil;
			TRIVIA_ANSWERS5[destIdx] = srcA5 and srcA5[i] or nil;
			TRIVIA_ANSWERS6[destIdx] = srcA6 and srcA6[i] or nil;
			TRIVIA_ANSWERS7[destIdx] = srcA7 and srcA7[i] or nil;
			TRIVIA_ANSWERS8[destIdx] = srcA8 and srcA8[i] or nil;
			TRIVIA_CHOICES[destIdx]  = srcChoices and srcChoices[i] or nil;
		end
		i = i + 1;
	end
end

function Trivia_LoadQuestionSet(qlist, silent)
	qlist = string.lower(qlist or "warcraft");
	if (qlist == "geog") then qlist = "geography"; end
	if (qlist == "twow") then qlist = "turtle"; end

	TRIVIA_QUESTIONS = {};
	TRIVIA_ANSWERS1 = {};
	TRIVIA_ANSWERS2 = {};
	TRIVIA_ANSWERS3 = {};
	TRIVIA_ANSWERS4 = {};
	TRIVIA_ANSWERS5 = {};
	TRIVIA_ANSWERS6 = {};
	TRIVIA_ANSWERS7 = {};
	TRIVIA_ANSWERS8 = {};
	TRIVIA_CHOICES = {};

	if (qlist == "turtle") then
		Trivia_AppendSet(TURTLE_TRIVIA_QUESTIONS, TURTLE_TRIVIA_ANSWERS1, TURTLE_TRIVIA_ANSWERS2, TURTLE_TRIVIA_ANSWERS3, TURTLE_TRIVIA_ANSWERS4, TURTLE_TRIVIA_ANSWERS5, TURTLE_TRIVIA_ANSWERS6, TURTLE_TRIVIA_ANSWERS7, TURTLE_TRIVIA_ANSWERS8, TURTLE_TRIVIA_CHOICES);
	elseif (qlist == "wow") then
		Trivia_AppendSet(WOW_TRIVIA_QUESTIONS, WOW_TRIVIA_ANSWERS1, WOW_TRIVIA_ANSWERS2, WOW_TRIVIA_ANSWERS3, WOW_TRIVIA_ANSWERS4, WOW_TRIVIA_ANSWERS5, WOW_TRIVIA_ANSWERS6, WOW_TRIVIA_ANSWERS7, WOW_TRIVIA_ANSWERS8, WOW_TRIVIA_CHOICES);
	elseif (qlist == "warcraft") then
		Trivia_AppendSet(TURTLE_TRIVIA_QUESTIONS, TURTLE_TRIVIA_ANSWERS1, TURTLE_TRIVIA_ANSWERS2, TURTLE_TRIVIA_ANSWERS3, TURTLE_TRIVIA_ANSWERS4, TURTLE_TRIVIA_ANSWERS5, TURTLE_TRIVIA_ANSWERS6, TURTLE_TRIVIA_ANSWERS7, TURTLE_TRIVIA_ANSWERS8, TURTLE_TRIVIA_CHOICES);
		Trivia_AppendSet(WOW_TRIVIA_QUESTIONS, WOW_TRIVIA_ANSWERS1, WOW_TRIVIA_ANSWERS2, WOW_TRIVIA_ANSWERS3, WOW_TRIVIA_ANSWERS4, WOW_TRIVIA_ANSWERS5, WOW_TRIVIA_ANSWERS6, WOW_TRIVIA_ANSWERS7, WOW_TRIVIA_ANSWERS8, WOW_TRIVIA_CHOICES);
	elseif (qlist == "geography") then
		Trivia_AppendSet(GEOGRAPHY_TRIVIA_QUESTIONS, GEOGRAPHY_TRIVIA_ANSWERS1, GEOGRAPHY_TRIVIA_ANSWERS2, GEOGRAPHY_TRIVIA_ANSWERS3, GEOGRAPHY_TRIVIA_ANSWERS4, GEOGRAPHY_TRIVIA_ANSWERS5, GEOGRAPHY_TRIVIA_ANSWERS6, GEOGRAPHY_TRIVIA_ANSWERS7, GEOGRAPHY_TRIVIA_ANSWERS8, GEOGRAPHY_TRIVIA_CHOICES);
	elseif (qlist == "normal") then
		Trivia_AppendSet(NORMAL_TRIVIA_QUESTIONS, NORMAL_TRIVIA_ANSWERS1, NORMAL_TRIVIA_ANSWERS2, NORMAL_TRIVIA_ANSWERS3, NORMAL_TRIVIA_ANSWERS4, NORMAL_TRIVIA_ANSWERS5, NORMAL_TRIVIA_ANSWERS6, NORMAL_TRIVIA_ANSWERS7, NORMAL_TRIVIA_ANSWERS8, NORMAL_TRIVIA_CHOICES);
	elseif (qlist == "all") then
		Trivia_AppendSet(TURTLE_TRIVIA_QUESTIONS, TURTLE_TRIVIA_ANSWERS1, TURTLE_TRIVIA_ANSWERS2, TURTLE_TRIVIA_ANSWERS3, TURTLE_TRIVIA_ANSWERS4, TURTLE_TRIVIA_ANSWERS5, TURTLE_TRIVIA_ANSWERS6, TURTLE_TRIVIA_ANSWERS7, TURTLE_TRIVIA_ANSWERS8, TURTLE_TRIVIA_CHOICES);
		Trivia_AppendSet(WOW_TRIVIA_QUESTIONS, WOW_TRIVIA_ANSWERS1, WOW_TRIVIA_ANSWERS2, WOW_TRIVIA_ANSWERS3, WOW_TRIVIA_ANSWERS4, WOW_TRIVIA_ANSWERS5, WOW_TRIVIA_ANSWERS6, WOW_TRIVIA_ANSWERS7, WOW_TRIVIA_ANSWERS8, WOW_TRIVIA_CHOICES);
		Trivia_AppendSet(GEOGRAPHY_TRIVIA_QUESTIONS, GEOGRAPHY_TRIVIA_ANSWERS1, GEOGRAPHY_TRIVIA_ANSWERS2, GEOGRAPHY_TRIVIA_ANSWERS3, GEOGRAPHY_TRIVIA_ANSWERS4, GEOGRAPHY_TRIVIA_ANSWERS5, GEOGRAPHY_TRIVIA_ANSWERS6, GEOGRAPHY_TRIVIA_ANSWERS7, GEOGRAPHY_TRIVIA_ANSWERS8, GEOGRAPHY_TRIVIA_CHOICES);
		Trivia_AppendSet(NORMAL_TRIVIA_QUESTIONS, NORMAL_TRIVIA_ANSWERS1, NORMAL_TRIVIA_ANSWERS2, NORMAL_TRIVIA_ANSWERS3, NORMAL_TRIVIA_ANSWERS4, NORMAL_TRIVIA_ANSWERS5, NORMAL_TRIVIA_ANSWERS6, NORMAL_TRIVIA_ANSWERS7, NORMAL_TRIVIA_ANSWERS8, NORMAL_TRIVIA_CHOICES);
	else
		return false;
	end

	TRIVIA_QLIST = qlist;
	Trivia_RandomiseOrder();
	Trivia_UpdateToggleButton();

	if (not silent) then
		Trivia_ConsoleMessage("Question set selected: " .. YELLOW .. TRIVIA_QLIST .. WHITE .. " (" .. table.getn(TRIVIA_QUESTIONS) .. " questions).");
	end
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
		Trivia_Help();
		return;
	end

	local sub = msgArgs[1];
	local arg = msgArgs[2];

	if (sub == "start") then
		Trivia_Start();
	elseif (sub == "stop") then
		Trivia_Stop();
	elseif (sub == "toggle") then
		Trivia_Toggle();
	elseif (sub == "skip") then
		Trivia_SkipQuestion();
		Trivia_ConsoleMessage("Question skipped.");
	elseif (sub == "shuffle") then
		Trivia_UnSchedule("all");
		Trivia_RandomiseOrder();
		Trivia_ConsoleMessage("Questions shuffled.");
		if (TRIVIA_ENABLED) then
			Trivia_SendMessage("Questions shuffled. Restarting with a new question in 5 seconds.");
			Trivia_Schedule("NEXT_QUESTION", 5);
		end
	elseif (sub == "clear") then
		TRIVIA_SCORES = {};
		TRIVIA_TIME_RECORD = {["time"] = TRIVIA_QUESTION_TIMEOUT + 1, ["holder"] = "noone"};
		Trivia_ConsoleMessage("Scores cleared.");
		if (TRIVIA_ENABLED) then
			Trivia_SendMessage("Scores cleared.");
		end
	elseif (sub == "score" or sub == "scores") then
		Trivia_ReportScores();
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
	elseif (sub == "qlist") then
		if (not arg) then
			Trivia_ConsoleMessage("Current question set: " .. YELLOW .. tostring(TRIVIA_QLIST) .. WHITE .. " (" .. table.getn(TRIVIA_QUESTIONS) .. " questions)");
			Trivia_ConsoleMessage("Available question sets (/trivia qlist <name>):");
			Trivia_ConsoleMessage("  " .. CYAN .. "warcraft" .. WHITE .. " - Turtle WoW + WoW + Warcraft I/II/III & Lore combined");
			Trivia_ConsoleMessage("  " .. CYAN .. "turtle" .. WHITE .. "   - Turtle WoW custom content questions only");
			Trivia_ConsoleMessage("  " .. CYAN .. "wow" .. WHITE .. "      - World of Warcraft & Warcraft I/II/III/Lore questions");
			Trivia_ConsoleMessage("  " .. CYAN .. "geography" .. WHITE .. "- World & US Geography questions");
			Trivia_ConsoleMessage("  " .. CYAN .. "normal" .. WHITE .. "   - General mixed trivia questions");
			Trivia_ConsoleMessage("  " .. CYAN .. "all" .. WHITE .. "      - All question sets combined");
		elseif (TRIVIA_ENABLED) then
			Trivia_ErrorMessage("Stop the trivia bot first before changing question sets ('/trivia stop').");
		else
			if (not Trivia_LoadQuestionSet(arg, false)) then
				Trivia_ErrorMessage("Unrecognised question set '" .. arg .. "'. Try '/trivia qlist'.");
			end
		end
	elseif (sub == "channel") then
		if (not arg) then
			Trivia_ConsoleMessage("Current channel: " .. YELLOW .. tostring(TRIVIA_CHANNEL));
			Trivia_ConsoleMessage("Usage: /trivia channel [SAY|PARTY|RAID|GUILD|<custom channel>]");
		else
			if (GetChannelName(TRIVIA_CHANNEL) > 0) then
				LeaveChannelByName(TRIVIA_CHANNEL);
			end
			if (arg == "guild") then
				TRIVIA_CHANNEL = "GUILD";
				Trivia_ConsoleMessage("Channel set to: " .. TRIVIA_CHANNEL);
			elseif (arg == "say") then
				TRIVIA_CHANNEL = "SAY";
				Trivia_ConsoleMessage("Channel set to: " .. TRIVIA_CHANNEL);
			elseif (arg == "party") then
				TRIVIA_CHANNEL = "PARTY";
				Trivia_ConsoleMessage("Channel set to: " .. TRIVIA_CHANNEL);
			elseif (arg == "raid") then
				TRIVIA_CHANNEL = "RAID";
				Trivia_ConsoleMessage("Channel set to: " .. TRIVIA_CHANNEL);
			else
				NEW_TRIVIA_CHANNEL = arg;
				Trivia_ChangeChannel();
			end
			Trivia_UpdateToggleButton();
		end
	elseif (sub == "help") then
		Trivia_Help();
	else
		Trivia_ErrorMessage("Invalid Command - Try '/trivia help'");
	end
end

function Trivia_Help()
	Trivia_ConsoleMessage(YELLOW .. "--- TriviaBot-TurtleWoW v" .. TRIVIA_VERSION .. " Commands ---");
	Trivia_ConsoleMessage(CYAN .. "/trivia start | stop | toggle" .. WHITE .. " - Start, stop, or toggle TriviaBot.");
	Trivia_ConsoleMessage(CYAN .. "/trivia lock" .. WHITE .. " - Lock/unlock the moveable on-screen Trivia button.");
	Trivia_ConsoleMessage(CYAN .. "/trivia disable | enable" .. WHITE .. " - Disable (hide) or enable (show) the Trivia button.");
	Trivia_ConsoleMessage(CYAN .. "/trivia button reset" .. WHITE .. " - Reset the moveable button to screen center.");
	Trivia_ConsoleMessage(CYAN .. "/trivia qlist [warcraft|turtle|wow|geography|normal|all]" .. WHITE .. " - Select question list.");
	Trivia_ConsoleMessage(CYAN .. "/trivia channel [SAY|PARTY|RAID|GUILD|<channel>]" .. WHITE .. " - Set trivia chat channel.");
	Trivia_ConsoleMessage(CYAN .. "/trivia choices" .. WHITE .. " - Toggle A/B/C/D multiple-choice options on/off.");
	Trivia_ConsoleMessage(CYAN .. "/trivia skip | shuffle | clear | score" .. WHITE .. " - Skip question, shuffle, clear, or report scores.");
end

-------------------------------------------------------------------------------
-- Start / Stop / Toggle & Moveable On-Screen Button
-------------------------------------------------------------------------------

function Trivia_Start()
	if (TRIVIA_ENABLED) then
		Trivia_ConsoleMessage("Trivia is already running! Use '/trivia stop' to stop.");
		return;
	end
	if (table.getn(TRIVIA_QUESTIONS) == 0) then
		Trivia_LoadQuestionSet(TRIVIA_QLIST or "warcraft", true);
	end
	TRIVIA_ENABLED = true;
	TRIVIA_ACCEPTING_ANSWERS = false;
	Trivia_UnSchedule("all");
	Trivia_UpdateToggleButton();
	Trivia_ConsoleMessage("Trivia started in channel " .. YELLOW .. TRIVIA_CHANNEL .. WHITE .. " (" .. TRIVIA_QLIST .. " set). First question in 2 seconds!");
	Trivia_SendMessage("Trivia started (" .. TRIVIA_QLIST .. " set)! Answer with A, B, C, D or type the answer. First question coming up!");
	Trivia_Schedule("NEXT_QUESTION", 2);
end

function Trivia_Stop()
	Trivia_UnSchedule("all");
	local wasEnabled = TRIVIA_ENABLED;
	TRIVIA_ENABLED = false;
	TRIVIA_ACCEPTING_ANSWERS = false;
	Trivia_UpdateToggleButton();
	if (wasEnabled) then
		Trivia_SendMessage("Trivia bot stopped.");
	end
	Trivia_ConsoleMessage("Trivia bot stopped.");
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
	Trivia_LoadQuestionSet(nextSet, false);
end

function Trivia_CreateToggleButton()
	if (TriviaBotToggleButton) then
		return;
	end
	Trivia_EnsureConfig();

	local btn = CreateFrame("Button", "TriviaBotToggleButton", UIParent);
	btn:SetWidth(124);
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
			if (TRIVIA_ENABLED) then
				Trivia_SkipQuestion();
				Trivia_ConsoleMessage("Question skipped.");
			else
				Trivia_CycleQuestionSet();
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
	GameTooltip:AddDoubleLine("Question Set:", tostring(TRIVIA_QLIST) .. " (" .. table.getn(TRIVIA_QUESTIONS) .. ")", 0.8, 0.8, 0.8, 0.4, 0.9, 1);
	GameTooltip:AddDoubleLine("A/B/C/D Choices:", TRIVIA_CONFIG.showChoices and "Enabled" or "Disabled", 0.8, 0.8, 0.8, 1, 1, 1);
	GameTooltip:AddDoubleLine("Button Position:", TRIVIA_CONFIG.locked and "Locked" or "Unlocked", 0.8, 0.8, 0.8, TRIVIA_CONFIG.locked and 1 or 0.3, TRIVIA_CONFIG.locked and 0.6 or 1, 0.3);
	GameTooltip:AddLine(" ");
	GameTooltip:AddLine("Left-Click: " .. WHITE .. (TRIVIA_ENABLED and "Stop Trivia" or "Start Trivia"), 0, 1, 0);
	if (TRIVIA_ENABLED) then
		GameTooltip:AddLine("Right-Click: " .. WHITE .. "Skip Current Question", 0, 0.8, 1);
	else
		GameTooltip:AddLine("Right-Click: " .. WHITE .. "Cycle Question Set", 0, 0.8, 1);
	end
	if (not TRIVIA_CONFIG.locked) then
		GameTooltip:AddLine("Left-Drag: " .. WHITE .. "Move Button", 0.7, 0.7, 0.7);
	end
	GameTooltip:AddLine("Commands: " .. GREY .. "/trivia lock | /trivia disable", 0.6, 0.6, 0.6);
	GameTooltip:Show();
end

function Trivia_UpdateToggleButton()
	Trivia_EnsureConfig();
	if (not TriviaBotToggleButton) then
		Trivia_CreateToggleButton();
	end
	if (not TriviaBotToggleButton) then
		return;
	end

	if (TRIVIA_CONFIG.buttonDisabled) then
		TriviaBotToggleButton:Hide();
		return;
	end

	TriviaBotToggleButton:Show();
	local lockTag = TRIVIA_CONFIG.locked and (GREY .. " [L]" .. WHITE) or "";
	if (TRIVIA_ENABLED) then
		TriviaBotToggleButton.text:SetText(WHITE .. "Trivia: " .. GREEN .. "ON" .. lockTag);
		TriviaBotToggleButton:SetBackdropBorderColor(0.2, 0.9, 0.2, 1.0);
	else
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

	local noOfQuestions = table.getn(TRIVIA_QUESTIONS);
	local n = 1;
	while (n <= noOfQuestions) do
		TRIVIA_QUESTION_ORDER[n] = n;
		n = n + 1;
	end

	local tmp, randIdx;
	local i;
	local j = 5;
	while (j > 0) do
		i = 1;
		while (i <= noOfQuestions) do
			randIdx = math.random(noOfQuestions);
			tmp = TRIVIA_QUESTION_ORDER[i];
			TRIVIA_QUESTION_ORDER[i] = TRIVIA_QUESTION_ORDER[randIdx];
			TRIVIA_QUESTION_ORDER[randIdx] = tmp;
			i = i + 1;
		end
		j = j - 1;
	end
end

function Trivia_BuildChoicesForQuestion(qIdx)
	local correctAns = TRIVIA_ANSWERS1[qIdx] or "";
	local rawChoices = TRIVIA_CHOICES[qIdx];
	local opts = {};

	if (rawChoices and table.getn(rawChoices) >= 4) then
		opts[1] = rawChoices[1];
		opts[2] = rawChoices[2];
		opts[3] = rawChoices[3];
		opts[4] = rawChoices[4];
	else
		opts[1] = correctAns;
		local totalQ = table.getn(TRIVIA_QUESTIONS);
		local normCorrect = Trivia_NormalizeText(correctAns);
		local attempts = 0;
		while (table.getn(opts) < 4 and attempts < 60 and totalQ > 4) do
			attempts = attempts + 1;
			local pickIdx = math.random(totalQ);
			local candidate = TRIVIA_ANSWERS1[pickIdx];
			if (candidate and Trivia_NormalizeText(candidate) ~= normCorrect) then
				local dup = false;
				local k = 1;
				while (k <= table.getn(opts)) do
					if (Trivia_NormalizeText(opts[k]) == Trivia_NormalizeText(candidate)) then
						dup = true;
						break;
					end
					k = k + 1;
				end
				if (not dup) then
					table.insert(opts, candidate);
				end
			end
		end
		while (table.getn(opts) < 4) do
			table.insert(opts, "None of these (" .. table.getn(opts) .. ")");
		end
	end

	-- Determine which option is the canonical correct choice before shuffling (index 1)
	local canonicalCorrect = opts[1];

	-- Fisher-Yates shuffle on the 4 options
	local i = 4;
	while (i >= 2) do
		local r = math.random(i);
		local tmp = opts[i];
		opts[i] = opts[r];
		opts[r] = tmp;
		i = i - 1;
	end

	local letters = {"a", "b", "c", "d"};
	TRIVIA_CURRENT_OPTIONS = {};
	TRIVIA_CURRENT_CORRECT_LETTER = "a";

	local idx = 1;
	while (idx <= 4) do
		local ltr = letters[idx];
		TRIVIA_CURRENT_OPTIONS[ltr] = opts[idx];
		if (opts[idx] == canonicalCorrect) then
			TRIVIA_CURRENT_CORRECT_LETTER = ltr;
		end
		idx = idx + 1;
	end
end

function Trivia_AskQuestion()
	local totalQ = table.getn(TRIVIA_QUESTIONS);
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
	TRIVIA_WRONG_LETTER_COOLDOWN = {};
	Trivia_BuildChoicesForQuestion(qIdx);

	Trivia_SendMessage("Q: " .. TRIVIA_QUESTIONS[qIdx]);

	if (TRIVIA_CONFIG.showChoices and TRIVIA_CURRENT_OPTIONS["a"]) then
		local lineAB = "A) " .. TRIVIA_CURRENT_OPTIONS["a"] .. " | B) " .. TRIVIA_CURRENT_OPTIONS["b"];
		local lineCD = "C) " .. TRIVIA_CURRENT_OPTIONS["c"] .. " | D) " .. TRIVIA_CURRENT_OPTIONS["d"];
		local singleLine = lineAB .. " | " .. lineCD;
		if (string.len(singleLine) <= 220) then
			Trivia_SendMessage(singleLine);
		else
			Trivia_SendMessage(lineAB);
			Trivia_SendMessage(lineCD);
		end
	end

	TRIVIA_QUESTION_STARTTIME = GetTime();
	TRIVIA_ACCEPTING_ANSWERS = true;
	Trivia_UnSchedule("all");
	Trivia_Schedule("QUESTION_TIMEOUT", TRIVIA_QUESTION_TIMEOUT);
	Trivia_Schedule("QUESTION_WARN", TRIVIA_QUESTION_TIMEWARN);
end

function Trivia_QuestionTimeout()
	TRIVIA_ACCEPTING_ANSWERS = false;
	Trivia_SendMessage("Time is up! No correct answer was given.");

	if (TRIVIA_SCORE_REPORT == 1) then
		Trivia_Schedule("SHOW_ANSWER", 3);
		Trivia_Schedule("REPORT_SCORERS", 7);
		Trivia_Schedule("NEXT_QUESTION", 14);
		TRIVIA_SCORE_REPORT = 5;
	else
		TRIVIA_SCORE_REPORT = TRIVIA_SCORE_REPORT - 1;
		Trivia_Schedule("SHOW_ANSWER", 3);
		Trivia_Schedule("NEXT_QUESTION", 8);
	end
end

function Trivia_SkipQuestion()
	if (TRIVIA_ENABLED) then
		TRIVIA_ACCEPTING_ANSWERS = false;
		Trivia_SendMessage("Question was skipped.");
		Trivia_UnSchedule("all");
		Trivia_Schedule("SHOW_ANSWER", 2);
		Trivia_Schedule("NEXT_QUESTION", 5);
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
	local patterns = {
		"^(.+) at age %d+",
		"^(.+) in %d%d%d%d",
		"^(.+) as the %d+",
		"^(.+) in nepal",
		"^(.+) with %d+"
	};
	local i = 1;
	local n = table.getn(patterns);
	while (i <= n) do
		local _, _, core = string.find(normAns, patterns[i]);
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
	local qIdx = TRIVIA_QUESTION_ORDER[TRIVIA_ACTIVE_QUESTION];
	if (not qIdx) then return; end

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

	-- 2. Check full / likely text answer across ANSWERS1..8 and displayed correct option
	if (not isCorrect) then
		local answerTables = {
			TRIVIA_ANSWERS1, TRIVIA_ANSWERS2, TRIVIA_ANSWERS3, TRIVIA_ANSWERS4,
			TRIVIA_ANSWERS5, TRIVIA_ANSWERS6, TRIVIA_ANSWERS7, TRIVIA_ANSWERS8
		};
		local i = 1;
		while (i <= 8) do
			local ansTable = answerTables[i];
			local targetAns = ansTable and ansTable[qIdx];
			if (targetAns and Trivia_IsLikelyMatch(msg, targetAns)) then
				isCorrect = true;
				break;
			end
			i = i + 1;
		end
		if (not isCorrect and TRIVIA_CURRENT_CORRECT_LETTER and TRIVIA_CURRENT_OPTIONS[TRIVIA_CURRENT_CORRECT_LETTER]) then
			if (Trivia_IsLikelyMatch(msg, TRIVIA_CURRENT_OPTIONS[TRIVIA_CURRENT_CORRECT_LETTER])) then
				isCorrect = true;
			end
		end
	end

	if (isCorrect) then
		TRIVIA_ACCEPTING_ANSWERS = false;
		Trivia_UnSchedule("all");

		local canonicalAns = TRIVIA_ANSWERS1[qIdx] or "";
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

		local score = TRIVIA_SCORES[player];
		if (score) then
			score = score + 1;
		else
			score = 1;
		end
		TRIVIA_SCORES[player] = score;

		if (TRIVIA_SCORE_REPORT == 1) then
			Trivia_Schedule("REPORT_SCORERS", 4);
			Trivia_Schedule("NEXT_QUESTION", 12);
			TRIVIA_SCORE_REPORT = 5;
		else
			TRIVIA_SCORE_REPORT = TRIVIA_SCORE_REPORT - 1;
			Trivia_Schedule("NEXT_QUESTION", 7);
		end
	end
end

-------------------------------------------------------------------------------
-- Scoring & Whisper Score
-------------------------------------------------------------------------------

function Trivia_ReportScores()
	local TRIVIA_SORTED = {};
	for player, score in pairs(TRIVIA_SCORES) do
		table.insert(TRIVIA_SORTED, {["player"] = player, ["score"] = score});
	end

	if (table.getn(TRIVIA_SORTED) == 0) then
		Trivia_SendMessage("No scores recorded yet.");
		return;
	end

	table.sort(TRIVIA_SORTED, function(v1, v2)
		return v1["score"] > v2["score"];
	end);

	Trivia_SendMessage("Standing so far:");
	local id = 1;
	local count = table.getn(TRIVIA_SORTED);
	while (id <= count and id <= 3) do
		local record = TRIVIA_SORTED[id];
		local ess = (record["score"] == 1) and "" or "s";
		Trivia_SendMessage(id .. "]: " .. record["player"] .. " (" .. record["score"] .. " point" .. ess .. ")");
		id = id + 1;
	end

	if (TRIVIA_TIME_RECORD["holder"] ~= "noone") then
		Trivia_SendMessage("Speed Record: " .. TRIVIA_TIME_RECORD["holder"] .. " in " .. TRIVIA_TIME_RECORD["time"] .. " sec");
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
	SendChatMessage("[TurtleTrivia]: You currently have " .. score .. " point" .. ess .. ".", "WHISPER", nil, player);
end

function Trivia_ClearTells(player)
	TRIVIA_TELLS[player] = nil;
end

-------------------------------------------------------------------------------
-- Safe Event Scheduler (Mutation-Safe)
-------------------------------------------------------------------------------

function Trivia_DoSchedule()
	if (not TRIVIA_SCHEDULE) then return; end
	local now = GetTime();
	local dueEvents = {};
	local i = table.getn(TRIVIA_SCHEDULE);

	while (i >= 1) do
		local ev = TRIVIA_SCHEDULE[i];
		if (ev and ev["time"] <= now) then
			table.insert(dueEvents, ev["name"]);
			table.remove(TRIVIA_SCHEDULE, i);
		end
		i = i - 1;
	end

	local j = table.getn(dueEvents);
	while (j >= 1) do
		Trivia_OnEvent(dueEvents[j]);
		j = j - 1;
	end
end

function Trivia_Schedule(name, timeOffset)
	local thisEvent = {["name"] = name, ["time"] = GetTime() + timeOffset};
	table.insert(TRIVIA_SCHEDULE, thisEvent);
end

function Trivia_UnSchedule(id)
	if (id == "all") then
		TRIVIA_SCHEDULE = {};
	else
		table.remove(TRIVIA_SCHEDULE, id);
	end
end

-------------------------------------------------------------------------------
-- Channel & Output Helpers
-------------------------------------------------------------------------------

function Trivia_ChangeChannel()
	if (GetChannelName(TRIVIA_CHANNEL) > 0) then
		LeaveChannelByName(TRIVIA_CHANNEL);
		Trivia_Schedule("RETRY_CHANNEL_CHANGE", 1);
	else
		local protected_channel = {"general", "trade", "lookingforgroup", "guildrecruitment", "localdefence", "worlddefence", "world"};
		local protected = false;
		for _, channel in ipairs(protected_channel) do
			if (string.find(string.lower(NEW_TRIVIA_CHANNEL), "^" .. channel .. "[.]*") ~= nil) then
				protected = channel;
				break;
			end
		end
		if (protected ~= false) then
			Trivia_ErrorMessage("Channel '" .. NEW_TRIVIA_CHANNEL .. "' contains a protected keyword: " .. protected .. ", unable to change channel.");
			Trivia_ErrorMessage("Spamming a global server channel can get you muted or even banned.");
			JoinChannelByName(TRIVIA_CHANNEL);
			NEW_TRIVIA_CHANNEL = TRIVIA_CHANNEL;
			ChatFrame_AddChannel(DEFAULT_CHAT_FRAME, TRIVIA_CHANNEL);
		else
			JoinChannelByName(NEW_TRIVIA_CHANNEL);
			ChatFrame_AddChannel(DEFAULT_CHAT_FRAME, NEW_TRIVIA_CHANNEL);
		end

		if (GetChannelName(NEW_TRIVIA_CHANNEL) > 0) then
			TRIVIA_CHANNEL = NEW_TRIVIA_CHANNEL;
			Trivia_ConsoleMessage("Channel set to: " .. TRIVIA_CHANNEL);
			Trivia_UpdateToggleButton();
		else
			Trivia_Schedule("RETRY_CHANNEL_CHANGE", 1);
		end
	end
end

function Trivia_SendMessage(msg)
	msg = "[TurtleTrivia]: " .. msg;

	if (TRIVIA_CHANNEL == "GUILD") then
		SendChatMessage(msg, "GUILD");
	elseif (TRIVIA_CHANNEL == "SAY") then
		SendChatMessage(msg, "SAY");
	elseif (TRIVIA_CHANNEL == "PARTY") then
		SendChatMessage(msg, "PARTY");
	elseif (TRIVIA_CHANNEL == "RAID") then
		SendChatMessage(msg, "RAID");
	elseif (TRIVIA_CHANNEL ~= nil) then
		local id = GetChannelName(TRIVIA_CHANNEL);
		if (id > 0) then
			SendChatMessage(msg, "CHANNEL", nil, id);
		else
			Trivia_ErrorMessage("Unable to send to channel '" .. tostring(TRIVIA_CHANNEL) .. "'.");
			Trivia_ErrorMessage("Reset channel with '/trivia channel [SAY|PARTY|RAID|GUILD|<channel>]'");
			Trivia_ErrorMessage("Current Trivia game stopped.");
			Trivia_UnSchedule("all");
			TRIVIA_ENABLED = false;
			TRIVIA_ACCEPTING_ANSWERS = false;
			Trivia_UpdateToggleButton();
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
