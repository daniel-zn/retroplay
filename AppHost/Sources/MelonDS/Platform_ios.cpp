// RetroPlay iOS Platform stubs for melonDS core (no Qt).
#include "Platform.h"
#include <chrono>
#include <condition_variable>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <functional>
#include <mutex>
#include <thread>
#include <unistd.h>
#include <sys/stat.h>

namespace melonDS {
namespace Platform {

void SignalStop(StopReason, void*) {}

std::string GetLocalFilePath(const std::string& filename) { return filename; }

FileHandle* OpenFile(const std::string& path, FileMode mode) {
    unsigned m = (unsigned)mode;
    const char* fm = "rb";
    if (m & (unsigned)FileMode::Write) {
        if (m & (unsigned)FileMode::Preserve) fm = "r+b";
        else fm = "w+b";
    } else {
        fm = "rb";
    }
    FILE* f = fopen(path.c_str(), fm);
    if (!f && (m & (unsigned)FileMode::Write) && !(m & (unsigned)FileMode::NoCreate))
        f = fopen(path.c_str(), "w+b");
    return reinterpret_cast<FileHandle*>(f);
}
FileHandle* OpenLocalFile(const std::string& path, FileMode mode) { return OpenFile(path, mode); }
bool FileExists(const std::string& name) { struct stat st{}; return ::stat(name.c_str(), &st) == 0; }
bool LocalFileExists(const std::string& name) { return FileExists(name); }
bool CheckFileWritable(const std::string& filepath) { return access(filepath.c_str(), W_OK) == 0 || !FileExists(filepath); }
bool CheckLocalFileWritable(const std::string& filepath) { return CheckFileWritable(filepath); }
bool CloseFile(FileHandle* file) { return file ? fclose(reinterpret_cast<FILE*>(file)) == 0 : false; }
bool IsEndOfFile(FileHandle* file) { return file ? feof(reinterpret_cast<FILE*>(file)) != 0 : true; }
bool FileReadLine(char* str, int count, FileHandle* file) { return file && fgets(str, count, reinterpret_cast<FILE*>(file)); }
u64 FilePosition(FileHandle* file) { return file ? (u64)ftell(reinterpret_cast<FILE*>(file)) : 0; }
bool FileSeek(FileHandle* file, s64 offset, FileSeekOrigin origin) {
    if (!file) return false;
    int whence = SEEK_SET;
    switch (origin) {
        case FileSeekOrigin::Start: whence = SEEK_SET; break;
        case FileSeekOrigin::Current: whence = SEEK_CUR; break;
        case FileSeekOrigin::End: whence = SEEK_END; break;
    }
    return fseek(reinterpret_cast<FILE*>(file), (long)offset, whence) == 0;
}
void FileRewind(FileHandle* file) { if (file) rewind(reinterpret_cast<FILE*>(file)); }
u64 FileRead(void* data, u64 size, u64 count, FileHandle* file) {
    return file ? (u64)fread(data, (size_t)size, (size_t)count, reinterpret_cast<FILE*>(file)) : 0;
}
bool FileFlush(FileHandle* file) { return file ? fflush(reinterpret_cast<FILE*>(file)) == 0 : false; }
u64 FileWrite(const void* data, u64 size, u64 count, FileHandle* file) {
    return file ? (u64)fwrite(data, (size_t)size, (size_t)count, reinterpret_cast<FILE*>(file)) : 0;
}
u64 FileWriteFormatted(FileHandle* file, const char* fmt, ...) {
    if (!file) return 0;
    va_list ap; va_start(ap, fmt);
    int n = vfprintf(reinterpret_cast<FILE*>(file), fmt, ap);
    va_end(ap);
    return n > 0 ? (u64)n : 0;
}
u64 FileLength(FileHandle* file) {
    if (!file) return 0;
    FILE* f = reinterpret_cast<FILE*>(file);
    long cur = ftell(f); fseek(f, 0, SEEK_END); long end = ftell(f); fseek(f, cur, SEEK_SET);
    return end > 0 ? (u64)end : 0;
}

void Log(LogLevel, const char* fmt, ...) {
    va_list ap; va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap);
}

Thread* Thread_Create(std::function<void()> func) {
    return reinterpret_cast<Thread*>(new std::thread(std::move(func)));
}
void Thread_Free(Thread* thread) {
    auto* t = reinterpret_cast<std::thread*>(thread);
    if (t) { if (t->joinable()) t->detach(); delete t; }
}
void Thread_Wait(Thread* thread) {
    auto* t = reinterpret_cast<std::thread*>(thread);
    if (t && t->joinable()) t->join();
}

struct Sema { std::mutex m; std::condition_variable cv; int count = 0; };
Semaphore* Semaphore_Create() { return reinterpret_cast<Semaphore*>(new Sema); }
void Semaphore_Free(Semaphore* sema) { delete reinterpret_cast<Sema*>(sema); }
void Semaphore_Reset(Semaphore* sema) { auto* s = reinterpret_cast<Sema*>(sema); std::lock_guard g(s->m); s->count = 0; }
void Semaphore_Wait(Semaphore* sema) {
    auto* s = reinterpret_cast<Sema*>(sema);
    std::unique_lock lock(s->m);
    s->cv.wait(lock, [&]{ return s->count > 0; });
    --s->count;
}
bool Semaphore_TryWait(Semaphore* sema, int timeout_ms) {
    auto* s = reinterpret_cast<Sema*>(sema);
    std::unique_lock lock(s->m);
    if (timeout_ms <= 0) { if (s->count <= 0) return false; --s->count; return true; }
    bool ok = s->cv.wait_for(lock, std::chrono::milliseconds(timeout_ms), [&]{ return s->count > 0; });
    if (ok) --s->count;
    return ok;
}
void Semaphore_Post(Semaphore* sema, int count) {
    auto* s = reinterpret_cast<Sema*>(sema);
    { std::lock_guard g(s->m); s->count += count; }
    s->cv.notify_all();
}

Mutex* Mutex_Create() { return reinterpret_cast<Mutex*>(new std::mutex); }
void Mutex_Free(Mutex* mutex) { delete reinterpret_cast<std::mutex*>(mutex); }
void Mutex_Lock(Mutex* mutex) { reinterpret_cast<std::mutex*>(mutex)->lock(); }
void Mutex_Unlock(Mutex* mutex) { reinterpret_cast<std::mutex*>(mutex)->unlock(); }
bool Mutex_TryLock(Mutex* mutex) { return reinterpret_cast<std::mutex*>(mutex)->try_lock(); }

void Sleep(u64 usecs) { std::this_thread::sleep_for(std::chrono::microseconds(usecs)); }
static auto gStart = std::chrono::steady_clock::now();
u64 GetMSCount() {
    return (u64)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - gStart).count();
}
u64 GetUSCount() {
    return (u64)std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - gStart).count();
}

void WriteNDSSave(const u8*, u32, u32, u32, void*) {}
void WriteGBASave(const u8*, u32, u32, u32, void*) {}
void WriteFirmware(const Firmware&, u32, u32, void*) {}
void WriteDateTime(int, int, int, int, int, int, void*) {}

void MP_Begin(void*) {}
void MP_End(void*) {}
int MP_SendPacket(u8*, int, u64, void*) { return 0; }
int MP_RecvPacket(u8*, u64*, void*) { return 0; }
int MP_SendCmd(u8*, int, u64, void*) { return 0; }
int MP_SendReply(u8*, int, u64, u16, void*) { return 0; }
int MP_SendAck(u8*, int, u64, void*) { return 0; }
int MP_RecvHostPacket(u8*, u64*, void*) { return 0; }
u16 MP_RecvReplies(u8*, u64, u16, void*) { return 0; }
int Net_SendPacket(u8*, int, void*) { return 0; }
int Net_RecvPacket(u8*, void*) { return 0; }

void Camera_Start(int, void*) {}
void Camera_Stop(int, void*) {}
void Camera_CaptureFrame(int, u32*, int, int, bool, void*) {}
void Mic_Start(void*) {}
void Mic_Stop(void*) {}
int Mic_ReadInput(s16*, int, void*) { return 0; }

AACDecoder* AAC_Init() { return nullptr; }
void AAC_DeInit(AACDecoder*) {}
bool AAC_Configure(AACDecoder*, int, int) { return false; }
bool AAC_DecodeFrame(AACDecoder*, const void*, int, void*, int) { return false; }


bool Addon_KeyDown(KeyType, void*) { return false; }
void Addon_RumbleStart(u32, void*) {}
void Addon_RumbleStop(void*) {}
float Addon_MotionQuery(MotionQueryType, void*) { return 0.f; }

DynamicLibrary* DynamicLibrary_Load(const char*) { return nullptr; }
void DynamicLibrary_Unload(DynamicLibrary*) {}
void* DynamicLibrary_LoadFunction(DynamicLibrary*, const char*) { return nullptr; }

} // namespace Platform
} // namespace melonDS
