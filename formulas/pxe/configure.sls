include:
  - /formulas/pxe/install

php7.0_module:
  apache_module.enabled

/var/www/html/index.html:
  file.missing

/var/www/html/index.php:
  file.managed:
    - contents: |
        <?php
        phpinfo();
        ?>
