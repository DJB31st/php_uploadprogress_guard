<?php

session_start();
header('Content-Type: text/plain');
echo "sapi=", PHP_SAPI, " guard=", (int)extension_loaded('hp_uploadprogress_guard'), " ini=", ini_get('session.upload_progress.enabled'), "\n";
echo "post_keys=", implode(',', array_keys($_POST)), "\n";
echo "files=", count($_FILES), " size=", $_FILES['f']['size'] ?? -1, " err=", $_FILES['f']['error'] ?? -1, "\n";
echo "session_keys=", implode(',', array_keys($_SESSION)), "\n";
