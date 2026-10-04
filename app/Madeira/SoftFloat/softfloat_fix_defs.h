/* Compile guards for FEX's vendored SoftFloat-3e. FEX configures these via
 * target compile definitions during its own build; the app's vendored helper
 * .c files replicate the same set so primitives.h/internals.h compile with
 * matching inline settings (INLINE_LEVEL=4 makes primitives static-inline,
 * so no external primitives symbols are needed at link time). */
#if !defined(SOFTFLOAT_BUILTIN_CLZ)
#define SOFTFLOAT_BUILTIN_CLZ 1
#endif
#if !defined(INLINE_LEVEL)
#define INLINE_LEVEL 4
#endif
#if !defined(INLINE)
#define INLINE static inline
#endif
#if !defined(SOFTFLOAT_FAST_INT64)
#define SOFTFLOAT_FAST_INT64 1
#endif
#if !defined(SOFTFLOAT_FAST_DIV32TO16)
#define SOFTFLOAT_FAST_DIV32TO16 1
#endif
#if !defined(SOFTFLOAT_FAST_DIV64TO32)
#define SOFTFLOAT_FAST_DIV64TO32 1
#endif