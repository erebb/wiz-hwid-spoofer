#pragma once
#include <iostream>
#include <random>
#include "minhook/MinHook.h"
#include "Config.hpp"

#ifdef _WIN64
#pragma comment(lib, "minhook/VC16/lib/Release/libMinHook.x64.lib")
#else
#pragma comment(lib, "minhook/VC16/lib/Release/libMinHook.x86.lib")
#endif

struct RawSMBIOSData
{
	BYTE    Used20CallingMethod;
	BYTE    SMBIOSMajorVersion;
	BYTE    SMBIOSMinorVersion;
	BYTE    DmiRevision;
	DWORD    Length;
	BYTE    SMBIOSTableData[];
};

struct dmi_header
{
    BYTE type;
    BYTE length;
    WORD handle;
    BYTE data[1];
};

unsigned int(__stdcall* GetSystemFirmwareTable_orig)(DWORD FirmwareTableProviderSignature, DWORD FirmwareTableID, PVOID pFirmwareTableBuffer, DWORD BufferSize);
unsigned int __stdcall GetSystemFirmwareTable_hook(DWORD FirmwareTableProviderSignature, DWORD FirmwareTableID, PVOID pFirmwareTableBuffer, DWORD BufferSize) {
    printf("OOPS SMBIOS!\n");

    if (pFirmwareTableBuffer == nullptr) { // they are just querying size
        return GetSystemFirmwareTable_orig(FirmwareTableProviderSignature, FirmwareTableID, pFirmwareTableBuffer, BufferSize);
    }

    const auto orig_ret = GetSystemFirmwareTable_orig(FirmwareTableProviderSignature, FirmwareTableID, pFirmwareTableBuffer, BufferSize); 

    HWIDConfig conf;
    const auto mac = conf.get_mac();
    const auto num_smbios = conf.get_num_smbios();
    const auto ascii_smbios = conf.get_ascii_smbios();

    printf("mac\n");
    for (auto x : conf.get_mac()) {
        printf("%02X ", x);
    }
    printf("\n\n");

    printf("smbios\n");
    for (auto x : conf.get_num_smbios()) {
        printf("%02X ", x);
    }
    printf("\n\n");

    for (auto x : conf.get_ascii_smbios()) {
        printf("%c", x);
    }
    printf("\n\n");

    auto* Smbios = reinterpret_cast<RawSMBIOSData*>(pFirmwareTableBuffer);
    auto p = 0;
    auto sid_count = 0;
    for (auto i = 0; i < Smbios->Length; i++) {
        const auto h = reinterpret_cast<dmi_header*>(Smbios->SMBIOSTableData + p);

        if (h->type == 1)
        {
            if (sid_count == 0) { // mac is always first
                for (auto m = 0; m < 6; m++) {
                    (Smbios->SMBIOSTableData + p + i)[m] = mac.at(m);
                }
                sid_count++;
                continue;
            }
        }

        for (auto x = 0; x < h->length; x++)
        {
            if (*(Smbios->SMBIOSTableData + p + x) != 0 && *(Smbios->SMBIOSTableData + p + x) != 0xff && *(Smbios->SMBIOSTableData + p + x) >= 0x30 && *(Smbios->SMBIOSTableData + p + x) <= 0x39) // is a number?
                *(Smbios->SMBIOSTableData + p + x) = num_smbios.at(x);
            else if (*(Smbios->SMBIOSTableData + p + x) >= 0x41 && *(Smbios->SMBIOSTableData + p + x) <= 0x7A) // is ascii character
                *(Smbios->SMBIOSTableData + p + x) = ascii_smbios.at(x);
        }
        p += h->length;
    }

    printf("spoofed smbios\n");


    return orig_ret;
}

HANDLE(__stdcall* o_CreateFileA)(LPCSTR                lpFileName,
    DWORD                 dwDesiredAccess,
    DWORD                 dwShareMode,
    LPSECURITY_ATTRIBUTES lpSecurityAttributes,
    DWORD                 dwCreationDisposition,
    DWORD                 dwFlagsAndAttributes,
    HANDLE                hTemplateFile);

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
        printf("spoofed fileread (check reg for new uuid)\n");

        return reinterpret_cast<void*>(-1); // this forces them to read from registry
    }
    return ret;
}

HMODULE me;
bool (__stdcall* FreeLibrary_orig)(HMODULE hLibModule);
bool __stdcall FreeLibrary_hook(HMODULE hLibModule) {
    if (hLibModule == me) {
        printf("stopping self from unloading\n");
        return 1;
    }
    return FreeLibrary_orig(hLibModule);
}

void hook_free() {
    auto kern32 = LoadLibrary(L"Kernel32.dll");
    const auto adr = GetProcAddress(kern32, "FreeLibrary");
    MH_CreateHook(adr, &FreeLibrary_hook, reinterpret_cast<LPVOID*>(&FreeLibrary_orig));
    MH_EnableHook(adr);
}

void hook_k32() {
    const auto kernbase = GetModuleHandle(L"KernelBase.dll");
#ifdef _WIN64
    const LPVOID gsft_addr = GetProcAddress(kernbase, MAKEINTRESOURCEA(751)); // ordinal 751.. might not work for multiple versions of windows, couldn't get by name for some reason?
#else
    const LPVOID gsft_addr = GetProcAddress(kernbase, MAKEINTRESOURCEA(754)); // ordinal 754.. might not work for multiple versions of windows, couldn't get by name for some reason?
#endif
    auto t = MH_CreateHook(gsft_addr, &GetSystemFirmwareTable_hook, reinterpret_cast<LPVOID*>(&GetSystemFirmwareTable_orig));
    MH_EnableHook(gsft_addr);

    const auto kern32 = GetModuleHandle(L"Kernel32.dll");
    const LPVOID createfileaadr = GetProcAddress(kern32, "CreateFileA");
    MH_CreateHook(createfileaadr, &CreateFileA_h, reinterpret_cast<LPVOID*>(&o_CreateFileA));
    MH_EnableHook(createfileaadr);
}