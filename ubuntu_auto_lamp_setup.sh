#!/bin/bash -e -a
#########################################################
# This script is intended to be run like this:
#
#   curl -s https://website.com/ubuntu_auto_lamp_setup.sh | bash
#
#########################################################

# Make sure the script is running as root?
if [[ $EUID -ne 0 ]]
  then
    echo "This script must be run as root."
    exit
fi

# Update
echo ">>> Updating our list of packages ..."
apt-get update > /dev/null


echo ">>> Installing Base Items ( curl, wget, certbot, expect ) ..."
# Install base items
apt-get install -y curl wget expect certbot > /dev/null

#########################################################
# Install LAMP Stack
#########################################################

echo
read -p "- Would you like to install LAMP stack? (y/n): " install_lamp < /dev/tty
if [[ $install_lamp = 'y' ]]; then

    echo
    echo "==============================================="
    echo ">>> LAMP Stack Installation"
    echo "==============================================="
    echo

    if ! whereis apache2 | grep -q "/"; then

        echo
        echo ">>> Installing Apache"
        echo

        # Install Apache and the Apache certbot plugin using Ubuntu’s package manager 
        apt-get update > /dev/null
        apt install -y apache2 python3-certbot-apache

        # disable the default website that comes installed with Apache.
        a2dissite 000-default

    else
        echo
        echo ">>> Apache Already Installed"
        echo
    fi

    # allow port 80 traffic 
    ufw allow 'Apache' > /dev/null

    if ! whereis mysql | grep -q "/"; then

        echo
        echo ">>> Installing MYSQL"
        echo

        # Install MySQL without prompt ( pre-seed the debconf database with root user password)
        debconf-set-selections <<< 'mysql-server mysql-server/root_password password root'
        debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password root'

        # Install MySQL package
        apt-get update > /dev/null
        apt install -y  mysql-server

        # Securing MySQL
        echo
        echo ">>> Securing MYSQL"
        echo

        # Default password
        MYSQL_ROOT_PASSWORD="root"

        SECURE_MYSQL=$(expect -c "
        set timeout 2
        spawn mysql_secure_installation
        expect \"Enter password for user root:\"
        send \"root\r\"
        expect \"Press y|Y for Yes, any other key for No:\"
        send \"n\r\"
        expect \"Change the password for root ? ((Press y|Y for Yes, any other key for No)\"
        send \"n\r\"
        expect \"Remove anonymous users?\"
        send \"y\r\"
        expect \"Disallow root login remotely?\"
        send \"y\r\"
        expect \"Remove test database and access to it?\"
        send \"y\r\"
        expect \"Reload privilege tables now?\"
        send \"y\r\"
        expect eof
        ")

        echo "$SECURE_MYSQL"

    else

        echo
        echo ">>> MySQL Already Installed"
        echo

    fi

    if ! whereis php | grep -q "/"; then

        echo
        echo ">>> Installing PHP"
        echo

        # Install PHP and other packages ( php-mysql, a PHP module that allows PHP to communicate with MySQL-based databases. 'libapache2-mod-php' to enable Apache to handle PHP files.  )
        apt-get update > /dev/null
        apt install -y php libapache2-mod-php php-mysql

    else

        echo
        echo ">>> PHP Already Installed"
        echo

    fi
fi
#########################################################
# Website(s) Configuration
#########################################################
echo
read -p "- Would you like to create virtual host(s) for your site(s) ? (y/n): " website_creation < /dev/tty
if [[ $website_creation = 'y' ]]; then

    echo
    echo "==============================================="
    echo ">>> Virtual Host(s) Configuration"
    echo "==============================================="
    echo

    echo
    echo ">>> Creating virtual host for your site(s)"
    echo

    echo
    echo "- Enter all the domains (without www.) you want to host on this server (Print 'save' when finished):"
    while IFS= read -r line < /dev/tty || exit; do
        [[ $line = "save" ]] && break
        [[ $line =~ "www." ]] && continue
        if [[ $line =~ "." ]]; then
            # Create the directory for the domain
            mkdir /var/www/html/"$line"

            # Assign ownership of the directory with the $USER environment variable, which will reference your current system user
            chown -R $USER:$USER /var/www/html/"$line"

            # Create test files
            echo '<html>
<head>
     <title>'$line' website</title>
</head>
<body>
    <h1>Hello World!</h1>
    <p>Welcome to <strong>'$line'</strong>.</p>
</body>
</html>' > /var/www/html/"$line"/index.html
            echo '<?php
phpinfo();' > /var/www/html/"$line"/info.php

            # Create virtual host
            echo '<VirtualHost *:80>
    ServerName '$line'
    ServerAlias www.'$line'
    ServerAdmin admin@'$line'
    DocumentRoot /var/www/html/'$line'
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>' > /etc/apache2/sites-available/"$line".conf

            echo '<VirtualHost *:80>
    ServerName '$line'
    ServerAlias www.'$line'
    ServerAdmin admin@'$line'
    DocumentRoot /var/www/html/'$line'
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>' > /etc/apache2/sites-available/"$line".conf

            # Enable the new virtual host
            a2ensite "$line" > /dev/null

            # Display success message
            echo "> Record for "$line" was created succesfully."
        fi
    done
fi

echo
read -p "- Would you like to use LetsEncrypt (certbot) to configure SSL(https) for your existing site(s)?
  Note 1: This will generate a certificate for every virtual host on your apache server.
  Note 2: Do this only if your domain(s) DNS is pointing correctly to this server.
  (y/n): " generate_cert < /dev/tty
if [[ $generate_cert = 'y' ]]; then

    echo
    echo "==============================================="
    echo ">>> SSL Configuration"
    echo "==============================================="
    echo

    # Register with Let's Encrypt, including agreeing to the Terms of Service.
    # We'd let certbot ask the user interactively, but when this script is
    # run in the recommended curl-pipe-to-bash method there is no TTY and
    # certbot will fail if it tries to ask.
    if [ ! -d /etc/letsencrypt/accounts/acme-v02.api.letsencrypt.org/ ]; then
        echo
        echo "-----------------------------------------------"
        echo "We're automatically agreeing to Let's Encrypt subscriber agreement."
        echo "See https://letsencrypt.org."
        echo
        certbot register --register-unsafely-without-email --agree-tos --no-eff-email > /dev/null
    fi
    # Make sure no other Certbot instance is running ( avoid error "Another instance of Certbot is already running." )
    if find / -type f -name ".certbot.lock" > /dev/null; then
        find / -type f -name ".certbot.lock" -exec rm {} \;
    fi

    # Find all vhost files ( default.conf & ssl.conf ) and add their content to a temporary file
    find /etc/apache2/sites-available -type f -name "*.conf" -not -name "*ssl.conf" -not -name "*default.conf" -not -name "www.*" -exec cat {} \; > temp-vhost.txt
    # Use 'awk' on the temporary file content to extract existing domain into an array
    existing_domains=($(awk '$1 ~ /^(ServerName)/ { for (i=2; i<=NF; i++) print $i }' temp-vhost.txt))

    # Convert the array to the format we can use to use the domains on certbot command
    deli=""
    joined_domains=""
    for site in "${existing_domains[@]}"; do
        read -p "- Would you like to configure SSL for $site
  (y/n): " generate_cert_for_site < /dev/tty
        if [[ $generate_cert_for_site = 'y' ]]; then
            joined_domains+="$deli$site"
            deli=","
        fi
    done
    # Remove the temp file
    rm temp-vhost.txt

    echo
    echo ">>> Generate SSL certifcate(s) for the selected domain(s):"
    echo
    # Make sure Certbot will run non-interactively
    # Allow it to enable the site and SSL modules for us
    certbot --apache -n -d "$joined_domains" --redirect --keep-until-expiring --expand --apache-handle-modules "True" --apache-handle-sites "True"

    # Run cron job for auto-renewal ( if it doesn't already exist )
    if ! crontab -l &> /dev/null | grep -q "certbot renew"; then
        crontab -l &> /dev/null > cronjobs.txt #Dump the existing cron jobs to a file
        echo "15 3 * * * /usr/bin/certbot renew --quiet" >> cronjobs.txt # Add a new job to the file
        cat cronjobs.txt > /var/spool/cron/crontabs/"$USER" # Replace content of crontab with our cron jobs file
        rm cronjobs.txt
    fi

    # allow traffic secure for Apache profile ( Use 'ufw status' to verify  )
    ufw allow 'Apache Full' > /dev/null
    ufw delete allow 'Apache' > /dev/null

fi

# Reload apache2 so our changes would take effect
systemctl reload apache2

echo ">>> Running clean up ..."

# Remove 'expect' package
apt-get purge -y expect > /dev/null
# Remove packages that are no longer needed
apt-get autoremove -y > /dev/null