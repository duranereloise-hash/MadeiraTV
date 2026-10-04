/* SoftFloat-3e F16 rounding helper — state-free variant compatible with FEX's
 * vendored SoftFloat. Rounds to nearest, ties to even; flags are not reported
 * (no softfloat_state in this internal's FEX signature). */

#include "softfloat_fix_defs.h"
#include <stdbool.h>
#include <stdint.h>
#include "platform.h"
#include "internals.h"
#include "softfloat.h"

float16_t
 softfloat_roundPackToF16( bool sign, int_fast16_t exp, uint_fast16_t sig )
{
    const uint_fast8_t roundingMode = softfloat_round_near_even;
    bool roundNearEven = true;
    uint_fast8_t roundIncrement = 0x8;
    uint_fast8_t roundBits;
    uint_fast16_t uiZ;
    union ui16_f16 uZ;

    roundBits = sig & 0xF;
    if ( 0x1D <= (unsigned int) exp ) {
        if ( exp < 0 ) {
            bool isTiny = (exp < -1) || (sig + roundIncrement < 0x8000);
            sig = softfloat_shiftRightJam32( sig, -exp );
            exp = 0;
            roundBits = sig & 0xF;
            (void) isTiny;
        } else if ( (0x1D < exp) || (0x8000 <= sig + roundIncrement) ) {
            uiZ = packToF16UI( sign, 0x1F, 0 ) - ! roundIncrement;
            goto uiZ;
        }
    }
    sig = (sig + roundIncrement)>>4;
    sig &= ~(uint_fast16_t) (! (roundBits ^ 8) & roundNearEven);
    if ( ! sig ) exp = 0;
    uiZ = packToF16UI( sign, exp, sig );
 uiZ:
    uZ.ui = uiZ;
    return uZ.f;
}