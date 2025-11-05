#ifndef LLAMA_H
#define LLAMA_H

#include "ggml.h"
#include "ggml-backend.h"

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#ifdef LLAMA_SHARED
#    if defined(_WIN32) && !defined(__MINGW32__)
#        ifdef LLAMA_BUILD
#            define LLAMA_API __declspec(dllexport)
#        else
#            define LLAMA_API __declspec(dllimport)
#        endif
#    else
#        define LLAMA_API __attribute__ ((visibility ("default")))
#    endif
#else
#    define LLAMA_API
#endif

#ifdef __GNUC__
#    define DEPRECATED(func, hint) func __attribute__((deprecated(hint)))
#elif defined(_MSC_VER)
#    define DEPRECATED(func, hint) __declspec(deprecated(hint)) func
#else
#    define DEPRECATED(func, hint) func
#endif

#define LLAMA_DEFAULT_SEED 0xFFFFFFFF

#define LLAMA_TOKEN_NULL -1

#define LLAMA_FILE_MAGIC_GGLA 0x67676c61u // 'ggla'
#define LLAMA_FILE_MAGIC_GGSN 0x6767736eu // 'ggsn'
#define LLAMA_FILE_MAGIC_GGSQ 0x67677371u // 'ggsq'

#define LLAMA_SESSION_MAGIC   LLAMA_FILE_MAGIC_GGSN
#define LLAMA_SESSION_VERSION 9

#define LLAMA_STATE_SEQ_MAGIC   LLAMA_FILE_MAGIC_GGSQ
#define LLAMA_STATE_SEQ_VERSION 2

#ifdef __cplusplus
extern "C" {
#endif

    //
    // C interface
    //
    // TODO: show sample usage
    //

    struct llama_vocab;

    typedef int32_t llama_pos;
    typedef int32_t llama_token;
    typedef int32_t llama_seq_id;

    enum llama_vocab_type {
        LLAMA_VOCAB_TYPE_NONE = 0, // For models without vocab
        LLAMA_VOCAB_TYPE_SPM  = 1, // LLaMA tokenizer based on byte-level BPE with byte fallback
        LLAMA_VOCAB_TYPE_BPE  = 2, // GPT-2 tokenizer based on byte-level BPE
        LLAMA_VOCAB_TYPE_WPM  = 3, // BERT tokenizer based on WordPiece
        LLAMA_VOCAB_TYPE_UGM  = 4, // T5 tokenizer based on Unigram
        LLAMA_VOCAB_TYPE_RWKV = 5, // RWKV tokenizer based on greedy tokenization
    };

    // pre-tokenization types
    enum llama_vocab_pre_type {
        LLAMA_VOCAB_PRE_TYPE_DEFAULT        = 0,
        LLAMA_VOCAB_PRE_TYPE_LLAMA3         = 1,
        LLAMA_VOCAB_PRE_TYPE_DEEPSEEK_LLM   = 2,
        LLAMA_VOCAB_PRE_TYPE_DEEPSEEK_CODER = 3,
        LLAMA_VOCAB_PRE_TYPE_FALCON         = 4,
        LLAMA_VOCAB_PRE_TYPE_MPT            = 5,
        LLAMA_VOCAB_PRE_TYPE_STARCODER      = 6,
        LLAMA_VOCAB_PRE_TYPE_GPT2           = 7,
        LLAMA_VOCAB_PRE_TYPE_REFACT         = 8,
        LLAMA_VOCAB_PRE_TYPE_COMMAND_R      = 9,
        LLAMA_VOCAB_PRE_TYPE_STABLELM2      = 10,
        LLAMA_VOCAB_PRE_TYPE_QWEN2          = 11,
        LLAMA_VOCAB_PRE_TYPE_OLMO           = 12,
        LLAMA_VOCAB_PRE_TYPE_DBRX           = 13,
        LLAMA_VOCAB_PRE_TYPE_SMAUG          = 14,
        LLAMA_VOCAB_PRE_TYPE_PORO           = 15,
        LLAMA_VOCAB_PRE_TYPE_CHATGLM3       = 16,
        LLAMA_VOCAB_PRE_TYPE_CHATGLM4       = 17,
        LLAMA_VOCAB_PRE_TYPE_VIKING         = 18,
        LLAMA_VOCAB_PRE_TYPE_JAIS           = 19,
        LLAMA_VOCAB_PRE_TYPE_TEKKEN         = 20,
        LLAMA_VOCAB_PRE_TYPE_SMOLLM         = 21,
        LLAMA_VOCAB_PRE_TYPE_CODESHELL      = 22,
        LLAMA_VOCAB_PRE_TYPE_BLOOM          = 23,
        LLAMA_VOCAB_PRE_TYPE_GPT3_FINNISH   = 24,
        LLAMA_VOCAB_PRE_TYPE_EXAONE         = 25,
        LLAMA_VOCAB_PRE_TYPE_CHAMELEON      = 26,
        LLAMA_VOCAB_PRE_TYPE_MINERVA        = 27,
        LLAMA_VOCAB_PRE_TYPE_DEEPSEEK3_LLM  = 28,
        LLAMA_VOCAB_PRE_TYPE_GPT4O          = 29,
        LLAMA_VOCAB_PRE_TYPE_SUPERBPE       = 30,
        LLAMA_VOCAB_PRE_TYPE_TRILLION       = 31,
        LLAMA_VOCAB_PRE_TYPE_BAILINGMOE     = 32,
        LLAMA_VOCAB_PRE_TYPE_LLAMA4         = 33,
    };

    enum llama_rope_type {
        LLAMA_ROPE_TYPE_NONE   = -1,
        LLAMA_ROPE_TYPE_NORM   = 0,
        LLAMA_ROPE_TYPE_NEOX   = GGML_ROPE_TYPE_NEOX,
        LLAMA_ROPE_TYPE_MROPE  = GGML_ROPE_TYPE_MROPE,
        LLAMA_ROPE_TYPE_VISION = GGML_ROPE_TYPE_VISION,
    };

    enum llama_token_type { //TODO: remove, required until per token attributes are available from GGUF file
        LLAMA_TOKEN_TYPE_UNDEFINED    = 0,
        LLAMA_TOKEN_TYPE_NORMAL       = 1,
        LLAMA_TOKEN_TYPE_UNKNOWN      = 2,
        LLAMA_TOKEN_TYPE_CONTROL      = 3,
        LLAMA_TOKEN_TYPE_USER_DEFINED = 4,
        LLAMA_TOKEN_TYPE_UNUSED       = 5,
        LLAMA_TOKEN_TYPE_BYTE         = 6,
    };

    enum llama_token_attr {
        LLAMA_TOKEN_ATTR_UNDEFINED    = 0,
        LLAMA_TOKEN_ATTR_UNKNOWN      = 1 << 0,
        LLAMA_TOKEN_ATTR_UNUSED       = 1 << 1,
        LLAMA_TOKEN_ATTR_NORMAL       = 1 << 2,
        LLAMA_TOKEN_ATTR_CONTROL      = 1 << 3,  // SPECIAL?
        LLAMA_TOKEN_ATTR_USER_DEFINED = 1 << 4,
        LLAMA_TOKEN_ATTR_BYTE         = 1 << 5,
        LLAMA_TOKEN_ATTR_NORMALIZED   = 1 << 6,
        LLAMA_TOKEN_ATTR_LSTRIP       = 1 << 7,
        LLAMA_TOKEN_ATTR_RSTRIP       = 1 << 8,
        LLAMA_TOKEN_ATTR_SINGLE_WORD  = 1 << 9,
    };

    // model file types
    enum llama_ftype {
        LLAMA_FTYPE_ALL_F32              = 0,
        LLAMA_FTYPE_MOSTLY_F16           = 1,  // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q4_0          = 2,  // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q4_1          = 3,  // except 1d tensors
        // LLAMA_FTYPE_MOSTLY_Q4_1_SOME_F16 = 4,  // tok_embeddings.weight and output.weight are F16
        // LLAMA_FTYPE_MOSTLY_Q4_2       = 5,  // support has been removed
        // LLAMA_FTYPE_MOSTLY_Q4_3       = 6,  // support has been removed
        LLAMA_FTYPE_MOSTLY_Q8_0          = 7,  // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q5_0          = 8,  // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q5_1          = 9,  // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q2_K          = 10, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q3_K_S        = 11, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q3_K_M        = 12, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q3_K_L        = 13, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q4_K_S        = 14, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q4_K_M        = 15, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q5_K_S        = 16, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q5_K_M        = 17, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q6_K          = 18, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_IQ2_XXS       = 19, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_IQ2_XS        = 20, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_Q2_K_S        = 21, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_IQ3_XS        = 22, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_IQ3_XXS       = 23, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_IQ1_S         = 24, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_IQ4_NL        = 25, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_IQ3_S         = 26, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_IQ3_M         = 27, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_IQ2_S         = 28, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_IQ2_M         = 29, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_IQ4_XS        = 30, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_IQ1_M         = 31, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_BF16          = 32, // except 1d tensors
        //LLAMA_FTYPE_MOSTLY_Q4_0_4_4      = 33, // removed from gguf files, use Q4_0 and runtime repack
        //LLAMA_FTYPE_MOSTLY_Q4_0_4_8      = 34, // removed from gguf files, use Q4_0 and runtime repack
        //LLAMA_FTYPE_MOSTLY_Q4_0_8_8      = 35, // removed from gguf files, use Q4_0 and runtime repack
        LLAMA_FTYPE_MOSTLY_TQ1_0         = 36, // except 1d tensors
        LLAMA_FTYPE_MOSTLY_TQ2_0         = 37, // except 1d tensors

        LLAMA_FTYPE_GUESSED = 1024, // not specified in the model file
    };

    enum llama_rope_scaling_type {
        LLAMA_ROPE_SCALING_TYPE_UNSPECIFIED = -1,
        LLAMA_ROPE_SCALING_TYPE_NONE        = 0,
        LLAMA_ROPE_SCALING_TYPE_LINEAR      = 1,
        LLAMA_ROPE_SCALING_TYPE_YARN        = 2,
        LLAMA_ROPE_SCALING_TYPE_LONGROPE    = 3,
        LLAMA_ROPE_SCALING_TYPE_MAX_VALUE   = LLAMA_ROPE_SCALING_TYPE_LONGROPE,
    };

    enum llama_pooling_type {
        LLAMA_POOLING_TYPE_UNSPECIFIED = -1,
        LLAMA_POOLING_TYPE_NONE = 0,
        LLAMA_POOLING_TYPE_MEAN = 1,
        LLAMA_POOLING_TYPE_CLS  = 2,
        LLAMA_POOLING_TYPE_LAST = 3,
        LLAMA_POOLING_TYPE_RANK = 4, // used by reranking models to attach the classification head to the graph
    };

    enum llama_attention_type {
        LLAMA_ATTENTION_TYPE_UNSPECIFIED = -1,
        LLAMA_ATTENTION_TYPE_CAUSAL      = 0,
        LLAMA_ATTENTION_TYPE_NON_CAUSAL  = 1,
    };

    enum llama_split_mode {
        LLAMA_SPLIT_MODE_NONE  = 0, // single GPU
        LLAMA_SPLIT_MODE_LAYER = 1, // split layers and KV across GPUs
        LLAMA_SPLIT_MODE_ROW   = 2, // split layers and KV across GPUs, use tensor parallelism if supported
    };

    // TODO: simplify (https://github.com/ggml-org/llama.cpp/pull/9294#pullrequestreview-2286561979)
    typedef struct llama_token_data {
        llama_token id; // token id
        float logit;    // log-odds of the token
        float p;        // probability of the token
    } llama_token_data;

    typedef struct llama_token_data_array {
        // TODO: consider SoA
        // NOTE: this pointer can be modified by the samplers
        llama_token_data * data;
        size_t size;
        int64_t selected; // this is the index in the data array (i.e. not the token id)
        bool sorted;
    } llama_token_data_array;

    typedef bool (*llama_progress_callback)(float progress, void * user_data);

    enum llama_model_kv_override_type {
        LLAMA_KV_OVERRIDE_TYPE_INT,
        LLAMA_KV_OVERRIDE_TYPE_FLOAT,
        LLAMA_KV_OVERRIDE_TYPE_BOOL,
        LLAMA_KV_OVERRIDE_TYPE_STR,
    };

    struct llama_model_kv_override {
        enum llama_model_kv_override_type tag;

        char key[128];

        union {
            int64_t val_i64;
            double  val_f64;
            bool    val_bool;
            char    val_str[128];
        };
    };

    struct llama_model_tensor_buft_override {
        const char * pattern;
        ggml_backend_buffer_type_t buft;
    };

    struct llama_model_params {
        // NULL-terminated list of devices to use for offloading (if NULL, all available devices are used)
        ggml_backend_dev_t * devices;

        // NULL-terminated list of buffer types to use for tensors that match a pattern
        const struct llama_model_tensor_buft_override * tensor_buft_overrides;

        int32_t n_gpu_layers; // number of layers to store in VRAM
        enum llama_split_mode split_mode; // how to split the model across multiple GPUs

        // the GPU that is used for the entire model when split_mode is LLAMA_SPLIT_MODE_NONE
        int32_t main_gpu;

        // proportion of the model (layers or rows) to offload to each GPU, size: llama_max_devices()
        const float * tensor_split;

        // Called with a progress value between 0.0 and 1.0. Pass NULL to disable.
        // If the provided progress_callback returns true, model loading continues.
        // If it returns false, model loading is immediately aborted.
        llama_progress_callback progress_callback;

        // context pointer passed to the progress callback
        void * progress_callback_user_data;

        // override key-value pairs of the model meta data
        const struct llama_model_kv_override * kv_overrides;

        // Keep the booleans together to avoid misalignment during copy-by-value.
        bool vocab_only;    // only load the vocabulary, no weights
        bool use_mmap;      // use mmap if possible
        bool use_mlock;     // force system to keep model in RAM
        bool check_tensors; // validate model tensor data
    };

    typedef struct llama_logit_bias {
        llama_token token;
        float bias;
    } llama_logit_bias;

    typedef struct llama_sampler_chain_params {
        bool no_perf; // whether to measure performance timings
    } llama_sampler_chain_params;

    // used in chat template
    typedef struct llama_chat_message {
        const char * role;
        const char * content;
    } llama_chat_message;

    // lora adapter
    struct llama_adapter_lora;

    // Helpers for getting default parameters
    // TODO: update API to start accepting pointers to params structs (https://github.com/ggml-org/llama.cpp/discussions/9172)
    LLAMA_API struct llama_sampler_chain_params  llama_sampler_chain_default_params(void);

    // Initialize the llama + ggml backend
    // If numa is true, use NUMA optimizations
    // Call once at the start of the program
    LLAMA_API void llama_backend_init(void);

    // Call once at the end of the program - currently only used for MPI
    LLAMA_API void llama_backend_free(void);

    //optional:

    // LLAMA_API int64_t llama_time_us(void);

    LLAMA_API size_t llama_max_devices(void);

    LLAMA_API bool llama_supports_mmap       (void);
    LLAMA_API bool llama_supports_mlock      (void);
    LLAMA_API bool llama_supports_gpu_offload(void);
    LLAMA_API bool llama_supports_rpc        (void);

    DEPRECATED(LLAMA_API int32_t llama_n_vocab    (const struct llama_vocab * vocab), "use llama_vocab_n_tokens instead");

    // Get the model's RoPE frequency scaling factor
    LLAMA_API enum llama_vocab_type llama_vocab_type(const struct llama_vocab * vocab);

    LLAMA_API int32_t llama_vocab_n_tokens(const struct llama_vocab * vocab);

    //
    // Vocab
    //

    LLAMA_API llama_vocab * llama_load_vocab_from_file(const char * fname,
                                                            bool use_mmap,
                                                            bool check_tensors,
                                                            const llama_model_kv_override * param_overrides_p);
    LLAMA_API llama_vocab * llama_load_vocab_from_buffer(const void * model_buffer,
                                                            size_t buffer_size,
                                                            bool use_mmap,
                                                            bool check_tensors,
                                                            const llama_model_kv_override * param_overrides_p);
                
    LLAMA_API void llama_vocab_free(llama_vocab * vocab);

    LLAMA_API const char * llama_vocab_get_text(const struct llama_vocab * vocab, llama_token token);

    LLAMA_API float llama_vocab_get_score(const struct llama_vocab * vocab, llama_token token);

    LLAMA_API enum llama_token_attr llama_vocab_get_attr(const struct llama_vocab * vocab, llama_token token);

    // Check if the token is supposed to end generation (end-of-generation, eg. EOS, EOT, etc.)
    LLAMA_API bool llama_vocab_is_eog(const struct llama_vocab * vocab, llama_token token);

    // Identify if Token Id is a control token or a render-able token
    LLAMA_API bool llama_vocab_is_control(const struct llama_vocab * vocab, llama_token token);

    LLAMA_API uint32_t llama_vocab_size(const struct llama_vocab * vocab);

    LLAMA_API int max_token_len(const struct llama_vocab * vocab);

    // Special tokens
    LLAMA_API llama_token llama_vocab_bos(const struct llama_vocab * vocab); // beginning-of-sentence
    LLAMA_API llama_token llama_vocab_eos(const struct llama_vocab * vocab); // end-of-sentence
    LLAMA_API llama_token llama_vocab_eot(const struct llama_vocab * vocab); // end-of-turn
    LLAMA_API llama_token llama_vocab_eom(const struct llama_vocab * vocab); // end-of-message
    LLAMA_API llama_token llama_vocab_sep(const struct llama_vocab * vocab); // sentence separator
    LLAMA_API llama_token llama_vocab_nl (const struct llama_vocab * vocab); // next-line
    LLAMA_API llama_token llama_vocab_pad(const struct llama_vocab * vocab); // padding

    LLAMA_API bool llama_vocab_get_add_bos(const struct llama_vocab * vocab);
    LLAMA_API bool llama_vocab_get_add_eos(const struct llama_vocab * vocab);

    LLAMA_API llama_token llama_vocab_fim_pre(const struct llama_vocab * vocab);
    LLAMA_API llama_token llama_vocab_fim_suf(const struct llama_vocab * vocab);
    LLAMA_API llama_token llama_vocab_fim_mid(const struct llama_vocab * vocab);
    LLAMA_API llama_token llama_vocab_fim_pad(const struct llama_vocab * vocab);
    LLAMA_API llama_token llama_vocab_fim_rep(const struct llama_vocab * vocab);
    LLAMA_API llama_token llama_vocab_fim_sep(const struct llama_vocab * vocab);

    DEPRECATED(LLAMA_API const char * llama_token_get_text(const struct llama_vocab * vocab, llama_token token), "use llama_vocab_get_text instead");
    DEPRECATED(LLAMA_API float llama_token_get_score(const struct llama_vocab * vocab, llama_token token), "use llama_vocab_get_score instead");
    DEPRECATED(LLAMA_API enum llama_token_attr llama_token_get_attr(const struct llama_vocab * vocab, llama_token token), "use llama_vocab_get_attr instead");
    DEPRECATED(LLAMA_API bool llama_token_is_eog(const struct llama_vocab * vocab, llama_token token), "use llama_vocab_is_eog instead");
    DEPRECATED(LLAMA_API bool llama_token_is_control(const struct llama_vocab * vocab, llama_token token), "use llama_vocab_is_control instead");
    DEPRECATED(LLAMA_API llama_token llama_token_bos(const struct llama_vocab * vocab), "use llama_vocab_bos instead");
    DEPRECATED(LLAMA_API llama_token llama_token_eos(const struct llama_vocab * vocab), "use llama_vocab_eos instead");
    DEPRECATED(LLAMA_API llama_token llama_token_eot(const struct llama_vocab * vocab), "use llama_vocab_eot instead");
    DEPRECATED(LLAMA_API llama_token llama_token_cls(const struct llama_vocab * vocab), "use llama_vocab_cls instead");
    DEPRECATED(LLAMA_API llama_token llama_token_sep(const struct llama_vocab * vocab), "use llama_vocab_sep instead");
    DEPRECATED(LLAMA_API llama_token llama_token_nl (const struct llama_vocab * vocab), "use llama_vocab_nl instead");
    DEPRECATED(LLAMA_API llama_token llama_token_pad(const struct llama_vocab * vocab), "use llama_vocab_pad instead");
    DEPRECATED(LLAMA_API bool llama_add_bos_token(const struct llama_vocab * vocab), "use llama_vocab_get_add_bos instead");
    DEPRECATED(LLAMA_API bool llama_add_eos_token(const struct llama_vocab * vocab), "use llama_vocab_get_add_eos instead");
    DEPRECATED(LLAMA_API llama_token llama_token_fim_pre(const struct llama_vocab * vocab), "use llama_vocab_fim_pre instead");
    DEPRECATED(LLAMA_API llama_token llama_token_fim_suf(const struct llama_vocab * vocab), "use llama_vocab_fim_suf instead");
    DEPRECATED(LLAMA_API llama_token llama_token_fim_mid(const struct llama_vocab * vocab), "use llama_vocab_fim_mid instead");
    DEPRECATED(LLAMA_API llama_token llama_token_fim_pad(const struct llama_vocab * vocab), "use llama_vocab_fim_pad instead");
    DEPRECATED(LLAMA_API llama_token llama_token_fim_rep(const struct llama_vocab * vocab), "use llama_vocab_fim_rep instead");
    DEPRECATED(LLAMA_API llama_token llama_token_fim_sep(const struct llama_vocab * vocab), "use llama_vocab_fim_sep instead");

    // CLS is equivalent to BOS
    DEPRECATED(LLAMA_API llama_token llama_vocab_cls(const struct llama_vocab * vocab), // classification
            "use llama_vocab_bos instead");

    //
    // Tokenization
    //
    // The API is thread-safe.
    //

    /// @details Convert the provided text into tokens.
    /// @param tokens The tokens pointer must be large enough to hold the resulting tokens.
    /// @return Returns the number of tokens on success, no more than n_tokens_max
    /// @return Returns a negative number on failure - the number of tokens that would have been returned
    /// @param add_special Allow to add BOS and EOS tokens if model is configured to do so.
    /// @param parse_special Allow tokenizing special and/or control tokens which otherwise are not exposed and treated
    ///                      as plaintext. Does not insert a leading space.
    LLAMA_API int32_t llama_tokenize(
        const struct llama_vocab * vocab,
                      const char * text,
                         int32_t   text_len,
                     llama_token * tokens,
                         int32_t   n_tokens_max,
                            bool   add_special,
                            bool   parse_special);

    // Token Id -> Piece.
    // Uses the vocabulary in the provided context.
    // Does not write null terminator to the buffer.
    // User can skip up to 'lstrip' leading spaces before copying (useful when encoding/decoding multiple tokens with 'add_space_prefix')
    // @param special If true, special tokens are rendered in the output.
    LLAMA_API int32_t llama_token_to_piece(
              const struct llama_vocab * vocab,
                           llama_token   token,
                                  char * buf,
                               int32_t   length,
                               int32_t   lstrip,
                                  bool   special);

    /// @details Convert the provided tokens into text (inverse of llama_tokenize()).
    /// @param text The char pointer must be large enough to hold the resulting text.
    /// @return Returns the number of chars/bytes on success, no more than text_len_max.
    /// @return Returns a negative number on failure - the number of chars/bytes that would have been returned.
    /// @param remove_special Allow to remove BOS and EOS tokens if model is configured to do so.
    /// @param unparse_special If true, special tokens are rendered in the output.
    LLAMA_API int32_t llama_detokenize(
        const struct llama_vocab * vocab,
               const llama_token * tokens,
                         int32_t   n_tokens,
                            char * text,
                         int32_t   text_len_max,
                            bool   remove_special,
                            bool   unparse_special);

    //
    // Model split
    //

    /// @details Build a split GGUF final path for this chunk.
    ///          llama_split_path(split_path, sizeof(split_path), "/models/ggml-model-q4_0", 2, 4) => split_path = "/models/ggml-model-q4_0-00002-of-00004.gguf"
    //  Returns the split_path length.
    LLAMA_API int llama_split_path(char * split_path, size_t maxlen, const char * path_prefix, int split_no, int split_count);

    /// @details Extract the path prefix from the split_path if and only if the split_no and split_count match.
    ///          llama_split_prefix(split_prefix, 64, "/models/ggml-model-q4_0-00002-of-00004.gguf", 2, 4) => split_prefix = "/models/ggml-model-q4_0"
    //  Returns the split_prefix length.
    LLAMA_API int llama_split_prefix(char * split_prefix, size_t maxlen, const char * split_path, int split_no, int split_count);

    // Print system information
    // LLAMA_API const char * llama_print_system_info(void);

    // Set callback for all future logging events.
    // If this is not called, or NULL is supplied, everything is output on stderr.
    LLAMA_API void llama_log_set(ggml_log_callback log_callback, void * user_data);

#ifdef __cplusplus
}
#endif

#endif // LLAMA_H
