<?php
header('Content-type: text/plain');
$mac = ($_GET["mac"]);
exec("grep $mac hosts", $output);
$type_array = explode(" = ", $output[0]);
$type = $type_array[1];
$bootfile = file_get_contents("$type.pxe");
echo $bootfile;
?>
