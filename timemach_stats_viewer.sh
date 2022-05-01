#!/bin/bash

# Name:
# -----
# timemach_stats_viewer.sh
#
# Purpose:
# --------
# This job prints out how much is left to backup using time machine
#
# Dependencies:
# -------------
#
# iterm_notify.sh				to send a macOS notification via iTerm2 Shell Integration
#								edit the script to the location of iterm_notify.sh  (script uses ~/bin/iterm_notify.sh)
#
# Customization:
# --------------
#
#
# Crontab Example:
# ----------------
# This example runs the job every day at 12:01 AM
#
# MIN          HOUR   MDAY     MON     DOW      COMMAND
# 1              0      *       *       *       /Users/me/bin/timemach_stats_viewer.sh &> /dev/null
#

usage() {

	echo "Usage:		"${0##*/}"  [-k -l -s -n -r NN] 
	
OPTIONS:
   -q		quiet (do not log the results)
   -k		keep alive (restart backups, if they are not running)
   -l		list current backups only
   -n 		to send a macOS notification via iTerm2 Shell Integration when the script ends
   -s 		list current status only
   -r NN 	repeat check after sleeping NN seconds, example '-r 30' to sleep 30 seconds before repeating the check
"
}

ConvertSecs() {

	echo $1 | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}'

}

TMSnapShots() {
	TM_URL=$(tmutil destinationinfo | grep "^Name" -c)

	X=0
	while [ "$X" -lt "$TM_URL" ]; do
		/usr/libexec/PlistBuddy -c "Print :Destinations:$X:SnapshotDates" /Library/Preferences/com.apple.TimeMachine.plist 2>/dev/null | grep ":" | sed 's/^ *//g'
		let X=X+1
	done
}

ConvertDatesToReadable() {
	while IFS= read -r line; do
		#		echo $line

		# if we are in standard time, then the date needs to be adjusted by an hour

		if [ $(echo $line | grep -c -e "PST" -e "MST" -e "CST" -e "EST") != 0 ]; then
			TS_DATE=$(date -j -v-1H -f "%a %b %d %T %Z %Y" "$line" "+%Y-%m-%d-%H:%M:%S" 2>/dev/null)
		else
			TS_DATE=$(date -j -f "%a %b %d %T %Z %Y" "$line" "+%Y-%m-%d-%H:%M:%S" 2>/dev/null)
		fi
		echo $TS_DATE
	done

}

ConvertDatesToSeconds() {
	while IFS= read -r line; do
		#		echo $line

		# if we are in standard time, then the date needs to be adjusted by an hour

		if [ $(echo $line | grep -c -e "PST" -e "MST" -e "CST" -e "EST") != 0 ]; then
			TS_DATE=$(date -j -v-1H -f "%a %b %d %T %Z %Y" "$line" "+%s" 2>/dev/null)
		else
			TS_DATE=$(date -j -f "%a %b %d %T %Z %Y" "$line" "+%s" 2>/dev/null)
		fi
		echo $TS_DATE
	done

}

NAME=$(basename "$0")
VER=9
MY_HOSTNAME=$(/bin/hostname -s)

d=$(date "+%Y-%m-%d - %H:%M:%S")

SLEEP_TIME=0
KEEP_ALIVE=0
LIST_BACKUPS=0
LIST_STATUS=0
SHOW_PATH=0
NOTIFY=0

while getopts "klnpsr:?" OPTION; do
	case $OPTION in
	k)
		KEEP_ALIVE=1
		;;
	p)
		SHOW_PATH=1
		;;
	r)
		SLEEP_TIME=$(echo $OPTARG)
		;;
	l)
		LIST_BACKUPS=1
		;;
	n)
		NOTIFY=1
		;;
	s)
		LIST_STATUS=1
		;;
	?)
		usage
		exit
		;;
	esac
done

VOLUMES=$(ls -d /Volumes/Backups\ of\ $MY_HOSTNAME* | grep -c Backups)

if [ "$VOLUMES" != "1" ]; then
	printf "$d - $MY_HOSTNAME - $NAME - WARNING: There are $VOLUMES folders named 'Backups of $MY_HOSTNAME*' in '/Volumes' \n"
fi

if [ "$LIST_STATUS" = "0" ]; then

	# Determine if it is configured.
	TM_CONFIGURED=0
	TM_URL=""
	TM_LAST_SNAPSHOT_DATE=""
	TM_LAST_SNAPSHOT_TS=""
	TM_FIRST_SNAPSHOT_DATE=""
	TM_FIRST_SNAPSHOT_TS=""
	SNAPSHOT_COUNT="0"

	if [ -e /usr/bin/tmutil ]; then

		V=$(/usr/bin/tmutil destinationinfo | grep "No destinations configured")

		if [ -z "$V" ]; then
			# Get dates

			TM_SNAPSHOT_DATES=$(TMSnapShots | ConvertDatesToReadable | sort)

			if [ "$TM_SNAPSHOT_DATES" == "" ]; then
				printf "$d - $MY_HOSTNAME - $NAME - # TM Backups: No backups taken\n"
			else
				TM_SNAPSHOT_DATES_SEC=$(TMSnapShots | ConvertDatesToSeconds | sort)

				# Get the most recent snapshot date
				TM_LAST_SNAPSHOT_TS=$(echo "$TM_SNAPSHOT_DATES" | tail -1)

				# Get the oldest snapshot date
				TM_FIRST_SNAPSHOT_TS=$(echo "$TM_SNAPSHOT_DATES" | head -1)

				# Get the number of snapshots
				SNAPSHOT_COUNT=$(echo "$TM_SNAPSHOT_DATES" | grep -c ":")

				# Check if the most recent snapshot is more than 24 hours old
				TM_LAST_SNAPSHOT_SEC=$(echo "$TM_SNAPSHOT_DATES_SEC" | tail -1)
				CURRENT_SEC=$(date '+%s')
				#CURRENT_SEC=$EPOCHREALTIME

				let TM_ELAPSED=$CURRENT_SEC-$TM_LAST_SNAPSHOT_SEC

				#				echo "$TM_ELAPSED seconds"

				# Sometimes the timestamp on the last snapshot is in the future, if so, get the prior one
				if [ $TM_ELAPSED -lt 0 ]; then
					TM_LAST_SNAPSHOT_TS=$(echo "$TM_SNAPSHOT_DATES" | tail -2 | head -1)
					TM_LAST_SNAPSHOT_SEC=$(echo "$TM_SNAPSHOT_DATES_SEC" | tail -2 | head -1)
					let TM_ELAPSED=$CURRENT_SEC-$TM_LAST_SNAPSHOT_SEC
					let SNAPSHOT_COUNT=$SNAPSHOT_COUNT-1
				fi

				TM_DAYS=$(eval "echo $(($TM_ELAPSED / 3600 / 24))")
				TIME_AGO=$(eval "echo $(/usr/local/bin/gdate -ud "@$TM_ELAPSED" +'$TM_DAYS days %-H hours %-M minutes %-S seconds')" | sed "s/^0 days//" | sed "s/^ //" | sed "s/^0 hours//" | sed "s/^ //" | sed "s/^0 minutes//" | sed "s/^ //")

				#				echo "[$TIME_AGO] = $TM_ELAPSED seconds"

				printf "$d - $MY_HOSTNAME - $NAME - # TM Backups: $SNAPSHOT_COUNT -> $TM_FIRST_SNAPSHOT_TS to $TM_LAST_SNAPSHOT_TS ($TIME_AGO ago)\n"

				if [ $TM_ELAPSED -gt 86400 ]; then
					TM_DAYS=$(eval "echo $(($TM_ELAPSED / 3600 / 24))")
					printf "$d - $MY_HOSTNAME - $NAME - WARNING: Last backup was $TIME_AGO ago \n"
				fi
			fi

		else
			printf "$d - $MY_HOSTNAME - $NAME - # TM Backups: No destinations configured\n"
		fi
	fi
fi

if [ "$LIST_BACKUPS" = "1" ]; then
	[ "$NOTIFY" = "1" ] && [ -f ~/bin/iterm_notify.sh ] && ~/bin/iterm_notify.sh "Script $NAME Finished"
	exit
fi

LAST_PATH=""
LAST_PHASE=""
PHASE_COUNT=0

while [ 1 = 1 ]; do

	d=$(date "+%Y-%m-%d - %H:%M:%S")

	LOG_START="$(date -j -v-10M +'%Y-%m-%d %H:%M:%S')"

	if [ "$SHOW_PATH" = "1" ]; then
		LOG_START="$(date -j -v-10M +'%Y-%m-%d %H:%M:%S')"
		#		FILTER='processImagePath contains "backupd" and subsystem beginswith "com.apple.TimeMachine"'
		FILTER='subsystem == "com.apple.TimeMachine"'
		TM_LOG=$(log show --style syslog --info --start "$LOG_START" --predicate "$FILTER" | grep "Current" | tail -n1)
		TM_FILE=$(echo $TM_LOG | sed "s/$Macintosh HD - Data/\|Path:/g" | cut -f2 -d"|")

		#		echo TM_FILE="$TM_FILE"
		#		echo TM_STAT="$TM_STAT"

		TM_PATH=". $TM_FILE"

	else
		TM_PATH=""
	fi
	if [ "$TM_PATH" = "$LAST_PATH" ]; then
		TM_PATH=""
	else
		LAST_PATH=$TM_PATH
	fi

	SKIP=0

	PHASE=$(/usr/bin/tmutil currentphase)

	if [ "$PHASE" = "$LAST_PHASE" ]; then
		let PHASE_COUNT=$PHASE_COUNT+1
	else
		LAST_PHASE="$PHASE"
		PHASE_COUNT=1
	fi

	TMSTATUS1=$(/usr/bin/tmutil status)
	DEST_INFO=$(echo "$TMSTATUS1" | grep "DestinationMountPoint = " | cut -f2 -d"=" | sed "s/;//g" | sed "s/\"//g" | sed "s/^ //")

	if [ "$DEST_INFO" = "" ]; then
		INFO_TEXT="$PHASE"
	else
		INFO_TEXT="$PHASE -> $DEST_INFO"
	fi

	case "$PHASE" in

	"Starting")
		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] starting up \n"
		;;
	"HealthCheckCopyHFSMeta")
		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] running health check \n"
		;;
	"HealthCheckFsck")
		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] running health check \n"
		;;
	"MountingBackupVol")
		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] mounting volume \n"
		;;
	"MountingBackupVolForHealthCheck")
		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] mounting volume \n"
		;;
	"ThinningPreBackup")
		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] pre-processing... \n"
		;;
	"ThinningPostBackup")
		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT post-processing... \n"
		;;
	"Finishing")
		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] finishing up \n"
		;;
	"PreparingSourceVolumes")
		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] preparing source volumes \n"
		;;
	"SizingChanges")
		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] sizing changes \n"
		;;
	"FindingChanges")
		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] finding changes \n"
		;;
	"DeletingOldBackups")
		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] deleting old backups \n"
		;;

	"Copying")

		TIME_REMAIN=""

		TMSTATUS=$(echo "$TMSTATUS1" | sed "s/ //g" | sed "s/;//g" | sed "s/\"//g")

		TMRUNNING=$(echo "$TMSTATUS" | grep "^BackupPhase" | cut -f2 -d"=")
		PERCENT=$(echo "$TMSTATUS" | grep "^_raw_Percent" | cut -f2 -d"=")
		TOT_FILES=$(echo "$TMSTATUS" | grep "^totalFiles" | cut -f2 -d"=")
		CUR_FILES=$(echo "$TMSTATUS" | grep "^files" | cut -f2 -d"=")
		TOT_BYTES=$(echo "$TMSTATUS" | grep "^totalBytes=" | cut -f2 -d"=")
		CUR_BYTES=$(echo "$TMSTATUS" | grep "^bytes=" | cut -f2 -d"=")
		TIME_REMAIN=$(echo "$TMSTATUS" | grep "^TimeRemaining=" | cut -f2 -d"=")

		#			echo "P=$PERCENT; TF=$TOT_FILES; CF=$CUR_FILES; TB=$TOT_BYTES; CB=$CUR_BYTES"

		[ "$PERCENT" = "" ] && PERCENT=0
		[ "$TOT_FILES" = "" ] && TOT_FILES=0
		[ "$CUR_FILES" = "" ] && CUR_FILES=0
		[ "$TOT_BYTES" = "" ] && TOT_BYTES=0
		[ "$CUR_BYTES" = "" ] && CUR_BYTES=0

		NPERCENT=$(echo "scale=5 ; $PERCENT * 100" | bc)

		REM_FILES=$(echo "scale=5 ; $TOT_FILES - $CUR_FILES" | bc)
		REM_BYTES=$(echo "scale=5 ; ( $TOT_BYTES - $CUR_BYTES ) / 1024 / 1024" | bc)
		REM_BYTESR=$(echo "scale=5 ; ( $TOT_BYTES - $CUR_BYTES )" | bc)

		export LC_NUMERIC="en_US.UTF-8"

		if [ "$TIME_REMAIN" != "" ]; then
			TIME_REMAIN=" - Time Remaining: $(ConvertSecs $TIME_REMAIN)"
		fi

		DESC="Remaining"

		if [ $REM_FILES -lt 0 ]; then
			let REM_FILES=-$REM_FILES
			DESC="Extra files found"
		fi

		if [ $REM_BYTESR -lt 0 ]; then
			REM_BYTES=$(echo "-1 * $REM_BYTES" | bc)
			DESC="Extra files found"
		fi

		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status [$PHASE_COUNT] ($INFO_TEXT) %'0.5f%% - $DESC: %'0.0f files - %'0.0f MB$TIME_REMAIN$TM_PATH\n" $NPERCENT $REM_FILES $REM_BYTES

		;;

	\
		"BackupNotRunning")
		if [ "$KEEP_ALIVE" = 1 ]; then
			printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($PHASE): not running \n"
			/usr/bin/tmutil startbackup
			printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status: not running - starting it up!\n"
		else
			exit
		fi

		;;
	*)

		printf "$d - $MY_HOSTNAME - $NAME - Time Machine Status ($PHASE) [$PHASE_COUNT] : unknown phase \n"
		;;

	esac

	if [ "$SLEEP_TIME" = "0" ]; then
		[ "$NOTIFY" = "1" ] && [ -f ~/bin/iterm_notify.sh ] && ~/bin/iterm_notify.sh "Script $NAME Finished"
		exit
	else
		sleep $SLEEP_TIME
	fi
done
