<?php
header('Content-type: text/plain');
$mac = ($_GET["mac"]);
exec("cat assignments/$mac", $hostname);
$type = explode("-", $hostname[0]);
exec("grep 'd-i netcfg/choose_interface' preseed/$type[0].preseed | awk '{ print $4 }'", $interface);
$bootfile = file_get_contents("common.pxe");
$bootfile = str_replace("http://pxe/preseed/host-type.preseed", "http://".$_SERVER['SERVER_ADDR']."/preseed/".$type[0].".preseed", $bootfile);
$bootfile = str_replace("undefined-hostname", "$hostname[0]", $bootfile);
$bootfile = str_replace("interface=auto", "interface=$interface[0]", $bootfile);
echo $bootfile;
echo $type[0];
?>
