#include <sourcemod>
#include <socket>
#include <json>

public Plugin:myinfo = {
	name = "Set player names from a database",
	author = "Darkid",
	description = "Players joining a server will have their nicknames set to a nickname to reduce confusion",
	version = "1.0",
	url = "https://github.com/jbzdarkid/L4D2_Statistics/blob/master/scripting/nicknames.sp"
};

/* I want to do a get request to
 * https://l4d2statistics.cloudant.com/us_test/_design/nickname/_view/nickname?key=\"76561198024979346\"
 * and then parse the result via JSON.
 * The result looks like:
 * {"total_rows":2,"offset":0,"rows":[
 * {"id":"76561198024979346","key":"76561198024979346","value":"darkid"}
 * ]}
 * So I want data["rows"]["value"].
 */

public OnPluginStart() {
	new Handle:socket = SocketCreate(SOCKET_TCP, OnSocketError);
	new Handle:hFile = OpenFile("dl.htm", "wb");
	SocketSetArg(socket, hFile);
	// connect the socket
	SocketConnect(socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, "l4d2statistics.cloudant.com", 80)
	HookEvent("player_team", EventHook:PlayerJoin, EventHookMode_PostNoCopy);
}

public PlayerJoin(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client && IsClientInGame(client) && IsClientConnected(client)) {
		new String:steamId[64];
		GetClientAuthString(client, steamId, sizeof(steamId));
		new String:nickname[64];
		GetPlayerNickname(nickname, sizeof(nickname), steamId);
		FakeClientCommand(client, "setinfo name \"%s\"", nickname);
	}
}

public OnSocketConnected(String:url, String:location) {
	new Handle:socket = SocketCreate(SOCKET_TCP, OnSocketError);
	new Handle:hFile = OpenFile(location, "wb");
	SocketSetArg(socket, hFile);
	SocketConnect(socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, "www.sourcemod.net", 80)
}

public OnSocketConnected(Handle:socket, any:arg) {
	// socket is connected, send the http request
	decl String:requestStr[100];
	Format(requestStr, sizeof(requestStr), "GET /%s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n", "index.php", "www.sourcemod.net");
	SocketSend(socket, requestStr);
}

public OnSocketReceive(Handle:socket, String:receiveData[], const dataSize, any:hFile) {
	// receive another chunk and write it to <modfolder>/dl.htm
	// we could strip the http response header here, but for example's sake we'll leave it in

	WriteFileString(hFile, receiveData, false);
}

public OnSocketDisconnected(Handle:socket, any:hFile) {
	// Connection: close advises the webserver to close the connection when the transfer is finished
	// we're done here

	CloseHandle(hFile);
	CloseHandle(socket);
}

public OnSocketError(Handle:socket, const errorType, const errorNum, any:hFile) {
	// a socket error occured

	LogError("socket error %d (errno %d)", errorType, errorNum);
	CloseHandle(hFile);
	CloseHandle(socket);
}
