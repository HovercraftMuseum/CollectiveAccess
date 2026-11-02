<?php
/* ----------------------------------------------------------------------
 * CollectiveAccess Providence - default setup.php for this container image
 * ----------------------------------------------------------------------
 *
 * This file is baked into the image and contains NO secrets and no
 * site-specific values. Every setting is read from environment variables
 * (normally set via compose.yaml and your .env file).
 *
 * Prefer to manage setup.php yourself? Copy setup.php-dist from the
 * Providence release, edit it, and mount it over /var/www/html/setup.php.
 * Your file then takes precedence and image updates never overwrite it.
 *
 * Any variable can also be supplied as a file by setting <NAME>_FILE to
 * the path of a file containing the value (Docker secrets convention),
 * e.g. CA_DB_PASSWORD_FILE=/run/secrets/ca_db_password
 *
 * Based on setup.php-dist from Providence 2.0.11. When upgrading CA,
 * compare this file with the new release's setup.php-dist for new options.
 * ----------------------------------------------------------------------
 */

if (!function_exists('ca_env')) {
	function ca_env(string $name, $default = null) {
		$file = getenv($name.'_FILE');
		if ($file !== false && $file !== '' && is_readable($file)) {
			return rtrim(file_get_contents($file), "\r\n");
		}
		$value = getenv($name);
		return ($value === false || $value === '') ? $default : $value;
	}
}
if (!function_exists('ca_env_bool')) {
	function ca_env_bool(string $name, bool $default = false) : bool {
		$value = ca_env($name);
		if ($value === null) { return $default; }
		return in_array(strtolower((string)$value), ['1', 'true', 'yes', 'on'], true);
	}
}

# --------------------------------------------------------------------------------------------
# Database
# --------------------------------------------------------------------------------------------
if (!defined("__CA_DB_HOST__")) {
	define("__CA_DB_HOST__", ca_env('CA_DB_HOST', 'db'));
}
if (!defined("__CA_DB_PORT__")) {
	define("__CA_DB_PORT__", ca_env('CA_DB_PORT', '3306'));
}
if (!defined("__CA_DB_USER__")) {
	define("__CA_DB_USER__", ca_env('CA_DB_USER', 'collectiveaccess'));
}
if (!defined("__CA_DB_PASSWORD__")) {
	define("__CA_DB_PASSWORD__", ca_env('CA_DB_PASSWORD', ''));
}
if (!defined("__CA_DB_DATABASE__")) {
	define("__CA_DB_DATABASE__", ca_env('CA_DB_DATABASE', 'collectiveaccess'));
}

# --------------------------------------------------------------------------------------------
# Identity
# --------------------------------------------------------------------------------------------
if (!defined("__CA_APP_DISPLAY_NAME__")) {
	define("__CA_APP_DISPLAY_NAME__", ca_env('CA_APP_DISPLAY_NAME', 'CollectiveAccess'));
}
if (!defined("__CA_ADMIN_EMAIL__")) {
	define("__CA_ADMIN_EMAIL__", ca_env('CA_ADMIN_EMAIL', 'admin@example.org'));
}

# Fixed on purpose: the media directory path is derived from this name
# (media/<app_name>), and the media volume is mounted at that path.
if (!defined("__CA_APP_NAME__")) {
	define("__CA_APP_NAME__", "collectiveaccess");
}

if (!defined("__CA_AUTH_ADAPTER__")) {
	define("__CA_AUTH_ADAPTER__", ca_env('CA_AUTH_ADAPTER', 'CaUsers'));
}

# --------------------------------------------------------------------------------------------
# Outgoing email (optional)
# --------------------------------------------------------------------------------------------
if (ca_env('CA_SMTP_SERVER')) {
	if (!defined("__CA_SMTP_SERVER__")) { define("__CA_SMTP_SERVER__", ca_env('CA_SMTP_SERVER')); }
	if (!defined("__CA_SMTP_PORT__")) { define("__CA_SMTP_PORT__", ca_env('CA_SMTP_PORT', '587')); }
	if (!defined("__CA_SMTP_AUTH__")) { define("__CA_SMTP_AUTH__", ca_env('CA_SMTP_AUTH', 'LOGIN')); }
	if (!defined("__CA_SMTP_USER__")) { define("__CA_SMTP_USER__", ca_env('CA_SMTP_USER', '')); }
	if (!defined("__CA_SMTP_PASSWORD__")) { define("__CA_SMTP_PASSWORD__", ca_env('CA_SMTP_PASSWORD', '')); }
	if (!defined("__CA_SMTP_SSL__")) { define("__CA_SMTP_SSL__", ca_env('CA_SMTP_SSL', 'TLS')); }
}

# --------------------------------------------------------------------------------------------
# Locale and time
# --------------------------------------------------------------------------------------------
# Note: CA docs advise switching to 'UTC' *before* running bulk data imports,
# otherwise dates may import incorrectly.
date_default_timezone_set(ca_env('CA_TIMEZONE', 'UTC'));

# Must exist in the locale list of the installation profile you choose.
if (!defined("__CA_DEFAULT_LOCALE__")) {
	define("__CA_DEFAULT_LOCALE__", ca_env('CA_DEFAULT_LOCALE', 'en_US'));
}

# --------------------------------------------------------------------------------------------
# Background processing
# --------------------------------------------------------------------------------------------
# Large media is queued and processed in the background. In CA 2.0 the web
# container launches `caUtils process-task-queue` itself at the end of a
# request (app.conf: background_process_mode = process), so no cron job or
# separate worker container is required.
if (!defined("__CA_QUEUE_ENABLED__")) {
	define("__CA_QUEUE_ENABLED__", ca_env_bool('CA_QUEUE_ENABLED', true) ? 1 : 0);
}

# --------------------------------------------------------------------------------------------
# URLs
# --------------------------------------------------------------------------------------------
# Apache mod_rewrite is enabled in the image, so clean URLs can be used.
if (!defined("__CA_USE_CLEAN_URLS__")) {
	define("__CA_USE_CLEAN_URLS__", ca_env_bool('CA_USE_CLEAN_URLS', false) ? 1 : 0);
}

# Uncomment and set via env only if CA cannot work out its own hostname
# (for example behind some reverse proxies).
if (ca_env('CA_SITE_HOSTNAME') && !defined("__CA_SITE_HOSTNAME__")) {
	define("__CA_SITE_HOSTNAME__", ca_env('CA_SITE_HOSTNAME'));
}
if (ca_env('CA_SITE_PROTOCOL') && !defined("__CA_SITE_PROTOCOL__")) {
	define("__CA_SITE_PROTOCOL__", ca_env('CA_SITE_PROTOCOL'));
}

# --------------------------------------------------------------------------------------------
# Paths: keep writable state outside the code tree so the image stays immutable
# --------------------------------------------------------------------------------------------
if (!defined("__CA_TEMP_DIR__")) {
	define("__CA_TEMP_DIR__", ca_env('CA_TEMP_DIR', '/var/lib/collectiveaccess/tmp/ca'));
}
if (!defined("__CA_LOG_DIR__")) {
	define("__CA_LOG_DIR__", ca_env('CA_LOG_DIR', '/var/lib/collectiveaccess/log'));
}

# --------------------------------------------------------------------------------------------
# Caching
# --------------------------------------------------------------------------------------------
# 'redis' is recommended by CA for performance. Falls back to 'file' if unset.
if (!defined('__CA_CACHE_BACKEND__')) {
	define('__CA_CACHE_BACKEND__', ca_env('CA_CACHE_BACKEND', 'redis'));
}
if (!defined('__CA_REDIS_HOST__')) {
	define('__CA_REDIS_HOST__', ca_env('CA_REDIS_HOST', 'redis'));
}
if (!defined('__CA_REDIS_PORT__')) {
	define('__CA_REDIS_PORT__', (int)ca_env('CA_REDIS_PORT', 6379));
}
if (!defined('__CA_REDIS_DB__')) {
	define('__CA_REDIS_DB__', (int)ca_env('CA_REDIS_DB', 0));
}

# --------------------------------------------------------------------------------------------
# Optional services
# --------------------------------------------------------------------------------------------
if (!defined("__CA_GOOGLE_MAPS_KEY__")) {
	define("__CA_GOOGLE_MAPS_KEY__", ca_env('CA_GOOGLE_MAPS_KEY', ''));
}
if (!defined("__CA_HC_INFO_KEY__")) {
	define('__CA_HC_INFO_KEY__', ca_env('CA_HC_INFO_KEY'));
}

# --------------------------------------------------------------------------------------------
# Database TLS (not needed when the database runs in the same compose stack)
# --------------------------------------------------------------------------------------------
if (!defined("__CA_DB_USE_SSL__")) {
	define("__CA_DB_USE_SSL__", ca_env_bool('CA_DB_USE_SSL', false));
}
if (!defined("__CA_DB_SSL_VERIFY_CERT__")) {
	define("__CA_DB_SSL_VERIFY_CERT__", true);
}
if (!defined("__CA_DB_SSL_KEY__")) {
	define("__CA_DB_SSL_KEY__", null);
}
if (!defined("__CA_DB_SSL_CERTIFICATE__")) {
	define("__CA_DB_SSL_CERTIFICATE__", null);
}
if (!defined("__CA_DB_SSL_CA_CERTIFICATE__")) {
	define("__CA_DB_SSL_CA_CERTIFICATE__", null);
}
if (!defined("__CA_DB_SSL_CA_PATH__")) {
	define("__CA_DB_SSL_CA_PATH__", null);
}

# --------------------------------------------------------------------------------------------
# Safety switches
# --------------------------------------------------------------------------------------------
# DANGER: allows the web installer to wipe an existing database. Only ever
# enable briefly while evaluating installation profiles on a test copy.
if (!defined('__CA_ALLOW_INSTALLER_TO_OVERWRITE_EXISTING_INSTALLS__')) {
	define('__CA_ALLOW_INSTALLER_TO_OVERWRITE_EXISTING_INSTALLS__', ca_env_bool('CA_ALLOW_INSTALLER_OVERWRITE', false));
}

# Show detailed errors on screen. Keep false in production.
if (!defined('__CA_STACKTRACE_ON_EXCEPTION__')) {
	define('__CA_STACKTRACE_ON_EXCEPTION__', ca_env_bool('CA_STACKTRACE_ON_EXCEPTION', false));
}

require(__DIR__."/app/helpers/post-setup.php");
