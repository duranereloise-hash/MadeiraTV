/* SoftFloat-3e int32 conversion helper — state-free variant compatible with
 * FEX's vendored SoftFloat (which has no global exceptionFlags/roundingMode).
 * Round-to-nearest-even; flags are not reported because the FEX API has no
 * state parameter for this internal. */

#include "softfloat_fix_defs.h"
#include <stdbool.h>
#include <stdint.h>
#include "platform.h"
#include "internals.h"
#include "specialize.h"
#include "softfloat.h"

uint_fast32_t
 softfloat_roundToUI32(
     bool sign, uint_fast64_t sig, uint_fast8_t roundingMode, bool exact )
{
    uint_fast16_t roundIncrement, roundBits;
    uint_fast32_t z;

    (void) exact;
    roundIncrement = 0x800;
    if (
        (roundingMode != softfloat_round_near_maxMag)
            && (roundingMode != softfloat_round_near_even)
    ) {
        roundIncrement = 0;
        if ( sign ) {
            if ( !sig ) return 0;
            if ( roundingMode == softfloat_round_min ) goto invalid;
#ifdef SOFTFLOAT_ROUND_ODD
            if ( roundingMode == softfloat_round_odd ) goto invalid;
#endif
        } else {
            if ( roundingMode == softfloat_round_max ) roundIncrement = 0xFFF;
        }
    }
    roundBits = sig & 0xFFF;
    sig += roundIncrement;
    if ( sig & UINT64_C( 0xFFFFF00000000000 ) ) goto invalid;
    z = sig>>12;
    if (
        (roundBits == 0x800) && (roundingMode == softfloat_round_near_even)
    ) {
        z &= ~(uint_fast32_t) 1;
    }
    if ( sign && z ) goto invalid;
    return z;
 invalid:
    return sign ? ui32_fromNegOverflow : ui32_fromPosOverflow;
}