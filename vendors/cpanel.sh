#!/bin/bash

# CPanel-specific functions for PrimeMover
# All CPanel vendor operations

cpDomains() {

	search_dir="/home"

	StartDomainLogging

	for entry in "$search_dir"/*
	do

		if [[ -d "$entry"/etc ]]
		then
			cd $entry/etc/*/
			appname=$(basename $PWD)

			SingleCPDomain
		else
			echo "This doesn't appear to be a live Apache site..."
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

SingleCPDomain() {

	sourcedomain="$appname"

	rootfolder="$entry/public_html/" # Grab root folder location

	finaldomain="$appname"

	if [ ${#finaldomain} -lt 3 ]
	then

		printf '%-20s %-40s %-20s %-30s %-30s\n' $appname "NO DOMAIN!!!" "UNKNOWN" "$rootfolder   ****SKIPPING****"

	else
		if [ -d $rootfolder ]
		then
			cd $rootfolder
			cd ..
			username=$(basename $PWD)

			dots=$(echo "$finaldomain" | awk -F. '{ print NF - 1 }')

			if [ $dots -ge 2 ]
			then
				if [[ $finaldomain == "staging."* ]]
				then
					printf '%-20s %-40s %-20s %-30s %-30s\n' $appname "$finaldomain (STAGING)" $username $rootfolder
				else
					printf '%-20s %-40s %-20s %-30s %-30s\n' $appname "$finaldomain (SUBDOMAIN)" $username $rootfolder
				fi
			else
				printf '%-20s %-40s %-20s %-30s %-30s\n' "$appname" $finaldomain $username $rootfolder
			fi

			echo "$appname $finaldomain $username $rootfolder ${#finaldomain}" >> /var/tmp/primemover.domains.tmp

		else
			printf '%-20s %-40s %-20s %-30s %-30s\n' "$appname" $finaldomain "UNKNOWN!!!" "SITE ROOT FOLDER DAMAGED OR MISSING!   ****SKIPPING****"
		fi
	fi

}
