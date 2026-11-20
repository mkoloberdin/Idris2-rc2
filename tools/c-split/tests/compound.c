typedef struct { int a; int b; } Pair;
Pair p2 = (Pair){ 3, 4 };
int f(void) { return p2.a; }
