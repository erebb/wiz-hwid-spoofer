# wiz-hwid-spoofer
Usermode hwid spoofer for the game Wizard101
For launcher spoofing, use a proxy dll (dbghelp.dll) to initialize hooks before any api calls
For client spoofing, imitate WizardCommandLineCSR.dll to initialize hooks before any api calls

hooks GetAdaptersInfo, GetSystemFirmwareTable, CreateFileA, FreeLibraryA
