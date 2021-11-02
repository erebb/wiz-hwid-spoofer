#include <Windows.h>
#include <DbgHelp.h>
#include "../common/Kern32Hooks.hpp"
#include "../common/AdapterInfo.hpp"

#define EXPORT comment(linker, "/EXPORT:" __FUNCTION__ "=" __FUNCDNAME__)

DWORD64 __stdcall SymGetModuleBase64(HANDLE hProcess, DWORD64 qwAddr) {
#pragma EXPORT
	return 0;
}

PVOID __stdcall SymFunctionTableAccess64(HANDLE hProcess, DWORD64 AddrBase) {
#pragma EXPORT
	int x = 0;
	return &x;
}

BOOL __stdcall StackWalk64(DWORD MachineType, HANDLE hProcess, HANDLE hThread, LPSTACKFRAME64 StackFrame, PVOID ContextRecord, PREAD_PROCESS_MEMORY_ROUTINE64 ReadMemoryRoutine, PFUNCTION_TABLE_ACCESS_ROUTINE64 FunctionTableAccessRoutine, PGET_MODULE_BASE_ROUTINE64 GetModuleBaseRoutine, PTRANSLATE_ADDRESS_ROUTINE64 TranslateAddress) {
#pragma EXPORT
	return FALSE;
}

DWORD WINAPI main(LPVOID lpThreadParameter) {
	MH_Initialize();
	hook_adap();
	hook_k32();
	return 1;
}

BOOL APIENTRY DllMain(HMODULE Module, DWORD Reason, void* Reserved) {
	if (Reason == DLL_PROCESS_ATTACH) {
		main(0);
	}
	return TRUE;
}