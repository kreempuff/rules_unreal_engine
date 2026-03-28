#include "a.h"
#include "b.h"  // A includes B's header — circular at header level

int compute_a() {
    return get_a_value() + get_b_value();
}
