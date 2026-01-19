#!/bin/bash

# Name:
# -----
# timemach_stats_viewer.sh
#
# Purpose:
# --------
# This job prints out time machine status messages
#
# Dependencies:
# -------------
#
# iterm_notify.sh				to send a macOS notification via iTerm2 Shell Integration
#								edit the script to the location of iterm_notify.sh  (script uses ~/bin/iterm_notify.sh)
#
# gdate	(optional)				to print nano-seconds as part of the timestamp output.  To install: brew intall coreutils
#
# Customization:
# --------------
#
# LOGFILE						Location of where the log is updated showing actions taken
#
# Crontab Example:
# ----------------
# This example runs the job every day at 12:01 AM
#
# MIN          HOUR   MDAY     MON     DOW      COMMAND
# 1              0      *       *       *       /Users/me/bin/timemach_stats.sh -b       	&> /dev/null
#

usage() {

	echo "Usage:		"${0##*/}"  [-q -k -l -b -n -p -r NN]

OPTIONS:
   -q		quiet (do not log the results)
   -b       bootstrap and start a backup if one has not been taken in the last two hours
   -k		keep alive (restart backups, if they are not running)
   -l		list current backups only
   -n 		to send a macOS notification via iTerm2 Shell Integration when the script ends
   -p		show current file path that is being backed up
   -r NN 	repeat check after sleeping NN seconds, example '-r 30' to sleep 30 seconds before repeating the check
"
}

Print_DateTime() {
	# Prioritize gdate (GNU Date) for millisecond/nanosecond precision
	if command -v gdate >/dev/null 2>&1; then
		echo $(gdate "+%Y-%m-%d - %H:%M:%S.%2N")
	else
		echo $(date "+%Y-%m-%d - %H:%M:%S")
	fi	
}

# Convert date strings to readable format
ConvertDatesToReadable() {
	while IFS= read -r line; do
		# if we are in standard time, then the date needs to be adjusted by an hour

		if date +%Z | grep -q "ST$"; then
			TS_DATE=$(date -j -v-1H -f "%a %b %d %T %Z %Y" "$line" "+%Y-%m-%d-%H:%M:%S" 2>/dev/null)
		else
			TS_DATE=$(date -j -f "%a %b %d %T %Z %Y" "$line" "+%Y-%m-%d-%H:%M:%S" 2>/dev/null)
		fi
		echo $TS_DATE
	done
}

# Convert date strings to seconds since epoch
ConvertDatesToSeconds() {
	while IFS= read -r line; do
		# if we are in standard time, then the date needs to be adjusted by an hour

		if date +%Z | grep -q "ST$"; then
			TS_DATE=$(date -j -v-1H -f "%a %b %d %T %Z %Y" "$line" "+%s" 2>/dev/null)
		else
			TS_DATE=$(date -j -f "%a %b %d %T %Z %Y" "$line" "+%s" 2>/dev/null)
		fi
		echo $TS_DATE
	done
}

# Convert seconds to HH:MM:SS format
ConvertSecs() {
  echo "$1" | awk '{printf "%d:%02d:%02d", $1/3600, ($1/60)%60, $1%60}'
}

CovertSecs_to_HumanReadable() {
	total_seconds=${1#-}
	# Calculate time units
	days=$(( total_seconds / 86400 ))
	hours=$(( (total_seconds % 86400) / 3600 ))
	minutes=$(( (total_seconds % 3600) / 60 ))
	seconds=$(( total_seconds % 60 ))
	
	# Determine the label and format the output
	if [ "$total_seconds" -ge 86400 ]; then
		# More than a day
		printf "%d days, %02d:%02d:%02d hours\n" "$days" "$hours" "$minutes" "$seconds"
	
	elif [ "$total_seconds" -ge 3600 ]; then
		# More than an hour (8201 falls here)
		printf "%02d:%02d:%02d hours\n" "$hours" "$minutes" "$seconds"
	
	elif [ "$total_seconds" -ge 60 ]; then
		# More than a minute
		printf "%02d:%02d minutes\n" "$minutes" "$seconds"
	
	else
		# Seconds only
		printf "%02d seconds\n" "$seconds"
	fi
}

TMSnapShots() {
	NUM_DESTINATIONS=$(/usr/bin/tmutil destinationinfo | grep "^Name" -c)

	X=0
	while [ "$X" -lt "$NUM_DESTINATIONS" ]; do
		/usr/libexec/PlistBuddy -c "Print :Destinations:$X:SnapshotDates" /Library/Preferences/com.apple.TimeMachine.plist 2>/dev/null | grep ":" | sed 's/^ *//g'
		let X=X+1
	done
}

TMSnapShots_ByDest() {
	BOOTSTRAP_DEST=""
	BOOTSTRAP_SECS=0

	TM_DESTINFO=$(/usr/bin/tmutil destinationinfo | grep -v Kind | grep -v URL | grep -v "Mount Point")

	NUM_DESTINATIONS=$(echo "$TM_DESTINFO" | grep "^Name" -c)

	if [ "$NUM_DESTINATIONS" != 1 ]
	then
		X=0
		while [ "$X" -lt "$NUM_DESTINATIONS" ]; do

			DEST_ID=$(/usr/libexec/PlistBuddy -c "Print :Destinations:$X:DestinationID" /Library/Preferences/com.apple.TimeMachine.plist)
			DEST_NAME=$(echo "$TM_DESTINFO" | grep -i -B 1 $DEST_ID | head -1 | cut -f2 -d ":" | sed "s/^ //g")
			SNAPSHOTS=$(/usr/libexec/PlistBuddy -c "Print :Destinations:$X:SnapshotDates" /Library/Preferences/com.apple.TimeMachine.plist 2>/dev/null | grep ":" | sed 's/^ *//g')
			FIRST_SNAPSHOT=$(echo "$SNAPSHOTS" | ConvertDatesToReadable | sort | head -1)
			LAST_SNAPSHOT=$(echo "$SNAPSHOTS"  | ConvertDatesToReadable | sort | tail -1)
			LAST_SNAPSHOT_SECONDS=$(echo "$SNAPSHOTS"  | ConvertDatesToSeconds | sort | tail -1)
			
			SECONDS_NOW=$(date +%s)
			LAST_SNAPSHOT_RELATIVE=$(eval "echo $(($SECONDS_NOW- $LAST_SNAPSHOT_SECONDS))")

			THIS_SNAPSHOT_COUNT=$(echo "$SNAPSHOTS" | wc -l | sed 's/^ *//g')
			
			if [ $LAST_SNAPSHOT_RELATIVE -gt 7200 ]; then
				if [ $LAST_SNAPSHOT_RELATIVE -gt $BOOTSTRAP_SECS ]; then
					BOOTSTRAP_DEST="$DEST_ID"
					BOOTSTRAP_NAME="$DEST_NAME"
					BOOTSTRAP_SECS=$LAST_SNAPSHOT_RELATIVE
				fi
			fi
			
			if [ "$X" != 0 ]
			then
				let SS_TIME_DIFF=PRIOR_SNAPSHOT_SECONDS-LAST_SNAPSHOT_SECONDS
				
				SS_LAST_BACKUP=$(CovertSecs_to_HumanReadable "$SS_TIME_DIFF")

				SS_TIME_DIFF=$(echo "($SS_LAST_BACKUP difference)")
			else
				SS_TIME_DIFF=""
			fi

			let X=X+1

			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME -   #$X: [$DEST_NAME] - # Backups: $THIS_SNAPSHOT_COUNT -> $FIRST_SNAPSHOT to $LAST_SNAPSHOT $SS_TIME_DIFF\n" | tee -a "$LOGFILE"

			PRIOR_SNAPSHOT_SECONDS=$LAST_SNAPSHOT_SECONDS

		done
		
		if [ "$BOOTSTRAP" = 1 ] && [ "$BOOTSTRAP_DEST" != "" ] && [ $(/usr/bin/tmutil currentphase) = "BackupNotRunning" ]
		then
			BOOTSTRAP_SECS=$(CovertSecs_to_HumanReadable "$BOOTSTRAP_SECS")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - INFO: Starting Backup on $BOOTSTRAP_NAME (it was $BOOTSTRAP_SECS ago)\n" | tee -a "$LOGFILE"
			/usr/bin/tmutil startbackup -d "$BOOTSTRAP_DEST"
			sleep 10
		fi
	fi
}

GetLastBackupStatus() {

	# Determine if it is configured.
	TM_CONFIGURED=0
	NUM_DESTINATIONS=""
	TM_LAST_SNAPSHOT_DATE=""
	TM_LAST_SNAPSHOT_TS=""
	TM_FIRST_SNAPSHOT_DATE=""
	TM_FIRST_SNAPSHOT_TS=""
	SNAPSHOT_COUNT="0"

	if [ -e /usr/bin/tmutil ]; then

		V=$(/usr/bin/tmutil destinationinfo | grep "No destinations configured")

		if [ -z "$V" ]; then
			# Get dates

			TM_SNAPSHOTS=$(TMSnapShots)

			if [ "$TM_SNAPSHOTS" == "" ]; then
				printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - # TM Backups: No backups taken\n" | tee -a "$LOGFILE"
			else

				FIRST_SNAPSHOT=$(echo "$TM_SNAPSHOTS"     | ConvertDatesToReadable | sort | head -1 )
				FIRST_SNAPSHOT_SEC=$(echo "$TM_SNAPSHOTS" | ConvertDatesToSeconds  | sort | head -1 )
				LAST_SNAPSHOT=$(echo "$TM_SNAPSHOTS"      | ConvertDatesToReadable | sort | tail -1 )
				LAST_SNAPSHOT_SEC=$(echo "$TM_SNAPSHOTS"  | ConvertDatesToSeconds  | sort | tail -1 )
				ALL_SNAPSHOT_COUNT=$(echo "$TM_SNAPSHOTS" | wc -l | sed 's/^ *//g')

				CURRENT_SEC=$(date '+%s')

				let TM_ELAPSED=$CURRENT_SEC-$LAST_SNAPSHOT_SEC
				TM_DAYS=$(eval "echo $(($TM_ELAPSED / 3600 / 24))")
				TIME_AGO=$(CovertSecs_to_HumanReadable "$TM_ELAPSED")

				#echo "[$TIME_AGO] = $TM_ELAPSED seconds"

				printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Total # TM Backups: $ALL_SNAPSHOT_COUNT -> $FIRST_SNAPSHOT to $LAST_SNAPSHOT ($TIME_AGO ago)\n" | tee -a "$LOGFILE"

				TMSnapShots_ByDest

				if [ $TM_ELAPSED -gt 86400 ]; then
					printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - WARNING: Last backup was $TIME_AGO ago \n" | tee -a "$LOGFILE"
				fi
			fi

		else
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - # TM Backups: No destinations configured\n" | tee -a "$LOGFILE"
		fi
	fi
}

NAME=$(basename "$0")
VER=10
MY_HOSTNAME=$(/bin/hostname -s)

# for home brew
if [ -f /opt/homebrew/bin/brew ]
then
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Default log file, unique per machine
LOGFILE=$HOME/bin/Logfiles/timemach_$MY_HOSTNAME.log
mkdir -p "$(dirname "$LOGFILE")"

# Set defaults
BOOTSTRAP=0
KEEP_ALIVE=0
SHOW_PATH=0
SLEEP_TIME=0
LIST_BACKUPS=0
NOTIFY=0

while getopts "bkpqlnr:?" OPTION; do
	case $OPTION in
	b)											# start a backup if one has not completed in the last two hours
		BOOTSTRAP=1
		;;
	k)											# start a backup, if one is not running
		KEEP_ALIVE=1
		;;
	p)											# print the path that is being backed up
		SHOW_PATH=1
		;;
	q)
		LOGFILE="/dev/null"						# do not save the results to a log file 
		;;
	l)											# list backups only
		LIST_BACKUPS=1
		;;
	n)											# use iterm notify when script ends 
		NOTIFY=1
		;;
	r)											# repeat the check after $SLEEP_TIME seconds
		SLEEP_TIME=$(echo $OPTARG)
		;;
	?)
		usage
		exit
		;;
	esac
done

NUM_VOLUMES=$(ls -d /Volumes/Backups\ of\ $MY_HOSTNAME* 2>&1 | grep -v "No such" | grep -c Backups)

if [ $NUM_VOLUMES -gt 1 ]; then
	printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - WARNING: There are $NUM_VOLUMES folders named 'Backups of $MY_HOSTNAME*' in '/Volumes' \n" | tee -a "$LOGFILE"
fi

GetLastBackupStatus

if [ "$LIST_BACKUPS" = "1" ]; then
	[ "$NOTIFY" = "1" ] && [ -f ~/bin/iterm_notify.sh ] && ~/bin/iterm_notify.sh "Script $NAME Finished - $(tail -n1 $LOGFILE)"
	exit 0
fi

LAST_PATH=""
LAST_PHASE=""
PHASE_COUNT=0
DEST_PRINT=0


while [ 1 = 1 ]; do

	LOG_START="$(date -j -v-10M +'%Y-%m-%d %H:%M:%S')"

	if [ "$SHOW_PATH" = "1" ]; then
		LOG_START="$(date -j -v-10M +'%Y-%m-%d %H:%M:%S')"
		
		#		FILTER='processImagePath contains "backupd" and subsystem beginswith "com.apple.TimeMachine"'
		FILTER='subsystem == "com.apple.TimeMachine"'
		TM_LOG=$(log show --style syslog --info --start "$LOG_START" --predicate "$FILTER" | grep "Current" | tail -n1)
		TM_FILE=$(echo "$TM_LOG" | sed "s/$Macintosh HD - Data/\|Path:/g" | cut -f2 -d"|")

		TM_PATH=". $TM_FILE"

	else
		TM_PATH=""
	fi
	
	# if the path has not changed, then empty out the string so that it does not print again 
	if [ "$TM_PATH" = "$LAST_PATH" ]; then
		TM_PATH=""
	else
		LAST_PATH="$TM_PATH"
	fi

	SKIP=0

	PHASE=$(/usr/bin/tmutil currentphase)

	# if the phase is the same as last time, then increment the phase count
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

	TM_DESTINFO=$(/usr/bin/tmutil destinationinfo | grep -v Kind | grep -v URL | grep -v "Mount Point")
	DEST_ID=$(tmutil status | grep "DestinationID" | cut -f2 -d'"')

	if [ "$DEST_ID" != "" ] && [ "$DEST_PRINT" = 0 ]
	then
		DEST_NAME=$(echo "$TM_DESTINFO" | grep -i -B 1 $DEST_ID | head -1 | cut -f2 -d ":" | sed "s/^ //g")

		printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Current Time Machine Destination : $DEST_NAME \n" | tee -a "$LOGFILE"
		DEST_PRINT=1
	fi

	case "$PHASE" in

		"BackupNotRunning")
			if [ "$KEEP_ALIVE" = 1 ]; then
				printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($PHASE): not running \n" | tee -a "$LOGFILE"
				/usr/bin/tmutil startbackup
				sleep 10
				printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status: not running - starting it up!\n" | tee -a "$LOGFILE"
			else
				[ "$NOTIFY" = "1" ] && [ -f ~/bin/iterm_notify.sh ] && ~/bin/iterm_notify.sh "Script $NAME Finished - $(tail -n1 $LOGFILE)"
				exit 1
			fi
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
			
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status [%3d] ($INFO_TEXT) %'0.5f%% - $DESC: %'0.0f files - %'0.0f MB$TIME_REMAIN$TM_PATH\n" $PHASE_COUNT $NPERCENT $REM_FILES $REM_BYTES | tee -a "$LOGFILE"
			
			;;
		"CreatingSnapshot")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] creating snapshot \n" | tee -a "$LOGFILE"
			;;
		"DeletingOldBackups")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] deleting old backups \n" | tee -a "$LOGFILE"
			;;
		"FindingChanges")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] finding changes \n" | tee -a "$LOGFILE"
			;;
		"Finishing")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] finishing up \n" | tee -a "$LOGFILE"
			;;
		"HealthCheckCopyHFSMeta")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] running health check \n" | tee -a "$LOGFILE"
			;;
		"HealthCheckFsck")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] running health check \n" | tee -a "$LOGFILE"
			;;
		"MountingBackupVol")
					printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] mounting volume \n" | tee -a "$LOGFILE"
					;;
		"MountingDiskImage")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] mounting disk image \n" | tee -a "$LOGFILE"
			;;
		"MountingBackupVolForHealthCheck")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] mounting volume \n" | tee -a "$LOGFILE"
			;;
		"PreparingSourceVolumes")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] preparing source volumes \n" | tee -a "$LOGFILE"
			;;
		"SizingChanges")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] sizing changes \n" | tee -a "$LOGFILE"
			;;
		"Starting")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] starting up \n" | tee -a "$LOGFILE"
			GetLastBackupStatus
			;;
		"ThinningPreBackup")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] pre-processing... \n" | tee -a "$LOGFILE"
			;;
		"ThinningPostBackup")
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($INFO_TEXT): [$PHASE_COUNT] post-processing... \n" | tee -a "$LOGFILE"
			;;
		*)
			printf "$(Print_DateTime)- $MY_HOSTNAME - $NAME - Time Machine Status ($PHASE) [$PHASE_COUNT] : unknown phase \n" | tee -a "$LOGFILE"
			;;
	esac

	if [ "$SLEEP_TIME" = "0" ]; then
		[ "$NOTIFY" = "1" ] && [ -f ~/bin/iterm_notify.sh ] && ~/bin/iterm_notify.sh "Script $NAME Finished - $(tail -n1 $LOGFILE)"
		exit 0
	else
		sleep $SLEEP_TIME
	fi

done

[ "$NOTIFY" = "1" ] && [ -f ~/bin/iterm_notify.sh ] && ~/bin/iterm_notify.sh "Script $NAME Finished - $(tail -n1 $LOGFILE)"
exit 0
