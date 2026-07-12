#pragma gnu
static inline unsigned long f(unsigned long a, unsigned long b) {
  for (unsigned long i = 0; i < b; ++i) a += i ? a : b;
  switch (a) { case 0: return 1; default: break; }
  return a;
}
