#include <windows.h>
#include <tlhelp32.h>
#include "../common/AdapterInfo.hpp"
#include "../common/Kern32Hooks.hpp"

DWORD WINAPI main(LPVOID lpThreadParameter) {
	MH_Initialize();
	hook_free();
	hook_adap();
	hook_k32();
	return 1;
}

BOOL APIENTRY DllMain(HMODULE Module, DWORD Reason, void* Reserved) {
	if (Reason == DLL_PROCESS_ATTACH) {
		me = Module;
		main(0);
	}
	return TRUE;
}