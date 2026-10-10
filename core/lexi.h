#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// Instances are thread-confined. Returned UTF-8 strings live until the next call.
void* lexi_create(void);
void lexi_destroy(void* engine);
int lexi_load(void* engine, const char* path);
int lexi_load_layout(void* engine, const char* path);
// Fuzzy full-pinyin bits: 0=z/zh,c/ch,s/sh; 1=n/l; 2=an/ang,en/eng,in/ing.
// Default mask is 0; unknown bits are ignored. Exact dictionary matches outrank fuzzy.
void lexi_set_fuzzy(void* engine, int mask);
// Atomically replace personal phrases from UTF-8 TSV: trigger<Tab>text.
// Unique triggers: 1..32 lowercase ASCII letters; text: 1..512 bytes, no controls.
// At most 1 MiB / 1000 rows. Empty files clear phrases. Returns rows or -1.
int lexi_load_phrases(void* engine, const char* path);
// Local utility and curated emoji candidates; enabled by default, no network.
// Arithmetic accepts +-*/(), decimal literals, unary signs; max 64 query bytes,
// 32 nested parentheses/unary signs, and absolute intermediate values <= 1e12.
void lexi_set_tools(void* engine, int enabled);
// Shared local UTF-8 history: text<Tab>count (1..1000000), <=2000 rows / 1 MiB.
// Disabled by default. Platform supplies the path and creates its parent directory.
// Returns 0 (configured/no-op) or -1 (invalid/error). Unchanged configuration is
// a no-op; queries refresh the stamp. Concurrent replacements may defer loading
// to the next query. Disabled configuration performs no history I/O; a null path
// retains the configured path when disabling. Configuration/queries create no files.
// Invalid files are never overwritten
// by recording; enabling still configures the path so explicit clear can repair it.
int lexi_history(void* e, const char* path, int enabled);
// Records only a displayed ordinary candidate from the last query, using its
// code (ASCII case normalized) and effective mode (null means pinyin).
// Text must be <=16 Unicode codepoints / 128 UTF-8 bytes; segments/tool/emoji
// are excluded. Returns 1 recorded, 0 disabled, -1 invalid/error.
int lexi_record_selection(void* e, const char* code, const char* mode, const char* text);
// Explicitly replaces the configured shared file with an empty file under lock,
// even while disabled or if corrupt. Unconfigured engines are a successful no-op.
// Returns 0 or -1. All engines sharing a path must preserve its .lock sidecar.
int lexi_clear_history(void* e);
const char* lexi_query(void* engine, const char* code, const char* mode, const char* language, int correction);
const char* lexi_error(void* engine);
int lexi_count(void* engine);
int lexi_candidate_count(void* engine);
const char* lexi_candidate_field(void* engine, int index, int field);
#ifdef __cplusplus
}
#endif
