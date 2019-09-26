#!/bin/zsh

### config file
# this script will not source the config file as it runs as root and does not ask for a password after installation


### checking root
if [[ $(id -u) -ne 0 ]]
then 
    echo "script is not run as root, exiting..."
    exit
else
    :
fi


### variables
SERVICE_NAME=com.cert.install_update
SCRIPT_INSTALL_NAME=cert_install_update

echo ''


### waiting for logged in user
loggedInUser=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
NUM=0
MAX_NUM=15
SLEEP_TIME=3
# waiting for loggedInUser to be available
while [[ "$loggedInUser" == "" ]] && [[ "$NUM" -lt "$MAX_NUM" ]]
do
    sleep "$SLEEP_TIME"
    NUM=$((NUM+1))
    loggedInUser=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
done
#echo ''
#echo "NUM is $NUM..."
#echo "loggedInUser is $loggedInUser..."
if [[ "$loggedInUser" == "" ]]
then
    WAIT_TIME=$((MAX_NUM*SLEEP_TIME))
    echo "loggedInUser could not be set within "$WAIT_TIME"s, exiting..."
    exit
else
    :
fi


### in addition to showing them in terminal write errors to logfile when run from batch script
env_check_if_run_from_batch_script() {
    BATCH_PIDS=()
    BATCH_PIDS+=$(ps aux | grep "/batch_script_part.*.command" | grep -v grep | awk '{print $2;}')
    if [[ "$BATCH_PIDS" != "" ]] && [[ -e "/tmp/batch_script_in_progress" ]]
    then
        RUN_FROM_BATCH_SCRIPT="yes"
    else
        :
    fi
}

env_start_error_log() {
    local ERROR_LOG_DIR=/Users/"$loggedInUser"/Desktop/batch_error_logs
    if [[ ! -e "$ERROR_LOG_DIR" ]]
    then
        local ERROR_LOG_NUM=1
    else
        local ERROR_LOG_NUM=$(($(ls -1 "$ERROR_LOG_DIR" | awk -F'_' '{print $1}' | sort -n | tail -1)+1))
    fi
    mkdir -p "$ERROR_LOG_DIR"
    if [[ "$ERROR_LOG_NUM" -le "9" ]]; then ERROR_LOG_NUM="0"$ERROR_LOG_NUM""; else :; fi
    local ERROR_LOG="$ERROR_LOG_DIR"/"$ERROR_LOG_NUM"_"$SERVICE_NAME"_errorlog.txt
    echo "### "$SERVICE_NAME"" >> "$ERROR_LOG"
    #echo "### $(date "+%Y-%m-%d %H:%M:%S")" >> "$ERROR_LOG"
    echo '' >> "$ERROR_LOG"
    exec 2> >(tee -ia "$ERROR_LOG" >&2)
}

env_stop_error_log() {
    exec 2<&-
    exec 2>&1
}

env_check_if_run_from_batch_script
if [[ "$RUN_FROM_BATCH_SCRIPT" == "yes" ]]; then env_start_error_log; else :; fi


### logfile
EXECTIME=$(date '+%Y-%m-%d %T')
LOGDIR=/var/log
LOGFILE="$LOGDIR"/"$SCRIPT_INSTALL_NAME".log

if [[ -f "$LOGFILE" ]]
then
    # only macos takes care of creation time, linux doesn`t because it is not part of POSIX
    LOGFILEAGEINSECONDS="$(( $(date +"%s") - $(stat -f "%B" $LOGFILE) ))"
    MAXLOGFILEAGE=$(echo "30*24*60*60" | bc)
    #echo $LOGFILEAGEINSECONDS
    #echo $MAXLOGFILEAGE
    # deleting logfile after 30 days
    if [[ "$LOGFILEAGEINSECONDS" -lt "$MAXLOGFILEAGE" ]];
    then
        echo "logfile not older than 30 days..."
    else
        # deleting logfile
        echo "deleting logfile..."
        sudo rm "$LOGFILE"
        sudo touch "$LOGFILE"
        sudo chmod 644 "$LOGFILE"
    fi
else
    sudo touch "$LOGFILE"
    sudo chmod 644 "$LOGFILE"
fi

sudo echo "" >> "$LOGFILE"
sudo echo $EXECTIME >> "$LOGFILE"


### additional functions
certificate_variable_check() {
    
    # macos
    MACOS_VERSION=$(sw_vers -productVersion)
    MACOS_VERSION_MAJOR=$(echo "$MACOS_VERSION" | cut -f1,2 -d'.')
    env_convert_version_comparable() { echo "$@" | awk -F. '{ printf("%d%02d%02d\n", $1,$2,$3); }'; }

    # keychain
    KEYCHAIN="/System/Library/Keychains/SystemRootCertificates.keychain"
    
    # variable for search/replace by install script
    CERTIFICATE_NAME="FILL_IN_NAME_HERE"
    SERVER_IP="FILL_IN_IP_HERE"
    
    if [[ $(echo "$CERTIFICATE_NAME" | grep "^FILL_IN_*") != "" ]] || [[ $(echo "$CERTIFICATE_NAME" | grep "^FILL_IN_*") != "" ]]
    then
        echo "at least one variable not set correctly, exiting..."
        exit
    else
        :
    fi

}

install_update_certificate() {

    # deleting old installed certificate
    if [[ $(security find-certificate -a -c "$CERTIFICATE_NAME" "$KEYCHAIN") != "" ]]
    then
        #CERT_SHA1=$(security find-certificate -c "$CERTIFICATE_NAME" -a -Z "$KEYCHAIN" | awk '/SHA-1/{print $NF}')
        #sudo security delete-certificate -Z "$CERT_SHA1" "$KEYCHAIN"
        sudo security delete-certificate -c "$CERTIFICATE_NAME" "$KEYCHAIN"
    else
        :
    fi
    
    # downloading new certificate
    if [[ -e /tmp/"$CERTIFICATE_NAME".crt ]]
    then
        rm -f /tmp/"$CERTIFICATE_NAME".crt
    else
        :
    fi
    #echo quit | openssl s_client -showcerts -servername "$SERVER_IP" -connect "$SERVER_IP":443 2>/dev/null > /tmp/"$CERTIFICATE_NAME".crt
    echo quit | openssl s_client -showcerts -connect "$SERVER_IP":443 2>/dev/null > /tmp/"$CERTIFICATE_NAME".crt

    # add certificate to keychain and trust all
    #sudo security add-trusted-cert -d -r trustAsRoot -k "$KEYCHAIN" "/Users/$USER/Desktop/cacert.pem"

    # add certificate to keychain and no value set
    #sudo security add-trusted-cert -r trustAsRoot -k "$KEYCHAIN" "/Users/$USER/Desktop/cacert.pem"
    
    # add certificate to keychain and trust ssl
    VERSION_TO_CHECK_AGAINST=10.14
    if [[ $(env_convert_version_comparable "$MACOS_VERSION_MAJOR") -le $(env_convert_version_comparable "$VERSION_TO_CHECK_AGAINST") ]]
    then
        # macos versions until and including 10.14
        sudo security add-trusted-cert -d -r trustAsRoot -p ssl -e hostnameMismatch -k "$KEYCHAIN" /tmp/"$CERTIFICATE_NAME".crt
    else
        # macos versions 10.15 and up
        # in 10.15 /System default gets mounted read-only
        # can only be mounted read/write with according SIP settings
        sudo mount -uw /
        # stays mounted rw until next reboot
        sleep 0.5
        sudo security add-trusted-cert -d -r trustAsRoot -p ssl -e hostnameMismatch -k "$KEYCHAIN" /tmp/"$CERTIFICATE_NAME".crt
        #sudo mount -ur /
        #sleep 0.5
    fi
    
    # checking that certificate is installed, not untrusted and matches the domain
    # exporting certificate
    security find-certificate -a -p -c "$CERTIFICATE_NAME" "$KEYCHAIN" > /tmp/local_"$CERTIFICATE_NAME".pem
    if [[ $(security verify-cert -r /tmp/local_"$CERTIFICATE_NAME".pem -p ssl -s "$CERTIFICATE_NAME" | grep "successful") != "" ]]
    then
        echo "the certificate is installed, trusted and working..."
    else
        echo "there seems to be a problem with the installation of the certificate..."
    fi

}

check_weekday() {
    # checking if it is needed to check the certificates by weekday
    if [[ "$(LANG=en_US date +%A)" != "Thursday" ]]
    then
        echo "it's not thursday, no need to check certificates..."
        echo "exiting script..."
        exit
    else
        :
    fi
}

setting_config() {
    ### sourcing .$SHELLrc or setting PATH
    # as the script is run from a launchd it would not detect the binary commands and would fail checking if binaries are installed
    # needed if binary is installed in a special directory
    if [[ -n "$BASH_SOURCE" ]] && [[ -e /Users/"$loggedInUser"/.bashrc ]] && [[ $(cat /Users/"$loggedInUser"/.bashrc | grep 'PATH=.*/usr/local/bin:') != "" ]]
    then
        echo "sourcing .bashrc..."
        . /Users/"$loggedInUser"/.bashrc
    elif [[ -n "$ZSH_VERSION" ]] && [[ -e /Users/"$loggedInUser"/.zshrc ]] && [[ $(cat /Users/"$loggedInUser"/.zshrc | grep 'PATH=.*/usr/local/bin:') != "" ]]
    then
        echo "sourcing .zshrc..."
        ZSH_DISABLE_COMPFIX="true"
        . /Users/"$loggedInUser"/.zshrc
    else
        echo "setting path for script..."
        export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
    fi
}
# run before main function, e.g. for time format
setting_config &> /dev/null


### cert check
cert_check() {
    
    ### loggedInUser
    echo "loggedInUser is $loggedInUser..."
    
    
    ### sourcing .$SHELLrc or setting PATH
    #setting_config
    
    
    ### script
	certificate_variable_check

    #check_weekday
    
    # checking homebrew and script dependencies
    if sudo -H -u "$loggedInUser" command -v brew &> /dev/null
    then
    	# installed
        echo "homebrew is installed..."
        # checking for missing dependencies
        for formula in openssl
        #for formula in 123
        do
        	if [[ $(sudo -H -u "$loggedInUser" brew list | grep "^$formula$") == '' ]]
        	then
        		#echo """$formula"" is NOT installed..."
        		MISSING_SCRIPT_DEPENDENCY="yes"
        		osascript -e 'tell app "System Events" to display dialog "the script cert_install_update.sh needs '$formula' to be installed via homebrew..."'
        	else
        		#echo """$formula"" is installed..."
        		:
        	fi
        done
        if [[ "$MISSING_SCRIPT_DEPENDENCY" == "yes" ]]
        then
            echo "at least one needed homebrew tool is missing, exiting..."
            exit
        else
            echo "needed homebrew tools are installed..."   
        fi
        unset MISSING_SCRIPT_DEPENDENCY
    else
        # not installed
        echo "homebrew is not installed, exiting..."
        exit
    fi
    
    # giving the network some time
    ping -c5 "$SERVER_IP" >/dev/null 2>&1
    if [ "$?" = 0 ]
    then
        :
    else
        echo "server not found, waiting 60s for next try..."
        sleep 60
    fi
 
    # checking if online
    ping -c5 "$SERVER_IP" >/dev/null 2>&1
    if [[ "$?" = 0 ]]
    then
        echo "server found, checking certificates..."
        
        # server cert in pem format
        if [[ -e /tmp/server_"$CERTIFICATE_NAME".pem ]]
        then
            rm -f /tmp/server_"$CERTIFICATE_NAME".pem
        else
            :
        fi
        SERVER_CERT_PEM=$(echo quit | openssl s_client -connect "$SERVER_IP":443 2>/dev/null | openssl x509) &> /dev/null
        if [[ "$?" -eq 0 ]]
        then
        
            #echo quit | openssl s_client -connect "$SERVER_IP":443 2>/dev/null | openssl x509 > /tmp/server_"$CERTIFICATE_NAME".pem
            #SERVER_CERT_PEM=$(cat /tmp/server_"$CERTIFICATE_NAME".pem)
            # or
            #true | openssl s_client -connect services.greenenergypeak.de:443 2>/dev/null | openssl x509
            
            # checking if certificate is installed
            if [[ $(security find-certificate -a -c "$CERTIFICATE_NAME" "$KEYCHAIN") == "" ]]
            then
                echo "certificate $CERTIFICATE_NAME not found, installing..."
                install_update_certificate
            else
                :
            fi
            
            # local cert in pem format
            if [[ -e /tmp/local_"$CERTIFICATE_NAME".pem ]]
            then
                rm -f /tmp/local_"$CERTIFICATE_NAME".pem
            else
                :
            fi
            LOCAL_CERT_PEM=$(security find-certificate -a -p -c "$CERTIFICATE_NAME" "$KEYCHAIN")
            #security find-certificate -a -p -c "$CERTIFICATE_NAME" "$KEYCHAIN" > /tmp/local_"$CERTIFICATE_NAME".pem
            #LOCAL_CERT_PEM=$(cat /tmp/local_"$CERTIFICATE_NAME".pem)
    
            # checking if update needed
            if [[ "$SERVER_CERT_PEM" == "$LOCAL_CERT_PEM" ]]
            then
                echo "server certificate matches local certificate, no need to update..."
            else
                echo "server certificate does not match local certificate, updating..."
                install_update_certificate
            fi
            
            # cleaning up
            if [[ -e /tmp/"$CERTIFICATE_NAME".crt ]]
            then
                rm -f /tmp/"$CERTIFICATE_NAME".crt
            else
                :
            fi
            if [[ -e /tmp/server_"$CERTIFICATE_NAME".pem ]]
            then
                rm -f /tmp/server_"$CERTIFICATE_NAME".pem
            else
                :
            fi
            if [[ -e /tmp/local_"$CERTIFICATE_NAME".pem ]]
            then
                rm -f /tmp/local_"$CERTIFICATE_NAME".pem
            else
                :
            fi  
            
        else
            echo "certificate could not be loaded from server, exiting script..."
            exit
        fi      
        
    else
        echo "server not found, exiting script..."
        exit
    fi
	
}

if [[ "$RUN_FROM_BATCH_SCRIPT" == "yes" ]]
then 
    (time ( cert_check )) | tee -a "$LOGFILE"
else
    (time ( cert_check )) 2>&1 | tee -a "$LOGFILE"
fi

echo '' >> "$LOGFILE"

### stopping the error output redirecting
if [[ "$RUN_FROM_BATCH_SCRIPT" == "yes" ]]; then env_stop_error_log; else :; fi
