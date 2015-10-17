#include <sourcemod>
#include <sdktools>
#include <socket>
#include <EasyJSON>
#pragma semicolon 1

#define NAME_SIZE 256

public Plugin:myinfo = {
	name = "Nickname Tracker",
	author = "Darkid",
	description = "Players can get a list of the nicknames of active players.",
	version = "3.1",
	url = "www.github.com/jbzdarkid/L4D2_Statistics"
};

new Handle:nicknames;
new Handle:nicknamesToUpload;
new Handle:renamePlayers;

public OnPluginStart() {
	nicknames = CreateTrie();
	nicknamesToUpload = CreateStack(64);
	HookEvent("player_team", PlayerTeam);
	HookEvent("round_end", RoundEnd);
	renamePlayers = CreateConVar("rename_players", "Rename players to their given nickname when they join.", "1");
}

// Truncates off the STEAM_1:X: from steam names.
GetSteamId(client, String:output[]) {
	new String:steamId[20];
	GetClientAuthString(client, steamId, sizeof(steamId));
	strcopy(output, 9, steamId[10]);
	output[9] = 0;
}

public PlayerTeam(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client <= 0 || client > MaxClients) return;
	if (!IsClientInGame(client)) return;
	if (IsFakeClient(client)) return;
	if (GetEventInt(event, "oldteam") != 0) return;
	decl String:steamId[64];
	GetSteamId(client, steamId);
	decl String:ign[NAME_SIZE];
	if (GetTrieString(nicknames, steamId, ign, NAME_SIZE)) return;
	GetClientName(client, ign, NAME_SIZE);
	new Handle:socket = SocketCreate(SOCKET_TCP, SocketError);
	SocketConnect(socket, GetNicknameQuery, GetNicknameResponse, SocketClosed, "l4d2statistics.cloudant.com", 80);
}

public GetNicknameQuery(Handle:socket, any:jsonData) {
	PrintToServer("GetNicknameQuery");
	decl String:requestStr[1024];
	// GET /nicknames/32356809 HTTP/1.1
	// Host: l4d2statistics.cloudant.com
	// Accept: */*
	//
	//
	Format(requestStr, sizeof(requestStr), "GET /nicknames/%s HTTP/1.1\nHost: l4d2statistics.cloudant.com\nAccept: */*\n\n", "32356809");
	SocketSend(socket, requestStr);
}

public GetNicknameResponse(Handle:socket, String:data[], const dataSize, any:jsonData) {
	PrintToServer("GetNicknameResponse");
	new index = StrContains(data, "\r\n\r\n");
	strcopy(data, dataSize, data[index]);
	TrimString(data);
	PrintToServer(data);
	new Handle:json = DecodeJSON(data);
	if (json == INVALID_HANDLE) return;

	new String:steamId[64] = "32356809";
	new String:ign[NAME_SIZE] = "darkid";
	new client = 0;
	decl String:error[128];
	if (JSONGetString(json, "error", error, sizeof(error))) {
		if (strcmp(error, "not_found") == 0) {
			PrintToServer("Steam ID %s unknown, adding to upload queue.", steamId);
			PushStackString(nicknamesToUpload, steamId);
			new Handle:names = CreateArray(64);
			PushArrayString(names, ign);
			SetTrieValue(nicknames, steamId, names);
		} else {
			PrintToServer("Error: %s", error);
		}
	} else {
		decl Handle:names;
		JSONGetArray(json, "names", names);
		SetTrieValue(nicknames, steamId, names);
		PrintToServer("Found %d nickname(s) for Steam ID %s", GetArraySize(names), steamId);
		if (GetConVarBool(renamePlayers)) {
			new String:nickname[NAME_SIZE];
			GetArrayString(names, 0, nickname, NAME_SIZE);
			SetClientInfo(client, "name", nickname);
		}
	}
}

public RoundEnd(Handle:event, const String:name[], bool:dontBroadcast) {
	PrintToServer("RoundEnd");
	new Handle:socket = SocketCreate(SOCKET_TCP, SocketError);
	decl String:steamId[64];
	PopStackString(nicknamesToUpload, steamId, sizeof(steamId));
	decl Handle:names;
	GetTrieValue(nicknames, steamId, names);
	SocketConnect(socket, PutNicknameQuery, PutNicknameResponse, SocketClosed, "l4d2statistics.cloudant.com", 80);
}

public PutNicknameQuery(Handle:socket, any:jsonData) {
	PrintToServer("PutNicknameQuery");
	new String:steamId[64] = "32356809";
	decl String:requestStr[1024];
	// PUT /nicknames/32356809 HTTP/1.1
	// Host: l4d2statistics.cloudant.com
	// Accept: */*
	// Content-Length: 20
	// Content-Type: application/json
	//
	// {"names":["darkid"]}
	new String:request[1024] = "{\"names\":[\"jbzdarkid\"]}";
	PrintToServer("Length: %d", strlen(request));
	Format(requestStr, sizeof(requestStr), "PUT /nicknames/%s HTTP/1.1\nHost: l4d2statistics.cloudant.com\nAccept: */*\nContent-Length: %d\nContent-Type: application/json\n\n%s\n", steamId, strlen(request), request);
	PrintToServer("PutNicknamyQuery:\n");
	PrintToServer(requestStr);
	SocketSend(socket, requestStr);
}

public PutNicknameResponse(Handle:socket, String:data[], const dataSize, any:jsonData) {
	PrintToServer("PutNicknameResponse");
	new index = StrContains(data, "\r\n\r\n");
	strcopy(data, dataSize, data[index]);
	TrimString(data);
	new Handle:json = DecodeJSON(data);
	if (json == INVALID_HANDLE) return;

	new String:steamId[64] = "32356809";
	decl String:error[128];
	if (JSONGetString(json, "error", error, sizeof(error))) {
		PrintToServer("Nickname upload failed: %s", error);
		PushStackString(nicknamesToUpload, steamId);
	} else {
		PrintToServer("Sucessfuly uploaded nickname for Steam ID %s", steamId);
	}
}

public SocketClosed(Handle:socket, any:jsonData) {
	CloseHandle(socket);
}

public SocketError(Handle:socket, errorType, errorNum, any:jsonData) {
	PrintToServer("Socket error %d (Type %d)", errorNum, errorType);
	LogMessage("Socket error %d (Type %d)", errorNum, errorType);
	CloseHandle(socket);
}