<?php
header('Content-Type: text/plain');
echo "code=", http_response_code(), " post=", count($_POST), " files=", count($_FILES),
	" peak=", round(memory_get_peak_usage(true) / 1048576), "M",
	" guard=", (int) extension_loaded('hp_uploadprogress_guard'), "\n";
