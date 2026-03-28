#pragma once

// Forward declare A's function
int get_a_value();

// B's function that A will call
inline int get_b_value() { return 7; }

// B's function that calls A
int compute_b();
