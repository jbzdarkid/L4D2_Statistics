#include <sourcemod>
#include <SteamWorks>

public Plugin:myinfo = {
	name = "Test",
	author = "Darkid",
	description = "Work dammit",
	version = "0Alpha",
	url = "none"
};

public OnPluginStart() {
	RegConsoleCmd("find_darkid", FindDarkid);
}

stock PrintToConsoleAll(const String:format[], any:...)
{
	decl String:text[192];
	for (new x = 1; x <= MaxClients; x++)
	{
		if (IsClientInGame(x))
		{
			SetGlobalTransTarget(x);
			VFormat(text, sizeof(text), format, 2);
			PrintToConsole(x, text);
		}
	}
}

public Action:FindDarkid(client, args) {
	client = 1;
	if (client != 0 && IsClientInGame(client) && IsClientConnected(client)) {
		new String:steamId[64];
		GetClientAuthString(client, steamId, sizeof(steamId));
		new String:shortId[9];
		for (new i=0; i<sizeof(shortId); i++) {
			shortId[i] = steamId[i+10];
		}
		PrintToConsoleAll("[Debug] Steam Short id: %s", shortId);
		PrintToConsoleAll("[Debug]");
		new Handle:request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, "https://l4d2statistics.cloudant.com/us_test/_design/nickname/_view/nickname");
		// SteamWorks_SetHTTPRequestGetOrPostParameter(request, "key", steamId);
		SteamWorks_SetHTTPRequestGetOrPostParameter(request, "format", "txt" );
		SteamWorks_SetHTTPCallbacks(request, NicknameCallback);
		SteamWorks_SendHTTPRequest(request);
	}
}
	
public NicknameCallback(Handle:hRequest, bool:bFailure, bool:bRequestSuccessful, EHTTPStatusCode:eStatusCode) {
	decl requestSize;
	SteamWorks_GetHTTPResponseBodySize(hRequest, requestSize);
	decl String:requestResponse[requestSize];
	SteamWorks_GetHTTPResponseBodyData(hRequest, requestResponse, requestSize);
	new nickLength = requestSize-87;
	new String:nickname[nickLength];
	for (new i=0; i<nickLength-1; i++) {
		nickname[i] = requestResponse[i+80];
	}
	nickname[nickLength-1] = 0;
	PrintToConsoleAll("Nickname: %s", nickname);
	// JSON:JsonResponse = json_decode(requestResponse)
	// decl JSON:Rows;
	// json_get_cell(JsonResponse, "rows", *Rows)
	// decl JSON:DumbArray;
	// json_get_array()
	// FakeClientCommand(client, "setinfo name \"%s\"", nickname);
}