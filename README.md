# TimeMachine
Scripts to Manage Time Machine



# timemach_stats_viewer.sh


Purpose:
--------
This job prints out how much is left to backup using time machine

Dependencies:
-------------

iterm_notify.sh				to send a macOS notification via iTerm2 Shell Integration
		 						      edit the script to the location of iterm_notify.sh  (script uses ~/bin/iterm_notify.sh)

Usage
--------------
./timemach_stats_viewer.sh  [-k -l -s -n -r NN]

OPTIONS:
</br>      -q		  quiet (do not log the results)
</br>      -k		  keep alive (restart backups, if they are not running)
</br>      -l		  list current backups only
</br>      -n 		to send a macOS notification via iTerm2 Shell Integration when the script ends
</br>      -s 		list current status only
</br>      -r NN 	repeat check after sleeping NN seconds, example '-r 30' to sleep 30 seconds before repeating the check




Customization:
--------------
Install iTerm2 Shell Integration and update the location of the script to use the '-n' option.
