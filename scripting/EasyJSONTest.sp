#include <sourcemod>
#include <EasyJSON>

public OnPluginStart() {
	new Handle:jsonObject = CreateJSON();

	JSONSetInteger(jsonObject, "int", 42);
	decl integer;
	if (JSONGetInteger(jsonObject, "other", integer)) {
		SetFailState("Got value that didn't exist.");
	} else if (JSONGetInteger(jsonObject, "int", integer)) {
		if (integer != 42) {
			SetFailState("GetInteger returned the wrong value: %d", integer);
		} else {
			RemoveFromJSON(jsonObject, "int");
			if (JSONGetInteger(jsonObject, "int", integer)) {
				SetFailState("Integer wasn't destroyed.");
			} else {
				PrintToServer("Integer test passed.");
			}
		}
	} else {
		SetFailState("Couldn't get defined integer value from object.");
	}

	JSONSetBoolean(jsonObject, "bool", true);
	decl bool:boolean;
	if (JSONGetBoolean(jsonObject, "other", boolean)) {
		SetFailState("Got value that didn't exist.");
	} else if (JSONGetBoolean(jsonObject, "bool", boolean)) {
		if (boolean != true) {
			SetFailState("GetBoolean returned the wrong value: false");
		} else {
			RemoveFromJSON(jsonObject, "bool");
			if (JSONGetBoolean(jsonObject, "bool", boolean)) {
				SetFailState("Boolean wasn't destroyed.");
			} else {
				PrintToServer("Boolean test passed.");
			}
		}
	} else {
		SetFailState("Couldn't get defined boolean value from object.");
	}

	JSONSetFloat(jsonObject, "float", 3.7);
	decl Float:floating;
	if (JSONGetFloat(jsonObject, "other", floating)) {
		SetFailState("Got value that didn't exist.");
	} else if (JSONGetFloat(jsonObject, "float", floating)) {
		if (floating != 3.7) {
			SetFailState("GetFloat returned the wrong value: %f", floating);
		} else {
			RemoveFromJSON(jsonObject, "float");
			if (JSONGetFloat(jsonObject, "float", floating)) {
				SetFailState("Float wasn't destroyed.");
			} else {
				PrintToServer("Float test passed.");
			}
		}
	} else {
		SetFailState("Couldn't get defined float value from object.");
	}

	JSONSetString(jsonObject, "str", "carrot");
	decl String:str[8];
	if (JSONGetString(jsonObject, "other", str, sizeof(str))) {
		SetFailState("Got value that didn't exist.");
	} else if (JSONGetString(jsonObject, "str", str, sizeof(str))) {
		if (strcmp(str, "carrot") != 0) {
			SetFailState("GetString returned the wrong value: %s", str);
		} else {
			RemoveFromJSON(jsonObject, "str");
			if (JSONGetString(jsonObject, "str", str, sizeof(str))) {
				SetFailState("String wasn't destroyed.");
			} else {
				PrintToServer("String test passed.");
			}
		}
	} else {
		SetFailState("Couldn't get defined string value from object.");
	}

	new Handle:jsonArray = CreateArray();
	JSONPushArrayInteger(jsonArray, 18);

	// I can't check out-of-bounds, since GetArrayCell will just SetFailState. Trust me that you can't get things out of range, k?
	if (JSONGetArrayInteger(jsonArray, 0, integer)) {
		if (integer != 18) {
			SetFailState("GetArrayInteger returned the wrong value: %d", integer);
		} else {
			PrintToServer("Array Integer test passed.")
		}
	} else {
		SetFailState("Couldn't get defined integer value from array.");
	}

	JSONPushArrayString(jsonArray, "pickle");

	if (JSONGetArrayString(jsonArray, 1, str, sizeof(str))) {
		if (strcmp(str, "pickle") != 0) {
			SetFailState("GetArrayString returned the wrong value: %s", str);
		} else {
			PrintToServer("ArrayString test passed.")
		}
	} else {
		SetFailState("Couldn't get defined string value from array.");
	}

	JSONPushArrayBoolean(jsonArray, true);

	if (JSONGetArrayBoolean(jsonArray, 2, boolean)) {
		if (boolean != true) {
			SetFailState("GetArrayString returned the wrong value: %s", str);
		} else {
			PrintToServer("ArrayBoolean test passed.")
		}
	} else {
		SetFailState("Couldn't get defined string value from array.");
	}

	JSONPushArrayFloat(jsonArray, -4.0);

	if (JSONGetArrayFloat(jsonArray, 3, floating)) {
		if (floating != -4.0) {
			SetFailState("GetArrayFloat returned the wrong value: %f", floating);
		} else {
			PrintToServer("ArrayFloat test passed.")
		}
	} else {
		SetFailState("Couldn't get defined string value from array.");
	}

	decl String:encode[128];
	EncodeArray(jsonArray, encode, sizeof(encode), false);
	decl String:compare[128];
	Format(compare, sizeof(compare), "[%d,\"%s\",true,%7.6f]", integer, str, floating);
	if (strcmp(encode, compare) != 0) {
		SetFailState("EncodeArray test failed.")
	} else {
		PrintToServer("EncodeArray test passed.");
	}

	JSONSetArray(jsonObject, "array", jsonArray);
	encode = "";
	EncodeJSON(jsonObject, encode, sizeof(encode), false);
	Format(compare, sizeof(compare), "{\"array\": %s}", compare);
	if (strcmp(encode, compare) != 0) {
		SetFailState("EncodeObject test failed.")
	} else {
		PrintToServer("EncodeObject test passed.");
	}
}