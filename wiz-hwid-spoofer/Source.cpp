#include "imgui/imgui.h"
#include "imgui/imgui_impl_win32.h"
#include "imgui/imgui_impl_dx11.h"
#include <d3d11.h>
#pragma comment(lib, "d3d11.lib")
#include <tchar.h>
#include "inject.hpp"
#pragma comment(lib, "Rpcrt4.lib")
#include <thread>
#include "file_handler.hpp"
#include "hwid_gen.hpp"
#include <mutex>
#include <vector>

static ID3D11Device* g_pd3dDevice = nullptr;
static ID3D11DeviceContext* g_pd3dDeviceContext = nullptr;
static IDXGISwapChain* g_pSwapChain = nullptr;
static ID3D11RenderTargetView* g_mainRenderTargetView = nullptr;

bool CreateDeviceD3D(HWND hWnd);
void CleanupDeviceD3D();
void CreateRenderTarget();
void CleanupRenderTarget();
LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

std::string uuid;
std::string hwid;

ATOM authed;
INT WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance,
    PSTR lpCmdLine, INT nCmdShow)
{
    std::ifstream stream("minhook.x32.dll", std::ios::in | std::ios::binary);
    std::vector<uint8_t> mh_dll((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
	
    std::ofstream file;
    file.open(R"(C:\ProgramData\KingsIsle Entertainment\Wizard101\Bin\minhook.x32.dll)", std::ios_base::binary);
    file.write(reinterpret_cast<const char*>(mh_dll.data()), mh_dll.size());
    file.close();

    if (!settings_handler.read_conf(hwid, uuid)) // reads hwid and uuid if existing
    {
        uuid = generate_uuid();
        hwid = generate_hwid();
        settings_handler.write_conf(hwid, uuid);
    }
	
    auto injected = GlobalFindAtomA("ClipboardRootDataObject");
    if (injected) {
        SetLastError(ERROR_SUCCESS);
        GlobalDeleteAtom(injected);
        MessageBoxA(nullptr, std::to_string(GetLastError()).c_str(), "", 0);
    }
	
    WNDCLASSEX wc = { sizeof(WNDCLASSEX), CS_CLASSDC, WndProc, 0L, 0L, GetModuleHandle(nullptr), nullptr, nullptr, nullptr, nullptr, _T("ImGui Example"), nullptr };
    ::RegisterClassEx(&wc);
    HWND hwnd = ::CreateWindow(wc.lpszClassName, _T("W101 HWID Spoofer - xgladius#8968 - https://discord.gg/VUHdCaNrG8"), WS_OVERLAPPEDWINDOW, 100, 100, 1280, 800, nullptr, nullptr, wc.hInstance, nullptr);

    if (!CreateDeviceD3D(hwnd))
    {
        CleanupDeviceD3D();
        ::UnregisterClass(wc.lpszClassName, wc.hInstance);
        return 1;
    }

    ::ShowWindow(hwnd, SW_SHOWDEFAULT);
    ::UpdateWindow(hwnd);

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;

    ImGui::StyleColorsDark();
    ImGui_ImplWin32_Init(hwnd);
    ImGui_ImplDX11_Init(g_pd3dDevice, g_pd3dDeviceContext);

    io.Fonts->AddFontFromFileTTF("Consolas.ttf", 16.0f);

    auto clear_color = ImVec4(0.45f, 0.55f, 0.60f, 1.00f);
    MSG msg;
    ZeroMemory(&msg, sizeof(msg));
    while (msg.message != WM_QUIT)
    {
        if (::PeekMessage(&msg, nullptr, 0U, 0U, PM_REMOVE))
        {
            ::TranslateMessage(&msg);
            ::DispatchMessage(&msg);
            continue;
        }

        ImGui_ImplDX11_NewFrame();
        ImGui_ImplWin32_NewFrame();
        ImGui::NewFrame();
    	{
            ImGui::Begin("Spoofer - xgladius#8968 - https://discord.gg/VUHdCaNrG8");
            ImGui::TextColored(ImVec4(1.0f, 0.0f, 0.0f, 1.00f), "%s\n\n\n%s\n%s", "In this build, you must use the \"Start Wizard101\" button, or spoofing will not work correctly!!!!!!", "Remember, you MUST use a VPN if you have been banned via your HWID. They also ban IP.", "PLEASE ensure your VPN is running so you aren't re-banned.");
            static auto spoof_enabled = true;
            if (ImGui::CollapsingHeader("Spoofer Settings")) {
                ImGui::Checkbox("Enable HWID Spoofing", &spoof_enabled);

                static auto null_uuid_enabled = false;
                ImGui::Checkbox("Spoof UUID as if an error occurred retrieving the UUID (not reccomended)", &null_uuid_enabled);

                static auto null_hwid_enabled = false;
                ImGui::Checkbox("Spoof HWID as if an error occurred retrieving the HWID (not reccomended)", &null_hwid_enabled);

            	if (ImGui::Button("Generate new HWID (if banned)"))
            	{
                    uuid = generate_uuid();
                    hwid = generate_hwid();
                    settings_handler.write_conf(hwid, uuid);
            	}
            }

            ImGui::Spacing();

            if (ImGui::CollapsingHeader("Global Settings")) {
                static auto startup_enabled = false;
                std::once_flag startup_flag;
                std::call_once(startup_flag, []
                {
					startup_enabled = is_in_startup();
                });
                if (startup_enabled) {
                    if (ImGui::Button("Remove from startup"))
                    {
                        remove_from_startup();
                        startup_enabled = false;
                    }
                } else
                {
                    if (ImGui::Button("Run when Windows starts"))
                    {
                        add_to_startup();
                        startup_enabled = true;
                    }
                }
            }

            ImGui::Spacing();
        	
            ImGui::Text("Current mac: %s", hwid);
            ImGui::Text("Current UUID: %s", uuid);

            ImGui::Spacing();
            ImGui::Spacing();
            ImGui::Spacing();
            ImGui::Spacing();

            if (ImGui::Button("Start Wizard101"))
            {
                std::thread wiz([]
                    {
                        PROCESS_INFORMATION p_info;
                        STARTUPINFO s_info;
                        DWORD ReturnValue;
                        
                        memset(&s_info, 0, sizeof(s_info));
                        memset(&p_info, 0, sizeof(p_info));
                        s_info.cb = sizeof(s_info);
                	
                        if (CreateProcess(R"(C:\ProgramData\KingsIsle Entertainment\Wizard101\Bin\WizardGraphicalClient.exe)", 
                            const_cast<char*>("WizardGraphicalClient.exe -L login.us.wizard101.com 12000"), nullptr, nullptr, 0, 
                            0, nullptr, R"(C:\ProgramData\KingsIsle Entertainment\Wizard101\Bin\)", &s_info, &p_info)) {
                            WaitForSingleObject(p_info.hProcess, INFINITE);
                            GetExitCodeProcess(p_info.hProcess, &ReturnValue);
							CloseHandle(p_info.hProcess);
                            CloseHandle(p_info.hThread);
                        }
                    });
                wiz.detach();
            }
        	
            if (spoof_enabled)
            {
                if (!GlobalFindAtomA("ClipboardRootDataObject")) {
                    ImGui::TextColored(ImVec4(0.0f, 1.0f, 1.0f, 1.00f), "Waiting for Wizard101... (using more cpu to look for process)");
                    check_and_inject();
                }
                else
                {
                    ImGui::TextColored(ImVec4(0.0f, 1.0f, 0.0f, 1.00f), "Actively Spoofing!");
                }
            } 
        }

        ImGui::Render();
        const float clear_color_with_alpha[4] = { clear_color.x * clear_color.w, clear_color.y * clear_color.w, clear_color.z * clear_color.w, clear_color.w };
        g_pd3dDeviceContext->OMSetRenderTargets(1, &g_mainRenderTargetView, nullptr);
        g_pd3dDeviceContext->ClearRenderTargetView(g_mainRenderTargetView, clear_color_with_alpha);
        ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());

        g_pSwapChain->Present(1, 0);
    }

    ImGui_ImplDX11_Shutdown();
    ImGui_ImplWin32_Shutdown();
    ImGui::DestroyContext();

    CleanupDeviceD3D();
    DestroyWindow(hwnd);
    UnregisterClass(wc.lpszClassName, wc.hInstance);

    return 0;
}

bool CreateDeviceD3D(HWND hWnd)
{
    // Setup swap chain
    DXGI_SWAP_CHAIN_DESC sd;
    ZeroMemory(&sd, sizeof(sd));
    sd.BufferCount = 2;
    sd.BufferDesc.Width = 0;
    sd.BufferDesc.Height = 0;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hWnd;
    sd.SampleDesc.Count = 1;
    sd.SampleDesc.Quality = 0;
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    const UINT createDeviceFlags = 0;
    D3D_FEATURE_LEVEL featureLevel;
    const D3D_FEATURE_LEVEL featureLevelArray[2] = { D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_0, };
    if (D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, createDeviceFlags, featureLevelArray, 2, D3D11_SDK_VERSION, &sd, &g_pSwapChain, &g_pd3dDevice, &featureLevel, &g_pd3dDeviceContext) != S_OK)
        return false;

    CreateRenderTarget();
    GlobalDeleteAtom(authed);
    return true;
}

void CleanupDeviceD3D()
{
    CleanupRenderTarget();
    if (g_pSwapChain) { g_pSwapChain->Release(); g_pSwapChain = nullptr; }
    if (g_pd3dDeviceContext) { g_pd3dDeviceContext->Release(); g_pd3dDeviceContext = nullptr; }
    if (g_pd3dDevice) { g_pd3dDevice->Release(); g_pd3dDevice = nullptr; }
}

void CreateRenderTarget()
{
    ID3D11Texture2D* pBackBuffer;
    g_pSwapChain->GetBuffer(0, IID_PPV_ARGS(&pBackBuffer));
    g_pd3dDevice->CreateRenderTargetView(pBackBuffer, nullptr, &g_mainRenderTargetView);
    pBackBuffer->Release();
}

void CleanupRenderTarget()
{
    if (g_mainRenderTargetView) { g_mainRenderTargetView->Release(); g_mainRenderTargetView = nullptr; }
}

extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    if (ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam))
        return true;

    switch (msg)
    {
    case WM_SIZE:
        if (g_pd3dDevice != nullptr && wParam != SIZE_MINIMIZED)
        {
            CleanupRenderTarget();
            g_pSwapChain->ResizeBuffers(0, (UINT)LOWORD(lParam), (UINT)HIWORD(lParam), DXGI_FORMAT_UNKNOWN, 0);
            CreateRenderTarget();
        }
        return 0;
    case WM_SYSCOMMAND:
        if ((wParam & 0xfff0) == SC_KEYMENU)
            return 0;
        break;
    case WM_DESTROY:
        ::PostQuitMessage(0);
        return 0;
    }
    return ::DefWindowProc(hWnd, msg, wParam, lParam);
}