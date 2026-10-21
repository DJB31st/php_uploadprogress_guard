/*
 * hp_uploadprogress_guard - owns PHP's multipart/form-data post handler.
 *
 * At MINIT the SAPI post entry for multipart/form-data (main/rfc1867.c's handler) is replaced by
 * ours. Two modes, selected by the INI_SYSTEM setting hp_uploadprogress_guard.mode:
 *   parse  (default) hand the request to the copy of main/rfc1867.c compiled into this module
 *                    (rfc1867_copy.c), so a patched parser can ship without rebuilding PHP.
 *   block            refuse the request before any parsing: the body is never read, $_POST and
 *                    $_FILES stay empty, the response code is set to 415 and a warning is logged.
 *                    Emergency mode for CVE-2026-109618 / CVE-2026-109619 while no fix exists.
 * hp_uploadprogress_guard.allow_ips: comma separated client IPs that are always parsed (admins, monitoring).
 * hp_uploadprogress_guard.detach_upload_progress (default 1): at MINIT, after ext/session has started, drop
 *   ext/session's multipart upload-progress handler (php_session_rfc1867_callback) from main/rfc1867.c's
 *   callback pointer, so that handler is unreachable whatever session.upload_progress.* says.
 * All settings are PHP_INI_SYSTEM: php.ini / php-fpm.conf only, never .user.ini, .htaccess or ini_set().
 */
#ifdef HAVE_CONFIG_H
#include "config.h"
#endif
#include "php.h"
#include "php_ini.h"
#include "ext/standard/info.h"
#include "SAPI.h"
#include "rfc1867.h"
#include <string.h>

#define HP_MPG_VERSION "2.0.0"
#define HP_MPG_NAME "hp_uploadprogress_guard"

SAPI_API SAPI_POST_HANDLER_FUNC(hp_rfc1867_post_handler);
static SAPI_POST_HANDLER_FUNC(hp_upg_dispatch);

static sapi_post_entry hp_upg_entry = { MULTIPART_CONTENT_TYPE, sizeof(MULTIPART_CONTENT_TYPE) - 1, NULL, hp_upg_dispatch };
static int hp_upg_installed = 0;
static int hp_upg_detached = 0;

PHP_INI_BEGIN()
	PHP_INI_ENTRY("hp_uploadprogress_guard.mode", "parse", PHP_INI_SYSTEM, NULL)
	PHP_INI_ENTRY("hp_uploadprogress_guard.allow_ips", "", PHP_INI_SYSTEM, NULL)
	PHP_INI_ENTRY("hp_uploadprogress_guard.detach_upload_progress", "1", PHP_INI_SYSTEM, NULL)
PHP_INI_END()

static int hp_upg_client_allowed(void)
{
	const char *allow = INI_STR("hp_uploadprogress_guard.allow_ips");
	char *ip;
	int allowed = 0;

	if (!allow || !*allow) {
		return 0;
	}
#if PHP_VERSION_ID < 70000
	ip = sapi_getenv("REMOTE_ADDR", sizeof("REMOTE_ADDR") - 1 TSRMLS_CC);
#else
	ip = sapi_getenv("REMOTE_ADDR", sizeof("REMOTE_ADDR") - 1);
#endif
	if (ip && *ip) {
		size_t iplen = strlen(ip);
		const char *p = allow;
		while (*p) {
			const char *q;
			while (*p == ' ' || *p == ',') p++;
			q = p;
			while (*q && *q != ',' && *q != ' ') q++;
			if ((size_t)(q - p) == iplen && memcmp(p, ip, iplen) == 0) {
				allowed = 1;
				break;
			}
			p = q;
		}
	}
	if (ip) {
		efree(ip);
	}
	return allowed;
}

static SAPI_POST_HANDLER_FUNC(hp_upg_dispatch)
{
	const char *mode = INI_STR("hp_uploadprogress_guard.mode");

	if (mode && strcmp(mode, "block") == 0 && !hp_upg_client_allowed()) {
		/* Nothing is read from the body; the SAPI discards it. */
		SG(sapi_headers).http_response_code = 415;
		/* error log only: never the output stream, whatever display_errors says */
#if PHP_VERSION_ID < 70000
		php_log_err("hp_uploadprogress_guard: multipart/form-data request refused (mode=block)" TSRMLS_CC);
#else
		php_log_err("hp_uploadprogress_guard: multipart/form-data request refused (mode=block)");
#endif
		return;
	}
#if PHP_VERSION_ID < 70000
	hp_rfc1867_post_handler(content_type_dup, arg TSRMLS_CC);
#else
	hp_rfc1867_post_handler(content_type_dup, arg);
#endif
}

static PHP_MINIT_FUNCTION(hp_uploadprogress_guard)
{
	REGISTER_INI_ENTRIES();
#if PHP_VERSION_ID < 70000
	sapi_unregister_post_entry(&hp_upg_entry TSRMLS_CC);
	if (sapi_register_post_entry(&hp_upg_entry TSRMLS_CC) == SUCCESS) {
#else
	sapi_unregister_post_entry(&hp_upg_entry);
	if (sapi_register_post_entry(&hp_upg_entry) == SUCCESS) {
#endif
		hp_upg_installed = 1;
	}
	if (INI_BOOL("hp_uploadprogress_guard.detach_upload_progress") && php_rfc1867_callback != NULL) {
		php_rfc1867_callback = NULL;
		hp_upg_detached = 1;
	}
	return SUCCESS;
}

static PHP_MSHUTDOWN_FUNCTION(hp_uploadprogress_guard)
{
	UNREGISTER_INI_ENTRIES();
	return SUCCESS;
}

static PHP_MINFO_FUNCTION(hp_uploadprogress_guard)
{
	php_info_print_table_start();
	php_info_print_table_row(2, HP_MPG_NAME, "enabled");
	php_info_print_table_row(2, "version", HP_MPG_VERSION);
	php_info_print_table_row(2, "multipart/form-data handler replaced", hp_upg_installed ? "yes" : "no");
	php_info_print_table_row(2, "mode", INI_STR("hp_uploadprogress_guard.mode"));
	php_info_print_table_row(2, "session.upload_progress handler detached", hp_upg_detached ? "yes" : "no");
	php_info_print_table_end();
	DISPLAY_INI_ENTRIES();
}

static const zend_module_dep hp_upg_deps[] = {
	ZEND_MOD_OPTIONAL("session")
	ZEND_MOD_END
};

zend_module_entry hp_uploadprogress_guard_module_entry = {
	STANDARD_MODULE_HEADER_EX,
	NULL,
	hp_upg_deps,
	HP_MPG_NAME,
	NULL,
	PHP_MINIT(hp_uploadprogress_guard),
	PHP_MSHUTDOWN(hp_uploadprogress_guard),
	NULL,
	NULL,
	PHP_MINFO(hp_uploadprogress_guard),
	HP_MPG_VERSION,
	STANDARD_MODULE_PROPERTIES
};

#ifdef COMPILE_DL_HP_UPLOADPROGRESS_GUARD
ZEND_GET_MODULE(hp_uploadprogress_guard)
#endif
