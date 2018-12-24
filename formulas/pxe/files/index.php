<?php
header('Content-type: text/plain');
$mac = ($_GET["mac"]);
exec("grep $mac hosts", $output);
$type_array = explode(" = ", $output[0]);
$type = $type_array[1];
exec("echo -n $type-$(uuidgen)", $hostname);
exec("grep 'd-i netcfg/choose_interface' preseed/$type.preseed | awk '{ print $4 }'", $interface);
$bootfile = file_get_contents("common.pxe");
$bootfile = str_replace("http://pxe/preseed/host-type.preseed", "http://".$_SERVER['SERVER_ADDR']."/preseed/".$type.".preseed", $bootfile);
$bootfile = str_replace("undefined-hostname", "$hostname[0]", $bootfile);
$bootfile = str_replace("interface=auto", "interface=$interface[0]", $bootfile);
if (!is_dir('pending_hosts/' . $type)) {
  mkdir('pending_hosts/' . $type);
}
file_put_contents("pending_hosts/$type/$hostname[0]","$hostname[0]");
echo $bootfile;
?>
