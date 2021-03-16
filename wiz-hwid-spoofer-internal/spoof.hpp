#pragma once
#pragma comment(lib, "Rpcrt4.lib")
#include <string>
#include <Windows.h>
#include <iostream>
#pragma comment(lib, "iphlpapi.lib")
#include <Iphlpapi.h>

inline void set_key_str_val(const char* path, const char* key, std::string& value)
{
	std::cout << "Setting " << path << "\\" << key << " to " << value << std::endl;
	HKEY res;
	if (RegOpenKeyEx(HKEY_CURRENT_USER, path, 0, KEY_WRITE, &res) == NO_ERROR) {
		if (RegSetValueEx(res, key, 0, 1, reinterpret_cast<const byte*>(value.data()), value.size() * 2) != NO_ERROR)
		{
			std::cout << "Error setting uuid: " << GetLastError() << std::endl;
		}
		RegCloseKey(res);
	}
}

inline void set_uuid(std::string uuid_str_)
{
	set_key_str_val("Software\\KingsIsle", "UUID", uuid_str_);
}

inline void set_username(std::string username)
{
	set_key_str_val("Software\\KingsIsle\\Wizard101", "UserName", username);
}