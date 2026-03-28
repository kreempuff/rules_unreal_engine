#include "b.h"
#include "a.h"  // B includes A's header — circular at header level

int compute_b() {
    return get_b_value() + get_a_value();
}
