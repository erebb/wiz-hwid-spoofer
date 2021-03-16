#pragma once
#include <fstream>
#include <commdlg.h>

inline struct settings
{
	static void write_conf(const std::string &hwid, const std::string &uuid)
	{
		std::ofstream conf_file(R"(C:/ProgramData/KingsIsle Entertainment/Wizard101/Bin/spoofer.config)");
		if (conf_file) {
			conf_file << hwid; // garunteed 22 characters
			conf_file << uuid; // garunteed 38 characters (32 but including four '-', '{' and '}'
			conf_file.close();
		}
	}

	static bool read_conf(std::string &hwid, std::string &uuid)
	{
		std::ifstream conf_file(R"(C:/ProgramData/KingsIsle Entertainment/Wizard101/Bin/spoofer.config)");
		if (conf_file)
		{
			const std::string whole((std::istreambuf_iterator<char>(conf_file)),
				std::istreambuf_iterator<char>());

			const auto uuid_start = whole.find('{');
			hwid = whole.substr(0, uuid_start);
			uuid = whole.substr(uuid_start, whole.find('}'));

			conf_file.close();
			return true;
		}
		return false;
	}
} settings_handler;

inline bool is_in_startup()
{
	HKEY Handle_Key = nullptr;
	RegOpenKeyEx(HKEY_CURRENT_USER,
		R"(Software\Microsoft\Windows\CurrentVersion\Run)",
		0,
		KEY_ALL_ACCESS,
		&Handle_Key);
	DWORD dwType;
	return RegQueryValueEx(Handle_Key, "Wizard101 Spoofer", nullptr, &dwType, nullptr, nullptr) == ERROR_SUCCESS;
}

inline void add_to_startup() // %appdata%\Microsoft\Windows\Start Menu\Programs\Startup
{
	TCHAR szFilepath[MAX_PATH];

	/* Get the current executable's full path */
	GetModuleFileName(nullptr, szFilepath, MAX_PATH);

	HKEY Handle_Key = nullptr;
	
	RegOpenKeyEx(HKEY_CURRENT_USER,
		R"(Software\Microsoft\Windows\CurrentVersion\Run)",
		0,
		KEY_ALL_ACCESS,
		&Handle_Key);
	RegSetValueEx(Handle_Key, "Wizard101 Spoofer", 0, 1, reinterpret_cast<uint8_t*>(szFilepath), MAX_PATH);
}

inline void remove_from_startup()
{
	HKEY Handle_Key = nullptr;
	RegOpenKeyEx(HKEY_CURRENT_USER,
		R"(Software\Microsoft\Windows\CurrentVersion\Run)",
		0,
		KEY_ALL_ACCESS,
		&Handle_Key);
	RegDeleteValue(Handle_Key, "Wizard101 Spoofer");
}