#include <sourcemod>
#include <socket> // For talking to CouchDB
#include <EasyJSON> // For interpreting CouchDB
#pragma semicolon 1

#define ID_SIZE 64
#define NAME_SIZE 256
#define REV_SIZE 64
#define ERROR_SIZE 256

public Plugin:myinfo = {
    name = "Logging",
    author = "Darkid",
    description = "Logging events in the game, to be analyzed later.",
    version = "1.0",
    url = "www.github.com/jbzdarkid/L4D2_Statistics"
};

new Handle:log;

public OnPluginStart() {
    log = CreateArray(1);
    HookEvent("player_hurt", PlayerHurt);
}

// **************** Utility functions ****************
// Truncates off the STEAM_1:X: from steam names.
GetSteamId(client, String:output[]) {
    new String:steamId[20];
    GetClientAuthString(client, steamId, ID_SIZE);
    strcopy(output, 9, steamId[10]);
    output[9] = 0;
}

// Verifies that the player is a real player in the game.
IsValidPlayer(client) {
    if (client <= 0 || client > MaxClients) return false;
    if (!IsClientInGame(client)) return false;
    if (IsFakeClient(client)) return false;
}

// Returns a json object of a lot of client information.
Handle:GetClientInfo(client) {
    new Handle:data = CreateJSON();
    decl String:steamId[ID_SIZE];
    GetSteamId(client, steamId);
    JSONSetString(data, "steamid", steamId);
    GetClientAbsOrigin(client, origin);
    new Handle:position = CreateArray(1);
    PushArrayCell(position, JSONCreateFloat(origin[0]));
    PushArrayCell(position, JSONCreateFloat(origin[1]));
    PushArrayCell(position, JSONCreateFloat(origin[2]));
    JSONSetArray(data, "position", position);
    new team = GetClientTeam(client);
    JSONSetInteger(data, "team", JSONCreateInteger(team));
    if (team == 3) {
        new class = GetEntProp(victim, Prop_Send, "m_zombieClass");
        JSONSetInteger(data, "class", JSONCreateInteger(class));
    }
    return data;
}

// **************** Events ****************
public PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast) {
    new victim = GetClientOfUserId(GetEventInt(event, "userid"));
    if (!IsValidPlayer(victim)) return;
    new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
    if (!IsValidPlayer(attacker)) return;
    new Handle:entry = CreateJSON();

    // Strings
    decl String:weapon[128];
    GetEventString(event, "weapon", weapon, sizeof(weapon));
    JSONSetString(entry, "weapon", JSONCreateString(weapon));

    // Integers
    JSONSetInteger(entry, "damage dealth", GetEventInt(event, "dmg_health"));
    JSONSetInteger(entry, "remaining health", GetEventInt(event, "health"));

    // Floats
    JSONSetFloat(entry, "timestamp", GetEngineTime());

    // Arrays

    // Objects
    new Handle:victimData = GetClientData(victim);
    JSONSetObject(entry, "victim", victimData);

    new Handle:attackerData = GetClientData(attacker);
    JSONSetObject(entry, "attacker", attackerData);

    decl String:debugStr[1024];
    EncodeJSON(entry, debugStr, sizeof(debugStr));
    PrintToChatAll(debugStr);

    PushArrayCell(log, entry);

}