#!/bin/bash

# RunCloud-specific functions for PrimeMover
# All RunCloud vendor operations

RCtoSP() {

	echo "Confirming that we have the ServerPilot shell tools..."
	ServerPilotShell

	echo "Getting all local RunCloud site domains..."
	rcDomains

	echo ""
	echo "Are we moving all of these sites to the same server? Please enter YES or NO..."

	read SameSPforAll < /dev/tty

	if [[ $SameSPforAll == "YES" ]] || [[ $SameSPforAll == "yes" ]] || [[ $SameSPforAll == "Yes" ]] || [[ $SameSPforAll == "Y" ]] || [[ $SameSPforAll == "y" ]]
	then
		SameServer="yes"

		echo "What is the remote IP of the target ServerPilot server?"

		read targetserver < /dev/tty

		#remote_IP="$targetserver"

		DoSSH $targetserver

	else
		echo "We'll gather a different IP address for each site during the migration..."
	fi


	while read -r appname site_to_clone username rootfolder count
	do

		echo "Starting with site $site_to_clone from $rootfolder..."

		dots=$(echo "$site_to_clone" | awk -F. '{ print NF - 1 }')

		if [[ $site_to_clone == "staging."* ]] && [[ $dots -ge 2 ]]
		then
			echo "This is a staging site..."
			ShipOnly

			# NEED WORK HERE!!!

		elif [[ $site_to_clone == "canary."* ]] && [[ $dots -ge 2 ]]
		then
			echo "This is a UpdateSafely site, skipping..."
		else

			# FIND PHP HERE!!!

			if [ -f "/etc/php56rc/fpm.d/$appname.conf" ]
			then
				echo "PHP56RC file found... setting PHP to verison 5.6"
				php="php5.6"
			elif [ -f "/etc/php70rc/fpm.d/$appname.conf" ]
			then
				echo "PHP70RC file found... setting PHP to verison 7.0"
				php="php7.0"
			elif [ -f "/etc/php71rc/fpm.d/$appname.conf" ]
			then
				echo "PHP71RC file found... setting PHP to verison 7.1"
				php="php7.1"
			else
				echo "No PHP file found... defaulting to PHP7.0"
				php="php7.0"
			fi

			if [[ $SameServer == "yes" ]]
			then
				echo "We're using the same IP address $targetserver for all sites..."
			else
				echo "What is the remote IP of the target ServerPilot server for site $site_to_clone?"

				echo "You'll need the root password for the remote ServerPilot system and root password login access will need to be ON."

				read targetserver < /dev/tty

				#remote_IP="$targetserver"

				DoSSH $targetserver

			fi

			currentuser=$username

			if [[ $currentuser = "runcloud" ]]
			then
				echo "Current user is runcloud, switching to serverpilot..."
				currentuser=serverpilot
			else
				echo "We'll need to build this user $currentuser on the remote ServerPilot system..."
			fi

			#Make sure we don't have any underscores...
			echo $appname > tempfile
			appname=$(sed 's/\_/-/g' tempfile)
			rm tempfile

			appdomain=$site_to_clone

			PushToSP

			sleep 1

			echo "Running remote restoration process..."


		fi

		#echo "Getting next site..."

	done <"/var/tmp/primemover.domains.tmp2"

	echo "All sites processed!"

}

SingleRCDomain() {

	sourcedomain=$(awk '/server_name/,/;/' /etc/nginx-rc/conf.d/$appname.d/main.conf)
	sourcedomain=$(echo "$sourcedomain" | sed 's/\S*\_name\S*//g')
	sourcedomain=$(echo "${sourcedomain//;}") # Drop trailing semicolon
	sourcedomain2=$(echo "$sourcedomain" | sed 's/\S*\www\S*//g')

	rootfolder=$(awk '/root/,/;/' /etc/nginx-rc/conf.d/$appname.d/main.conf) # Grab root folder location
	rootfolder=$(echo $rootfolder | awk '{print $2;}')
	rootfolder=$(echo "${rootfolder//;}") # Drop trailing semicolon

	if [ ${#sourcedomain2} -lt 4 ]
	then
		finaldomain=$sourcedomain
	else
		finaldomain=$sourcedomain2
	fi

	if [ ${#finaldomain} -lt 3 ]
	then

		printf '%-20s %-40s %-20s %-30s %-30s\n' $appname "NO DOMAIN!!!" "UNKNOWN" "$rootfolder   ****SKIPPING****"

	else
		if [ -d $rootfolder ]
		then
			cd $rootfolder
			cd ../..
			username=$(basename $PWD)

			domaincount=$(echo $finaldomain | wc -w)

			if [ $domaincount == "1" ]
			then
				grid=work
			else
				#echo "This site has more than one domain! We're only able to process the first URL..."
				finaldomain=$(echo $finaldomain | awk '{print $1;}')
			fi

			finaldomain=$(echo "$finaldomain" | sed "s/ //g")

			dots=$(echo "$finaldomain" | awk -F. '{ print NF - 1 }')

			if [ $dots -ge 2 ]
			then

				if [[ $finaldomain == "staging."* ]]
				then
					if [[ $restore == "yes" ]]
					then
						echo "Final domain for this site: $finaldomain"
					else
						printf '%-20s %-40s %-20s %-30s %-30s\n' $appname "$finaldomain (STAGING)" $username $rootfolder
					fi
				else
					if [[ $restore == "yes" ]]
					then
						echo "Final domain for this site: $finaldomain"
					else
						printf '%-20s %-40s %-20s %-30s %-30s\n' $appname "$finaldomain (SUBDOMAIN)" $username $rootfolder
					fi
				fi
			else
				if [[ $restore == "yes" ]]
				then
					echo "Final domain for this site: $finaldomain"
				else
					printf '%-20s %-40s %-20s %-30s %-30s\n' "$appname" $finaldomain $username $rootfolder
				fi
			fi

			echo "$appname $finaldomain $username $rootfolder ${#finaldomain}" >> /var/tmp/primemover.domains.tmp

		else
			printf '%-20s %-40s %-20s %-30s %-30s\n' "$appname" $finaldomain "UNKNOWN!!!" "SITE ROOT FOLDER DAMAGED OR MISSING!   ****SKIPPING****"
		fi
	fi

}

rcDomains() {

	search_dir="/etc/nginx-rc/conf.d"

	StartDomainLogging

	for entry in "$search_dir"/*
	do

		if [[ $entry == *".conf" ]]
		then
			# Skipping app .conf file...
			grid=work
		else
			#echo "Entry is $entry..."
			appname=$(basename $entry)
			appname=$(echo "${appname//.d}")
			SingleRCDomain
		fi
	done

	echo "************************************************************************************************************************"
	echo ""
	echo ""
	echo "PLEASE CONFIRM THIS LIST OF SITES LOOKS CORRECT... PRESS CTRL-Z to CANCEL if there is an error!!!"
	echo ""
	echo ""
	read -t 10 -n 1 -s -r -p "Press any key to confirm or wait ten seconds..." ;
	echo ""

sort -k5 -n /var/tmp/primemover.domains.tmp > /var/tmp/primemover.domains.tmp2

}

PushToRC() {

	echo "What is the IP address of your target RunCloud Server?"
	read targetserver < /dev/tty

	echo "You'll need to have a root password for the remote RunCloud."

	echo "Getting ready to connect to target server..."

	sleep 1

	DoSSH "$targetserver"

	#example... 45.63.75.240

	echo "What is the remote path for this site on your target RunCloud Server?"
	read RCRemotePath < /dev/tty

	RCappname=$(basename $RCRemotePath)

	RCusername=$(dirname $RCRemotePath)

	RCusername=$(dirname $RCusername)

	RCusername=$(basename $RCusername)

	#example... /home/runcloud/webapps/primemover-test

	echo "Packaging up site..."

	#TARBALL THE SITE

	PackageSite

	sleep 2

	echo "Copying to remote RunCloud Server..."

	scp /srv/users/$username/apps/$appname/primemover-$appname-migration-file.gz root@$remote_IP:/home/$RCusername/webapps/$RCappname/primemover-$RCappname-migration-file.gz

	sleep 1

	echo "Running remote restoration process..."

	if [[ $run == "1" ]]
	then
		ssh root@$remote_IP "sleep 3 && wget https://www.dropbox.com/s/1wpxv8kr9bfqz8i/primemover.sh && mv primemover.sh /usr/local/bin/primemover && chmod +x /usr/local/bin/primemover && sleep 1 && tar -xzf /home/$RCusername/webapps/$RCappname/primemover-$RCappname-migration-file.gz -C /home/$RCusername/webapps/$RCappname/ --overwrite && cd /home/$RCusername/webapps/$RCappname/ && echo $finaldomain > source.domain && primemover restore" < /dev/null
	else
		#ssh root@$remote_IP "sleep 3 && tar -xzf /home/$RCusername/webapps/$RCappname/primemover-$RCappname-migration-file.gz -C /home/$RCusername/webapps/$RCappname/ --overwrite && cd /home/$RCusername/webapps/$RCappname/ && primemover restore" < /dev/null
		ssh root@$remote_IP "sleep 3 && wget https://www.dropbox.com/s/1wpxv8kr9bfqz8i/primemover.sh && mv primemover.sh /usr/local/bin/primemover && chmod +x /usr/local/bin/primemover && sleep 1 && tar -xzf /home/$RCusername/webapps/$RCappname/primemover-$RCappname-migration-file.gz -C /home/$RCusername/webapps/$RCappname/ --overwrite && cd /home/$RCusername/webapps/$RCappname/ && echo $finaldomain > source.domain && primemover restore" < /dev/null
	fi

	sleep 1

}

RCtoGP() {

	rcDomains

	$site_to_clone="ALL"

	DoWork

}

RCtoRC() {

	echo "Migrating from a RunCloud server to another RunCloud Server..."

	rcDomains

	echo ""
	echo "Are we moving all of these sites to the same server? Please enter YES or NO..."

	read SameRCforAll < /dev/tty

	if [[ $SameRCforAll == "YES" ]] || [[ $SameRCforAll == "yes" ]] || [[ $SameRCforAll == "Yes" ]] || [[ $SameRCforAll == "Y" ]] || [[ $SameRCforAll == "y" ]]
	then
		SameServer="yes"

		echo "What is the remote IP of the target RunCloud server?"

		read targetserver < /dev/tty

		DoSSH $targetserver

	else
		echo "We'll gather a different IP address for each site during the migration..."
	fi

	while read -r appname site_to_clone username rootfolder count
	do

		echo "Starting with site $site_to_clone from $rootfolder..."

		dots=$(echo "$site_to_clone" | awk -F. '{ print NF - 1 }')

		if [[ $site_to_clone == "staging."* ]] && [[ $dots -ge 2 ]]
		then
			echo "This is a staging site..."
			ShipOnly

		elif [[ $site_to_clone == "canary."* ]] && [[ $dots -ge 2 ]]
		then
			echo "This is a UpdateSafely site, skipping..."
		else

			if [[ $SameServer == "yes" ]]
			then
				echo "We're using the same IP address $targetserver for all sites..."
			else
				echo "What is the remote IP of the target RunCloud server for site $site_to_clone?"

				read targetserver < /dev/tty

				DoSSH $targetserver

			fi

			currentuser=$username

			PushToRC

			sleep 1

			echo "Running remote restoration process..."

		fi

	done <"/var/tmp/primemover.domains.tmp2"

	echo "All sites processed!"

}
