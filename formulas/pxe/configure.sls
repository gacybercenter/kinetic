include:
  - /formulas/pxe/install

php7.0_module:
  apache_module.enabled:
    - name: php7.0

/var/www/html/index.html:
  file.absent

/var/www/html/index.php:
  file.managed:
    - contents: |
        <?php
        phpinfo();
        ?>
