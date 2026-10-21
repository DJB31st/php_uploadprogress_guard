PHP_ARG_ENABLE(hp_multipart_guard, whether to enable hp_multipart_guard,
[  --enable-hp-multipart-guard   Enable hp_multipart_guard], yes)
if test "$PHP_HP_MULTIPART_GUARD" != "no"; then
  PHP_NEW_EXTENSION(hp_multipart_guard, hp_multipart_guard.c rfc1867_copy.c, $ext_shared)
fi
