#pragma once
#include <Windows.h>
#include <iostream>
#include <tlhelp32.h>
#include <Psapi.h>

bool has_module_loaded(DWORD pid, const char* name)
{
    const auto proc = OpenProcess(PROCESS_QUERY_INFORMATION |
        PROCESS_VM_READ,
        FALSE, pid);
	
    if (proc == nullptr)
        return false;

    DWORD cbNeeded;
    HMODULE hMods[1024];
    if (EnumProcessModules(proc, hMods, sizeof(hMods), &cbNeeded))
    {
        for (auto i = 0; i < (cbNeeded / sizeof(HMODULE)); i++)
        {
            TCHAR szModName[MAX_PATH];
            if (GetModuleFileNameEx(proc, hMods[i], szModName,
                sizeof(szModName) / sizeof(TCHAR)))
            {
                std::string rname = name;
                std::string pname = szModName;
                if (pname.find(rname) != std::string::npos) {
                    CloseHandle(proc);
                    return true;
                }
            }
        }
    }

    CloseHandle(proc);

    return false;
}

bool inject_dll(const int& pid, const std::string& path)
{
    const auto dll_size = path.length() + 1;
    const auto proc = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);

    if (proc == nullptr)
    {
        return false;
    }

    const auto alloc = VirtualAllocEx(proc, nullptr, dll_size, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    if (alloc == nullptr)
    {
        return false;
    }

    if (WriteProcessMemory(proc, alloc, path.c_str(), dll_size, nullptr) == 0)
    {
        return false;
    }

    DWORD thread_id;
    const auto load_lib_adr = reinterpret_cast<LPTHREAD_START_ROUTINE>(GetProcAddress(LoadLibrary("kernel32"), "LoadLibraryA"));
    if (CreateRemoteThread(proc, nullptr, 0, load_lib_adr, alloc, 0, &thread_id) == nullptr)
    {
        return false;
    }

    return true;
}

void check_and_inject()
{
    PROCESSENTRY32 entry;
    entry.dwSize = sizeof(PROCESSENTRY32);
    const auto snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, NULL);

    if (Process32First(snapshot, &entry) == TRUE)
    {
        while (Process32Next(snapshot, &entry) == TRUE)
        {
            int pid = entry.th32ProcessID;
            if (_stricmp(entry.szExeFile, "WizardLauncher.exe") == 0 || _stricmp(entry.szExeFile, "WizardGraphicalClient.exe") == 0)
            {
                if (!has_module_loaded(pid, "wiz-hwid-spoofer-internal"))
                {
                    TCHAR  buffer[4096] = TEXT("");
                    TCHAR** lpp = { nullptr };

                    GetFullPathName("wiz-hwid-spoofer-internal.dll", 4096, buffer, lpp);

                    inject_dll(pid, buffer);
                }
            }
        }
    }
}