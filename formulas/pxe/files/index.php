<?php
header('Content-type: text/plain');
$mac = ($_GET["mac"]);
exec("grep $mac hosts", $output);
$type_array = explode(" = ", $output[0]);
$type = $type_array[1];
exec("echo -n $type-$(uuidgen)", $hostname);
$bootfile = file_get_contents("$type.pxe");
$bootfile = str_replace("http://pxe", "http://".$_SERVER['SERVER_ADDR'], $bootfile);
$bootfile = str_replace("undefined-hostname", "$hostname[0]", $bootfile);
echo $bootfile;
?>
