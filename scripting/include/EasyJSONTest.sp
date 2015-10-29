#include <sourcemod>
#include <EasyJSON>

public OnPluginStart() {
	new Handle:jsonObject = CreateJSON();

	JSONSetInteger(jsonObject, "int", 42);
	decl integer;
	if (JSONGetInteger(jsonObject, "other", integer)) {
		PrintToServer("\tGot value that didn't exist.");
	} else if (JSONGetInteger(jsonObject, "int", integer)) {
		if (integer != 42) {
			PrintToServer("\tGetInteger returned the wrong value: %d", integer);
		} else {
			RemoveFromJSON(jsonObject, "int");
			if (JSONGetInteger(jsonObject, "int", integer)) {
				PrintToServer("\tInteger wasn't destroyed.");
			} else {
				PrintToServer("Integer test passed.");
			}
		}
	} else {
		PrintToServer("\tCouldn't get defined integer value from object.");
	}

	JSONSetBoolean(jsonObject, "bool", true);
	decl bool:boolean;
	if (JSONGetBoolean(jsonObject, "other", boolean)) {
		PrintToServer("\tGot value that didn't exist.");
	} else if (JSONGetBoolean(jsonObject, "bool", boolean)) {
		if (boolean != true) {
			PrintToServer("\tGetBoolean returned the wrong value: false");
		} else {
			RemoveFromJSON(jsonObject, "bool");
			if (JSONGetBoolean(jsonObject, "bool", boolean)) {
				PrintToServer("\tBoolean wasn't destroyed.");
			} else {
				PrintToServer("Boolean test passed.");
			}
		}
	} else {
		PrintToServer("\tCouldn't get defined boolean value from object.");
	}

	JSONSetFloat(jsonObject, "float", 3.7);
	decl Float:floating;
	if (JSONGetFloat(jsonObject, "other", floating)) {
		PrintToServer("\tGot value that didn't exist.");
	} else if (JSONGetFloat(jsonObject, "float", floating)) {
		if (floating != 3.7) {
			PrintToServer("\tGetFloat returned the wrong value: %f", floating);
		} else {
			RemoveFromJSON(jsonObject, "float");
			if (JSONGetFloat(jsonObject, "float", floating)) {
				PrintToServer("\tFloat wasn't destroyed.");
			} else {
				PrintToServer("Float test passed.");
			}
		}
	} else {
		PrintToServer("\tCouldn't get defined float value from object.");
	}

	JSONSetString(jsonObject, "str", "carrot");
	decl String:str[8];
	if (JSONGetString(jsonObject, "other", str, sizeof(str))) {
		PrintToServer("\tGot value that didn't exist.");
	} else if (JSONGetString(jsonObject, "str", str, sizeof(str))) {
		if (strcmp(str, "carrot") != 0) {
			PrintToServer("\tGetString returned the wrong value: %s", str);
		} else {
			RemoveFromJSON(jsonObject, "str");
			if (JSONGetString(jsonObject, "str", str, sizeof(str))) {
				PrintToServer("\tString wasn't destroyed.");
			} else {
				PrintToServer("String test passed.");
			}
		}
	} else {
		PrintToServer("\tCouldn't get defined string value from object.");
	}

	new Handle:jsonArray = CreateArray();
	JSONPushArrayInteger(jsonArray, 42);

	integer = -1;
	// I can't check out-of-bounds, since GetArrayCell will just fail. Trust me that you can't get things out of range, k?
	if (JSONGetArrayInteger(jsonArray, 0, integer)) {
		if (integer != 42) {
			PrintToServer("\tGetArrayInteger returned the wrong value: %d", integer);
		} else {
			PrintToServer("Array Integer test passed.")
		}
	} else {
		PrintToServer("\tCouldn't get defined integer value from array.");
	}

	JSONPushArrayString(jsonArray, "pickle");

	str = "";
	if (JSONGetArrayString(jsonArray, 1, str, sizeof(str))) {
		if (strcmp(str, "pickle") != 0) {
			PrintToServer("\tGetArrayString returned the wrong value: %s", str);
		} else {
			PrintToServer("Array String test passed.")
		}
	} else {
		PrintToServer("\tCouldn't get defined string value from array.");
	}

}