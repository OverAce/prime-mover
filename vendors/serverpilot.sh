#!/bin/bash

# ServerPilot-specific functions for PrimeMover
# All ServerPilot vendor operations

ServerPilotShell() {

	#Check if ServerPilot API is Installed...
	if [ -f "/usr/local/bin/serverpilot" ]
	then
		echo "ServerPilot API Already Installed!"
		sed -i 's/printf "%-20s"/printf "%-30s"/g' /usr/local/bin/serverpilot #Fixes the column bleed issue...Just making sure here!
		source ~/.bash_profile
	else
		#install jq
		sudo apt-get -y install jq
		curl -sSL https://raw.githubusercontent.com/kodie/serverpilot-shell/master/lib/serverpilot.sh > /usr/local/bin/serverpilot
		chmod a+x /usr/local/bin/serverpilot
		sed -i 's/printf "%-20s"/printf "%-25s"/g' /usr/local/bin/serverpilot #Fixes the column bleed issue...
		echo "Enter ClientID from ServerPilot Account..."
		read clientID
		echo "Enter API Key from ServerPilot Account..."
		read APIkey
		printf '\nexport serverpilot_client_id="'$clientID'"\nexport serverpilot_api_key="'$APIkey'"' >> ~/.bash_profile && source ~/.bash_profile
	fi

}

GetSPUserAppDetails() {

	appholder=word$appnameCOL
	appname=$(echo ${!appholder})

	runholder=word$runtimeCOL
	php=$(echo ${!runholder})

	appidhold=word$appidCOL
	appid=$(echo ${!appidhold})

	serverhold=word$serveridCOL
	serverid=$(echo ${!serverhold})

	datehold=word$datecreatedCOL
	datecreated=$(echo ${!datehold})

	userhold=word$sysuserCOL
	sysuserid=$(echo ${!userhold})

	echo ""
	echo ""
	echo "Application Name/Folder is $appname"
	echo "PHP Version is $php"
	echo "User ID is $sysuserid"
	serverpilot sysusers $sysuserid > /var/tmp/primemover/source-user-name.txt

	serverCOL=$(awk -v name='serverid' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/source-user-name.txt)
	#echo "serverid Column is $serverCOL"

	usernameCOL=$(awk -v name='name' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/source-user-name.txt)
	#echo "UserName Column is $usernameCOL"

	userIDCOL=$(awk -v name='id' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/source-user-name.txt)
	#echo "UserID Column is $userIDCOL"

	sed '1d' /var/tmp/primemover/source-user-name.txt > /var/tmp/primemover/tmpfile; mv /var/tmp/primemover/tmpfile /var/tmp/primemover/source-user-name.txt

	if [ $usernameCOL -eq 1 ]
	then
		currentuser=$(awk '{print $1}' /var/tmp/primemover/source-user-name.txt)
	elif [ $usernameCOL -eq 2 ]
	then
		currentuser=$(awk '{print $2}' /var/tmp/primemover/source-user-name.txt)
	else
		currentuser=$(awk '{print $3}' /var/tmp/primemover/source-user-name.txt)
	fi

	currentuser=$(echo $currentuser|tr -d '\n')
	echo "System User Name for this App is $currentuser"

}

PushToSP() {

	#echo "Creating New System User $currentuser on Target Server $targetserver..."

	targetID=$(serverpilot find servers lastaddress=$targetserver id)

	if [[ $currentuser == "serverpilot" ]]
	then
		echo "Default serverpilot user already exists on remote system..."
		serverpilot find sysusers serverid=$targetID > /var/tmp/primemover/new-server-users.txt
		sed -r -n -e /$currentuser/p /var/tmp/primemover/new-server-users.txt > /var/tmp/primemover/new-user-details.txt

		newuserIDCOL=$(awk -v name='id' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/new-server-users.txt)
		#echo "New User ID Column is $newuserIDCOL"

		if [[ $newuserIDCOL -eq 1 ]]
		then
			newuserID=$(awk '{print $1}' /var/tmp/primemover/new-user-details.txt)
		elif [[ $newuserIDCOL -eq 2 ]]
		then
			newuserID=$(awk '{print $2}' /var/tmp/primemover/new-user-details.txt)
		else
			newuserID=$(awk '{print $3}' /var/tmp/primemover/new-user-details.txt)
		fi
	else

		MakeSPUser

	fi

	echo "Packaging up site..."

	#TARBALL THE SITE

	PackageSite

	echo "Default WP admin credentials are user $admin_user with email address $admin_email with pass $admin_password..."

	echo "Getting ready to build site $appdomain for application $appname for user ID $newuserID on PHP version $php ..."

	serverpilot apps create $appname $newuserID $php '["'$appdomain'","www.'$appdomain'"]' '{"site_title":"'$appname'","admin_user":"'$admin_user'","admin_password":"'$admin_password'","admin_email":"'$admin_email'"}'

	echo "Waiting for remote site build to complete..." #Add error checking here by routing that ^^^ output to a variable and checking it

	sleep 5

	scp $sitepack root@$remote_IP:/srv/users/$currentuser/apps/$appname/primemover-$appname-migration-file.gz

	sleep 1

	echo "Running remote restoration process..."

	if [[ $run == "1" ]]
	then
		ssh root@$remote_IP "sleep 3 && wget https://www.dropbox.com/s/1wpxv8kr9bfqz8i/primemover.sh && mv primemover.sh /usr/local/bin/primemover && chmod +x /usr/local/bin/primemover && sleep 1 && tar -xzf /srv/users/$currentuser/apps/$appname/primemover-$appname-migration-file.gz -C /srv/users/$currentuser/apps/$appname/public/ --overwrite && cd /srv/users/$currentuser/apps/$appname/public && echo $finaldomain > source.domain && primemover restore" < /dev/null
	else
		ssh root@$remote_IP "sleep 3 && wget https://www.dropbox.com/s/1wpxv8kr9bfqz8i/primemover.sh && mv primemover.sh /usr/local/bin/primemover && chmod +x /usr/local/bin/primemover && sleep 1 && tar -xzf /srv/users/$currentuser/apps/$appname/primemover-$appname-migration-file.gz -C /srv/users/$currentuser/apps/$appname/public/ --overwrite && cd /srv/users/$currentuser/apps/$appname/public && echo $finaldomain > source.domain && primemover restore" < /dev/null
	fi

	sleep 1

	echo "Remote restoration done... right?"

}

GetSPApps() {

	echo "These are all of the local apps we'll be moving..."

	echo ""

	cat /var/tmp/primemover/source-applications.txt

	sysuserCOL=$(awk -v name='sysuserid' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/source-applications.txt)

	runtimeCOL=$(awk -v name='runtime' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/source-applications.txt)

	appnameCOL=$(awk -v name='name' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/source-applications.txt)

	serveridCOL=$(awk -v name='serverid' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/source-applications.txt)

	datecreatedCOL=$(awk -v name='name' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/source-applications.txt)

	appidCOL=$(awk -v name='id' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/source-applications.txt)

}

PickTargetSP() {

	serverpilot servers > /var/tmp/primemover/server-list.txt

	echo "Here's our raw SP Server details for all connected nodes..."

	cat /var/tmp/primemover/server-list.txt

	serverCOL=$(awk -v name='name' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/server-list.txt)
	#echo "Server Column is located: Column $serverCOL..."

	ipaddressCOL=$(awk -v name='lastaddress' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/server-list.txt)
	#echo "IP Address Column is located: Column $ipaddressCOL..."

	idCOL=$(awk -v name='id' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/server-list.txt)
	#echo "ID Column is located: Column $idCOL..."

	awk -v col=name 'NR==1{for(i=1;i<=NF;i++){if($i==col){c=i;break}} print $c} NR>1{print $c}' /var/tmp/primemover/server-list.txt > /var/tmp/primemover/server-names.txt

	awk -v col=lastaddress 'NR==1{for(i=1;i<=NF;i++){if($i==col){c=i;break}} print $c} NR>1{print $c}' /var/tmp/primemover/server-list.txt > /var/tmp/primemover/server-ips.txt

	awk -v col=id 'NR==1{for(i=1;i<=NF;i++){if($i==col){c=i;break}} print $c} NR>1{print $c}' /var/tmp/primemover/server-list.txt > /var/tmp/primemover/server-ids.txt

	echo ""
	echo "Please keep in mind: THIS CAN POTENTIALLY BE DESTRUCTIVE!!!"
	echo ""
	echo "###########################################################"
	echo "########  Beginning Migration and Provisioning... #########"
	echo "########      Here are your available Servers     #########"
	echo "###########################################################"
	echo ""
	rownumber=0
	cp /var/tmp/primemover/server-names.txt /var/tmp/primemover/server-names.tmp
	sed -i -e "1d" /var/tmp/primemover/server-names.tmp
	sed -i -e "1d" /var/tmp/primemover/server-ips.txt
	sed -i -e "1d" /var/tmp/primemover/server-ids.txt
	while IFS=" " read -r entrydetail
	do
		rownumber=$((rownumber+1))
		currentIP=$(cat /var/tmp/primemover/server-ips.txt | awk '{print $"$ipaddressCOL"; exit}')
		currentID=$(cat /var/tmp/primemover/server-ids.txt | awk '{print $"$idCOL"; exit}')
		if [[ $currentIP == $ipaddress ]]
		then

			#Don't display this machine... it's obviously the source.
			sourcerow=$((rownumber+1))
			sourceserver=$entrydetail
			sourceID=$currentID
			sourceIP=$currentIP

		else

			echo "Server #$rownumber ... Named: $entrydetail ...	with IP Address of $currentIP"

		fi

		sed -i -e "1d" /var/tmp/primemover/server-ips.txt

	done < "/var/tmp/primemover/server-names.tmp"
	echo ""
	echo "Enter Target Server By Number..."
	read targetServer

	#targetServer=$((targetServer+1)) #Increment the server line number by 1 to accomodate the heading line within the source output

	serveridsource=$(cat /var/tmp/primemover/server-ids.txt)

	servernames=$(cat /var/tmp/primemover/server-names.txt)

	targetID=$(echo "$serveridsource" | sed -n "$targetServer"p)
	remote_IP=$(serverpilot find servers id=$targetID lastaddress)
	echo ""
	echo ""
	echo "The target server has an ID of... $targetID... with IP Address $remote_IP"
	echo ""
	echo "The source server has an ID of... $sourceID... with IP Address $sourceIP"
	echo ""
	echo "These are all of the Source Applications on $sourceserver..."
	echo ""

	serverpilot find apps serverid=$(serverpilot find servers name=$sourceserver id) > /var/tmp/primemover/source-applications.txt

	GetSPApps

	# echo "systemuserid Column: $sysuserCOL - runtime Column: $runtimeCOL - AppName Column: $appnameCOL - ServerID Column: $serveridCOL - Date Column: $datecreatedCOL - AppID Column is $appidCOL"

	echo ""
	echo "To begin initializing ALL apps press ENTER... NOTE: User passwords will be reset on target node!"

	read desiredapps

}

SPtoSP() {

	# The intention here is to move sites from a ServerPilot node to another ServerPilot node

	PickTargetSP

	if [ -z "$desiredapps" ]
	then

		sed '1d' /var/tmp/primemover/source-applications.txt > /var/tmp/primemover/tmpfile; mv /var/tmp/primemover/tmpfile /var/tmp/primemover/source-applications.txt
		echo "Copying ServerPilot Sites..."
		run=0
		while IFS=" " read -r word1 word2 word3 word4 word5 word6
		do

		  	((run++))

			GetSPUserAppDetails

			cd /srv/users/$currentuser/apps/$appname/public

			if ! $(wp core is-installed --allow-root);
			then

				echo "This is not a valid WordPress install, skipping this app!"

			else

				echo "Proceeding..."

				SingleSPDomain

				echo "The Final Domain for this application is $finaldomain"

				appdomain=$finaldomain

				PushToSP

			fi

		done < "/var/tmp/primemover/source-applications.txt"

	fi
}

MakeSPUser() {


	echo "Creating New System User $currentuser on Target Server $targetserver..."

	serverpilot sysusers create $targetserver $currentuser
	serverpilot find sysusers serverid=$SPRemoteIP > /var/tmp/primemover/new-server-users.txt
	sed -r -n -e /$currentuser/p /var/tmp/primemover/new-server-users.txt > /var/tmp/primemover/new-user-details.txt

  	newuserIDCOL=$(awk -v name='id' '{for (i=1;i<=NF;i++) if ($i==name) print i; exit}' /var/tmp/primemover/new-server-users.txt)
  	#echo "New User ID Column is $newuserIDCOL"

	if [[ $newuserIDCOL -eq 1 ]]
	then
		newuserID=$(awk '{print $1}' /var/tmp/primemover/new-user-details.txt)
	elif [[ $newuserIDCOL -eq 2 ]]
	then
		newuserID=$(awk '{print $2}' /var/tmp/primemover/new-user-details.txt)
	else
		newuserID=$(awk '{print $3}' /var/tmp/primemover/new-user-details.txt)
	fi

	randpass=$(openssl rand -base64 12)
	echo "New User $currentuser on Server $targetserver has ID $newuserID"
	serverpilot sysusers update $newuserID password $randpass
	echo "... and now has new random password $randpass"

}

BuildSPSite() {

	#MEH... This is gonna go.

	serverpilot apps create $appname $newuserID $php '["'$appdomain'","www.'$appdomain'"]' '{"site_title":"'$appname'","admin_user":"'$admin_user'","admin_password":"'$admin_password'","admin_email":"'$admin_email'"}'

}

SingleSPDomain() {

	sourcedomain=$(awk '/server_name/,/;/' /etc/nginx-sp/vhosts.d/$appname.conf)
	sourcedomain=$(echo "$sourcedomain" | sed '/server_name/d')
	sourcedomain=$(echo "$sourcedomain" | sed '/server-/d')
	sourcedomain=$(echo "$sourcedomain" | sed '/;/d')
	sourcedomain=$(echo "$sourcedomain" | awk '!a[$0]++')
	sourcedomain=$(echo "$sourcedomain" | sed "s/ //g")
	sourcedomain2=$(echo "$sourcedomain" | sed '/www./d')

	rootfolder=$(awk '/root/,/;/' /etc/nginx-sp/vhosts.d/$appname.conf) # Grab root folder location
	rootfolder=$(echo "${rootfolder//;}") # Drop trailing semicolon
	rootfolder=$(echo "${rootfolder//root }") # Drop root descriptor

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
			cd ../../..
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

spDomains() {

	search_dir="/etc/nginx-sp/vhosts.d"

	StartDomainLogging

	for entry in "$search_dir"/*
	do

		if [[ $entry != *".conf" ]]
		then
			grid=work
		else
			appname=$(basename $entry)
			appname=$(echo "${appname//.conf}")
			SingleSPDomain
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

SPtoGP() {

	LogMessage "Starting ServerPilot to GridPane migration"

	# Validate GridPane API token before starting
	ValidateGridPaneToken

	# Check disk space on source server
	CheckDiskSpace "/srv/users" 15

	# Get remote GridPane server IP
	echo ""
	echo "Please enter the IP address of your target GridPane server:"
	read -r remote_IP < /dev/tty

	if [ -z "$remote_IP" ]; then
		echo "ERROR: Remote IP address is required. Exiting..."
		exit 1
	fi

	LogMessage "Target GridPane server: $remote_IP"

	# Setup SSH connection
	DoSSH "$remote_IP"

	# Get all ServerPilot domains
	spDomains

	$site_to_clone="ALL"

	DoWork

	# Print summary
	echo ""
	echo "=========================================="
	echo "MIGRATION BATCH COMPLETED"
	echo "=========================================="
	echo "Check log file for details: $LOGFILE"
	echo "=========================================="
	echo ""

}

SPtoRC() {

	# The intention here is to move sites from a ServerPilot node to a RunCloud node...

	SourceID=$(serverpilot find servers lastaddress=$ipaddress id)

	serverpilot find apps serverid=$SourceID > /var/tmp/primemover/source-applications.txt

	GetSPApps

	echo ""
	echo "To begin initializing ALL apps press ENTER... NOTE: Destination sites must already be built inside of RunCloud!!!"

	read desiredapps

	if [ -z "$desiredapps" ]
	then

		sed '1d' /var/tmp/primemover/source-applications.txt > /var/tmp/primemover/tmpfile; mv /var/tmp/primemover/tmpfile /var/tmp/primemover/source-applications.txt
		echo "Copying ServerPilot Sites..."
		run=0
		while IFS=" " read -r word1 word2 word3 word4 word5 word6
		do

			GetSPUserAppDetails

			cd /srv/users/$currentuser/apps/$appname/public

			if ! $(wp core is-installed --allow-root);
			then

				echo "This is not a valid WordPress install, skipping this app!"

			else

				((run++))

				echo "Proceeding..."

				SingleSPDomain

				echo "The Final Domain for this application is $finaldomain"

				appdomain=$finaldomain

				PushToRC

			fi

		done < "/var/tmp/primemover/source-applications.txt"

	fi

}
