#!/bin/bash

# PrimeMover.io

# Universal WordPress VPS Migration Assistant

# Copyright 2018 PrimeMover.io - K. Patrick Gallagher

# Easily move WordPress sites between two different servers managed by GridPane, ServerPilot, RunCloud and Others...

# You'll need to already have manually built your sites at RunCloud and have WordPress successfully running there BEFORE trying to move sites in from other sources.
# ServerPilot site build code (via API) is already built but needs to be reintegrated to this work. 

source ~/.bash_profile

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root, exiting!!!" 
   exit 1
fi

# Check is PV is installed, and install if needed...
if ! type "pv" > /dev/null; then
	echo "PV was not installed... fixing..."
  	apt -y install pv
fi

mkdir -p /var/tmp/primemover

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source vendor-specific functions
source "${SCRIPT_DIR}/vendors/serverpilot.sh"
source "${SCRIPT_DIR}/vendors/runcloud.sh"
source "${SCRIPT_DIR}/vendors/gridpane.sh"
source "${SCRIPT_DIR}/vendors/cpanel.sh"

ipaddress=$(curl http://ip4.ident.me 2>/dev/null)

MigrateType=$1

# Logging setup for better troubleshooting
LOGFILE="/var/tmp/primemover/migration-$(date +%Y%m%d-%H%M%S).log"

LogMessage() {
	local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
	echo "$message" | tee -a "$LOGFILE"
}

# Validate GridPane API token
ValidateGridPaneToken() {
	if [[ $MigrateType == *"2GP"* ]] || [[ $MigrateType == "GP2GP" ]]; then
		if [ -z "$gridpanetoken" ]; then
			echo ""
			echo "ERROR: GridPane API token is required for GridPane migrations!"
			echo "Please enter your GridPane API token (found at https://my.gridpane.com/api):"
			read -r gridpanetoken < /dev/tty

			if [ -z "$gridpanetoken" ]; then
				echo "ERROR: Cannot proceed without GridPane API token. Exiting..."
				exit 1
			fi

			# Test the token with a simple API call
			LogMessage "Testing GridPane API token..."
			local test_result=$(curl -s -o /dev/null -w "%{http_code}" "https://my.gridpane.com/api/servers?api_token=$gridpanetoken")

			if [ "$test_result" != "200" ]; then
				echo "ERROR: GridPane API token appears to be invalid (HTTP $test_result)"
				echo "Please verify your token at https://my.gridpane.com/api"
				exit 1
			fi

			LogMessage "GridPane API token validated successfully"

			# Save token to bash_profile for future use
			if ! grep -q "export gridpanetoken=" ~/.bash_profile 2>/dev/null; then
				echo "export gridpanetoken=\"$gridpanetoken\"" >> ~/.bash_profile
				LogMessage "GridPane token saved to ~/.bash_profile"
			fi
		fi
	fi
}

# Check available disk space before starting
CheckDiskSpace() {
	local path=$1
	local required_gb=${2:-10}  # Default 10GB minimum

	LogMessage "Checking disk space at $path..."

	local available_kb=$(df "$path" | tail -1 | awk '{print $4}')
	local available_gb=$((available_kb / 1024 / 1024))

	if [ "$available_gb" -lt "$required_gb" ]; then
		echo ""
		echo "WARNING: Low disk space detected!"
		echo "Available: ${available_gb}GB"
		echo "Recommended minimum: ${required_gb}GB"
		echo ""
		echo "Site packaging creates temporary archives that can be very large."
		echo "Do you want to continue anyway? (yes/no)"
		read -r continue_anyway < /dev/tty

		if [[ ! "$continue_anyway" =~ ^[Yy][Ee][Ss]$ ]]; then
			echo "Migration cancelled due to insufficient disk space."
			exit 1
		fi
	else
		LogMessage "Disk space OK: ${available_gb}GB available"
	fi
}

# Improved error handling with detailed messages
HandleError() {
	local error_message=$1
	local site_name=${2:-"unknown"}
	local exit_code=${3:-1}

	LogMessage "ERROR: $error_message (Site: $site_name)"
	echo ""
	echo "=========================================="
	echo "ERROR OCCURRED"
	echo "=========================================="
	echo "Site: $site_name"
	echo "Error: $error_message"
	echo "Check log file: $LOGFILE"
	echo "=========================================="
	echo ""

	# Set global error flag
	y=1

	if [ "$exit_code" -eq 1 ]; then
		return 1
	fi
}

# Poll for remote site readiness instead of fixed sleep
WaitForRemoteSite() {
	local remote_ip=$1
	local site_domain=$2
	local max_wait=${3:-300}  # Default 5 minutes
	local elapsed=0

	LogMessage "Waiting for remote site $site_domain to be ready..."

	while [ $elapsed -lt $max_wait ]; do
		if ssh -n root@$remote_ip "[ -d /var/www/$site_domain/htdocs/wp-content/plugins/nginx-helper ]" 2>/dev/null; then
			LogMessage "Remote site is ready after ${elapsed} seconds"
			return 0
		fi

		sleep 5
		elapsed=$((elapsed + 5))

		if [ $((elapsed % 30)) -eq 0 ]; then
			echo "Still waiting for remote site... (${elapsed}s elapsed)"
		fi
	done

	HandleError "Timeout waiting for remote site to provision" "$site_domain"
	return 1
}

# Verify site after migration
VerifySiteMigration() {
	local remote_ip=$1
	local site_domain=$2

	LogMessage "Verifying migration for $site_domain..."

	# Check if WordPress is installed
	local wp_check=$(ssh -n root@$remote_ip "cd /var/www/$site_domain/htdocs && wp core is-installed --allow-root 2>&1" 2>&1)

	if [[ $wp_check == *"Error"* ]]; then
		HandleError "WordPress verification failed on remote site" "$site_domain" 0
		return 1
	fi

	# Check if database is accessible
	local db_check=$(ssh -n root@$remote_ip "cd /var/www/$site_domain/htdocs && wp db check --allow-root 2>&1" 2>&1)

	if [[ $db_check == *"Error"* ]] || [[ $db_check == *"error"* ]]; then
		HandleError "Database verification failed on remote site" "$site_domain" 0
		return 1
	fi

	# Get site URL to confirm
	local site_url=$(ssh -n root@$remote_ip "cd /var/www/$site_domain/htdocs && wp option get siteurl --allow-root 2>&1" 2>&1)

	LogMessage "Migration verified successfully! Site URL: $site_url"
	echo ""
	echo "✓ Migration verified successfully!"
	echo "  Site: $site_domain"
	echo "  URL: $site_url"
	echo ""

	return 0
}

MeImCounting() {
	
	echo "This is all very VERY aplha right now. Use at your own risk."
	echo " "
	echo "All kinds of things might be broken. It's a work in progress and we'll get it hammered out shortly."
	echo " "
	echo "Please feel free to help out."
	echo " "
	echo "Best of luck! Drop me a line at patrick at gridpane dot com"
	echo " "
	echo "You need to have already created SSH keys on both your source server and your destination server and shared them between the two."
	echo " "
	echo "This all automatically works if you're using GridPane because we (try, at least, to) kick all of the asses."

}
MeImCounting

CommandVariablesCheck() {
	
	#THIS IS OLD AND WILL SOON BE KILLED!!!
	#THIS IS OLD AND WILL SOON BE KILLED!!!
	#THIS IS OLD AND WILL SOON BE KILLED!!!
	
	# Checking correct startup variables
	if [ -z "$1" ] || [ -z "$2" ] 
	then
		echo " "
		echo " "
		echo "   ***************************************"
		echo "*******   ERROR - MISSING VARIABLES   *******"
		echo "   ***************************************"
		echo " "
		echo " "
		echo "Command line variables required: "
		echo " "
		echo " 1.) URL/ALL "
		echo " 2.) Target IP address "
		echo " 3.) *OPTIONAL* Source API token (GridPane servers only - ServerPilot and RunCloud API support coming soon) " 
		echo " 4.) *OPTIONAL* Target API token (GridPane servers only - ServerPilot and RunCloud API support coming soon) "
	
		# LOTS of work needs to be added in here to make this work seamlessly between SP and RC nodes, and between RC and RC, and between SP and SP, and... you get the point.
		echo " "
		echo " "
		exit 187;
	
	else
		# Set all the primary variables - Additional Variables - REQUIRED - But we'll get these soon... appname username finaldomain
		site_to_clone=$1
		remote_IP=$2	
		sourcetoken=$3
		targettoken=$3
	fi

}

# Install WP-CLI - Makes everything so much easier!!!
CheckWPcli() {
	
	if [ -f /usr/local/bin/wp ]
	then
		echo "WP-CLI is already installed, making sure it's the most current version..."
		yes | wp cli update --allow-root
	else
		curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
		chmod +x wp-cli.phar
		sudo mv wp-cli.phar /usr/local/bin/wp
	fi
	

	if [ -f /usr/local/bin/wp-completion.bash ]
	then
		if grep -q "source /usr/local/bin/wp-completion.bash" ~/.bash_profile; then 
		   echo "WP-CLI Bash Completion already set..."
		else
			echo "source /usr/local/bin/wp-completion.bash" >> ~/.bash_profile   
		fi
	else
		wget https://raw.githubusercontent.com/wp-cli/wp-cli/master/utils/wp-completion.bash
		mv wp-completion.bash /usr/local/bin/wp-completion.bash
	
		echo "source /usr/local/bin/wp-completion.bash" >> ~/.bash_profile
	fi

}
CheckWPcli

# Check is SSH key present, if not make it so... This currently only applies to migrating IN to GridPane servers... 
# Disabled by default because while I may be a total egotistical prick I recognize that you're MUCH more likely to be running on a SP or RC node than a GridPane managed box.

DoSSH() {
	
	if [ "$y" = "1" ]
	then
		echo "An error was detected during a previous function, skipping the site packaging step for this site..."
		return 1
	fi
	
	remote_IP=$1
	
	ipaddress=$(curl http://ip4.ident.me 2>/dev/null)
	
	if [ -f /root/.ssh/id_rsa.pub ]
	then
		echo "Local SSH Keys exist..." 
		echo ""
		
	else
		echo "We need to create a public key pair..." 
		echo "CREATING SSH!!!" 
		
		#echo -e "\n\n\n" | ssh-keygen -t rsa -b 4096
		ssh-keygen -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa
		
	fi
	
	echo "Checking remote connection to $remote_IP..."
	
	sshcheck=$(ssh-keygen -F $remote_IP 2>&1)
	
	if [ $? -eq 0 ]
	then
		echo "Remote host is already in the Known Hosts file..."
		echo ""
	else
		
		echo "Adding remote system at $remote_IP..."
		
		ssh-keyscan $remote_IP >> /root/.ssh/known_hosts
		
		echo "Remote host $remote_IP added to the known hosts file..."
	fi
	
	sshtatus=$(ssh -o BatchMode=yes -o ConnectTimeout=5 $remote_IP echo ok 2>&1)
	
	if [ "$sshtatus" == "ok" ]
	then
		echo "Remote SSH Test Successful..." 
	else
		if [[ $MigrateType == "RC2GP" ]] || [[ $MigrateType == "SP2GP" ]] || [[ $MigrateType == "GP2GP" ]]
		then
			curl -F "ssh_key=@/root/.ssh/id_rsa.pub" -F "source_ip=$ipaddress" -F "failover_ip=$remote_IP" https://my.gridpane.com/api/pair-external-servers?api_token=$gridpanetoken
			echo "Remote host added to the Known Hosts file..." 
			echo ""
		else
			echo "Attempting to connect to remote system at $remote_IP..."
	
			ssh-copy-id -i ~/.ssh/id_rsa.pub root@$remote_IP
		fi
			
	fi

}

















StartDomainLogging() {
	
	if [ -f /var/tmp/primemover.domains.tmp ]
	then
		rm /var/tmp/primemover.domains.tmp
	fi
	touch /var/tmp/primemover.domains.tmp

	echo ""
	echo "The following sites have been located on this server..."
	echo "************************************************************************************************************************"
	printf '%-20s %-40s %-20s %-30s %-30s\n' "APPLICATION" "DOMAIN" "USER" "LOCATION"
	echo "************************************************************************************************************************"
	
}

















# Build required site(s) on remote GridPane server 
# Currently works only with GridPane... cool your jets, I'm working on it.



DBExport() {

	if [ "$y" = "1" ]
	then
		HandleError "Previous function error detected, skipping database export" "${site_to_clone:-${appname}}" 0
		return 1
	fi

	LogMessage "Exporting database for ${site_to_clone:-${appname}}..."
	echo "Exporting Database..."

	export=$(wp db export database.sql --allow-root 2>&1)
	export_status=$?

	if [[ $export == *"PHP Parse error"* ]] || [ $export_status -ne 0 ]
	then
		LogMessage "WP-CLI export failed, attempting manual mysqldump..."
		echo "We have a config problem and WP-CLI can't run - attempting manual mysqldump..."

		WPDBNAME=`cat wp-config.php | grep DB_NAME | cut -d \' -f 4`
		WPDBUSER=`cat wp-config.php | grep DB_USER | cut -d \' -f 4`
		WPDBPASS=`cat wp-config.php | grep DB_PASSWORD | cut -d \' -f 4`

		if [ -z "$WPDBNAME" ] || [ -z "$WPDBUSER" ]; then
			HandleError "Cannot extract database credentials from wp-config.php" "${site_to_clone:-${appname}}"
			return 1
		fi

		mysqldump -u$WPDBUSER -p$WPDBPASS $WPDBNAME > database.sql 2>&1
		mysqldump_status=$?

		if [ $mysqldump_status -ne 0 ]; then
			HandleError "mysqldump failed with exit code $mysqldump_status" "${site_to_clone:-${appname}}"
			return 1
		fi

	else
		LogMessage "WP-CLI database export completed successfully"
		echo "Automated DB export completed successfully..."
	fi

	if [ -f database.sql ] && [ -s database.sql ]
	then
		local db_size=$(du -h database.sql | cut -f1)
		LogMessage "Database exported successfully (Size: $db_size)"
		echo "DB Exported successfully... (Size: $db_size)"
	else
		HandleError "Database file missing or empty after export" "${site_to_clone:-${appname}}"
		return 1
	fi

	chmod 400 database.sql
}

# Compress and package current site for secure copying

PackageSite() {
	
	if [ "$y" = "1" ]
	then
		echo "An error was detected during a previous function, skipping the site packaging step for this site..."
		return 1
	fi
	
	if [ $envir == "RC" ]
	then
		echo "Packaging local RunCloud powered site $appname for user $username..."

		cd /home/$username/webapps/$appname
		echo "Arrived at directory... $PWD"

		DBExport
		
		if [ "$y" = "1" ]
		then
			echo "An error was detected during a previous function, skipping the site packaging step for this site..."
			return 1
		fi

		#Need to get the DB prefix from wp-config... 
		tableprefix=$(sed -n -e '/$table_prefix/p' wp-config.php)
		echo $tableprefix > table.prefix
		chmod 400 table.prefix
		echo "Database Table Prefix Exported..."

		cp wp-config.php wp-config.last.config
		chmod 400 wp-config.last.config

		#tar -czf /home/$username/webapps/primemover-$appname-migration-file.gz . --exclude '*.zip' --exclude '*.gz' --exclude 'wp-config.php'
		
		tar -cf - . -P --exclude '*.zip' --exclude '*.gz' --exclude 'wp-config.php' | pv -s $(du -sb . | awk '{print $1}') | gzip > /home/$username/webapps/primemover-$appname-migration-file.gz

		echo "Cleaning up..."
		rm database.sql
		rm table.prefix
		rm wp-config.last.config
		
		echo "Site $site_to_clone has been successfully packed up..."
		
		sitepack="/home/$username/webapps/primemover-$appname-migration-file.gz"

	elif [ $envir == "SP" ]
	then
		echo "Packaging local ServerPilot powered site $appname for user $D..."
		
		# Get to the choppa...
		cd /srv/users/$username/apps/$appname/public
		echo "Arrived at directory... $PWD"
		
		DBExport
		
		if [ "$y" = "1" ]
		then
			echo "An error was detected during a previous function, skipping the site packaging step for this site..."
			return 1
		fi
		
		#Need to get the DB prefix from wp-config... 
		tableprefix=$(sed -n -e '/$table_prefix/p' wp-config.php)
		echo $tableprefix > table.prefix
		chmod 400 table.prefix
		echo "Database Table Prefix Exported..."

		cp wp-config.php wp-config.last.config
		chmod 400 wp-config.last.config

		#tar -czf /srv/users/$username/apps/$appname/primemover-$appname-migration-file.gz . --exclude '*.zip' --exclude '*.gz' --exclude 'wp-config.php'
		
		tar -cf - . -P --exclude '*.zip' --exclude '*.gz' --exclude 'wp-config.php' | pv -s $(du -sb . | awk '{print $1}') | gzip > /srv/users/$username/apps/$appname/primemover-$appname-migration-file.gz

		echo "Cleaning up..."
		rm database.sql
		rm table.prefix
		rm wp-config.last.config
		
		echo "Site $appname has been successfully packed up..."
		
		sitepack="/srv/users/$username/apps/$appname/primemover-$appname-migration-file.gz"
		
	elif [ $envir == "CP" ]
	then
		
		# HIGHLY EXPERIMENTAL!!! 
		
		echo "Packaging local CPanel powered site $appname for user $D..."
		
		# Get to the choppa...
		cd /home/$username/public_html/
		echo "Arrived at directory... $PWD"
		
		echo "Exporting DB..."
		DBExport
		
		if [ "$y" = "1" ]
		then
			echo "An error was detected during a previous function, skipping the site packaging step for this site..."
			return 1
		fi
		
		#Need to get the DB prefix from wp-config... 
		tableprefix=$(sed -n -e '/$table_prefix/p' wp-config.php)
		echo $tableprefix > table.prefix
		chmod 400 table.prefix
		echo "Database Table Prefix Exported..."

		cp wp-config.php wp-config.last.config
		chmod 400 wp-config.last.config

		#tar -czf /home/$username/public_html/primemover-$appname-migration-file.gz . --exclude '*.zip' --exclude '*.gz' --exclude 'wp-config.php'
		
		tar -cf - . -P --exclude '*.zip' --exclude '*.gz' --exclude 'wp-config.php' | pv -s $(du -sb . | awk '{print $1}') | gzip > /home/$username/public_html/primemover-$appname-migration-file.gz

		echo "Exported site pack..."
		
		echo "Cleaning up..."
		rm database.sql
		rm table.prefix
		rm wp-config.last.config
		
		echo "Site $appname has been successfully packed up..."
		
		sitepack="/home/$username/public_html/primemover-$appname-migration-file.gz"
		
	elif [ $envir == "GP" ] || [ $envir == "EE" ]
	then
		echo "Packaging local GridPane/EasyEngine compatible site $appname..."
		cd /var/www/$appname/htdocs
		echo "Arrived at directory... $PWD"
		
		DBExport
		
		if [ "$y" = "1" ]
		then
			echo "An error was detected during a previous function, skipping the site packaging step for this site..."
			return 1
		fi

		#Need to get the DB prefix from wp-config... 
		tableprefix=$(sed -n -e '/$table_prefix/p' ../wp-config.php)
		echo $tableprefix > table.prefix
		chmod 400 table.prefix
		echo "Database Table Prefix Exported..."

		cp ../wp-config.php wp-config.last.config
		chmod 400 wp-config.last.config

		#tar -czf /var/www/$appname/primemover-$appname-migration-file.gz . --exclude '*.zip' --exclude '*.gz' --exclude 'wp-config.php'
		
		tar -cf - . -P --exclude '*.zip' --exclude '*.gz' --exclude 'wp-config.php' | pv -s $(du -sb . | awk '{print $1}') | gzip > /var/www/$appname/primemover-$appname-migration-file.gz

		echo "Cleaning up..."
		rm database.sql
		rm table.prefix
		rm wp-config.last.config
		
		echo "Site $appname has been successfully packed up..."
		
		sitepack="/var/www/$appname/primemover-$appname-migration-file.gz"
		
	fi

}


# All of this is only going to work moving things into a GridPane server...
# Again, I'm working on it. 

ShipOnly() {
	
	cd $rootfolder
	if ! $(wp core is-installed --allow-root); 
	then
	  
		echo "This is not a valid WordPress install, skipping!!!"

	else
		
		echo "Packing up site $site_to_clone..."
		
		PackageSite
		
		echo "Migrating site $site_to_clone..."
		
		DoMigrate
		
	fi
	
	echo "Shipped $site_to_clone..."

}

SingleSite() {
	
	cd $rootfolder
	if ! $(wp core is-installed --allow-root); 
	then
	  
		echo "This is not a valid WordPress install, skipping!!!"

	else
		
		MakeSiteonRemote
		ShipOnly
		
	fi
	
	echo "Next site..."
	
}

CoreSiteLoop() {
	
	while read -r appname site_to_clone username rootfolder count 
	do
	    
		echo "Building site $site_to_clone from $rootfolder on remote server $remote_IP..."
		
		dots=$(echo "$site_to_clone" | awk -F. '{ print NF - 1 }')
			
		if [[ $site_to_clone == "staging."* ]] && [[ $dots -ge 2 ]]
		then
			echo "This is a staging site..."
			ShipOnly
		elif [[ $site_to_clone == "canary."* ]] && [[ $dots -ge 2 ]]
		then
			echo "This is a UpdateSafely site, skipping..."
		else
			#echo "Doing $appname $site_to_clone $username $rootfolder..."
			SingleSite
		fi
		
		#echo "Getting next site..."
				
	done <"/var/tmp/primemover.domains.tmp2"
	
	echo "All sites processed!"
	
}



# Secure Copy current packaged site to new server and restore
# All of this is only going to work moving things into a GridPane server...

DoMigrate() {
	
	if [ "$y" = "1" ]
	then
		echo "An error was detected during a previous function, skipping the migration step for this site..."
		return 1
	fi
	
	echo "Waiting for remote site to completely provision..."
	
	while ssh -n root@$remote_IP [ ! -d /var/www/$site_to_clone/htdocs/wp-content/plugins/nginx-helper ]
	do
	  sleep 5
	done
	
	scp $sitepack root@$remote_IP:/var/www/$site_to_clone/GPBUP-$site_to_clone-CLONE.gz
	
	if [[ $y -gt 0 ]]
	then
		echo "The secure copy to the remote server failed for site $site_to_clone! Exiting..."
		return 1
	else
		echo "Successfully copied site pack for $site_to_clone to remote system $remote_IP"
		rm $sitepack
	fi
	
	ssh -n root@$remote_IP "sleep 1 && cd /var/www/$site_to_clone/htdocs && gprestore" < /dev/null
	
	echo "Site $site_to_clone restored on remote system $remote_IP"

	echo "Cleaning up..."
	
	sleep 1

}



SimpleSimon() {
	
	echo "###########################################################"
	echo "######   Let's migrate all your sites, shall we?   ########"
	echo "######   We need to get some basic information...  ########"
	echo "###########################################################"
	echo ""
	echo "Please choose from one of the following options..."
	echo ""
	
	if [[ $envir == "SP" ]]
	then
		echo "1.) Migrate sites all local sites to a GridPane Server"
		echo ""
		echo "2.) Migrate sites all local sites to a RunCloud Server"
		echo ""
		echo "3.) Migrate sites all local sites to another ServerPilot Server"
		echo ""
	elif [[ $envir == "RC" ]]
	then
		echo "A.) Migrate sites all local sites to GridPane Server"
		echo ""
		echo "B.) Migrate sites all local sites to a ServerPilot Server"
		echo ""
		echo "C.) Migrate sites all local sites to another RunCloud Server"
		echo ""
	elif [[ $envir == "GP" ]] 
	then
		echo "X.) Migrate sites all local sites to another GridPane Server"
		echo ""
	elif [[ $envir == "EE" ]] 
	then
		echo "Y.) Migrate sites all local sites to a GridPane Server"
		echo ""
	elif [[ $envir == "CP" ]] 
	then
		echo "Z.) Migrate sites all local sites to a GridPane Server"
		echo ""
	else
		echo "We don't currently support your control panel or you have a non-standard installation."
		echo "Sorry, EXITING!"
		exit 187;
	fi
	
	read MigrateInput < /dev/tty
	
	if [[ $MigrateInput == "1" ]]
	then
		MigrateType=SP2GP
	elif [[ $MigrateInput == "2" ]]
	then
		MigrateType=SP2RC
	elif [[ $MigrateInput == "3" ]]
	then
		MigrateType=SP2SP
	elif [[ $MigrateInput == "A" ]] || [[ $MigrateInput == "a" ]]
	then
		MigrateType=RC2GP
	elif [[ $MigrateInput == "B" ]] || [[ $MigrateInput == "b" ]]
	then
		MigrateType=RC2SP
	elif [[ $MigrateInput == "C" ]] || [[ $MigrateInput == "c" ]]
	then
		MigrateType=RC2RC
	elif [[ $MigrateInput == "X" ]] || [[ $MigrateInput == "x" ]]
	then
		MigrateType=GP2GP
	elif [[ $MigrateInput == "Y" ]] || [[ $MigrateInput == "y" ]]
	then
		MigrateType=EE2CP
	elif [[ $MigrateInput == "Z" ]] || [[ $MigrateInput == "z" ]]
	then
		MigrateType=CP2GP
	else
		echo "You entered something weird - exiting!"
		exit 187;
	fi
	
	CheckMode	

}

WhatPlatform() {
	
	if [ -d /opt/gridpane ]
	then
		echo "This is a GridPane provisioned server..."
		envir="GP"
		#gpDomains
	elif [ -d "/etc/nginx-sp" ]
	then
		echo "This is a ServerPilot managed VPS..."
		envir="SP"
		#spDomains
	elif [ -d "/etc/nginx-rc/" ]
	then
		echo "This is a RunCloud managed VPS..."
		envir="RC"
		#rcDomains
	elif [ -f "/usr/local/cpanel/cpanel" ]
	then
		echo "This is a CPanel managed VPS..."
		echo "CPANEL MIGRATIONS ARE HIGHLY EXPERIMENTAL!!!"
		ECHO " YOU'VE BEEN WARNED, HOMESLICE"
		envir="CP"
		#cpDomains
	elif [ -f "/usr/local/bin/ee" ]
	then
		echo "This is a EasyEngine install... "
		envir="EE"
		#gpDomains
	else
		echo "We don't yet have support for Plesk/CPanel or similar shared hosting environments."
		echo "Sorry. Deuces."
		exit 187;
	fi	

}

LoopLocalSites() {
	
	if [ $envir == "GP" ]
	then
		echo ""
		echo "Processing local GridPane Sites..."
		CoreSiteLoop
		
	elif [ $envir == "EE" ]
	then
		echo ""
		echo "Processing local EasyEngine Sites..."
		CoreSiteLoop
		
	elif [ $envir == "CP" ]
	then
		echo ""
		echo "Processing local CPanel Sites... even though we probably shouldn't."
		CoreSiteLoop
		
	elif [ $envir == "SP" ]
	then
		echo ""
		echo "Processing local ServerPilot Sites..."
		CoreSiteLoop
		
	elif [ $envir == "RC" ]
	then
		echo ""
		echo "Processing local RunCloud Sites..."
		CoreSiteLoop
	fi		

}





GetWPAdmin() {
	
	echo "Before we proceed we need to collect default WP admin details for the new sites we'll be creating."
	echo ""
	echo "If your migrations succeed these account details will obviously be wiped out."
	echo ""
	echo "Your current existing account credentials will overwrite these temporary details."
	echo ""
	echo "These are primarily for testing purposes in the event that a site build fails."
	echo ""
	echo "Please enter default admin username..."
	echo ""
	read admin_user < /dev/tty
	echo "Please enter default admin email..."
	echo ""
	read admin_email < /dev/tty
	echo "Please enter default admin password..."
	echo ""
	read admin_password < /dev/tty

}

ImportDB() {
	
	if [ -f database.sql ]
	then
		wp db import database.sql --allow-root
	elif [ -f database.gz ]
	then
		tar -xzf database.gz
		wp db import database.sql --allow-root
	else
		echo "Error! Database backup file missing!"
		exit 187;
	fi

	echo "Database Imported... We Think"
	
	if [ -f database.sql ]
	then
		rm database.sql
	elif [ -f database.gz ]
	then
		rm database.gz
	else
		echo "No DB file to remove!"
	fi

	rm table.prefix

}

UpdateURL() {
	
	if [[ $envir == "RC" ]]
	then
		sourceURL=$(awk '{print $1; exit}' /home/$username/webapps/$appname/source.domain)
		
		cd /home/$username/webapps/$appname/
		
		echo "Replacing the source domain $sourceURL with the destination domain of $finaldomain"
		
		PATH=/RunCloud/Packages/php70rc/bin:/RunCloud/Packages/httpd-rc/bin:$PATH
		
		echo "Current path is... $PATH"
		
		URLResult=$(/usr/local/bin/wp search-replace ''$sourceURL'' ''$finaldomain'' --allow-root)
		
		echo "Result of search/replace is $URLResult"
	
		rm /home/$username/webapps/$appname/source.domain
		
	elif [[ $envir == "SP" ]]
	then
		sourceURL=$(awk '{print $1; exit}' /srv/users/$username/apps/$appname/public/source.domain)
		
		cd /srv/users/$username/apps/$appname/public
		
		echo "Replacing the source domain $sourceURL with the destination domain of $finaldomain"
		
		PATH=/RunCloud/Packages/php70rc/bin:/RunCloud/Packages/httpd-rc/bin:$PATH
		
		echo "Current path is... $PATH"
	
		URLResult=$(/usr/local/bin/wp search-replace ''$sourceURL'' ''$finaldomain'' --allow-root)
		
		echo "Result of search/replace is $URLResult"

		rm /srv/users/$username/apps/$appname/public/source.domain
		
	elif [[ $envir == "GP" ]]
	then
		sourceURL=$(awk '{print $1; exit}' /var/www/$appname/htdocs/source.domain)
		
		cd /var/www/$appname/htdocs/
		
		echo "Replacing the source domain $sourceURL with the destination domain of $finaldomain"
		
		PATH=/RunCloud/Packages/php70rc/bin:/RunCloud/Packages/httpd-rc/bin:$PATH
		
		echo "Current path is... $PATH"
	
		URLResult=$(/usr/local/bin/wp search-replace ''$sourceURL'' ''$finaldomain'' --allow-root)
		
		echo "Result of search/replace is $URLResult"

		rm /var/www/$appname/htdocs/source.domain
		
	else
		echo "We don't know how to update URLs for this control panel...???"
		echo "Sorry, EXITING!!!"
		exit 187;
	fi
		

}

DoWork() {
	
	# Do Work Son...

	#WhatPlatform # Now we where we're coming from and we SHOULD know all the domains as well...

	if [ "$site_to_clone" == "ALL" ] || [ "$site_to_clone" == "all" ]
	then 		
		echo ""
		echo "Determining this server's control environment..."
		LoopLocalSites

	else
		thedomain=$1 # The domain in question...
		domaindetails=$(sed -n "/$thedomain/p" /var/tmp/primemover.domains.tmp2 | head -1) # Find the first instance of that domain name (avoid staging etc)...
	
		echo $domaindetails | while read -r appname site_to_clone username rootfolder count 
		do
			if [ $envir == "GP" ]
			then
				echo ""
				echo "Processing single GridPane Site..."
				SingleSite
		
			elif [ $envir == "EE" ]
			then
				echo ""
				echo "Processing single EasyEngine Site..."
				SingleSite
			
			elif [ $envir == "CP" ]
			then
				echo ""
				echo "Processing single CPanel Site..."
				SingleSite
		
			elif [ $envir == "SP" ]
			then
				echo ""
				echo "Processing single ServerPilot Site..."
				SingleSite
		
			elif [ $envir == "RC" ]
			then
				echo ""
				echo "Processing single RunCloud Site..."
				SingleSite
			fi
		
		done		

	fi

}

CheckMode() {
	
	if [[ $MigrateType == "restore" ]]
	then
	
		DoRestore
		
	elif [[ $MigrateType == "SP2RC" ]] || [[ $MigrateType == "sp2rc" ]]
	then
	
		echo "Migrating from a ServerPilot Server to a RunCloud Server..."
		envir=SP
		SPtoRC

	elif [[ $MigrateType == "SP2SP" ]] || [[ $MigrateType == "sp2sp" ]]
	then
	
		echo "Migrating from a ServerPilot Server to another ServerPilot Server..."
	
		envir=SP
		GetWPAdmin
		ServerPilotShell
		SPtoSP
	
	elif [[ $MigrateType == "RC2RC" ]] || [[ $MigrateType == "rc2rc" ]]
	then
	
		echo "Migrating from a RunCloud server to another RunCloud Server..."
		envir=RC
		RCtoRC

	elif [[ $MigrateType == "RC2SP" ]] || [[ $MigrateType == "rc2sp" ]]
	then
	
		echo "Migrating from a RunCloud Server to a ServerPilot Server..."
		envir=RC
		GetWPAdmin
		RCtoSP

	elif [[ $MigrateType == "RC2GP" ]] || [[ $MigrateType == "rc2gp" ]]
	then
	
		echo "Migrating from a RunCloud Server to a GridPane Server..."
		envir=RC
		RCtoGP

	elif [[ $MigrateType == "SP2GP" ]] || [[ $MigrateType == "sp2gp" ]]
	then
	
		echo "Migrating from a ServerPilot Server to a GridPane Server..."
		envir=SP
		GetWPAdmin
		ServerPilotShell
		SPtoGP

	else
	
		echo "No command line input..."
		#echo "I guess I could ask a bunch of Simple Simon Questions..."
		
		WhatPlatform
		
		SimpleSimon
	
	fi

}

DoRestore() {
	
	currdir=$PWD
	appname=$(basename $currdir)

	if [[ $appname == "public" ]]
	then
	
		echo "This looks like a ServerPilot server..."
		
		envir=SP
	
		tableprefix=$(cat table.prefix)
		sed -i "/$table_prefix =/c\\$tableprefix" wp-config.php
		echo "Prefixes Fixed"
	
		ImportDB
	
		cd ..
		currdir=$PWD
		appname=$(basename $currdir)
		cd ../..
		username=$PWD
		username=$(basename $username)
		
		SingleSPDomain
		
		UpdateURL
		
		chown -R $username:$username /srv/users/$username/apps/$appname/public/*
	
	elif [[ $appname == "htdocs" ]]
	then
	
		echo "This looks like a GridPane server..."
		
		envir=GP
	
		tableprefix=$(cat table.prefix)
		sed -i "/$table_prefix =/c\\$tableprefix" ../wp-config.php
		echo "Prefixes Fixed"
	
		ImportDB
	
		cd ..
		currdir=$PWD
		appname=$(basename $currdir)
		#GridPane is currently single user...
		username=www-data
		
		SingleGPDomain
		
		UpdateURL
		
		chown -R $username:$username /var/www/$appname/htdocs/*
	
	else
	
		echo "This looks like a RunCloud server..."
		
		envir=RC
	
		tableprefix=$(cat table.prefix)
		sed -i "/$table_prefix =/c\\$tableprefix" wp-config.php
		echo "Prefixes Fixed"
	
		ImportDB
	
		cd ../..
		username=$PWD
		username=$(basename $username)
		
		SingleRCDomain
		
		UpdateURL
		
		chown -R $username:$username /home/$username/webapps/$appname/*
	
	fi
	
}

CheckMode
# Copyright 2018 PrimeMover.io - K. Patrick Gallagher
