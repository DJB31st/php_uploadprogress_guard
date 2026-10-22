/* Bind memcpy to its oldest x86_64 symbol version so the binaries load on glibc < 2.14 (CentOS 6 and
 * older). glibc 2.14 only added a new memcpy symbol version; the old one is the same function. */
#if defined(__x86_64__) && defined(__GLIBC__) && !defined(HP_GLIBC_COMPAT_H)
#define HP_GLIBC_COMPAT_H
__asm__(".symver memcpy,memcpy@GLIBC_2.2.5");
#endif
