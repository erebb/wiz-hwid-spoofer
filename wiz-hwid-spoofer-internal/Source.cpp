#include <winsock2.h>
#include <Windows.h>
#include "MinHook.h"
#include "spoof.hpp"
#include <tchar.h>
#include <Psapi.h>
#include <strsafe.h>
#include <thread>
#include "../wiz-hwid-spoofer/file_handler.hpp"

struct RawSMBIOSData
{
	BYTE    Used20CallingMethod;
	BYTE    SMBIOSMajorVersion;
	BYTE    SMBIOSMinorVersion;
	BYTE    DmiRevision;
	DWORD   Length;
	BYTE    SMBIOSTableData[];
};

typedef struct _dmi_header
{
	BYTE type;
	BYTE length;
	WORD handle;
}dmi_header;

unsigned int(__stdcall* o_GetSystemFirmwareTable)(DWORD FirmwareTableProviderSignature, DWORD FirmwareTableID, PVOID pFirmwareTableBuffer, DWORD BufferSize);

uint8_t ad1;
uint8_t ad2;
uint8_t ad3;
uint8_t ad4;
uint8_t ad5;
uint8_t ad6;

// THIS IS SUPER HACKY but i just overwrite all integer values
unsigned int __stdcall GetSystemFirmwareTable_h(DWORD FirmwareTableProviderSignature, DWORD FirmwareTableID, PVOID pFirmwareTableBuffer, DWORD BufferSize) // default value: {HW-ID-SMBIOS}
{
	if (pFirmwareTableBuffer == nullptr) { // they are just querying size
		return o_GetSystemFirmwareTable(FirmwareTableProviderSignature, FirmwareTableID, pFirmwareTableBuffer, BufferSize);
	}
	const auto ret = o_GetSystemFirmwareTable(FirmwareTableProviderSignature, FirmwareTableID, pFirmwareTableBuffer, BufferSize);
	auto* Smbios = reinterpret_cast<RawSMBIOSData*>(pFirmwareTableBuffer);
	auto p = 0;
	auto sidcount = 0;
	for (auto i = 0; i < Smbios->Length; i++) {
		const auto h = reinterpret_cast<dmi_header*>(Smbios->SMBIOSTableData + p);
		srand(time(nullptr));
		if (h->type == 1)
		{
			if (sidcount == 0) { // mac is always first
				(Smbios->SMBIOSTableData + p + 0x8)[0] = ad1;
				(Smbios->SMBIOSTableData + p + 0x8)[1] = ad2;
				(Smbios->SMBIOSTableData + p + 0x8)[2] = ad3;
				(Smbios->SMBIOSTableData + p + 0x8)[3] = ad4;
				(Smbios->SMBIOSTableData + p + 0x8)[4] = ad5;
				(Smbios->SMBIOSTableData + p + 0x8)[5] = ad6;
				sidcount++;
				continue;
			}
		}
		for (auto x = 0; x < h->length; x++)
		{
			if (*(Smbios->SMBIOSTableData + p + x) != 0 && *(Smbios->SMBIOSTableData + p + x) != 0xff && *(Smbios->SMBIOSTableData + p + x) >= 0x30 && *(Smbios->SMBIOSTableData + p + x) <= 0x39) // is a number?
			{
				*(Smbios->SMBIOSTableData + p + x) = rand() % (0x39 - 0x30 + 1) + 0x30;
			}
		}
		p += h->length;
	}
	std::cout << "Spoofed smbios" << std::endl;
	return ret;
}

HANDLE(__stdcall* o_CreateFileA)(LPCSTR                lpFileName,
	DWORD                 dwDesiredAccess,
	DWORD                 dwShareMode,
	LPSECURITY_ATTRIBUTES lpSecurityAttributes,
	DWORD                 dwCreationDisposition,
	DWORD                 dwFlagsAndAttributes,
	HANDLE                hTemplateFile);

// uuid is read from C:\ProgramData\KingsIsle Entertainment\Wizard101\Data:CRC NTFS exploit

HANDLE __stdcall CreateFileA_h(LPCSTR lpFileName,
	DWORD                 dwDesiredAccess,
	DWORD                 dwShareMode,
	LPSECURITY_ATTRIBUTES lpSecurityAttributes,
	DWORD                 dwCreationDisposition,
	DWORD                 dwFlagsAndAttributes,
	HANDLE                hTemplateFile)
{
	const auto ret = o_CreateFileA(lpFileName, dwDesiredAccess, dwShareMode, lpSecurityAttributes, dwCreationDisposition, dwFlagsAndAttributes, hTemplateFile);
	if (dwDesiredAccess == 0x80000000 && dwShareMode == 1 && lpSecurityAttributes == nullptr && dwCreationDisposition == 3 && dwFlagsAndAttributes == 0x80 && hTemplateFile == nullptr)
	{
		std::cout << "Spoofed uuid" << std::endl;
		return reinterpret_cast<void*>(-1); // this forces them to read from registry
	}
	return ret;
}

int(__stdcall* o_GetAdaptersInfo)(PIP_ADAPTER_INFO AdapterInfo, PULONG SizePointer);
int __stdcall GetAdaptersInfo_h(PIP_ADAPTER_INFO AdapterInfo, PULONG SizePointer) {
	if (o_GetAdaptersInfo(AdapterInfo, SizePointer) == NO_ERROR) {
		const auto oAdapterInfo = AdapterInfo;
		uint8_t it = 0;
		while (AdapterInfo)
		{
			AdapterInfo->Address[0] = ad1 + it;
			AdapterInfo->Address[1] = ad2 + it;
			AdapterInfo->Address[2] = ad3 + it;
			AdapterInfo->Address[3] = ad4 + it;
			AdapterInfo->Address[4] = ad5 + it;
			AdapterInfo->Address[5] = ad6 + it;
			AdapterInfo = AdapterInfo->Next;
			it++;
		}
		AdapterInfo = oAdapterInfo;
		std::cout << "Spoofed mac" << std::endl;
		return NO_ERROR;
	}
	return ERROR_NO_DATA;
}

void set_hwid(std::string hwid) // this is ugly but i wanted to get it out if someone makes a pull request with a better solution i would appreciate
{
	std::string a1;
	a1 += hwid[0];
	a1 += hwid[1];
	a1.erase(0, min(a1.find_first_not_of('0'), a1.size() - 1));
	ad1 = std::stoi(a1, nullptr, 16);

	std::string a2;
	a2 += hwid[4];
	a2 += hwid[5];
	a2.erase(0, min(a2.find_first_not_of('0'), a2.size() - 1));
	ad2 = std::stoi(a2, nullptr, 16);

	std::string a3;
	a3 += hwid[8];
	a3 += hwid[9];
	a3.erase(0, min(a3.find_first_not_of('0'), a3.size() - 1));
	ad3 = std::stoi(a3, nullptr, 16);

	std::string a4;
	a4 += hwid[12];
	a4 += hwid[13];
	a4.erase(0, min(a4.find_first_not_of('0'), a4.size() - 1));
	ad4 = std::stoi(a4, nullptr, 16);

	std::string a5;
	a5 += hwid[16];
	a5 += hwid[17];
	a5.erase(0, min(a5.find_first_not_of('0'), a5.size() - 1));
	ad5 = std::stoi(a5, nullptr, 16);

	std::string a6;
	a6 += hwid[20];
	a6 += hwid[21];
	a6.erase(0, min(a6.find_first_not_of('0'), a6.size() - 1));
	ad6 = std::stoi(a6, nullptr, 16);
}

ATOM self;
void __stdcall main() {
	AllocConsole();
	FILE* v;
	freopen_s(&v, "CONIN$", "r", stdin);
	freopen_s(&v, "CONOUT$", "w", stdout);
	freopen_s(&v, "CONOUT$", "w", stderr);
	if (v != nullptr) {
		fclose(v);
	}
	
	self = GlobalAddAtomA("ClipboardRootDataObject");

	std::string hwid;
	std::string uuid;
	settings_handler.read_conf(hwid, uuid);
	set_hwid(hwid);

	set_uuid(uuid);
	set_username("DONT USE LAUNCHER!");

	MH_Initialize();

	const auto kern32 = GetModuleHandle("Kernel32.dll");
	if (kern32) {
		const LPVOID gsft_addr = GetProcAddress(kern32, "GetSystemFirmwareTable");
		MH_CreateHook(gsft_addr, &GetSystemFirmwareTable_h, reinterpret_cast<LPVOID*>(&o_GetSystemFirmwareTable));
		MH_EnableHook(gsft_addr);

		const LPVOID createfileaadr = GetProcAddress(kern32, "CreateFileA");
		MH_CreateHook(createfileaadr, &CreateFileA_h, reinterpret_cast<LPVOID*>(&o_CreateFileA));
		MH_EnableHook(createfileaadr);
	}

	auto Iphlapi = GetModuleHandle("Iphlpapi.dll");
	while (!Iphlapi) {
		Iphlapi = GetModuleHandle("Iphlpapi.dll");
		Sleep(50);
	}
	const LPVOID gai_address = GetProcAddress(Iphlapi, "GetAdaptersInfo");
	MH_CreateHook(gai_address, &GetAdaptersInfo_h, reinterpret_cast<LPVOID*>(&o_GetAdaptersInfo));
	MH_EnableHook(gai_address);
}

BOOL APIENTRY DllMain(HMODULE Module, DWORD Reason, void* Reserved) {
	if (Reason == DLL_PROCESS_ATTACH) {
		CreateThread(nullptr, NULL, reinterpret_cast<LPTHREAD_START_ROUTINE>(main), nullptr, NULL, nullptr);
	} else if (Reason == DLL_PROCESS_DETACH)
	{
		GlobalDeleteAtom(self);
	}
	return TRUE;
}