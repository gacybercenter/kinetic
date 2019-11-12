<?php
header('Content-type: text/plain');
$mac = ($_GET["mac"]);
exec("cat assignments/$mac", $host_data);
$type = explode("-", $host_data[0]);

if (strpos($host_data[1], 'ubuntu') !== false) {
exec("grep 'd-i netcfg/choose_interface' preseed/$type[0].preseed | awk '{ print $4 }'", $interface);
$bootfile = file_get_contents("preseed.pxe");
$bootfile = str_replace("http://pxe/preseed/host-type.preseed", "http://pxe/preseed/".$type[0].".preseed", $bootfile);
$bootfile = str_replace("undefined-hostname", "$host_data[0]", $bootfile);
$bootfile = str_replace("interface=auto", "interface=$interface[0]", $bootfile);
echo $bootfile;
}

if (strpos($host_data[1], 'centos') !== false) {
exec("grep 'network --bootproto=dhcp' kickstart/$type[0].kickstart | cut -d'=' -f 3", $interface);
$bootfile = file_get_contents("kickstart.pxe");
$bootfile = str_replace("http://pxe/kickstart/host-type.kickstart", "http://pxe/kickstart/".$type[0].".kickstart", $bootfile);
$bootfile = str_replace("undefined-hostname", "$host_data[0]", $bootfile);
$bootfile = str_replace(":undefined-interface", ":$interface[0]", $bootfile);
echo $bootfile;
}
?>
