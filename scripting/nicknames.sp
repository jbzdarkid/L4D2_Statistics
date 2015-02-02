// When a player joins, get their data.
// Store it somehow?
// When a player's data fails to load, do a post request to save their current nickname.
#include <sourcemod>
#include <json>
#include <SteamWorks>

public Plugin:myinfo = {
	name = "Database statistics",
	author = "Darkid",
	description = "Players can get a list of tracked statistics from a server.",
	version = "2.0",
	url = "https://github.com/jbzdarkid/L4D2_Statistics/blob/master/scripting/nicknames.sp"
};

new Handle:dataStore;

public OnPluginStart() {
	dataStore = CreateKeyValues("");
	HookEvent("player_connect", OnPlayerJoin);
	RegConsoleCmd("sm_nicknames", GetNicknames, "Print to the client a list of player nicknames");
}

// Strips out the "value" from the json response. If no data, makes a post request with the player's current name.
public GetServerInfo(Handle:request, String:output[], String:steamId[]) {
	new requestSize;
	SteamWorks_GetHTTPResponseBodySize(request, requestSize);
	new String:requestResponse[requestSize];
	SteamWorks_GetHTTPResponseBodyData(request, requestResponse, requestSize);
	new JSON:JsonResponse = json_decode(requestResponse);
	json_get_cell(JsonResponse, "rows", JsonResponse);
	json_get_cell(JsonResponse, "0", JsonResponse);
	if (JsonResponse == JSON_INVALID) {
		// Do a post request here
	}
	json_encode(JsonResponse, requestResponse, requestSize);
	strcopy(output, requestSize-86, requestResponse[43]);
	strcopy(steamId, 9, requestResponse[24]);
}

GetSteamId(client, String:output[]) {
	new String:steamId[20];
	GetClientAuthString(client, steamId, sizeof(steamId));
	strcopy(output, 9, steamId[10]);
	output[9] = 0;
}

public OnPlayerJoin(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	local_OnPlayerJoin(client);
}
local_OnPlayerJoin(client) {
	if (client == 0 || !IsClientInGame(client) || !IsClientConnected(client)) return;
	new String:steamId[9];
	GetSteamId(client, steamId);
	if (KvJumpToKey(dataStore, steamId)) return; // Player already has local data
	new String:quotedSteamId[10];
	quotedSteamId[0] = 34; // The " character
	strcopy(quotedSteamId[1], 9, steamId);
	quotedSteamId[9] = 34;
	new Handle:request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, "https://l4d2statistics.cloudant.com/us_test/_design/nickname/_view/nickname");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "key", quotedSteamId);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "format", "txt" );
	SteamWorks_SetHTTPCallbacks(request, NicknameCallback);
	SteamWorks_SendHTTPRequest(request);
}

public Action:GetNicknames(client, args) {
	for (new target=1; target<MAXPLAYERS; target++) {
		if (!IsClientInGame(target) || !IsClientConnected(target)) continue;
		new String:steamId[9];
		GetSteamId(target, steamId);
		if (strcmp(steamId, "") == 0) continue;
		if (!KvJumpToKey(dataStore, steamId)) {
			local_OnPlayerJoin(target);
			PrintToChat(client, "Failed to find nickname for '%N'", target);
			continue;
		}
		new String:nickname[64];
		KvGetString(dataStore, steamId, nickname, sizeof(nickname));
		KvRewind(dataStore);
		PrintToChat(client, "'%N' -> '%s'", target, nickname);
	}
}
	
public NicknameCallback(Handle:hRequest, bool:bFailure, bool:bRequestSuccessful, EHTTPStatusCode:eStatusCode) {
	new String:nickname[128];
	new String:steamId[64];
	GetServerInfo(hRequest, nickname, steamId);
	KvJumpToKey(dataStore, steamId, true);
	KvSetString(dataStore, steamId, nickname);
	KvRewind(dataStore);
}