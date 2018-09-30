<?php
$mac = ($_GET["mac"]);
exec("grep $mac hosts", $output);
$type_array = explode("=", $output[0]);
$type = $type_array[1];
?>
