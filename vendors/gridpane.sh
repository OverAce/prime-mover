#!/bin/bash

# GridPane-specific functions for PrimeMover
# All GridPane vendor operations

SingleGPDomain() {

	sourcedomain=$(awk '/server_name/,/;/' /etc/nginx/sites-available/$appname)
	sourcedomain=$(echo "${sourcedomain//;}") # Drop trailing semicolon
	finaldomain=$(echo $sourcedomain | awk '{ $1=""; print}')
	domaincount=$(echo $finaldomain | wc -w)

	if [ $domaincount == "1" ]
	then
		grid=work
	else
		#echo "This site has more than one domain! We're only able to process the first URL..."
		finaldomain=$(echo $finaldomain | awk '{print $1;}')
	fi

	rootfolder="/var/www/$appname/htdocs"
	username="www-data"

	if [ ${#finaldomain} -lt 3 ]
	then

		printf '%-20s %-40s %-20s %-30s %-30s\n' $appname "NO DOMAIN!!!" "UNKNOWN" "$rootfolder   ****SKIPPING****"

	else
		if [ -d $rootfolder ]
		then

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

gpDomains() {

	search_dir="/etc/nginx/sites-available"

	StartDomainLogging

	for entry in "$search_dir"/*
	do
		#echo "Entry is $entry..."
		appname=$(basename $entry)
		#echo "Application located: $appname..."
		if [ $appname == "22222" ] || [ $appname == "default" ]
		then
			grid=work
		else
			SingleGPDomain
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

# Build required site(s) on remote GridPane server
# Currently works only with GridPane... cool your jets, I'm working on it.

MakeSiteonRemote() {

	if [ "$y" = "1" ]
	then
		echo "An error was detected during a previous function, skipping the remote site build step for this site..."
		return 1
	fi

	if ssh -n root@$remote_IP [ -d /var/www/$site_to_clone/htdocs/wp-content/plugins/nginx-helper ]
	then
		echo ""
		echo "****************************************************************************"
		echo "***** SITE ALREADY EXISTINGS ON REMOTE - PROCEDING WILL BE DESTRUCTIVE *****"
		echo "****************************************************************************"
		echo ""
		echo "You must press Y (Case Sensitive) to Proceed"
		echo "Otherwise in ten seconds this site migration will be automatically halted..."
		read -t 10 -n 1 -s -r -p "Press Y to continue, anything else will halt this migration!" < /dev/tty

		if [[ $REPLY =~ ^[Y]$ ]]
		then
		    echo "Proceeding with potentially destructive migration!!!"
			return 0
		fi

		exit 187;

	fi

	if [ $envir == "GP" ]
	then
		echo "Checking for staging and canary sites..."
		if [[ -d "/var/www/staging.$site_to_clone"  && -d "/var/www/canary.$site_to_clone" ]]
		then

			echo "Site $site_to_clone has staging and updates, building three remote sites on $remote_IP..."

			gpcurl=$(curl -d '{"server_ip":"'$remote_IP'", "source_ip":"'$remote_IP'", "url":"'$site_to_clone'", "checkedOptions":["wpfc","php7"], "checkedAdvancedOptions":["staging", "canary"]}' -H "Content-Type: application/json" -X POST https://my.gridpane.com/api/add-site?api_token=$gridpanetoken 2>&1)


		elif [ -d "/var/www/staging.$site_to_clone" ]
		then

			echo "Site $site_to_clone has a staging area, building two remote sites on $remote_IP..."

			gpcurl=$(curl -d '{"server_ip":"'$remote_IP'", "source_ip":"'$remote_IP'", "url":"'$site_to_clone'", "checkedOptions":["wpfc","php7"], "checkedAdvancedOptions":["staging"]}' -H "Content-Type: application/json" -X POST https://my.gridpane.com/api/add-site?api_token=$gridpanetoken 2>&1)

		elif [ -d "/var/www/canary.$site_to_clone" ]
		then

			echo "Site $site_to_clone has automatic updates, building two remote sites on $remote_IP..."

			gpcurl=$(curl -d '{"server_ip":"'$remote_IP'", "source_ip":"'$remote_IP'", "url":"'$site_to_clone'", "checkedOptions":["wpfc","php7"], "checkedAdvancedOptions":["canary"]}' -H "Content-Type: application/json" -X POST https://my.gridpane.com/api/add-site?api_token=$gridpanetoken 2>&1)

		else

			echo "Site $site_to_clone has no staging or updates, building one remote site on $remote_IP..."

			gpcurl=$(curl -d '{"server_ip":"'$remote_IP'",  "source_ip":"'$remote_IP'", "url":"'$site_to_clone'", "checkedOptions":["wpfc", "php7"]}' -H "Content-Type: application/json" -X POST https://my.gridpane.com/api/add-site?api_token=$gridpanetoken 2>&1)

		fi
	else
		echo "Building site $site_to_clone with staging and canary updates on remote GridPane server $remote_IP..."

		gpcurl=$(curl -d '{"server_ip":"'$remote_IP'", "source_ip":"'$remote_IP'", "url":"'$site_to_clone'", "checkedOptions":["wpfc","php7"], "checkedAdvancedOptions":["staging", "canary"]}' -H "Content-Type: application/json" -X POST https://my.gridpane.com/api/add-site?api_token=$gridpanetoken 2>&1)
	fi

	echo "Waiting on remote server build..."
	sleep 3

}
