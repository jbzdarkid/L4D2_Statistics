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
	new Handle:socket = SocketCreate(SOCKET_TCP, OnSocketError);
}

public OnSocketDisconnected(Handle:socket, any:hFile) {
	CloseHandle(socket);
}

public OnSocketError(Handle:socket, const errorType, const errorNum, any:hFile) {
	LogError("socket error %d (errno %d)", errorType, errorNum);
	CloseHandle(socket);
}

// Strips out the "value" from the json response. If no data, makes a post request with the player's current name.
public GetServerInfo(String:requestResponse, requestSize, String:output[], String:steamId[]) {
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
	if (client == 0 || !IsClientInGame(client) || IsFakeClient(client)) return;
	new String:steamId[9];
	GetSteamId(client, steamId);
	if (KvJumpToKey(dataStore, steamId)) return; // Player already has local data
	SocketConnect(socket, NicknameConnected, NicknameCallback, OnSocketDisconnected, "www.l4d2statistics.cloudant.com", 80);
}

/*
	PUT /us_test/32357809 HTTP/1.0
	Host: l4d2statistics.cloudant.com
	Content-Length: %d
	Content-Type: application/json
	
	{
	  %22_id%22:%22%s%22,
	  %22_rev%22:%22%s%22,
	  %22nickname%22:%22%s%22,
	}", size, steamId, rev, nickname
*/

/*
	"COPY /us_test/default HTTP/1.1
	Destination: %s", steamId
*/

public NicknameConnected(Handle:socket) {
	decl String:requestStr[256];
	Format(requestStr, sizeof(requestStr), "GET /us_test/_design/nickname/_view/nickname?key=%22%s%22\n\rHost: l4d2statistics.cloudant.com\n\rConnection: close", steamId);
	SocketSend(socket, requestStr);
}

public Action:GetNicknames(client, args) {
	for (new target=1; target<MAXPLAYERS; target++) {
		if (!IsClientInGame(target) || !IsClientConnected(target)) continue;
		new String:steamId[9];
		GetSteamId(target, steamId);
		if (strcmp(steamId, "") == 0) continue; // Mostly bots
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
	
public NicknameCallback(Handle:socket, String:receiveData[], const dataSize) {
	new String:nickname[128];
	new String:steamId[64];
	LogMessage("%d: %s", dataSize, receiveData);
	GetServerInfo(recieveData, dataSize, nickname, steamId);
	KvJumpToKey(dataStore, steamId, true);
	KvSetString(dataStore, steamId, nickname);
	KvRewind(dataStore);
}