#include <sourcemod>
#include <socket> // For talking to CouchDB
#include <EasyJSON> // For interpreting CouchDB
#include <l4d2_direct> // For getting team scores
#undef REQUIRE_PLUGIN
#include <l4d2lib> // For getting custom map distance
#define REQUIRE_PLUGIN
#include <left4downtown> // For getting default map distance
#pragma semicolon 1

#define ID_SIZE 64
#define NAME_SIZE 256
#define REV_SIZE 64
#define ERROR_SIZE 256

public Plugin:myinfo = {
	name = "Nickname Tracker",
	author = "Darkid",
	description = "Players can get a list of the nicknames of active players.",
	version = "3.4",
	url = "www.github.com/jbzdarkid/L4D2_Statistics"
};

/* Structure for playerData
{
	"32356809": {
		"names": ["darkid"],
		"elo": 1000,
		"_rev": "1-8aff9ee9d06671fa89c99d20a4b3ae"
	},
	"32356810": {
		"names": ["fig newtons"],
		"elo": 1001,
		"_rev": "2-6e1295ed6c29495e54cc05947f18c8af"
	}
}
*/
new Handle:playerData;
new Handle:playersWithNewData;
new Handle:renamePlayers;

new String:teamA[4][ID_SIZE];
new String:teamB[4][ID_SIZE];
new teamAScore;
new teamBScore;
new teamAScoreThisRound;
new teamBScoreThisRound;
new teamAPlayerCount;
new teamBPlayerCount;

new bool:isFirstHalf;
new bool:didRoundEnd;

public OnPluginStart() {
	playerData = CreateJSON();
	playersWithNewData = CreateArray(ID_SIZE);

	HookEvent("player_team", PlayerTeam);
	HookEvent("player_left_start_area", RoundStart);
	HookEvent("round_end", RoundEnd);

	renamePlayers = CreateConVar("mm_rename_players", "Rename players to their given nickname when they join.", "1");

	RegServerCmd("mm_usage", GetUsage);
	RegServerCmd("mm_debug", Debug);
	RegConsoleCmd("mm_nicknames", GetNicknames);
	RegConsoleCmd("mm_setnickname", SetNickname);
}

// **************** Utility functions ****************
// Truncates off the STEAM_1:X: from steam names.
GetSteamId(client, String:output[]) {
	new String:steamId[20];
	GetClientAuthString(client, steamId, ID_SIZE);
	strcopy(output, 9, steamId[10]);
	output[9] = 0;
}

// Gets a player's name and returns it in url-safe format.
GetPlayerName(client, String:output[]) {
	GetClientName(client, output, NAME_SIZE);
	new doubleNameSize = NAME_SIZE*2;
	ReplaceString(output, doubleNameSize, "\\", "\\\\", false);
	ReplaceString(output, doubleNameSize, "\"", "\\\"", false);
}

// Changes a player's name.
RenamePlayer(client, String:name[]) {
	if (!IsClientInGame(client)) return;
	if (IsFakeClient(client)) return;
	SetClientInfo(client, "name", name);
}

// Strips the HTML headers from a response and returns a JSON object.
Handle:ParseHTMLResponse(String:html[], length) {
	new index = StrContains(html, "\r\n\r\n");
	strcopy(html, length, html[index]);
	TrimString(html);
	new Handle:json = DecodeJSON(html);
	if (json == INVALID_HANDLE) {
		ThrowError("Couldn't parse json:\n%s", html);
	}
	return json;
}

// **************** Commands ****************
public Action:GetUsage(args) {
	new Handle:temp = CreateTrieSnapshot(playerData);
	PrintToServer("[MM] There are %d players being tracked.", TrieSnapshotLength(temp));
	CloseHandle(temp);
}

public Action:Debug(args) {
	decl String:print[2048];
	EncodeJSON(playerData, print, sizeof(print));
	PrintToServer(print);
}

public Action:GetNicknames(client, args) {}
public Action:SetNickname(client, args) {}

// **************** Events ****************
public PlayerTeam(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client <= 0 || client > MaxClients) return;
	if (!IsClientInGame(client)) return;
	if (IsFakeClient(client)) return;
	if (GetEventInt(event, "oldteam") != 0) return;
	decl String:steamId[ID_SIZE];
	GetSteamId(client, steamId);
	if (FindStringInArray(playersWithNewData, steamId) != -1) return;
	new Handle:socket = SocketCreate(SOCKET_TCP, SocketError);
	SocketSetArg(socket, client);
	SocketConnect(socket, GetPlayerDataQuery, GetPlayerDataResponse, SocketClosed, "l4d2statistics.cloudant.com", 80);
}

public MapChange() {
	isFirstHalf = false;
	teamAScore = L4D2Direct_GetVSCampaignScore(0);
	teamBScore = L4D2Direct_GetVSCampaignScore(1);
}

public RoundStart(Handle:event, const String:name[], bool:dontBroadcast) {
	didRoundEnd = false;
	if (!isFirstHalf) return;
	teamAPlayerCount = 0;
	teamBPlayerCount = 0;
	for (new client=1; client<=MaxClients; client++) {
		if (!IsClientInGame(client)) continue;
		if (IsFakeClient(client)) continue; // Shouldn't trigger, but why not.
		if (GetClientTeam(client) == 2) {
			GetSteamId(client, teamA[teamAPlayerCount++]);
		} else if (GetClientTeam(client) == 3) {
			GetSteamId(client, teamB[teamBPlayerCount++]);
		}
	}
	LogMessage("[MM] Round started as a %d vs %d.", teamAPlayerCount, teamBPlayerCount);
}

public RoundEnd(Handle:event, const String:name[], bool:dontBroadcast) {
	if (didRoundEnd) return; // This event gets called twice, for some reason. This prevents that from changing ELO twice.
	didRoundEnd = true;
	if (!isFirstHalf) {
		isFirstHalf = true;
		teamAScoreThisRound = L4D2Direct_GetVSCampaignScore(0) - teamAScore;
		LogMessage("[MM] First half ended. Survivors scored %d points.", teamAScoreThisRound);
		return;
	} else {
		isFirstHalf = false;
		teamBScoreThisRound = L4D2Direct_GetVSCampaignScore(1) - teamBScore;
		LogMessage("[MM] Second half ended. Survivors scored %d points.", teamBScoreThisRound);
	}
	PrintToChatAll("Team A (%d players) Score: %d", teamAPlayerCount, teamAScoreThisRound);
	PrintToChatAll("Team B (%d players) Score: %d", teamBPlayerCount, teamBScoreThisRound);

	if (teamAPlayerCount == 0 || teamBPlayerCount == 0) return;

	// Somehow players ELOs are getting modified... early
	new teamAELOAverage = 0;
	new teamBELOAverage = 0;
	for (new i=0; i<teamAPlayerCount; i++) {
		decl Handle:playerInfo;
		decl playerELO;
		JSONGetObject(playerData, teamA[i], playerInfo);
		JSONGetInteger(playerInfo, "elo", playerELO);
		teamAELOAverage += playerELO;
	}
	for (new i=0; i<teamBPlayerCount; i++) {
		decl Handle:playerInfo;
		decl playerELO;
		JSONGetObject(playerData, teamB[i], playerInfo);
		JSONGetInteger(playerInfo, "elo", playerELO);
		teamBELOAverage += playerELO;
	}
	teamAELOAverage /= teamAPlayerCount;
	teamBELOAverage /= teamBPlayerCount;
	PrintToChatAll("Team A average ELO: %d", teamAELOAverage);
	PrintToChatAll("Team B average ELO: %d", teamBELOAverage);

	new Float:mapDistance = 1.0*L4D2_GetMapValueInt("max_distance", -1);
	if (mapDistance == -1.0) mapDistance = 1.0*L4D_GetVersusMaxCompletionScore();
	decl Float:teamADistance, Float:teamABonus, Float:teamBDistance, Float:teamBBonus;
	if (teamAScoreThisRound < mapDistance) {
		teamADistance = 1.0*teamAScoreThisRound;
		teamABonus = mapDistance;
	} else {
		teamADistance = mapDistance;
		teamABonus = 1.0*teamAScoreThisRound;
	}
	if (teamBScoreThisRound < mapDistance) {
		teamBDistance = 1.0*teamBScoreThisRound;
		teamBBonus = mapDistance;
	} else {
		teamBDistance = mapDistance;
		teamBBonus = 1.0*teamBScoreThisRound;
	}

	new Float:distancePoints = teamADistance - teamBDistance;
	new Float:bonusPoints = Pow(SquareRoot(teamABonus) - SquareRoot(teamBBonus), 2.0);
	new scoreDifference = RoundToFloor(distancePoints + (teamABonus < teamBBonus ? -1 : 1) * bonusPoints);

	for (new i=0; i<teamAPlayerCount; i++) {
		decl Handle:playerInfo;
		decl playerELO;
		JSONGetObject(playerData, teamA[i], playerInfo);
		JSONGetInteger(playerInfo, "elo", playerELO);
		new adjustment = teamBELOAverage - playerELO + scoreDifference;
		PrintToChatAll("Player %s adjustment: %d = %d - %d + %d", teamA[i], adjustment, teamBELOAverage, playerELO, scoreDifference);
		new copy = playerELO;
		playerELO += adjustment/10;
		PrintToChatAll("Player %s ELO change: %d -> %d", teamA[i], copy, playerELO);
		JSONSetInteger(playerInfo, "elo", playerELO);
		new test;
		JSONGetInteger(playerInfo, "elo", test);
		PrintToChatAll("<235> %d = %d", playerELO, test);

		PushArrayString(playersWithNewData, teamA[i]);
	}
	for (new i=0; i<teamBPlayerCount; i++) {
		decl Handle:playerInfo;
		decl playerELO;
		JSONGetObject(playerData, teamB[i], playerInfo);
		JSONGetInteger(playerInfo, "elo", playerELO);
		new adjustment = teamAELOAverage - playerELO - scoreDifference;
		PrintToChatAll("Player %s adjustment: %d = %d - %d - %d", teamB[i], adjustment, teamAELOAverage, playerELO, scoreDifference);
		new copy = playerELO;
		playerELO += adjustment/10;
		PrintToChatAll("Player %s ELO change: %d -> %d", teamB[i], copy, playerELO);
		JSONSetInteger(playerInfo, "elo", playerELO);
		PushArrayString(playersWithNewData, teamB[i]);
	}
	if (GetArraySize(playersWithNewData) == 0) return;
	new Handle:socket = SocketCreate(SOCKET_TCP, SocketError);
	SocketSetArg(socket, playersWithNewData);
	SocketConnect(socket, UploadPlayerDataQuery, UploadPlayerDataResponse, SocketClosed, "l4d2statistics.cloudant.com", 80);
}

// **************** Queries and Callbacks ****************
// Called from PlayerJoin. It queries CouchDB for all info about a player.
public GetPlayerDataQuery(Handle:socket, any:client) {
	if (!IsClientInGame(client) || IsFakeClient(client)) return;
	decl String:steamId[ID_SIZE];
	GetSteamId(client, steamId);
	decl String:request[128];
	// GET /nicknames/32356809 HTTP/1.1
	// Host: l4d2statistics.cloudant.com
	// Accept: */*
	//
	//
	Format(request, sizeof(request), "GET /nicknames/%s HTTP/1.1\nHost: l4d2statistics.cloudant.com\nAccept: */*\n\n", steamId);
	SocketSend(socket, request);
}

// Called from GetPlayerDataQuery. It handles the response from CouchDB about player data, and saves it locally. If the response from couchdb is "error":"not_found", then we will create data for a new user.
public GetPlayerDataResponse(Handle:socket, String:data[], dataSize, any:client) {
	if (!IsClientInGame(client) || IsFakeClient(client)) return;
	new Handle:json = ParseHTMLResponse(data, dataSize);
	decl String:steamId[ID_SIZE];
	GetSteamId(client, steamId);
	decl String:error[ERROR_SIZE];
	if (!JSONGetString(json, "error", error, ERROR_SIZE)) {
		decl Handle:playerInfo;
		if (JSONGetObject(playerData, steamId, playerInfo)) {
			DestroyJSON(playerInfo); // Don't duplicate local data.
		}
		decl Handle:names;
		JSONGetArray(json, "names", names);
		JSONSetObject(playerData, steamId, json);
		LogMessage("[MM] Downloaded playerdata for %N (%s).", client, steamId);
		decl String:newName[NAME_SIZE];
		JSONGetArrayString(names, 0, newName, NAME_SIZE);
		LogMessage("[MM] Player %N has %d nicknames, primary is %s.", client, GetArraySize(names), newName); // Fix this
		if (GetConVarBool(renamePlayers)) {
			RenamePlayer(client, newName);
		}
	} else if (strcmp(error, "not_found") != 0) {
		decl String:reason[ERROR_SIZE];
		JSONGetString(json, "reason", reason, ERROR_SIZE);
		ThrowError("[MM] CouchDB Error: %s\n[MM] Reason: %s", error, reason);
	} else {
		LogMessage("[MM] A new challenger arrives: %N", client);
		decl String:ign[NAME_SIZE*2]; // To allow for escapement, we need twice the space.
		GetPlayerName(client, ign);
		new Handle:names = CreateArray(1);
		PushArrayCell(names, JSONCreateString(ign));
		new Handle:playerInfo = CreateJSON();
		JSONSetString(playerInfo, "_id", steamId);
		JSONSetArray(playerInfo, "names", names);
		JSONSetInteger(playerInfo, "elo", 1000);
		JSONSetObject(playerData, steamId, playerInfo);
		PushArrayString(playersWithNewData, steamId);
	}
}

// Called from PlayerJoin if there's a new player. Called from SetNickname. Called from RoundEnd. This sends an update to CouchDB about any number of players' data. any:players should be an adt_array containing steam ids.
public UploadPlayerDataQuery(Handle:socket, any:players) {
	new Handle:documentArray = CreateArray(1);
	for (new i=0; i<GetArraySize(players); i++) {
		decl String:steamId[ID_SIZE];
		GetArrayString(players, i, steamId, ID_SIZE);
		decl Handle:playerInfo;
		JSONGetObject(playerData, steamId, playerInfo);
		PushArrayCell(documentArray, JSONCreateObject(playerInfo));
	}
	new Handle:payload = CreateJSON();
	JSONSetArray(payload, "docs", documentArray);
	decl String:payloadStr[2048];
	EncodeJSON(payload, payloadStr, sizeof(payloadStr));
	decl String:request[2048];
	// POST /nicknames/32356809 HTTP/1.1
	// Host: l4d2statistics.cloudant.com
	// Accept: */*
	// Content-Length: 200
	// Content-Type: application/json
	//
	// [
	//  	{
	//  		"_id":"3235809",
	//  		"_rev":"1-8aff9ee9d06671fa89c99d20a4b3ae"
	//  		"names":["darkid"],
	//			"elo":1000
	//  	},
	//  	{
	//  		"_id":"3235810",
	//  		"_rev":"2-6e1295ed6c29495e54cc05947f18c8af"
	//  		"names":["fig newtons"],
	//			"elo":1001
	//  	}
	// ]
	Format(request, sizeof(request), "POST /nicknames/_bulk_docs HTTP/1.1\nHost: l4d2statistics.cloudant.com\nAccept: */*\nContent-Length: %d\nContent-Type: application/json\n\n%s\n", strlen(payloadStr), payloadStr);
	SocketSend(socket, request);
}

// Called from UploadPlayerDataQuery. Handles CouchDB conflicts, updates revision number on success to prevent further conflicts.
public UploadPlayerDataResponse(Handle:socket, String:data[], dataSize, any:players) {
	PrintToServer("UploadPlayerDataResponse");
	PrintToServer("%s", data);
	new Handle:json = ParseHTMLResponse(data, dataSize);
	PrintToServer("%d", GetArraySize(json));
	for (new i=0; i<GetArraySize(json); i++) {
		new Handle:playerInfo = GetArrayCell(json, i);
		decl String:error[ERROR_SIZE];
		if (!JSONGetString(json, "error", error, ERROR_SIZE)) {
			decl String:steamId[ID_SIZE];
			JSONGetString(playerInfo, "id", steamId, ID_SIZE);
			decl String:rev[REV_SIZE];
			JSONGetString(playerInfo, "rev", rev, REV_SIZE);
			JSONGetObject(playerData, steamId, playerInfo);
			JSONSetString(playerInfo, "_rev", rev);
			RemoveFromArray(players, FindStringInArray(players, steamId));
		} else if (strcmp(error, "conflict") == 0) {
			ThrowError("[MM] CouchDB upload conflict."); // I'm not sure what to do about this.
		} else {
			decl String:reason[ERROR_SIZE];
			JSONGetString(json, "reason", reason, ERROR_SIZE);
			ThrowError("[MM] CouchDB Error: %s\n[MM] Reason: %s", error, reason);
		}
	}
}

public SocketClosed(Handle:socket, any:arg) {
	CloseHandle(socket);
}

public SocketError(Handle:socket, errorType, errorNum, any:arg) {
	PrintToServer("Socket error %d (Type %d)", errorNum, errorType);
	LogMessage("Socket error %d (Type %d)", errorNum, errorType);
	CloseHandle(socket);
}