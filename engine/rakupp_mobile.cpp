// rakupp_mobile.cpp — see rakupp_mobile.h for why this layer exists.
#include "rakupp_mobile.h"

#include "Highlight.h"
#include <rakupp/rakupp.h>

#include <pthread.h>
#include <unistd.h>

#include <atomic>
#include <cctype>
#include <condition_variable>
#include <iostream>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>

namespace {

// Output a single run may buffer before the shim stops it. A runaway
// `loop { say 1 }` would otherwise grow without bound until the OS kills the
// app; a megabyte is far more than any lesson or playground program prints.
constexpr size_t kOutputCap = 1 << 20;

struct Segment {
    char stream;      // 'o' or 'e'
    std::string text;
};

std::mutex g_mu;
std::string g_pending;          // encoded segments not yet taken
char g_lastStream = 0;          // stream of the last segment in g_pending
size_t g_lastLenAt = 0;         // offset of that segment's length field
size_t g_produced = 0;          // bytes this run has printed so far
bool g_truncated = false;

std::atomic<int> g_state{RKM_IDLE};
std::atomic<int> g_exit{0};
std::atomic<bool> g_stopRequested{false};
std::atomic<RkInterp> g_rk{nullptr};

void putLen(std::string& s, size_t at, uint32_t n) {
    s[at]     = char(n & 0xff);
    s[at + 1] = char((n >> 8) & 0xff);
    s[at + 2] = char((n >> 16) & 0xff);
    s[at + 3] = char((n >> 24) & 0xff);
}

uint32_t getLen(const std::string& s, size_t at) {
    return uint32_t(uint8_t(s[at])) | uint32_t(uint8_t(s[at + 1])) << 8 |
           uint32_t(uint8_t(s[at + 2])) << 16 | uint32_t(uint8_t(s[at + 3])) << 24;
}

// Append to the pending buffer, extending the last segment when the stream is
// the same, so a loop of `say`s arrives as one segment rather than thousands.
void appendLocked(char stream, const char* text, size_t len) {
    if (g_lastStream == stream && !g_pending.empty()) {
        g_pending.append(text, len);
        putLen(g_pending, g_lastLenAt, getLen(g_pending, g_lastLenAt) + uint32_t(len));
        return;
    }
    g_pending.push_back(stream);
    g_lastLenAt = g_pending.size();
    g_pending.append(4, '\0');
    putLen(g_pending, g_lastLenAt, uint32_t(len));
    g_pending.append(text, len);
    g_lastStream = stream;
}

void onOutput(void*, const char* text, size_t len, int is_err) {
    std::lock_guard<std::mutex> lk(g_mu);
    if (g_truncated) return;
    if (g_produced + len > kOutputCap) {
        size_t room = kOutputCap - g_produced;
        appendLocked(is_err ? 'e' : 'o', text, room);
        static const char note[] = "\n[output stopped after 1 MB]\n";
        appendLocked('e', note, sizeof note - 1);
        g_truncated = true;
        g_stopRequested = true;
        if (RkInterp rk = g_rk.load()) rk_interrupt(rk);
        return;
    }
    g_produced += len;
    appendLocked(is_err ? 'e' : 'o', text, len);
}

// Standard input for an interactive run: what the host has sent so far, and
// a read that has caught up with it waits — as a terminal does — until the
// host sends more or ends the input. Installed as std::cin's buffer, which is
// where the engine reads `get`, `lines` and `prompt` from.
class InputBuf : public std::streambuf {
public:
    void reset(const std::string& prefill) {
        std::lock_guard<std::mutex> lk(mu_);
        data_ = prefill;
        pos_ = 0;
        cur_.clear();
        eof_ = false;
        setg(nullptr, nullptr, nullptr);
    }
    void push(const std::string& text) {
        std::lock_guard<std::mutex> lk(mu_);
        data_ += text;
        cv_.notify_all();
    }
    void close() {
        std::lock_guard<std::mutex> lk(mu_);
        eof_ = true;
        cv_.notify_all();
    }
    bool waiting() const { return waiting_.load(); }

protected:
    int_type underflow() override {
        if (gptr() && gptr() < egptr()) return traits_type::to_int_type(*gptr());
        std::unique_lock<std::mutex> lk(mu_);
        while (pos_ >= data_.size() && !eof_) {
            waiting_ = true;
            cv_.wait(lk);
        }
        waiting_ = false;
        if (pos_ >= data_.size()) return traits_type::eof();
        cur_.assign(data_, pos_, std::string::npos);
        pos_ = data_.size();
        setg(&cur_[0], &cur_[0], &cur_[0] + cur_.size());
        return traits_type::to_int_type(cur_[0]);
    }

private:
    std::mutex mu_;
    std::condition_variable cv_;
    std::string data_, cur_;
    size_t pos_ = 0;
    bool eof_ = false;
    std::atomic<bool> waiting_{false};
};

InputBuf g_input;

struct Job {
    std::string source, input, fileName, workdir;
    bool interactive = false;
};

void* runJob(void* arg) {
    Job* job = static_cast<Job*>(arg);
    if (!job->workdir.empty()) (void)chdir(job->workdir.c_str());
    // Every run gets a fresh interpreter: a playground program that declares
    // `class Point` must not collide with the one the last run declared.
    RkInterp rk = rk_new(nullptr);
    int rc = 3;
    if (!rk) {
        static const char msg[] = "The Raku engine could not start.\n";
        onOutput(nullptr, msg, sizeof msg - 1, 1);
    }
    else {
        rk_set_output(rk, onOutput, nullptr);
        std::streambuf* oldIn = nullptr;
        if (job->interactive) {
            g_input.reset(job->input);
            std::cin.clear();
            oldIn = std::cin.rdbuf(&g_input);
        }
        else {
            rk_set_input(rk, job->input.data(), job->input.size());
        }
        g_rk = rk;
        // A Stop that arrived before the interpreter existed still counts.
        if (g_stopRequested) {
            rk_interrupt(rk);
            g_input.close();
        }
        rk_run(rk, job->source.c_str(), job->fileName.c_str(), &rc);
        g_rk = nullptr;
        if (oldIn) {
            g_input.close();
            std::cin.rdbuf(oldIn);
            std::cin.clear();
        }
        rk_set_output(rk, nullptr, nullptr);
        rk_free(rk);
    }
    if (g_stopRequested && !g_truncated) rc = 130;
    delete job;
    g_exit = rc;
    g_state = RKM_FINISHED;
    return nullptr;
}

uint8_t* handOut(const std::string& s, int32_t* len) {
    if (len) *len = int32_t(s.size());
    if (s.empty()) return nullptr;
    auto* p = static_cast<uint8_t*>(std::malloc(s.size()));
    if (p) std::memcpy(p, s.data(), s.size());
    return p;
}

int classOf(const char* cls, const std::string& text) {
    if (!cls || !*cls) return RKM_HL_PLAIN;
    switch (cls[0]) {
        case 'k': return RKM_HL_KEYWORD;
        case 'c': return RKM_HL_COMMENT;
        case 'm': return RKM_HL_NUMBER;
        case 's': return cls[1] == 'r' ? RKM_HL_REGEX : RKM_HL_STRING;
        case 'n':
            if (cls[1] == 'b') return RKM_HL_BUILTIN;
            if (cls[1] == 'v') return RKM_HL_VARIABLE;
            if (!text.empty() && std::isupper(uint8_t(text[0]))) return RKM_HL_TYPE;
            return RKM_HL_NAME;
        default: return RKM_HL_PLAIN;
    }
}

} // namespace

extern "C" {

int rkm_start(const char* source, const char* input, const char* file_name,
              const char* workdir, int interactive) {
    int expected = g_state.load();
    if (expected == RKM_RUNNING) return -1;
    if (!g_state.compare_exchange_strong(expected, RKM_RUNNING)) return -1;
    {
        std::lock_guard<std::mutex> lk(g_mu);
        g_pending.clear();
        g_lastStream = 0;
        g_produced = 0;
        g_truncated = false;
    }
    g_stopRequested = false;
    g_exit = 0;

    auto* job = new Job{source ? source : "", input ? input : "",
                        file_name && *file_name ? file_name : "main.raku",
                        workdir ? workdir : "", interactive != 0};

    // The CLI runs Raku on a 1 GiB stack so deep recursion meets the
    // interpreter's own guard, which measures the real stack, rather than the
    // end of the stack. A phone gets less; if even that is refused, smaller.
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_t th;
    int rc = -1;
    for (size_t mb : {512, 128, 32, 8}) {
        if (pthread_attr_setstacksize(&attr, mb << 20) != 0) continue;
        rc = pthread_create(&th, &attr, runJob, job);
        if (rc == 0) break;
    }
    pthread_attr_destroy(&attr);
    if (rc != 0) {
        delete job;
        g_state = RKM_IDLE;
        return -2;
    }
    return 0;
}

void rkm_stop(void) {
    if (g_state.load() != RKM_RUNNING) return;
    g_stopRequested = true;
    if (RkInterp rk = g_rk.load()) rk_interrupt(rk);
    g_input.close();   // a program waiting for input must not wait forever
}

void rkm_send_input(const char* text) {
    if (text) g_input.push(text);
}

void rkm_end_input(void) { g_input.close(); }

int rkm_waiting_input(void) {
    return g_state.load() == RKM_RUNNING && g_input.waiting() ? 1 : 0;
}

int rkm_state(void) { return g_state.load(); }

int rkm_exit_code(void) { return g_exit.load(); }

uint8_t* rkm_take_output(int32_t* len) {
    std::string out;
    {
        std::lock_guard<std::mutex> lk(g_mu);
        out.swap(g_pending);
        g_lastStream = 0;
    }
    return handOut(out, len);
}

uint8_t* rkm_highlight(const char* source, int32_t* len) {
    std::string out;
    try {
        for (const auto& span : rakupp::scanSpans(source ? source : "")) {
            if (span.text.empty()) continue;
            out.push_back(char(classOf(span.cls, span.text)));
            size_t at = out.size();
            out.append(4, '\0');
            putLen(out, at, uint32_t(span.text.size()));
            out += span.text;
        }
    } catch (...) {
        out.clear();
    }
    return handOut(out, len);
}

void rkm_free(void* p) { std::free(p); }

const char* rkm_version(void) { return rk_version(); }

} // extern "C"
