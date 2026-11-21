// This module was licensed by BSD3.

#include <string.h>
#include "CollectSafe.h"

int64_t idris2rc2_testcs_add(int64_t a, int64_t b) { return a + b; }
int64_t idris2rc2_testcs_len(const char *s) { return (int64_t)strlen(s); }
// Wrong on purpose: a call to this means `C__collect_safe:` won over `C:`.
int64_t idris2rc2_testcs_wrong(void) { return 999; }
int64_t idris2rc2_testcs_right(void) { return 7; }
