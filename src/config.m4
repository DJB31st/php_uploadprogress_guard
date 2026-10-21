PHP_ARG_ENABLE(hp_uploadprogress_guard, whether to enable hp_uploadprogress_guard,
[  --enable-hp-uploadprogress-guard   Enable hp_uploadprogress_guard], yes)
if test "$PHP_HP_UPLOADPROGRESS_GUARD" != "no"; then
  PHP_NEW_EXTENSION(hp_uploadprogress_guard, hp_uploadprogress_guard.c, $ext_shared)
fi
