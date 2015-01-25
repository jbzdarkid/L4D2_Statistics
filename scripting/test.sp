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
	PrintToConsoleAll("[Debug] HI");
	PrintToConsoleAll("[Debug] Trying to find client 1...");
	if (client !=0 && IsClientInGame(client) && IsClientConnected(client)) {
		new String:steamId[64];
		GetClientAuthString(client, steamId, sizeof(steamId));
		PrintToConsoleAll("[Debug] Player %d name: %s", client, steamId);
		new String:shortId[8];
		for (new i=10; i<18; i++) {
			shortId[i-10] = steamId[i];
		}
		PrintToConsoleAll("[Debug] Short id: %s", shortId);
		new Handle:request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, "http://l4d2statistics.cloudant.com/us_test/_design/nickname/_view/nickname");
		SteamWorks_SetHTTPRequestGetOrPostParameter(request, "key", steamId);
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
	PrintToConsoleAll("%s", requestResponse);
	// JSON:JsonResponse = json_decode(requestResponse)
	// decl JSON:Rows;
	// json_get_cell(JsonResponse, "rows", *Rows)
	// decl JSON:DumbArray;
	// json_get_array()
	// FakeClientCommand(client, "setinfo name \"%s\"", nickname);
}