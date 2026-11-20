#include <stdio.h>
/* the parts share this preamble */
typedef struct { int a; int b; } Pair;

static int helper(int x);
int twice(int x);
extern char const names[];
int counter;

static inline int sq(int x) { return x * x; }

static Pair const p1 = { 1, 2 };
static struct { int n; int xs[2]; } const anon1 = { 2, { 10, 20 } };
static char const *const greeting = "hi; {not a brace}";

static int helper(int x) { return x + p1.a + anon1.xs[1]; }

// a stray semicolon after a body is an empty declaration
int twice(int x) { counter++; return helper(x) * 2; };

char const names[] = "na'mes";

int main(void) {
  printf("%d %d %s %s %d %d %c\n", twice(sq(3)), p1.b, greeting, names, anon1.n, counter, '}');
  return 0;
}
