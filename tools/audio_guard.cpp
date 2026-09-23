// Windows-only session guardian. No endpoint/master volume writes.
#define NOMINMAX
#include <audioclient.h>
#include <audiopolicy.h>
#include <mmdeviceapi.h>
#include <windows.h>
#ifndef AUDCLNT_S_NO_SINGLE_PROCESS
#define AUDCLNT_S_NO_SINGLE_PROCESS AUDCLNT_SUCCESS(0x00d)
#endif
#include <filesystem>
#include <fstream>
#include <iostream>
#include <set>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>
#include <wrl/client.h>
using Microsoft::WRL::ComPtr;
static void check(HRESULT hr, const char *operation) {
  if (FAILED(hr))
    throw std::runtime_error(std::string(operation) + " failed (HRESULT " +
                             std::to_string(static_cast<unsigned long>(hr)) +
                             ")");
}
static unsigned long long creation(HANDLE p) {
  FILETIME c, e, k, u;
  if (!GetProcessTimes(p, &c, &e, &k, &u))
    throw std::runtime_error("Cannot validate process creation time");
  return (static_cast<unsigned long long>(c.dwHighDateTime) << 32) |
         c.dwLowDateTime;
}
struct Process {
  HANDLE h;
  Process(DWORD pid, unsigned long long stamp)
      : h(OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                      pid)) {
    if (!h)
      throw std::runtime_error("Cannot open selected process");
    if (creation(h) != stamp) {
      CloseHandle(h);
      throw std::runtime_error("Process identity changed");
    }
  }
  ~Process() { CloseHandle(h); }
  bool alive() { return WaitForSingleObject(h, 0) == WAIT_TIMEOUT; }
};
struct Session {
  ComPtr<ISimpleAudioVolume> volume;
  bool changed = false;
};
struct Guardian {
  ComPtr<IMMDeviceEnumerator> devices;
  std::vector<Session> owned;
  std::set<std::wstring> seen;
  Guardian() {
    check(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                           IID_PPV_ARGS(&devices)),
          "CoreAudio enumerator");
  }
  ~Guardian() { restore(); }
  bool restore() {
    bool ok = true;
    for (auto &s : owned)
      if (s.changed) {
        BOOL muted = FALSE;
        HRESULT h = s.volume->GetMute(&muted);
        if (SUCCEEDED(h) && muted)
          h = s.volume->SetMute(FALSE, nullptr);
        if (FAILED(h) && h != AUDCLNT_E_DEVICE_INVALIDATED)
          ok = false;
        else
          s.changed = false;
      }
    return ok;
  }
  int scan(DWORD pid, int action) {
    ComPtr<IMMDeviceCollection> collection;
    check(
        devices->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &collection),
        "Playback device enumeration");
    UINT count = 0;
    check(collection->GetCount(&count), "Playback device count");
    int found = 0;
    for (UINT i = 0; i < count; ++i) {
      ComPtr<IMMDevice> device;
      check(collection->Item(i, &device), "Playback device");
      ComPtr<IAudioSessionManager2> manager;
      HRESULT hr =
          device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr,
                           reinterpret_cast<void **>(manager.GetAddressOf()));
      if (hr == AUDCLNT_E_DEVICE_INVALIDATED)
        continue;
      check(hr, "Session manager");
      ComPtr<IAudioSessionEnumerator> sessions;
      check(manager->GetSessionEnumerator(&sessions), "Session enumeration");
      int n = 0;
      check(sessions->GetCount(&n), "Session count");
      for (int j = 0; j < n; ++j) {
        ComPtr<IAudioSessionControl> control;
        check(sessions->GetSession(j, &control), "Session");
        ComPtr<IAudioSessionControl2> detail;
        check(control.As(&detail), "Session details");
        DWORD owner = 0;
        hr = detail->GetProcessId(&owner);
        if (hr == AUDCLNT_S_NO_SINGLE_PROCESS)
          continue;
        check(hr, "Session process");
        if (owner != pid)
          continue;
        AudioSessionState state;
        check(control->GetState(&state), "Session state");
        if (state == AudioSessionStateExpired)
          continue;
        ComPtr<ISimpleAudioVolume> volume;
        check(control.As(&volume), "Session volume");
        BOOL muted = FALSE;
        check(volume->GetMute(&muted), "Session mute");
        ++found;
        if (action == 0) {
          float gain = 0;
          check(volume->GetMasterVolume(&gain), "Session gain");
          std::cout << "mute=" << muted << " volume=" << gain << "\n";
          continue;
        }
        if (action == 2 || action == 3) {
          check(volume->SetMute(action == 2, nullptr), "Test mute");
          continue;
        }
        LPWSTR id = nullptr;
        check(detail->GetSessionInstanceIdentifier(&id), "Session identity");
        std::wstring key(id);
        CoTaskMemFree(id);
        if (seen.count(key))
          continue;
        owned.push_back({volume, false}); // Keep the reference before changing
                                          // state, including on exceptions.
        if (!muted) {
          check(volume->SetMute(TRUE, nullptr), "DF session mute");
          owned.back().changed = true;
        }
        seen.insert(key);
      }
    }
    return found;
  }
};
static void report(const std::filesystem::path &path, const std::string &line) {
  auto temp = path;
  temp += L".tmp";
  {
    std::ofstream out(temp);
    out << line << "\n";
    if (!out)
      throw std::runtime_error("Cannot write guardian status");
  }
  if (!MoveFileExW(temp.c_str(), path.c_str(),
                   MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    throw std::runtime_error("Cannot publish guardian status");
}
static int producer(const std::filesystem::path &ready) {
  ComPtr<IMMDeviceEnumerator> e;
  check(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                         IID_PPV_ARGS(&e)),
        "enumerator");
  ComPtr<IMMDevice> d;
  check(e->GetDefaultAudioEndpoint(eRender, eConsole, &d), "test endpoint");
  ComPtr<IAudioClient> c;
  check(d->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                    reinterpret_cast<void **>(c.GetAddressOf())),
        "test client");
  WAVEFORMATEX *f = nullptr;
  check(c->GetMixFormat(&f), "mix format");
  HRESULT h =
      c->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_NOPERSIST,
                    1000000, 0, f, nullptr);
  CoTaskMemFree(f);
  check(h, "silent stream");
  ComPtr<IAudioRenderClient> r;
  check(c->GetService(IID_PPV_ARGS(&r)), "render client");
  UINT32 size = 0;
  check(c->GetBufferSize(&size), "buffer size");
  check(c->Start(), "stream start");
  report(ready, "READY");
  for (int i = 0; i < 30000; ++i) {
    UINT32 used = 0;
    check(c->GetCurrentPadding(&used), "padding");
    if (size > used) {
      BYTE *p;
      check(r->GetBuffer(size - used, &p), "buffer");
      check(r->ReleaseBuffer(size - used, AUDCLNT_BUFFERFLAGS_SILENT),
            "zero PCM");
    }
    Sleep(10);
  }
  return 0;
}
int wmain(int argc, wchar_t **argv) {
  HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(init))
    return 2;
  int result = 0;
  std::filesystem::path status;
  try {
    const std::wstring_view mode = argc > 1 ? argv[1] : L"";
    if ((argc == 3 || argc == 4) && mode == L"--silent-producer") {
      if (argc == 4)
        Sleep(std::stoul(argv[3]));
      result = producer(argv[2]);
    } else if (argc == 3 && (mode == L"--probe" || mode == L"--test-mute" ||
                             mode == L"--test-unmute")) {
      Guardian g;
      result = g.scan(std::stoul(argv[2]),
                      mode == L"--probe" ? 0 : (mode == L"--test-mute" ? 2 : 3))
                   ? 0
                   : 3;
    } else if (argc == 8 && mode == L"--guard") {
      status = argv[6];
      std::filesystem::path stop = argv[7];
      Process parent(std::stoul(argv[2]), std::stoull(argv[3]));
      Process target(std::stoul(argv[4]), std::stoull(argv[5]));
      Guardian g;
      if (!parent.alive() || !target.alive())
        throw std::runtime_error(
            "Selected process exited before audio takeover");
      g.scan(std::stoul(argv[4]), 1);
      report(status, "READY");
      while (parent.alive() && target.alive() &&
             !std::filesystem::exists(stop)) {
        if (WaitForSingleObject(parent.h, 250) != WAIT_TIMEOUT)
          break;
        if (!target.alive())
          break;
        g.scan(std::stoul(argv[4]), 1);
      }
      if (!g.restore())
        throw std::runtime_error("Some DF sessions could not be restored; "
                                 "check DF in Windows Volume Mixer");
      report(status, "RESTORED");
    } else
      throw std::runtime_error("Usage: --guard parentPID parentCreation dfPID "
                               "dfCreation status stop");
  } catch (const std::exception &e) {
    std::cerr << e.what() << "\n";
    if (!status.empty())
      try {
        report(status, std::string("ERROR: ") + e.what());
      } catch (...) {
      }
    result = 1;
  }
  CoUninitialize();
  return result;
}
