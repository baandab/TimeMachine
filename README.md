Name:
-----
timemach_stats_viewer.sh

Purpose:
--------
This job prints out time machine status

Dependencies:
-------------
<code>
iterm_notify.sh        to send a macOS notification via iTerm2 Shell Integration
                       edit the script to the location of iterm_notify.sh  (script uses ~/bin/iterm_notify.sh)
<br>
gdate (optional)      to print nano-seconds as part of the timestamp output.  To install: brew intall coreutils
</code>

Customization:
--------------

LOGFILE						Location of where the log is updated showing actions taken

Crontab Example: 
----------------
This example runs the job every day at 12:01 AM
<br>
<code>
MIN          HOUR   MDAY     MON     DOW      COMMAND
1              0      *       *       *       /Users/me/bin/timemach_stats.sh -b       	&> /dev/null
</code>

Usage
-----
<code>
Usage:		timemach_stats.sh  [-q -k -l -b -n -p -r NN]
<br>
OPTIONS:
   -q		quiet (do not log the results)
   -b		bootstrap and start a backup if one has not been taken in the last two hours
   -k		keep alive (restart backups, if they are not running)
   -l		list current backups only
   -n		to send a macOS notification via iTerm2 Shell Integration when the script ends
   -p		show current file path that is being backed up
   -r NN 	repeat check after sleeping NN seconds, example '-r 30' to sleep 30 seconds before repeating the check
</code>
