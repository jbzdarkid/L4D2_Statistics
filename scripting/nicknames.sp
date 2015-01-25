#include <sourcemod>
#include <SteamWorks>
#include <json>

public Plugin:myinfo = {
	name = "Set player names from a database",
	author = "Darkid",
	description = "Players joining a server will have their nicknames set to a nickname to reduce confusion",
	version = "1.0",
	url = "https://github.com/jbzdarkid/L4D2_Statistics/blob/master/scripting/nicknames.sp"
};

/* I want to send an HTTP GET request to
 * https://l4d2statistics.cloudant.com/us_test/_design/nickname/_view/nickname?key=\"76561198024979346\"
 * and then parse the result via JSON.
 * The result looks like:
 * {"total_rows":2,"offset":0,"rows":[
 * {"id":"76561198024979346","key":"76561198024979346","value":"darkid"}
 * ]}
 * So I want data["rows"]["value"].
 */

public OnPluginStart() {
	HookEvent("player_team", EventHook:PlayerJoin, EventHookMode_PostNoCopy);
}

public PlayerJoin(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client && IsClientInGame(client) && IsClientConnected(client)) {
		new String:steamId[64];
		GetClientAuthString(client, steamId, sizeof(steamId));
		new String:nickname[64];
		
		new Handle:request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, "http://l4d2statistics.cloudant.com/us_test/_design/nickname/_view/nickname");
		SteamWorks_SetHTTPRequestGetOrPostParameter(request, "key", steamID);
		SteamWorks_SetHTTPRequestGetOrPostParameter(request, "format", "txt" );
		SteamWorks_SetHTTPCallbacks(request, NicknameCallback);
		SteamWorks_SendHTTPRequest(request);
	}
}

NicknameCallback(Handle:request, bool:bIOFailure, bool:successful, EHTTPStatusCode:status) {
	decl requestSize;
	if (SteamWorks_GetHTTPResponseBodySize(request, *requestSize)) {
		decl String:requestResponse[requestSize];
		SteamWorks_GetHTTPResponseBodyData(request, requestResponse, requestSize);
		JSON:JsonResponse = json_decode(requestResponse)
		decl JSON:Rows;
		json_get_cell(JsonResponse, "rows", *Rows)
		// decl JSON:DumbArray;
		// json_get_array()
		FakeClientCommand(client, "setinfo name \"%s\"", nickname);

	}
}