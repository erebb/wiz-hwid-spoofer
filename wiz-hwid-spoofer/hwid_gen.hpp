#pragma once
#include <string>
#include <algorithm>
#include <combaseapi.h>
#include <iomanip>

inline std::string generate_uuid()
{
    GUID uuid;
    if (CoCreateGuid(&uuid) != S_OK)
    {
        return "";
    }
	
    CHAR* wsz_uuid = nullptr;
    if (UuidToStringA(&uuid, reinterpret_cast<RPC_CSTR*>(&wsz_uuid)) != RPC_S_OK)
    {
        return "";
    }
    if (wsz_uuid != nullptr)
    {
        std::string uuid_str(wsz_uuid);
        std::transform(
            uuid_str.begin(), uuid_str.end(),
            uuid_str.begin(),
            toupper);
        uuid_str = "{" + uuid_str + "}";
        return uuid_str;
    }
    return std::string("");
}

inline std::string generate_hwid()
{
    std::string ret;
    srand(time(nullptr));
	for (auto i = 0; i < 6; i++)
	{
        char hexchar[3];
        sprintf_s(hexchar, "%02X", rand() % 0xff);
        ret += hexchar;
        if (i != 5)
            ret += "::";
	}
    return ret;
}