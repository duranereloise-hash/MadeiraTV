/* SoftFloat-3e F128 fused-multiply-add — minimal state-free definition
 * compatible with FEX's vendored SoftFloat. FEX declares softfloat_mulAddF128
 * without a struct softfloat_state but does not compile a body for it; this
 * table is only needed for the final app link. a*b is computed with the
 * public state-based f128_mul/f128_add under a local default state. */

#include "softfloat_fix_defs.h"
#include <stdbool.h>
#include <stdint.h>
#include "platform.h"
#include "internals.h"
#include "specialize.h"
#include "softfloat.h"

float128_t
 softfloat_mulAddF128(
     uint_fast64_t uiA64, uint_fast64_t uiA0,
     uint_fast64_t uiB64, uint_fast64_t uiB0,
     uint_fast64_t uiC64, uint_fast64_t uiC0,
     uint_fast8_t op )
{
    struct softfloat_state st;
    union ui128_f128 uA, uB, uC, uZ;

    (void) op;

    uA.ui.v64 = uiA64; uA.ui.v0  = uiA0;
    uB.ui.v64 = uiB64; uB.ui.v0  = uiB0;
    uC.ui.v64 = uiC64; uC.ui.v0  = uiC0;

    uZ.ui.v64 = defaultNaNF128UI64;
    uZ.ui.v0  = defaultNaNF128UI0;

    if ( expF128UI64( uiA64 ) == 0x7FFF || expF128UI64( uiB64 ) == 0x7FFF ||
         expF128UI64( uiC64 ) == 0x7FFF ) {
        return uZ.f;
    }

    st.detectTininess = softfloat_tininess_beforeRounding;
    st.roundingMode   = softfloat_round_near_even;
    st.exceptionFlags = 0;
    st.roundingPrecision = 80;

    uZ.f = f128_add( &st, f128_mul( &st, uA.f, uB.f ), uC.f );
    return uZ.f;
}