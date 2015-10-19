#include <sourcemod>
#include <socket> // For talking to CouchDB
#include <EasyJSON> // For interpreting CouchDB
#include <l4d2_direct> // For getting team scores
#pragma semicolon 1

#define ID_SIZE 64
#define NAME_SIZE 256
#define ERROR_SIZE 256

public Plugin:myinfo = {
	name = "Nickname Tracker",
	author = "Darkid",
	description = "Players can get a list of the nicknames of active players.",
	version = "3.3",
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
new bool:isNewGame;
new bool:didRoundEnd;

public OnPluginStart() {
	playerData = CreateJSON();

	HookEvent("player_team", PlayerTeam);
	HookEvent("player_left_start_area", RoundStart);
	HookEvent("round_end", RoundEnd);

	renamePlayers = CreateConVar("mm_rename_players", "Rename players to their given nickname when they join.", "1");
	isNewGame = true;

	RegServerCmd("mm_usage", GetUsage);
	RegConsoleCmd("mm_nicknames", GetNicknames);
	RegConsoleCmd("mm_setnickname", SetNickname);
}

// **************** Utility functions ****************
// Truncates off the STEAM_1:X: from steam names.
GetSteamId(client, String:output[]) {
	new String:steamId[20];
	GetClientAuthString(client, steamId, sizeof(steamId));
	strcopy(output, 9, steamId[10]);
	output[9] = 0;
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
public Action:GetUsage(args) {}
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
	new Handle:socket = SocketCreate(SOCKET_TCP, SocketError);
	SocketSetArg(socket, client);
	SocketConnect(socket, GetPlayerDataQuery, GetPlayerDataResponse, SocketClosed, "l4d2statistics.cloudant.com", 80);
}

public MapChange() {
	isFirstHalf = false;
	teamAScore = L4D2Direct_GetVSCampaignScore(0);
	teamBScore = L4D2Direct_GetVSCampaignScore(1);
	isNewGame = (teamAScore == 0) && (teamBScore == 0);
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
	new Float:teamAELOAverage = 0.0;
	for (new i=0; i<teamAPlayerCount; i++) {
		decl Handle:playerInfo;
		JSONGetObject(playerData, teamA[i], playerInfo);
		decl playerELO;
		JSONGetInteger(playerInfo, "elo", playerELO);
		teamAELOAverage += 1.0*playerELO/teamAPlayerCount;
	}
	new Float:teamBELOAverage = 0.0;
	for (new i=0; i<teamBPlayerCount; i++) {
		decl Handle:playerInfo;
		JSONGetObject(playerData, teamB[i], playerInfo);
		decl playerELO;
		JSONGetInteger(playerInfo, "elo", playerELO);
		teamBELOAverage += 1.0*playerELO/teamBPlayerCount;
	}

	decl min;
	if (teamAScoreThisRound < teamBScoreThisRound) {
		min = teamAScoreThisRound;
	} else {
		min = teamBScoreThisRound;
	}
	if (min <= 0) min = 1; // Prevents division by zero
	new Float:scoreDifference = 100.0*(teamAScoreThisRound - teamBScoreThisRound)/min;
	new Handle:players = CreateArray(ID_SIZE);
	for (new i=0; i<teamAPlayerCount; i++) {
		decl Handle:playerInfo;
		JSONGetObject(playerData, teamA[i], playerInfo);
		decl playerELO;
		JSONGetInteger(playerInfo, "elo", playerELO);
		new Float:adjustment = teamBELOAverage - playerELO + scoreDifference;
		playerELO = RoundToFloor((playerELO*128 + adjustment)/128);
		JSONSetInteger(playerInfo, "elo", playerELO);
		JSONSetObject(playerData, teamA[i], playerInfo);
		PushArrayString(players, teamA[i]);
	}
	for (new i=0; i<teamBPlayerCount; i++) {
		decl Handle:playerInfo;
		JSONGetObject(playerData, teamB[i], playerInfo);
		decl playerELO;
		JSONGetInteger(playerInfo, "elo", playerELO);
		new Float:adjustment = teamAELOAverage - playerELO + scoreDifference;
		playerELO = RoundToFloor((playerELO*128 + adjustment)/128);
		JSONSetInteger(playerInfo, "elo", playerELO);
		JSONSetObject(playerData, teamB[i], playerInfo);
		PushArrayString(players, teamB[i]);
	}
	new Handle:socket = SocketCreate(SOCKET_TCP, SocketError);
	SocketSetArg(socket, players);
	SocketConnect(socket, UploadPlayerDataQuery, UploadPlayerDataResponse, SocketClosed, "l4d2statistics.cloudant.com", 80);
}

// **************** Queries and Callbacks ****************
// Called from PlayerJoin. It queries CouchDB for all info about a player.
public GetPlayerDataQuery(Handle:socket, any:client) {
	if (!IsClientInGame(client) || IsFakeClient(client)) return;
	PrintToServer("GetPlayerDataQuery");
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
	PrintToServer("GetPlayerDataResponse");
	new Handle:json = ParseHTMLResponse(data, dataSize);
	decl String:steamId[ID_SIZE];
	GetSteamId(client, steamId);
	decl String:error[ERROR_SIZE];
	if (!JSONGetString(json, "error", error, ERROR_SIZE)) {
		decl Handle:names;
		JSONGetArray(json, "names", names);
		JSONSetObject(playerData, steamId, json);
		LogMessage("[MM] Downloaded playerdata for %N (%s).", client, steamId);
		decl String:newName[NAME_SIZE];
		GetArrayString(names, 0, newName, NAME_SIZE);
		LogMessage("[MM] Player %N has %d nicknames, primary is %s.", client, GetArraySize(names), newName);
		if (GetConVarBool(renamePlayers)) {
			RenamePlayer(client, newName);
		}
	} else if (strcmp(error, "not_found") != 0) {
		decl String:reason[256];
		JSONGetString(json, "reason", reason, sizeof(reason));
		ThrowError("[MM] CouchDB Error: %s\n[MM] Reason: %s", error, reason);
	} else {
		LogMessage("[MM] A new challenger arrives: %N", client);
		decl String:ign[NAME_SIZE];
		GetClientName(client, ign, NAME_SIZE); // Here is where we strip invalid chars.
		new Handle:names = CreateArray(1);
		PushArrayCell(names, JSONCreateString(ign));
		new Handle:playerInfo = CreateJSON();
		JSONSetString(playerInfo, "_id", steamId);
		JSONSetArray(playerInfo, "names", names);
		JSONSetInteger(playerInfo, "elo", 1000);
		JSONSetObject(playerData, steamId, playerInfo);
		new Handle:players = CreateArray(ID_SIZE);
		PushArrayString(players, steamId);
		socket = SocketCreate(SOCKET_TCP, SocketError);
		SocketSetArg(socket, players);
		SocketConnect(socket, UploadPlayerDataQuery, UploadPlayerDataResponse, SocketClosed, "l4d2statistics.cloudant.com", 80);
	}
}

// Called from PlayerJoin if there's a new player. Called from SetNickname. Called from RoundEnd. This sends an update to CouchDB about any number of players' data. any:players should be an adt_array containing steam ids.
public UploadPlayerDataQuery(Handle:socket, any:players) {
	PrintToServer("UploadPlayerDataQuery");
	new Handle:documentArray = CreateArray(1);
	for (new i=0; i<GetArraySize(players); i++) {
		decl String:steamId[ID_SIZE];
		GetArrayString(players, i, steamId, ID_SIZE);
		decl Handle:playerInfo;
		JSONGetObject(playerData, steamId, playerInfo);
		PushArrayCell(documentArray, playerInfo);
	}
	new Handle:payload = CreateJSON();
	JSONSetArray(payload, "docs", documentArray);
	decl String:payloadStr[2048];
	EncodeJSON(payload, payloadStr, sizeof(payloadStr));
	decl String:request[2048];
	// PUT /nicknames/32356809 HTTP/1.1
	// Host: l4d2statistics.cloudant.com
	// Accept: */*
	// Content-Length: 20
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
	Format(request, sizeof(request), "PUT /nicknames/_bulk_docs HTTP/1.1\nHost: l4d2statistics.cloudant.com\nAccept: */*\nContent-Length: %d\nContent-Type: application/json\n\n%s\n", strlen(payloadStr), payloadStr);
	SocketSend(socket, request);
}

// Called from UploadPlayerDataQuery. Handles CouchDB conflicts, updates revision number on success to prevent further conflicts.
public UploadPlayerDataResponse(Handle:socket, String:data[], dataSize, any:playerInfo) {
	PrintToServer("UploadPlayerDataResponse");
	new Handle:json = ParseHTMLResponse(data, dataSize);
	PrintToServer(data);
	PrintToServer("%d", GetArraySize(json));


	/*
	[
	  {
		"ok": true,
		"id": "FishStew",
		"rev":" 1-967a00dff5e02add41819138abb3284d"
	  },
	  {
		"ok": true,
		"id": "LambStew",
		"rev": "3-f9c62b2169d0999103e9f41949090807"
	  }
	]
	*/
	/*
	decl String:error[ERROR_SIZE];
	if (JSONGetString(json, "error", error, ERROR_SIZE)) {
		if (strcmp(error, "conflict")) {
			ThrowError("[MM] CouchDB upload conflict."); // I'm not sure what to do about this.
		} else {
			decl String:reason[256];
			JSONGetString(json, "reason", reason, sizeof(reason));
			ThrowError("[MM] CouchDB Error: %s\n[MM] Reason: %s", error, reason);
		}
	} else {
		decl bool:ok;
		JSONGetBoolean(json, "ok", ok);
		if (!ok) {
			ThrowError("<297> %s", data); // I don't know why this would happen.
		} else {
			decl String:rev[64];
			JSONGetString(json, "rev", rev, sizeof(rev));
			decl String:steamId[ID_SIZE];
			JSONGetString(playerInfo, "_id", steamId, ID_SIZE);
			JSONSetString(playerInfo, "_rev", rev);
			JSONSetObject(playerData, steamId, playerInfo);
			LogMessage("[MM] %s has been added to the database.", steamId);
		}
	}
	*/
}

public SocketClosed(Handle:socket, any:arg) {
	CloseHandle(socket);
	DestroyJSON(arg);
}

public SocketError(Handle:socket, errorType, errorNum, any:arg) {
	PrintToServer("Socket error %d (Type %d)", errorNum, errorType);
	LogMessage("Socket error %d (Type %d)", errorNum, errorType);
	CloseHandle(socket);
	DestroyJSON(arg);
}