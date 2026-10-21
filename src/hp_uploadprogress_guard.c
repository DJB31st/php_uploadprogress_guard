/*
 * hp_uploadprogress_guard - Hosted Power mitigation for CVE-2026-109618 /
 * CVE-2026-109619 (heap use-after-free in ext/session's multipart upload
 * progress handler, php_session_rfc1867_callback).
 *
 * main/rfc1867.c only invokes the multipart event callback when the global
 * function pointer php_rfc1867_callback is non-NULL. ext/session installs
 * its handler into that pointer in PHP_MINIT(session). This module declares
 * an (optional) dependency on session so it is started after it, and then
 * detaches the handler. The vulnerable code can no longer be reached from a
 * request, whatever session.upload_progress.* is set to in php.ini,
 * .user.ini, .htaccess or ini_set(). Everything else about sessions and file
 * uploads keeps working; only the session.upload_progress feature is gone.
 *
 * One source file builds unchanged against PHP 5.4 .. 8.5.
 */
#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "php.h"
#include "ext/standard/info.h"
#include "main/rfc1867.h"

#define HP_UPG_VERSION "1.0.0"
#define HP_UPG_NAME "hp_uploadprogress_guard"

static int hp_upg_detached = 0;

static PHP_MINIT_FUNCTION(hp_uploadprogress_guard)
{
	if (php_rfc1867_callback != NULL) {
		php_rfc1867_callback = NULL;
		hp_upg_detached = 1;
	}
	return SUCCESS;
}

static PHP_MINFO_FUNCTION(hp_uploadprogress_guard)
{
	php_info_print_table_start();
	php_info_print_table_row(2, HP_UPG_NAME, "enabled");
	php_info_print_table_row(2, "version", HP_UPG_VERSION);
	php_info_print_table_row(2, "rfc1867 (session.upload_progress) callback detached", hp_upg_detached ? "yes" : "no (none was installed)");
	php_info_print_table_end();
}

static const zend_module_dep hp_uploadprogress_guard_deps[] = {
	ZEND_MOD_OPTIONAL("session")
	ZEND_MOD_END
};

zend_module_entry hp_uploadprogress_guard_module_entry = {
	STANDARD_MODULE_HEADER_EX,
	NULL,
	hp_uploadprogress_guard_deps,
	HP_UPG_NAME,
	NULL,
	PHP_MINIT(hp_uploadprogress_guard),
	NULL,
	NULL,
	NULL,
	PHP_MINFO(hp_uploadprogress_guard),
	HP_UPG_VERSION,
	STANDARD_MODULE_PROPERTIES
};

#ifdef COMPILE_DL_HP_UPLOADPROGRESS_GUARD
ZEND_GET_MODULE(hp_uploadprogress_guard)
#endif
