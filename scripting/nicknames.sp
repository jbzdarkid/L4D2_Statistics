#include <sourcemod>
#include <sdktools>
#include <socket>
#include <EasyJSON>
#pragma semicolon 1

#define ID_SIZE 64
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
	nicknames = CreateJSON();
	nicknamesToUpload = CreateArray(ID_SIZE);
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

// Changes a player's name.
RenamePlayer(client, String:name[]) {
	if (!IsClientInGame(client)) return;
	if (IsFakeClient(client)) return;
	SetClientInfo(client, "name", name);
}

// Strips the HTML headers from a response and returns a JSON object.
Handle:ParseHTMLResponse(String:html[]) {
	new index = StrContains(html, "\r\n\r\n");
	strcopy(html, strlen(html), html[index]);
	TrimString(html);
	new Handle:json = DecodeJSON(html);
	if (json == INVALID_HANDLE) {
		ThrowError("Couldn't parse json:\n%s", html);
	}
	return json;
}

public PlayerTeam(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client <= 0 || client > MaxClients) return;
	if (!IsClientInGame(client)) return;
	if (IsFakeClient(client)) return;
	if (GetEventInt(event, "oldteam") != 0) return;
	decl String:steamId[ID_SIZE];
	GetSteamId(client, steamId);
	new Handle:jsonData = CreateJSON();
	if (JSONGetArray(nicknames, steamId, jsonData)) return;
	JSONSetString(jsonData, "steamId", steamId);
	decl String:ign[NAME_SIZE];
	GetClientName(client, ign, NAME_SIZE);
	JSONSetString(jsonData, "name", ign);
	JSONSetInteger(jsonData, "client", client);
	new Handle:socket = SocketCreate(SOCKET_TCP, SocketError);
	SocketSetArg(socket, jsonData);
	SocketConnect(socket, GetNicknameQuery, GetNicknameResponse, SocketClosed, "l4d2statistics.cloudant.com", 80);
}

public GetNicknameQuery(Handle:socket, any:jsonData) {
	PrintToServer("GetNicknameQuery");
	decl String:steamId[ID_SIZE];
	JSONGetString(jsonData, "steamId", steamId, ID_SIZE);
	decl String:request[1024];
	// GET /nicknames/32356809 HTTP/1.1
	// Host: l4d2statistics.cloudant.com
	// Accept: */*
	//
	//
	Format(request, sizeof(request), "GET /nicknames/%s HTTP/1.1\nHost: l4d2statistics.cloudant.com\nAccept: */*\n\n", steamId);
	SocketSend(socket, request);
}

public GetNicknameResponse(Handle:socket, String:data[], const dataSize, any:jsonData) {
	PrintToServer("GetNicknameResponse");
	new Handle:json = ParseHTMLResponse(data);
	decl String:steamId[ID_SIZE];
	JSONGetString(jsonData, "steamId", steamId, ID_SIZE);
	decl String:error[128];
	if (JSONGetString(json, "error", error, sizeof(error))) {
		if (strcmp(error, "not_found") == 0) {
			PrintToServer("Steam ID %s unknown, adding to upload queue.", steamId);
			PushArrayString(nicknamesToUpload, steamId);
			decl String:ign[NAME_SIZE];
			JSONGetString(jsonData, "name", ign, NAME_SIZE);
			new Handle:names = CreateArray(64);
			PushArrayString(names, ign);
			JSONSetArray(nicknames, steamId, names);
		} else {
			ThrowError("CouchDB responded with an error: %s");
		}
	} else {
		decl Handle:names;
		JSONGetArray(json, "names", names);
		JSONSetArray(nicknames, steamId, names);
		PrintToServer("Found %d nickname(s) for Steam ID %s", GetArraySize(names), steamId);
		if (GetConVarBool(renamePlayers)) {
			new String:nickname[NAME_SIZE];
			GetArrayString(names, 0, nickname, NAME_SIZE); // Using names[0] for their default name.
			decl client;
			JSONGetInteger(jsonData, "client", client);
			RenamePlayer(client, nickname);
		}
	}
}

public RoundEnd(Handle:event, const String:name[], bool:dontBroadcast) {
	if (GetArraySize(nicknamesToUpload) == 0) return;
	decl String:steamId[ID_SIZE];
	GetArrayString(nicknamesToUpload, 0, steamId, ID_SIZE);
	RemoveFromArray(nicknamesToUpload, 0);
	new Handle:jsonData = CreateJSON();
	JSONSetString(jsonData, "steamId", steamId);
	new Handle:socket = SocketCreate(SOCKET_TCP, SocketError);
	SocketSetArg(socket, jsonData);
	SocketConnect(socket, PutNicknameQuery, PutNicknameResponse, SocketClosed, "l4d2statistics.cloudant.com", 80);
}

public PutNicknameQuery(Handle:socket, any:jsonData) {
	PrintToServer("PutNicknameQuery");
	decl String:steamId[ID_SIZE];
	JSONGetString(jsonData, "steamId", steamId, ID_SIZE);
	decl Handle:names;
	JSONGetArray(nicknames, steamId, names);

	new Handle:names2 = CreateArray(1);
	for (new i=0; i<GetArraySize(names); i++) {
		decl String:temp[NAME_SIZE];
		GetArrayString(names, i, temp, NAME_SIZE);
		PushArrayCell(names2, JSONCreateString(temp));
	}

	new Handle:content = CreateJSON();
	JSONSetArray(content, "names", names2);
	decl String:contentStr[1024];
	EncodeJSON(content, contentStr, sizeof(contentStr));
	decl String:request[1024];
	// PUT /nicknames/32356809 HTTP/1.1
	// Host: l4d2statistics.cloudant.com
	// Accept: */*
	// Content-Length: 20
	// Content-Type: application/json
	//
	// {"names":["darkid"]}
	Format(request, sizeof(request), "PUT /nicknames/%s HTTP/1.1\nHost: l4d2statistics.cloudant.com\nAccept: */*\nContent-Length: %d\nContent-Type: application/json\n\n%s\n", steamId, strlen(contentStr), contentStr);
	PrintToServer("Request:");
	PrintToServer(request);
	SocketSend(socket, request);
}

public PutNicknameResponse(Handle:socket, String:data[], const dataSize, any:jsonData) {
	PrintToServer("PutNicknameResponse");
	new Handle:json = ParseHTMLResponse(data);
	decl String:steamId[ID_SIZE];
	JSONGetString(jsonData, "steamId", steamId, ID_SIZE);
	decl String:error[128];
	if (JSONGetString(json, "error", error, sizeof(error))) {
		PrintToServer("Nickname upload failed: %s", error);
		PushArrayString(nicknamesToUpload, steamId);
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