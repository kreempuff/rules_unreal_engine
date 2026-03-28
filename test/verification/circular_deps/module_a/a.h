#pragma once

// Forward declare B's function
int get_b_value();

// A's function that B will call
inline int get_a_value() { return 42; }

// A's function that calls B
int compute_a();
