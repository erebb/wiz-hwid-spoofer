#include <iostream>
#include <fstream>
#include <Urlmon.h>
#pragma comment(lib, "Urlmon.lib")
#include "../common/Config.hpp"

void delete_uuid()
{
	HKEY res;
	if (RegOpenKeyExA(HKEY_CURRENT_USER, "Software\\KingsIsle", 0, KEY_ALL_ACCESS, &res) == NO_ERROR) {
		const auto ret = RegDeleteValueA(res, "UUID");
		if (ret != NO_ERROR) {
			std::cerr << "Error deleting key... send to xgladius#8968 on discord: " << ret << std::endl;
		}
	}
	else {
		std::cerr << "Error opening key... send to xgladius#8968 on discord: " << GetLastError() << std::endl;
	}
}

void main() {
	if (CopyFile(L"dbghelp.dll", L"C:/ProgramData/KingsIsle Entertainment/Wizard101/PatchClient/BankA/dbghelp.dll", false) == 0) {
		std::cerr << "Failed to copy launcher dependancy... send to xgladius#8968 on discord: " << GetLastError() << std::endl;
	}

	if (CopyFile(L"dbghelp.dll", L"C:/ProgramData/KingsIsle Entertainment/Wizard101/PatchClient/BankB/dbghelp.dll", false) == 0) {
		std::cerr << "Failed to copy launcher dependancy... send to xgladius#8968 on discord: " << GetLastError() << std::endl;
	}

	if (CopyFile(L"WizardCommandLineCSR.dll", L"C:/ProgramData/KingsIsle Entertainment/Wizard101/Bin/WizardCommandLineCSR.dll", false) == 0) {
		std::cerr << "Failed to copy client dependancy... send to xgladius#8968 on discord: " << GetLastError() << std::endl;
	}

	delete_uuid();

	HWIDConfig config;
	config.new_mac();
	config.new_smbios();
	config.write();

	std::cout << "Installed sucessfully. Enjoy playing!" << std::endl;
	system("pause");
}
